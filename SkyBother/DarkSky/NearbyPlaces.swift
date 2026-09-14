import Foundation
import MapKit

/// A named public place from Apple Maps.
struct NearbyPlace: Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
}

/// Apple Maps search for public outdoor places — somewhere you can actually
/// turn up at night with a tripod. MapKit's search needs no API key, but returns
/// only a couple of dozen results per request, favouring the best-known places,
/// so callers aim several small searches rather than one big one. It also
/// throttles an app that searches too often, which is why every caller treats
/// "all searches failed" as an error rather than as "nothing here".
enum NearbyPlaceSearch {

    enum Query: String {
        case parks = "park"
        /// Boat ramps and landings are often the most open public ground on a
        /// lake or river — a clear sweep of sky over the water — and Apple Maps
        /// rarely files them under any category.
        case boatRamps = "boat ramp"
    }

    private static let categories: [MKPointOfInterestCategory] = [.park, .nationalPark, .campground, .beach, .marina]
    /// Apple Maps files these under "park", but they're small, usually lit,
    /// and rarely somewhere you can set up a tripod after dark.
    private static let unsuitableNameFragments = ["dog park", "playground", "skate", "splash", "water park",
                                                  "rv park", "ballpark", "sports complex", "athletic"]
    private static let rampNameFragments = ["ramp", "launch", "landing"]
    /// Unnamed map features come back titled with just their category, which
    /// tells someone nothing about where to drive.
    private static let genericNames: Set<String> = ["park", "beach", "marina", "campground", "boat ramp", "boat launch"]

    @MainActor
    static func places(_ query: Query, near latitude: Double, _ longitude: Double, spanMeters: Double) async throws -> [NearbyPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.rawValue
        request.resultTypes = .pointOfInterest
        if query == .parks {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        }
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                            latitudinalMeters: spanMeters, longitudinalMeters: spanMeters)
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            let lowercasedName = name.lowercased()
            guard !genericNames.contains(lowercasedName.trimmingCharacters(in: .whitespaces)) else { return nil }
            switch query {
            case .parks:
                guard let category = item.pointOfInterestCategory, categories.contains(category) else { return nil }
            case .boatRamps:
                guard rampNameFragments.contains(where: { lowercasedName.contains($0) }) else { return nil }
            }
            guard !unsuitableNameFragments.contains(where: { lowercasedName.contains($0) }) else { return nil }
            let coordinate = item.placemark.coordinate
            return NearbyPlace(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }

    /// Runs several searches, merging duplicates. Throws only if every search
    /// failed, so one throttled request doesn't sink the rest.
    @MainActor
    static func places(for searches: [(query: Query, latitude: Double, longitude: Double, spanMeters: Double)]) async throws -> [NearbyPlace] {
        var merged: [NearbyPlace] = []
        var failures = 0
        for search in searches {
            try Task.checkCancellation()
            let found: [NearbyPlace]
            do {
                found = try await places(search.query, near: search.latitude, search.longitude, spanMeters: search.spanMeters)
            } catch {
                failures += 1
                continue
            }
            for place in found where !merged.contains(where: {
                $0.name == place.name && abs($0.latitude - place.latitude) < 0.01 && abs($0.longitude - place.longitude) < 0.01
            }) {
                merged.append(place)
            }
        }
        if !searches.isEmpty && failures == searches.count { throw NearbySpotError.placeSearchUnavailable }
        return merged
    }
}
