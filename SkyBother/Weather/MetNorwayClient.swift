import Foundation

/// Backup forecast source, used only when Open-Meteo's request fails. Also
/// free and keyless — MET Norway asks only for an identifying User-Agent,
/// the same courtesy this app already extends to Wikipedia's API — so
/// falling back to it doesn't compromise the "no account, anywhere" design.
///
/// Its wire format differs from Open-Meteo's in ways that matter here: wind
/// is in m/s, not km/h; there is no visibility figure (derived below from
/// fog fraction instead); and outside the Nordics it publishes neither wind
/// gusts nor precipitation probability, only a precipitation *amount*, which
/// is turned into a rough probability proxy rather than left at a flat
/// default regardless of forecast.
struct MetNorwayClient {

    private static let userAgent = "SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; weather fallback)"

    func forecastURL(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://api.met.no/weatherapi/locationforecast/2.0/complete")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.4f", longitude))
        ]
        return components?.url
    }

    func fetch(latitude: Double, longitude: Double) async throws -> WeatherForecast {
        guard let url = forecastURL(latitude: latitude, longitude: longitude) else {
            throw WeatherError.malformedData
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        // Same identical-URL-on-every-refresh risk as OpenMeteoClient: a
        // live forecast should never be served from a local cache.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        // Fresh session per call — see OpenMeteoClient.fetch for why
        // `.shared`'s indefinite connection reuse is a real problem here.
        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WeatherError.badResponse(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw WeatherError.malformedData
        }

        return payload.forecast()
    }

    // MARK: - Wire format

    private struct Payload: Decodable {
        struct Geometry: Decodable {
            let coordinates: [Double]
        }

        struct TimeseriesEntry: Decodable {
            struct Data: Decodable {
                struct Instant: Decodable {
                    struct Details: Decodable {
                        let airTemperature: Double?
                        let dewPointTemperature: Double?
                        let relativeHumidity: Double?
                        let cloudAreaFraction: Double?
                        let cloudAreaFractionLow: Double?
                        let cloudAreaFractionMedium: Double?
                        let cloudAreaFractionHigh: Double?
                        let fogAreaFraction: Double?
                        let windSpeed: Double?
                        let windSpeedOfGust: Double?

                        enum CodingKeys: String, CodingKey {
                            case airTemperature = "air_temperature"
                            case dewPointTemperature = "dew_point_temperature"
                            case relativeHumidity = "relative_humidity"
                            case cloudAreaFraction = "cloud_area_fraction"
                            case cloudAreaFractionLow = "cloud_area_fraction_low"
                            case cloudAreaFractionMedium = "cloud_area_fraction_medium"
                            case cloudAreaFractionHigh = "cloud_area_fraction_high"
                            case fogAreaFraction = "fog_area_fraction"
                            case windSpeed = "wind_speed"
                            case windSpeedOfGust = "wind_speed_of_gust"
                        }
                    }
                    let details: Details
                }

                struct NextHours: Decodable {
                    struct Details: Decodable {
                        let precipitationAmount: Double?
                        enum CodingKeys: String, CodingKey {
                            case precipitationAmount = "precipitation_amount"
                        }
                    }
                    let details: Details?
                }

                let instant: Instant
                let next1Hours: NextHours?
                let next6Hours: NextHours?

                enum CodingKeys: String, CodingKey {
                    case instant
                    case next1Hours = "next_1_hours"
                    case next6Hours = "next_6_hours"
                }
            }

            let time: Date
            let data: Data
        }

        struct Properties: Decodable {
            let timeseries: [TimeseriesEntry]
        }

        let geometry: Geometry
        let properties: Properties

        func forecast() -> WeatherForecast {
            var hours: [HourlyWeather] = []
            hours.reserveCapacity(properties.timeseries.count)

            for entry in properties.timeseries {
                let details = entry.data.instant.details
                let total = details.cloudAreaFraction ?? 50
                let fog = details.fogAreaFraction ?? 0
                let windSpeedKmh = (details.windSpeed ?? 1.4) * 3.6
                let gustKmh = details.windSpeedOfGust.map { $0 * 3.6 } ?? windSpeedKmh * 1.4

                let precipitationAmount = entry.data.next1Hours?.details?.precipitationAmount
                    ?? entry.data.next6Hours?.details?.precipitationAmount ?? 0
                let precipitationProbability = precipitationAmount <= 0
                    ? 0 : clamp(precipitationAmount * 40, 5, 100)

                hours.append(HourlyWeather(
                    date: entry.time,
                    cloudCoverTotal: total,
                    cloudCoverLow: details.cloudAreaFractionLow ?? total / 3,
                    cloudCoverMid: details.cloudAreaFractionMedium ?? total / 3,
                    cloudCoverHigh: details.cloudAreaFractionHigh ?? total / 3,
                    temperatureCelsius: details.airTemperature ?? 10,
                    dewPointCelsius: details.dewPointTemperature ?? 5,
                    relativeHumidity: details.relativeHumidity ?? 70,
                    windSpeedKilometersPerHour: windSpeedKmh,
                    windGustsKilometersPerHour: gustKmh,
                    // No visibility figure is published; fog fraction stands in.
                    visibilityMeters: clamp(20000 * (1 - fog / 100), 1000, 20000),
                    precipitationProbability: precipitationProbability))
            }

            return WeatherForecast(hours: hours.sorted { $0.date < $1.date },
                                   timeZoneIdentifier: "UTC",
                                   elevationMeters: geometry.coordinates.count > 2 ? geometry.coordinates[2] : 0,
                                   retrievedAt: Date(),
                                   source: "MET Norway")
        }
    }
}
