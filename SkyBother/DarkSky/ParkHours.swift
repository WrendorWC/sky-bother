import Foundation

/// A place's posted opening hours, reduced to the one thing that matters here:
/// when it closes for the night.
struct PostedHours: Hashable, Sendable {
    enum Closing: Hashable, Sendable {
        /// Open around the clock.
        case never
        /// Closes at sunset or dusk — before it's dark enough to observe.
        case sunset
        /// Closes at a fixed local time, or runs past midnight if `crossesMidnight`.
        case time(hour: Int, minute: Int, crossesMidnight: Bool)
    }

    var closing: Closing
    /// The tag exactly as mapped, for the tooltip.
    var raw: String

    /// Parses the common, unambiguous forms of OpenStreetMap's `opening_hours`
    /// — "24/7", "sunrise-sunset", "dawn-dusk", "08:00-22:00", "Mo-Su 07:00-20:00",
    /// "08:00-sunset". Anything that varies by day or season, or has several
    /// rules, returns nil: a label that's right on Tuesdays and wrong on
    /// Saturdays is worse than no label, and the panel already tells people to
    /// check before they go.
    init?(openingHours: String) {
        let value = openingHours.trimmingCharacters(in: .whitespaces).lowercased()
        raw = openingHours
        if value == "24/7" || value == "mo-su 00:00-24:00" || value == "00:00-24:00" {
            closing = .never
            return
        }
        guard !value.contains(";"), !value.contains(","), !value.contains("off") else { return nil }

        var times = value
        for everyDay in ["mo-su ", "daily "] where times.hasPrefix(everyDay) {
            times = String(times.dropFirst(everyDay.count))
        }
        // Any other day or month prefix means the hours vary.
        guard times.first?.isNumber == true || times.hasPrefix("sunrise") || times.hasPrefix("dawn") else { return nil }

        let parts = times.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        let end = parts[1]
        if ["sunset", "dusk"].contains(end) {
            closing = .sunset
            return
        }
        guard let endTime = Self.clockTime(end) else { return nil }
        if endTime.hour == 24 && endTime.minute == 0, let start = Self.clockTime(parts[0]), start.hour == 0, start.minute == 0 {
            closing = .never
            return
        }
        let startTime = Self.clockTime(parts[0])
        let crossesMidnight = endTime.hour == 24
            || (startTime.map { endTime.hour * 60 + endTime.minute <= $0.hour * 60 + $0.minute } ?? false)
        closing = .time(hour: endTime.hour % 24, minute: endTime.minute, crossesMidnight: crossesMidnight)
    }

    private static func clockTime(_ text: String) -> (hour: Int, minute: Int)? {
        let pieces = text.split(separator: ":")
        guard pieces.count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]),
              (0...24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }
}

/// What OpenStreetMap knows about a place that Apple Maps doesn't expose to
/// apps: posted hours, and sometimes a website when Apple Maps has none.
struct ParkInfo: Hashable, Sendable {
    var hours: PostedHours?
    var website: URL?
}

/// Looks up a spot in OpenStreetMap through the public Overpass API — free,
/// no key; data © OpenStreetMap contributors, ODbL.
///
/// Hours are only mapped for a minority of parks (about one in eight around
/// Tampa Bay), so a miss is the normal case and simply means no label. Any
/// failure is silent for the same reason: this adds a detail when it's
/// known, and the spot is just as usable without it.
actor ParkHoursClient {

    private static let userAgent = "SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; park hours)"
    /// A spot's coordinates can be the open patch rather than the park's own
    /// pin, up to a couple of hundred metres away.
    private static let searchRadiusMeters = 400

    /// `.some(nil)` marks a spot known to have nothing mapped.
    private var cache: [String: ParkInfo?] = [:]

    func info(for spot: NearbySpot) async -> ParkInfo? {
        if let cached = cache[spot.id] { return cached }
        // The public Overpass server is busy and often turns requests away;
        // one retry covers most of that. Only a real answer — including "this
        // place has nothing mapped" — is cached, so a failed lookup gets
        // another try the next time the spot is shown.
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 3_000_000_000) }
            guard !Task.isCancelled else { return nil }
            if let answer = await Self.lookup(name: spot.name, latitude: spot.latitude, longitude: spot.longitude) {
                cache[spot.id] = .some(answer)
                return answer
            }
        }
        return nil
    }

    /// nil means the lookup itself failed; `.some(nil)` means it worked and
    /// found nothing useful.
    private static func lookup(name: String, latitude: Double, longitude: Double) async -> ParkInfo?? {
        let around = String(format: "around:%d,%.6f,%.6f", searchRadiusMeters, latitude, longitude)
        let query = "[out:json][timeout:10];("
            + "nwr(\(around))[\"leisure\"][\"name\"];"
            + "nwr(\(around))[\"tourism\"][\"name\"];"
            + "nwr(\(around))[\"boundary\"=\"protected_area\"][\"name\"];"
            + ");out tags center;"
        guard var components = URLComponents(string: "https://overpass-api.de/api/interpreter") else { return nil }
        components.queryItems = [URLQueryItem(name: "data", value: query)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(OverpassResponse.self, from: data)
        else { return nil }

        let wanted = normalized(name)
        let matches = decoded.elements.compactMap { element -> (tags: [String: String], distance: Double)? in
            guard let tags = element.tags, let candidate = tags["name"], namesMatch(normalized(candidate), wanted),
                  let point = element.center ?? element.point
            else { return nil }
            let distance = DarkSkyGeometry.distanceKilometers(fromLatitude: latitude, longitude: longitude,
                                                             toLatitude: point.lat, longitude: point.lon)
            return (tags, distance)
        }
        // Prefer a match that actually carries hours, then the nearest.
        guard let best = matches.min(by: { lhs, rhs in
            let lhsHasHours = lhs.tags["opening_hours"] != nil
            let rhsHasHours = rhs.tags["opening_hours"] != nil
            if lhsHasHours != rhsHasHours { return lhsHasHours }
            return lhs.distance < rhs.distance
        }) else { return .some(nil) }

        let hours = best.tags["opening_hours"].flatMap(PostedHours.init(openingHours:))
        let website = (best.tags["website"] ?? best.tags["contact:website"]).flatMap { URL(string: $0) }
        guard hours != nil || website != nil else { return .some(nil) }
        return ParkInfo(hours: hours, website: website)
    }

    /// Words that say what kind of place it is rather than which one — two
    /// different parks share "park", so it can't count toward a match.
    private static let genericWords: Set<String> = ["the", "of", "and", "at", "park", "parks", "preserve", "reserve",
                                                    "recreation", "recreational", "area", "state", "county", "regional",
                                                    "community", "district", "wilderness", "nature", "public"]

    private static func normalized(_ name: String) -> Set<String> {
        Set(name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !genericWords.contains($0) })
    }

    /// Apple Maps and OpenStreetMap often word the same park slightly
    /// differently ("Cypress Creek Preserve" / "Cypress Creek Conservation
    /// Area"), so match on the distinctive words they share rather than exact
    /// strings — and only within a few hundred metres, which rules out most
    /// coincidences.
    private static func namesMatch(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        let shared = lhs.intersection(rhs).count
        return Double(shared) / Double(min(lhs.count, rhs.count)) >= 0.8
    }

    private struct OverpassResponse: Decodable {
        struct Element: Decodable {
            struct Point: Decodable { var lat: Double; var lon: Double }
            var tags: [String: String]?
            var center: Point?
            var lat: Double?
            var lon: Double?
            var point: Point? { lat.flatMap { lat in lon.map { Point(lat: lat, lon: $0) } } }
        }
        var elements: [Element]
    }
}
