import Foundation

/// Finds public places a short distance away with a much more open view of the
/// sky than the site's own blocked horizon — for when the problem is trees and
/// rooftops rather than light pollution.
///
/// Apple Maps supplies the candidates (parks and boat ramps). ESA WorldCover's
/// satellite land cover then says what surrounds each one, pixel by pixel:
/// trees, buildings, grass, water. Around each place, every patch of open ground
/// within `searchAroundPlaceMeters` is tried as a standing point, with sight
/// lines cast in 36 directions; the highest obstruction along each line gives
/// the angle the sky is blocked below in that direction. The best standing point
/// wins, and the map pin goes there rather than to the place's own pin, which
/// is often a car park or a building.
///
/// Land cover says *what* is there, not how tall it is, so each class gets an
/// assumed height — see `obstructionHeight`. That's the weakest part of the
/// estimate: a stand of 25 m pines blocks more than it accounts for, a line of
/// young oaks less.
struct OpenHorizonFinder: Sendable {

    private let nightLights = NightLightsClient()
    private let landCover: LandCoverClient

    init(landCover: LandCoverClient) {
        self.landCover = landCover
    }

    /// How far from a place's pin to look for open ground. Far enough to cross a
    /// typical park; not so far that the spot lands in someone's back garden.
    static let searchAroundPlaceMeters = 200.0
    /// Sight lines stop here. At 600 m a 15 m tree line blocks under 1.5°.
    static let sightLineMeters = 600.0
    /// The least improvement over the site's own blocked horizon worth a trip.
    static let minimumImprovementDegrees = 5.0
    private static let eyeHeightMeters = 1.5
    private static let directions = 36

    /// Assumed height of whatever a land-cover class represents. Built-up is
    /// low because WorldCover files roads and car parks under it along with
    /// buildings, and a car park is exactly where most people set up.
    static func obstructionHeight(_ value: UInt8) -> Double {
        switch LandCoverClass(rawValue: value) {
        case .trees: return 15
        case .mangroves: return 6
        case .builtUp: return 4
        case .shrubland: return 2
        default: return 0
        }
    }

    /// Ground a person can stand on and set up a tripod.
    private static func isStandable(_ value: UInt8) -> Bool {
        switch LandCoverClass(rawValue: value) {
        case .grassland, .bare, .builtUp, .cropland, .mossAndLichen: return true
        default: return false
        }
    }

    @MainActor
    func search(around site: Site, radiusKilometers: Double) async throws -> NearbySpotSearchResult {
        let span = (radiusKilometers * 1000 + Self.searchAroundPlaceMeters) * 2
        let places = try await NearbyPlaceSearch.places(for: [
            (.parks, site.latitude, site.longitude, span),
            (.boatRamps, site.latitude, site.longitude, span)
        ])
        try Task.checkCancellation()

        let nightGrid = try await nightLights.grid(latitude: site.latitude, longitude: site.longitude)
        let cover = try await landCover.grid(latitude: site.latitude, longitude: site.longitude,
                                             halfSizeMeters: radiusKilometers * 1000 + Self.searchAroundPlaceMeters + Self.sightLineMeters)
        try Task.checkCancellation()

        return await Task.detached(priority: .userInitiated) {
            let field = SkyGlowField(grid: nightGrid)
            let homeBrightness = DarkSkyEstimate.zenithBrightness(glow: field.glow(latitude: site.latitude, longitude: site.longitude))
            let candidates = Self.candidateSpots(places: places, cover: cover, field: field, site: site,
                                                 radiusKilometers: radiusKilometers)
            return NearbySpotSearchResult(goal: .openHorizon, anchor: site, radiusKilometers: radiusKilometers,
                                          siteZenithBrightness: homeBrightness,
                                          siteEstimatedBortleClass: DarkSkyEstimate.bortleClass(forZenithBrightness: homeBrightness),
                                          candidates: candidates)
        }.value
    }

    // MARK: - Candidates

    /// Every place with a horizon noticeably more open than the site's; which
    /// of them to suggest is `NearbySpotSelection`'s call.
    private static func candidateSpots(places: [NearbyPlace], cover: LandCoverGrid, field: SkyGlowField, site: Site,
                                       radiusKilometers: Double) -> [NearbySpot] {
        places.compactMap { place in
            let placeDistance = DarkSkyGeometry.distanceKilometers(fromLatitude: site.latitude, longitude: site.longitude,
                                                                  toLatitude: place.latitude, longitude: place.longitude)
            guard placeDistance <= radiusKilometers + searchAroundPlaceMeters / 1000,
                  let best = bestStandingPoint(near: place, cover: cover),
                  best.horizon <= site.typicalHorizonAltitude - minimumImprovementDegrees
            else { return nil }

            let distance = DarkSkyGeometry.distanceKilometers(fromLatitude: site.latitude, longitude: site.longitude,
                                                             toLatitude: best.latitude, longitude: best.longitude)
            guard distance <= radiusKilometers else { return nil }
            let brightness = DarkSkyEstimate.zenithBrightness(glow: field.glow(latitude: best.latitude, longitude: best.longitude))

            return NearbySpot(name: place.name,
                              latitude: best.latitude,
                              longitude: best.longitude,
                              distanceKilometers: distance,
                              direction: DarkSkyGeometry.compassDirection(fromLatitude: site.latitude, longitude: site.longitude,
                                                                          toLatitude: best.latitude, longitude: best.longitude),
                              zenithBrightness: brightness,
                              estimatedBortleClass: DarkSkyEstimate.bortleClass(forZenithBrightness: brightness),
                              horizonAltitude: best.horizon,
                              clearestDirection: best.clearestDirection,
                              website: place.website)
        }
    }

    private struct StandingPoint {
        var latitude: Double
        var longitude: Double
        var horizon: Double
        var clearestDirection: String
    }

    /// The most open standable point within `searchAroundPlaceMeters` of a
    /// place, tested on a lattice about every 40 m.
    private static func bestStandingPoint(near place: NearbyPlace, cover: LandCoverGrid) -> StandingPoint? {
        guard let center = cover.position(latitude: place.latitude, longitude: place.longitude) else { return nil }
        let pixelHeight = cover.pixelHeightMeters
        let pixelWidth = cover.pixelWidthMeters(atLatitude: place.latitude)
        let rowReach = Int(searchAroundPlaceMeters / pixelHeight)
        let columnReach = Int(searchAroundPlaceMeters / pixelWidth)
        let stride = 2

        var best: (column: Int, row: Int, profile: [Double], horizon: Double, offset: Double)?
        for row in Swift.stride(from: center.row - rowReach, through: center.row + rowReach, by: stride) {
            for column in Swift.stride(from: center.column - columnReach, through: center.column + columnReach, by: stride) {
                guard (0..<cover.width).contains(column), (0..<cover.height).contains(row) else { continue }
                let dx = Double(column - center.column) * pixelWidth
                let dy = Double(row - center.row) * pixelHeight
                let offset = (dx * dx + dy * dy).squareRoot()
                guard offset <= searchAroundPlaceMeters, isStandable(cover[column, row]) else { continue }

                let profile = horizonProfile(column: column, row: row, cover: cover,
                                             pixelWidth: pixelWidth, pixelHeight: pixelHeight)
                let horizon = blockedHorizon(profile)
                // Closer to the pin wins a tie — it's more likely to be inside
                // the place itself.
                if best == nil || horizon < best!.horizon || (horizon == best!.horizon && offset < best!.offset) {
                    best = (column, row, profile, horizon, offset)
                }
            }
        }
        guard let best else { return nil }
        let coordinate = cover.coordinate(column: best.column, row: best.row)
        return StandingPoint(latitude: coordinate.latitude, longitude: coordinate.longitude,
                             horizon: best.horizon, clearestDirection: clearestDirection(best.profile))
    }

    /// Obstruction angle in each of `directions` evenly spaced directions,
    /// starting at north and running clockwise.
    static func horizonProfile(column: Int, row: Int, cover: LandCoverGrid,
                               pixelWidth: Double, pixelHeight: Double) -> [Double] {
        let stepMeters = min(pixelWidth, pixelHeight)
        let steps = Int(sightLineMeters / stepMeters)
        return (0..<directions).map { index in
            let azimuth = Double(index) * 360 / Double(directions)
            let east = sinDeg(azimuth)
            let north = cosDeg(azimuth)
            var steepest = 0.0
            for step in 1...steps {
                let distance = Double(step) * stepMeters
                let sampleColumn = column + Int((east * distance / pixelWidth).rounded())
                let sampleRow = row - Int((north * distance / pixelHeight).rounded())
                guard (0..<cover.width).contains(sampleColumn), (0..<cover.height).contains(sampleRow) else { break }
                let rise = obstructionHeight(cover[sampleColumn, sampleRow]) - eyeHeightMeters
                guard rise > 0 else { continue }
                steepest = max(steepest, atan2Deg(rise, distance))
            }
            return steepest
        }
    }

    /// One number for Settings' "blocked horizon": the altitude that clears
    /// three quarters of all directions, rounded up to a whole degree. The
    /// worst quarter is usually one nearby tree or building you can walk away
    /// from; averaging would hide a genuinely enclosed spot.
    static func blockedHorizon(_ profile: [Double]) -> Double {
        let sorted = profile.sorted()
        let index = min(sorted.count - 1, Int((Double(sorted.count) * 0.75).rounded(.down)))
        return sorted[index].rounded(.up)
    }

    /// Centre of the most open quarter of the sky, as a compass direction.
    private static func clearestDirection(_ profile: [Double]) -> String {
        let window = directions / 4
        var bestStart = 0
        var bestSum = Double.infinity
        for start in 0..<directions {
            let sum = (0..<window).reduce(0.0) { $0 + profile[(start + $1) % directions] }
            if sum < bestSum { bestSum = sum; bestStart = start }
        }
        let centerAzimuth = (Double(bestStart) + Double(window - 1) / 2) * 360 / Double(directions)
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return names[Int((normalize360(centerAzimuth) + 22.5) / 45) % 8]
    }
}
