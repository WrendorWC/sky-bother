import Foundation

enum WeatherError: LocalizedError {
    case badResponse(Int)
    case serviceError(String)
    case malformedData

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "Weather service returned HTTP \(code)."
        case .serviceError(let reason): return "Weather service error: \(reason)"
        case .malformedData: return "The weather response could not be read."
        }
    }
}

/// Open-Meteo forecast client. No API key, no account, no rate limit worth
/// worrying about at one call per location per refresh.
///
/// Times are requested as Unix timestamps rather than local ISO strings so that
/// nothing depends on parsing a naive datetime in the right zone.
struct OpenMeteoClient {

    static let hourlyVariables = [
        "cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high",
        "temperature_2m", "dew_point_2m", "relative_humidity_2m",
        "wind_speed_10m", "wind_gusts_10m", "visibility", "precipitation_probability"
    ]

    var session: URLSession = .shared

    func forecastURL(latitude: Double, longitude: Double, days: Int) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "hourly", value: Self.hourlyVariables.joined(separator: ",")),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "forecast_days", value: String(min(16, max(1, days))))
        ]
        return components?.url
    }

    func fetch(latitude: Double, longitude: Double, days: Int) async throws -> WeatherForecast {
        guard let url = forecastURL(latitude: latitude, longitude: longitude, days: days) else {
            throw WeatherError.malformedData
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadRevalidatingCacheData

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // Open-Meteo puts a human-readable reason in the body on 4xx.
            if let failure = try? JSONDecoder().decode(ServiceFailure.self, from: data) {
                throw WeatherError.serviceError(failure.reason)
            }
            throw WeatherError.badResponse(http.statusCode)
        }

        // `Hourly` now spells out every key explicitly (see its CodingKeys) —
        // `.convertFromSnakeCase` would fight those exact raw values instead of
        // the property names, breaking every field, not just the ones it
        // already couldn't handle. `Payload`'s own keys (timezone, elevation,
        // hourly) have no underscores, so they don't need a strategy either.
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw WeatherError.malformedData
        }

        return payload.forecast()
    }

    // MARK: - Wire format

    private struct ServiceFailure: Decodable {
        let reason: String
    }

    private struct Payload: Decodable {
        struct Hourly: Decodable {
            let time: [Double]
            let cloudCover: [Double?]?
            let cloudCoverLow: [Double?]?
            let cloudCoverMid: [Double?]?
            let cloudCoverHigh: [Double?]?
            let temperature2m: [Double?]?
            let dewPoint2m: [Double?]?
            let relativeHumidity2m: [Double?]?
            let windSpeed10m: [Double?]?
            let windGusts10m: [Double?]?
            let visibility: [Double?]?
            let precipitationProbability: [Double?]?

            // `.convertFromSnakeCase` cannot see the word boundary in
            // "temperature_2m" — the digit right after the underscore breaks
            // its heuristic, so it silently fails to match these five keys and
            // every field falls back to its default (temperature pinned at
            // 10°C, wind gusts at 10 km/h, etc.) regardless of the real
            // forecast. Spelling the keys out here is the fix.
            enum CodingKeys: String, CodingKey {
                case time
                case cloudCover = "cloud_cover"
                case cloudCoverLow = "cloud_cover_low"
                case cloudCoverMid = "cloud_cover_mid"
                case cloudCoverHigh = "cloud_cover_high"
                case temperature2m = "temperature_2m"
                case dewPoint2m = "dew_point_2m"
                case relativeHumidity2m = "relative_humidity_2m"
                case windSpeed10m = "wind_speed_10m"
                case windGusts10m = "wind_gusts_10m"
                case visibility
                case precipitationProbability = "precipitation_probability"
            }
        }

        let timezone: String?
        let elevation: Double?
        let hourly: Hourly

        func forecast() -> WeatherForecast {
            /// Missing samples are common at the far end of a forecast; a nil is
            /// filled with a neutral value rather than dropping the whole hour.
            func value(_ array: [Double?]?, _ index: Int, fallback: Double) -> Double {
                guard let array, index < array.count, let v = array[index] else { return fallback }
                return v
            }

            var hours: [HourlyWeather] = []
            hours.reserveCapacity(hourly.time.count)

            for (index, stamp) in hourly.time.enumerated() {
                let total = value(hourly.cloudCover, index, fallback: 50)
                hours.append(HourlyWeather(
                    date: Date(timeIntervalSince1970: stamp),
                    cloudCoverTotal: total,
                    cloudCoverLow: value(hourly.cloudCoverLow, index, fallback: total / 3),
                    cloudCoverMid: value(hourly.cloudCoverMid, index, fallback: total / 3),
                    cloudCoverHigh: value(hourly.cloudCoverHigh, index, fallback: total / 3),
                    temperatureCelsius: value(hourly.temperature2m, index, fallback: 10),
                    dewPointCelsius: value(hourly.dewPoint2m, index, fallback: 5),
                    relativeHumidity: value(hourly.relativeHumidity2m, index, fallback: 70),
                    windSpeedKilometersPerHour: value(hourly.windSpeed10m, index, fallback: 5),
                    windGustsKilometersPerHour: value(hourly.windGusts10m, index, fallback: 10),
                    visibilityMeters: value(hourly.visibility, index, fallback: 20000),
                    precipitationProbability: value(hourly.precipitationProbability, index, fallback: 0)))
            }

            return WeatherForecast(hours: hours.sorted { $0.date < $1.date },
                                   timeZoneIdentifier: timezone ?? "UTC",
                                   elevationMeters: elevation ?? 0,
                                   retrievedAt: Date(),
                                   source: "Open-Meteo")
        }
    }
}
