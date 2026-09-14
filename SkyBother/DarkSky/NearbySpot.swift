import Foundation

/// What a nearby spot is meant to improve on.
enum SpotGoal: String, CaseIterable, Identifiable, Sendable {
    /// Less light pollution — worth a drive of tens of miles.
    case darkerSky
    /// Fewer trees and buildings in the way — usually just a few minutes away.
    case openHorizon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .darkerSky: return "Darker sky"
        case .openHorizon: return "Open horizon"
        }
    }
}

enum NearbySpotError: LocalizedError {
    case placeSearchUnavailable

    var errorDescription: String? {
        switch self {
        case .placeSearchUnavailable: return "Apple Maps place search isn't answering right now. Try again in a minute."
        }
    }
}

/// A real, named place nearby that should be a better place to observe from.
struct NearbySpot: Identifiable, Hashable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
    var distanceKilometers: Double
    /// Compass direction from the site searched around, e.g. "NE".
    var direction: String
    var zenithBrightness: Double
    var estimatedBortleClass: Int
    /// Estimated blocked horizon in degrees, when land cover was checked.
    var horizonAltitude: Double?
    /// The most open 90° of sky from here, e.g. "S", when land cover was checked.
    var clearestDirection: String?
    /// The place's own website, from Apple Maps.
    var website: URL?

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

struct NearbySpotSearchResult: Sendable {
    var goal: SpotGoal
    /// The site searched around, as it was when the search ran.
    var anchor: Site
    var radiusKilometers: Double
    /// The model's own sky estimate for the site searched around, independent
    /// of the Bortle class set for it by hand.
    var siteZenithBrightness: Double
    var siteEstimatedBortleClass: Int
    /// Every place found that's noticeably better than the site, unranked.
    var candidates: [NearbySpot]
    /// What to suggest, per `NearbySpotSelection`: best first, then closer
    /// alternatives. Empty means nothing within range is noticeably better.
    var spots: [NearbySpot]

    init(goal: SpotGoal, anchor: Site, radiusKilometers: Double, siteZenithBrightness: Double,
         siteEstimatedBortleClass: Int, candidates: [NearbySpot]) {
        self.goal = goal
        self.anchor = anchor
        self.radiusKilometers = radiusKilometers
        self.siteZenithBrightness = siteZenithBrightness
        self.siteEstimatedBortleClass = siteEstimatedBortleClass
        self.candidates = candidates
        self.spots = NearbySpotSelection.recommend(candidates, goal: goal)
    }

    /// The same search widened to also consider what shorter searches found,
    /// so a longer distance never passes over a closer spot that's just as good.
    func including(_ others: [NearbySpotSearchResult]) -> NearbySpotSearchResult {
        let extra = others.flatMap(\.candidates).filter { $0.distanceKilometers <= radiusKilometers }
        return NearbySpotSearchResult(goal: goal, anchor: anchor, radiusKilometers: radiusKilometers,
                                      siteZenithBrightness: siteZenithBrightness,
                                      siteEstimatedBortleClass: siteEstimatedBortleClass,
                                      candidates: candidates + extra)
    }
}
