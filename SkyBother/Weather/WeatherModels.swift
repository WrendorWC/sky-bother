import Foundation

/// One hour of forecast, plus the derived quantities that actually matter for
/// imaging. Open-Meteo gives raw meteorology; the interpretation is ours.
struct HourlyWeather: Codable, Hashable, Identifiable, Sendable {
    var date: Date
    var cloudCoverTotal: Double
    var cloudCoverLow: Double
    var cloudCoverMid: Double
    var cloudCoverHigh: Double
    var temperatureCelsius: Double
    var dewPointCelsius: Double
    var relativeHumidity: Double
    var windSpeedKilometersPerHour: Double
    var windGustsKilometersPerHour: Double
    var visibilityMeters: Double
    var precipitationProbability: Double

    var id: Date { date }

    /// Total cloud cover weighted by how much each layer actually hurts. High
    /// cirrus at 60% is a far better night than low stratus at 60%, so the total
    /// (which already accounts for layer overlap) is scaled by the severity of
    /// the mix rather than by summing layers, which would double-count.
    var effectiveCloudCover: Double {
        let layerSum = cloudCoverLow + cloudCoverMid + cloudCoverHigh
        guard layerSum > 1 else { return cloudCoverTotal }
        let severity = (cloudCoverLow * 1.0 + cloudCoverMid * 0.85 + cloudCoverHigh * 0.5) / layerSum
        return clamp(cloudCoverTotal * severity, 0, 100)
    }

    /// 1 = clear, 0 = overcast.
    var clearFactor: Double {
        clamp(1 - effectiveCloudCover / 100, 0, 1)
    }

    /// Rough transparency proxy from humidity and reported visibility. Real
    /// transparency depends on aerosols aloft, which no free forecast exposes.
    var transparency: Double {
        let humidityTerm = clamp(1 - (relativeHumidity - 55) / 55, 0.25, 1)
        let visibilityTerm = clamp(visibilityMeters / 24000, 0.4, 1)
        return clamp(humidityTerm * visibilityTerm, 0.2, 1)
    }

    /// Rough seeing proxy from surface gusts. This only captures ground-level
    /// turbulence, not the jet stream, so treat it as a hint, not a forecast.
    var seeing: Double {
        clamp(1 - windGustsKilometersPerHour / 45, 0.15, 1)
    }

    /// Temperature minus dew point. Below a couple of degrees expect dew or
    /// frost on the corrector plate.
    var dewPointSpread: Double { temperatureCelsius - dewPointCelsius }

    var isPrecipitationLikely: Bool { precipitationProbability >= 40 }
}

struct WeatherForecast: Codable, Hashable, Sendable {
    var hours: [HourlyWeather]
    var timeZoneIdentifier: String
    var elevationMeters: Double
    var retrievedAt: Date

    static let empty = WeatherForecast(hours: [], timeZoneIdentifier: TimeZone.current.identifier,
                                       elevationMeters: 0, retrievedAt: .distantPast)

    var isEmpty: Bool { hours.isEmpty }

    var coveredRange: TimeWindow? {
        guard let first = hours.first, let last = hours.last else { return nil }
        return TimeWindow(start: first.date, end: last.date.addingTimeInterval(3600))
    }

    /// Linear interpolation between the bracketing hours. Returns nil when the
    /// date falls outside the forecast, which is how the planner knows to mark a
    /// night "beyond the forecast" instead of inventing clear skies.
    func interpolated(at date: Date) -> HourlyWeather? {
        guard !hours.isEmpty else { return nil }
        if date <= hours[0].date { return date >= hours[0].date.addingTimeInterval(-3600) ? hours[0] : nil }
        guard let last = hours.last else { return nil }
        if date >= last.date { return date <= last.date.addingTimeInterval(3600) ? last : nil }

        var low = 0
        var high = hours.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if hours[middle].date <= date { low = middle } else { high = middle }
        }

        let a = hours[low]
        let b = hours[high]
        let span = b.date.timeIntervalSince(a.date)
        guard span > 0 else { return a }
        let t = clamp(date.timeIntervalSince(a.date) / span, 0, 1)
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }

        return HourlyWeather(date: date,
                             cloudCoverTotal: mix(a.cloudCoverTotal, b.cloudCoverTotal),
                             cloudCoverLow: mix(a.cloudCoverLow, b.cloudCoverLow),
                             cloudCoverMid: mix(a.cloudCoverMid, b.cloudCoverMid),
                             cloudCoverHigh: mix(a.cloudCoverHigh, b.cloudCoverHigh),
                             temperatureCelsius: mix(a.temperatureCelsius, b.temperatureCelsius),
                             dewPointCelsius: mix(a.dewPointCelsius, b.dewPointCelsius),
                             relativeHumidity: mix(a.relativeHumidity, b.relativeHumidity),
                             windSpeedKilometersPerHour: mix(a.windSpeedKilometersPerHour, b.windSpeedKilometersPerHour),
                             windGustsKilometersPerHour: mix(a.windGustsKilometersPerHour, b.windGustsKilometersPerHour),
                             visibilityMeters: mix(a.visibilityMeters, b.visibilityMeters),
                             precipitationProbability: mix(a.precipitationProbability, b.precipitationProbability))
    }
}
