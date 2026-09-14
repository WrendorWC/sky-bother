import Foundation
import MapKit

enum DarkSkyFinderError: LocalizedError {
    case placeSearchUnavailable

    var errorDescription: String? {
        switch self {
        case .placeSearchUnavailable: return "Apple Maps place search isn't answering right now. Try again in a minute."
        }
    }
}

/// A real, named place nearby that should have a noticeably darker sky.
struct DarkSpot: Identifiable, Hashable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
    var distanceKilometers: Double
    /// Compass direction from the site searched around, e.g. "NE".
    var direction: String
    var zenithBrightness: Double
    var estimatedBortleClass: Int

    var id: String { String(format: "%@|%.4f|%.4f", name, latitude, longitude) }

    var mapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: String(format: "%.5f,%.5f", latitude, longitude)),
            URLQueryItem(name: "q", value: name)
        ]
        return components?.url
    }
}

struct DarkSkySearchResult: Sendable {
    /// The site searched around, as it was when the search ran.
    var anchor: Site
    var radiusKilometers: Double
    /// The model's own estimate for the site searched around, independent of
    /// the Bortle class set for it by hand.
    var siteZenithBrightness: Double
    var siteEstimatedBortleClass: Int
    /// Best first. Empty means nothing within range is noticeably darker.
    var spots: [DarkSpot]
}

/// Finds the best places to go stargazing within a given distance of a site.
///
/// Two stages, because sky glow and somewhere you can actually stand are
/// different questions. First the sky-glow model (`SkyGlowField`) scores a
/// lattice of points across the whole search area and picks a handful of the
/// darkest, well-separated patches. Then Apple Maps is searched around each of
/// those patches for public outdoor places — parks, campgrounds, beaches,
/// marinas — and each place found is scored again at its own exact location,
/// so a floodlit ballpark inside an otherwise dark patch still ranks poorly.
/// MapKit's search needs no API key, but returns only a couple of dozen results
/// per request, favouring the best-known places — so a single search of the
/// whole area would miss exactly the quiet places this is looking for, and the
/// searches are aimed at the dark patches instead.
struct DarkSkyFinder: Sendable {

    private let nightLights = NightLightsClient()

    /// About a third of a magnitude: the least that's worth a drive. The model
    /// scatters about 0.17 magnitudes against the reference atlas, so anything
    /// much smaller could just be noise.
    static let minimumImprovement = 0.35
    /// A preference for closer places among near-equals: a 50 km drive has to
    /// buy about 0.4 magnitudes more than one next door. The distance picker
    /// already sets how far someone is willing to go; this only breaks ties.
    private static let distancePenaltyPerKilometer = 0.008
    private static let maximumPatches = 5
    private static let maximumSpots = 3
    private static let placeCategories: [MKPointOfInterestCategory] = [.park, .nationalPark, .campground, .beach, .marina]
    /// Apple Maps files these under "park", but they're small, usually lit,
    /// and rarely somewhere you can set up a tripod after dark.
    private static let unsuitableNameFragments = ["dog park", "playground", "skate", "splash", "water park",
                                                  "rv park", "ballpark", "sports complex", "athletic"]

    @MainActor
    func search(around site: Site, radiusKilometers: Double) async throws -> DarkSkySearchResult {
        let grid = try await nightLights.grid(latitude: site.latitude, longitude: site.longitude)
        try Task.checkCancellation()

        let field = SkyGlowField(grid: grid)
        let (homeBrightness, patches) = await Task.detached(priority: .userInitiated) {
            let brightness = DarkSkyEstimate.zenithBrightness(glow: field.glow(latitude: site.latitude, longitude: site.longitude))
            return (brightness, Self.darkPatches(field: field, site: site, homeBrightness: brightness,
                                                 radiusKilometers: radiusKilometers))
        }.value
        try Task.checkCancellation()
        func result(_ spots: [DarkSpot]) -> DarkSkySearchResult {
            DarkSkySearchResult(anchor: site, radiusKilometers: radiusKilometers,
                                siteZenithBrightness: homeBrightness,
                                siteEstimatedBortleClass: DarkSkyEstimate.bortleClass(forZenithBrightness: homeBrightness),
                                spots: spots)
        }
        guard !patches.isEmpty else { return result([]) }

        // The darkest patches are often somewhere with nowhere to stand — open
        // water, roadless forest, a mountainside — so two more searches cover
        // the whole area (its best-known parks, wherever they are) and the
        // site's own surroundings (the closest ones, which the whole-area search
        // tends to crowd out).
        var searchAreas = patches.map { (latitude: $0.latitude, longitude: $0.longitude, span: 8000.0) }
        searchAreas.append((site.latitude, site.longitude, radiusKilometers * 2000))
        searchAreas.append((site.latitude, site.longitude, min(radiusKilometers * 2000, 16000)))

        var places: [(name: String, latitude: Double, longitude: Double)] = []
        var failedSearches = 0
        for area in searchAreas {
            try Task.checkCancellation()
            // One failed lookup shouldn't sink the others — but if every one
            // fails (MapKit throttles an app that searches too often), that
            // must not read as "nothing darker nearby".
            let found: [(name: String, latitude: Double, longitude: Double)]
            do {
                found = try await Self.outdoorPlaces(near: area.latitude, area.longitude, spanMeters: area.span)
            } catch {
                failedSearches += 1
                continue
            }
            for place in found where !places.contains(where: { $0.name == place.name
                && abs($0.latitude - place.latitude) < 0.01 && abs($0.longitude - place.longitude) < 0.01 }) {
                places.append(place)
            }
        }

        if failedSearches == searchAreas.count { throw DarkSkyFinderError.placeSearchUnavailable }

        let spots = await Task.detached(priority: .userInitiated) {
            Self.rankedSpots(places: places, field: field, site: site, homeBrightness: homeBrightness,
                             radiusKilometers: radiusKilometers)
        }.value
        return result(spots)
    }

    // MARK: - Stage one: dark patches

    private struct ScoredPoint {
        var latitude: Double
        var longitude: Double
        var distanceKilometers: Double
        var zenithBrightness: Double
        var rank: Double
    }

    private static func darkPatches(field: SkyGlowField, site: Site, homeBrightness: Double,
                                    radiusKilometers: Double) -> [ScoredPoint] {
        let step = clamp(radiusKilometers / 8, 1, 5)
        let latitudeStep = step / DarkSkyGeometry.kilometersPerDegree
        let longitudeStep = step / (DarkSkyGeometry.kilometersPerDegree * max(cosDeg(site.latitude), 0.2))
        let stepsOut = Int((radiusKilometers / step).rounded(.up))

        var points: [ScoredPoint] = []
        for north in -stepsOut...stepsOut {
            for east in -stepsOut...stepsOut {
                let latitude = site.latitude + Double(north) * latitudeStep
                let longitude = site.longitude + Double(east) * longitudeStep
                let distance = DarkSkyGeometry.distanceKilometers(fromLatitude: site.latitude, longitude: site.longitude,
                                                                 toLatitude: latitude, longitude: longitude)
                guard distance <= radiusKilometers, field.contains(latitude: latitude, longitude: longitude) else { continue }
                let point = score(latitude: latitude, longitude: longitude, distance: distance, field: field)
                if point.zenithBrightness - homeBrightness >= minimumImprovement {
                    points.append(point)
                }
            }
        }

        // Greedy pick of the best points, each far enough from the ones already
        // chosen that their map searches don't just find the same parks.
        let separation = max(3, radiusKilometers / 4)
        var chosen: [ScoredPoint] = []
        for point in points.sorted(by: { $0.rank > $1.rank }) {
            guard chosen.count < maximumPatches else { break }
            let isSeparate = chosen.allSatisfy {
                DarkSkyGeometry.distanceKilometers(fromLatitude: $0.latitude, longitude: $0.longitude,
                                                   toLatitude: point.latitude, longitude: point.longitude) >= separation
            }
            if isSeparate { chosen.append(point) }
        }
        return chosen
    }

    private static func score(latitude: Double, longitude: Double, distance: Double, field: SkyGlowField) -> ScoredPoint {
        let brightness = DarkSkyEstimate.zenithBrightness(glow: field.glow(latitude: latitude, longitude: longitude))
        return ScoredPoint(latitude: latitude, longitude: longitude, distanceKilometers: distance,
                           zenithBrightness: brightness,
                           rank: brightness - distancePenaltyPerKilometer * distance)
    }

    // MARK: - Stage two: real places

    @MainActor
    private static func outdoorPlaces(near latitude: Double, _ longitude: Double, spanMeters: Double) async throws -> [(name: String, latitude: Double, longitude: Double)] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "park"
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: placeCategories)
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                            latitudinalMeters: spanMeters, longitudinalMeters: spanMeters)
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { item in
            guard let name = item.name, let category = item.pointOfInterestCategory,
                  placeCategories.contains(category) else { return nil }
            let lowercasedName = name.lowercased()
            guard !unsuitableNameFragments.contains(where: { lowercasedName.contains($0) }) else { return nil }
            let coordinate = item.placemark.coordinate
            return (name, coordinate.latitude, coordinate.longitude)
        }
    }

    private static func rankedSpots(places: [(name: String, latitude: Double, longitude: Double)],
                                    field: SkyGlowField, site: Site, homeBrightness: Double,
                                    radiusKilometers: Double) -> [DarkSpot] {
        let scored: [(DarkSpot, Double)] = places.compactMap { place in
            let distance = DarkSkyGeometry.distanceKilometers(fromLatitude: site.latitude, longitude: site.longitude,
                                                             toLatitude: place.latitude, longitude: place.longitude)
            guard distance <= radiusKilometers,
                  field.contains(latitude: place.latitude, longitude: place.longitude)
            else { return nil }
            let point = score(latitude: place.latitude, longitude: place.longitude, distance: distance, field: field)
            guard point.zenithBrightness - homeBrightness >= minimumImprovement else { return nil }

            let spot = DarkSpot(name: place.name,
                                latitude: place.latitude,
                                longitude: place.longitude,
                                distanceKilometers: distance,
                                direction: DarkSkyGeometry.compassDirection(fromLatitude: site.latitude, longitude: site.longitude,
                                                                            toLatitude: place.latitude, longitude: place.longitude),
                                zenithBrightness: point.zenithBrightness,
                                estimatedBortleClass: DarkSkyEstimate.bortleClass(forZenithBrightness: point.zenithBrightness))
            return (spot, point.rank)
        }

        var spots: [DarkSpot] = []
        for (spot, _) in scored.sorted(by: { $0.1 > $1.1 }) {
            // The same park often appears once per entrance or section.
            guard !spots.contains(where: { $0.name == spot.name }) else { continue }
            spots.append(spot)
            if spots.count == maximumSpots { break }
        }
        return spots
    }
}
