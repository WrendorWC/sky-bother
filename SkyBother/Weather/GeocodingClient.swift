import Foundation

struct GeocodingResult: Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var latitude: Double
    var longitude: Double
    var elevationMeters: Double
    var timeZoneIdentifier: String
    var country: String?
    var admin1: String?

    /// "Cambridge, Massachusetts, United States"
    var subtitle: String {
        [admin1, country].compactMap { $0 }.joined(separator: ", ")
    }

    func makeSite(bortleClass: Int, horizonAltitude: Double) -> Site {
        Site(name: name,
             latitude: latitude,
             longitude: longitude,
             elevationMeters: elevationMeters,
             timeZoneIdentifier: timeZoneIdentifier,
             bortleClass: bortleClass,
             horizonAltitude: horizonAltitude)
    }
}

/// Place-name search, also from Open-Meteo, also key-free.
struct GeocodingClient {
    var session: URLSession = .shared

    func search(_ query: String) async throws -> [GeocodingResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WeatherError.badResponse(http.statusCode)
        }

        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw WeatherError.malformedData
        }

        return (payload.results ?? []).map {
            GeocodingResult(id: $0.id,
                            name: $0.name,
                            latitude: $0.latitude,
                            longitude: $0.longitude,
                            elevationMeters: $0.elevation ?? 0,
                            timeZoneIdentifier: $0.timezone ?? TimeZone.current.identifier,
                            country: $0.country,
                            admin1: $0.admin1)
        }
    }

    private struct Payload: Decodable {
        struct Entry: Decodable {
            let id: Int
            let name: String
            let latitude: Double
            let longitude: Double
            let elevation: Double?
            let timezone: String?
            let country: String?
            let admin1: String?
        }
        let results: [Entry]?
    }
}
