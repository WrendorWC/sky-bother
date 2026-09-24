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
        "wind_speed_10m", "wind_gusts_10m", "visibility", "precipitation_probability",
        "wind_direction_10m"
    ]

    /// Both models in one request. `best_match` is Open-Meteo's own pick —
    /// for the US that is HRRR/GFS, a single model, and on a night the models
    /// disagree it can be the most optimistic of them. The National Blend of
    /// Models is NOAA's weighted, bias-corrected blend of all of them, and
    /// what the NWS forecast starts from, so it is used wherever it exists.
    /// Outside its area (it reaches southern Canada, not Europe or Africa)
    /// the response simply has no NBM fields and `best_match` is used alone.
    static let models = ["best_match", "ncep_nbm_conus"]

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
            URLQueryItem(name: "forecast_days", value: String(min(16, max(1, days)))),
            URLQueryItem(name: "models", value: Self.models.joined(separator: ","))
        ]
        return components?.url
    }

    func fetch(latitude: Double, longitude: Double, days: Int) async throws -> WeatherForecast {
        guard let url = forecastURL(latitude: latitude, longitude: longitude, days: days) else {
            throw WeatherError.malformedData
        }

        var request = URLRequest(url: url)
        // A healthy Open-Meteo response comes back in well under a second —
        // 20s only ever gets spent sitting on a connection that's stalled or
        // dead, since there's a backup provider ready to try instead of
        // waiting that long to find out. Short enough to fail over fast,
        // long enough not to give up on a merely slow mobile/satellite link.
        request.timeoutInterval = 8
        // The URL is identical on every refresh (same site, same forecast
        // window) — revalidating against a local cache risks getting pinned
        // to a single bad response an overloaded backend served once, on
        // every "refresh" after, regardless of how many times it's pressed.
        // A live forecast should never come from a cache, full stop.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // A fresh session, not `.shared`: this client is created once and
        // lives for the app's whole run, and `.shared` pools and reuses one
        // HTTP/2 connection per host indefinitely. If the very first request
        // ever landed on one of Open-Meteo's unhealthy backend nodes, every
        // later refresh would keep getting silently pinned to that same bad
        // connection no matter how many times it's pressed. A new session
        // per call means every refresh gets its own independent attempt —
        // fresh DNS, fresh connection, a real chance at a healthy backend.
        let session = URLSession(configuration: .ephemeral)
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
        /// With more than one model requested, every series comes back
        /// suffixed with its model — `cloud_cover_best_match`,
        /// `cloud_cover_ncep_nbm_conus` — so the keys are read as they come
        /// rather than spelled out.
        struct Hourly: Decodable {
            let time: [Double]
            let series: [String: [Double?]]

            private struct Key: CodingKey {
                var stringValue: String
                var intValue: Int? { nil }
                init(stringValue: String) { self.stringValue = stringValue }
                init?(intValue: Int) { nil }
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: Key.self)
                time = try container.decode([Double].self, forKey: Key(stringValue: "time"))
                var series: [String: [Double?]] = [:]
                for key in container.allKeys where key.stringValue != "time" {
                    series[key.stringValue] = try? container.decode([Double?].self, forKey: key)
                }
                self.series = series
            }

            func value(_ variable: String, model: String, at index: Int) -> Double? {
                guard let values = series["\(variable)_\(model)"] ?? series[variable],
                      index < values.count else { return nil }
                return values[index]
            }
        }

        let timezone: String?
        let elevation: Double?
        let hourly: Hourly

        func forecast() -> WeatherForecast {
            var hours: [HourlyWeather] = []
            hours.reserveCapacity(hourly.time.count)

            for (index, stamp) in hourly.time.enumerated() {
                /// NBM where it has a value — its whole area, out to about 11
                /// days, visibility to about 3 — and `best_match` otherwise.
                /// A gap in both is filled with a neutral value rather than
                /// dropping the whole hour.
                func value(_ variable: String, fallback: Double) -> Double {
                    hourly.value(variable, model: "ncep_nbm_conus", at: index)
                        ?? hourly.value(variable, model: "best_match", at: index)
                        ?? fallback
                }
                func regular(_ variable: String) -> Double? {
                    hourly.value(variable, model: "best_match", at: index)
                }

                let total = value("cloud_cover", fallback: 50)
                let (low, mid, high) = Self.layers(total: total,
                                                   regularTotal: regular("cloud_cover"),
                                                   low: regular("cloud_cover_low"),
                                                   mid: regular("cloud_cover_mid"),
                                                   high: regular("cloud_cover_high"))
                hours.append(HourlyWeather(
                    date: Date(timeIntervalSince1970: stamp),
                    cloudCoverTotal: total,
                    cloudCoverLow: low,
                    cloudCoverMid: mid,
                    cloudCoverHigh: high,
                    temperatureCelsius: value("temperature_2m", fallback: 10),
                    dewPointCelsius: value("dew_point_2m", fallback: 5),
                    relativeHumidity: value("relative_humidity_2m", fallback: 70),
                    windSpeedKilometersPerHour: value("wind_speed_10m", fallback: 5),
                    windGustsKilometersPerHour: value("wind_gusts_10m", fallback: 10),
                    visibilityMeters: value("visibility", fallback: 20000),
                    precipitationProbability: value("precipitation_probability", fallback: 0),
                    windDirectionDegrees: hourly.value("wind_direction_10m", model: "ncep_nbm_conus", at: index)
                        ?? regular("wind_direction_10m")))
            }

            return WeatherForecast(hours: hours.sorted { $0.date < $1.date },
                                   timeZoneIdentifier: timezone ?? "UTC",
                                   elevationMeters: elevation ?? 0,
                                   retrievedAt: Date(),
                                   // Exactly this: `AppState` reads any other
                                   // source as the backup provider.
                                   source: "Open-Meteo")
        }

        /// How much cloud from one model, what kind from the other.
        ///
        /// NBM gives total cloud but no low/mid/high split, and the split is
        /// what lets thin cirrus count for less than low stratus. So the
        /// regular forecast's layers are scaled to NBM's total, keeping their
        /// mix. Where the regular forecast has no cloud to take a mix from,
        /// the total is spread evenly, as for any other missing split.
        static func layers(total: Double, regularTotal: Double?,
                           low: Double?, mid: Double?, high: Double?) -> (Double, Double, Double) {
            guard let low, let mid, let high, let regularTotal,
                  low + mid + high > 1, regularTotal > 0 else {
                return (total / 3, total / 3, total / 3)
            }
            let scale = total / regularTotal
            return (min(100, low * scale), min(100, mid * scale), min(100, high * scale))
        }
    }
}
