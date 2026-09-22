import Foundation

/// How likely the optics are to dew over — an estimate, not a prediction.
///
/// Built on the temperature/dew-point spread, because that is what the
/// forecast actually gives and what dew actually depends on. The one
/// correction on top of it is for radiative cooling: under a clear, calm sky
/// a telescope loses heat to space and sits below the air around it, so it
/// can dew over while the reported temperature is still several degrees
/// above the dew point. Waiting for the spread to reach zero before warning
/// would be warning too late.
enum DewRiskLevel: Int, Comparable, CaseIterable, Sendable {
    case low, moderate, high, veryHigh

    static func < (lhs: DewRiskLevel, rhs: DewRiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var name: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .veryHigh: return "Very High"
        }
    }

    var advice: String {
        switch self {
        case .low: return "Dew heater probably unnecessary"
        case .moderate: return "Monitor optics; dew protection may be useful"
        case .high, .veryHigh: return "Dew heater recommended"
        }
    }

    /// One step worse, stopping at the top.
    var raised: DewRiskLevel { DewRiskLevel(rawValue: min(rawValue + 1, DewRiskLevel.veryHigh.rawValue)) ?? .veryHigh }
}

/// What the risk is judged from at one moment.
///
/// Everything the model knows goes through here, so this is where a later
/// version would add what it doesn't yet: whether the rig has an exposed
/// corrector or a built-in heater and at what setting, the ground under the
/// tripod, the local terrain, or a sensor at the site.
struct DewConditions: Sendable {
    var spreadCelsius: Double
    /// Effective cloud cover, 0–100 — the same weighting the rest of the app
    /// uses, where thin high cloud counts for less than low cloud.
    var cloudCover: Double
    var windKilometersPerHour: Double
}

enum DewRisk {
    // The bands, as spreads in °F — how they are usually quoted — kept in
    // Celsius because that is what the forecast arrives in.
    static let lowAbove = fahrenheitSpread(10)
    static let moderateAbove = fahrenheitSpread(6)
    static let highAbove = fahrenheitSpread(3)

    /// Mostly clear, and near-still air (about 5 mph): the two things that
    /// let a telescope radiate its heat away faster than the air replaces it.
    /// Either one missing — cloud to reflect the heat back, or a breeze to
    /// keep the tube at ambient — and there is no extra step.
    static let clearBelowCloudCover = 30.0
    static let calmBelowKilometersPerHour = 8.0

    private static func fahrenheitSpread(_ degrees: Double) -> Double { degrees * 5 / 9 }

    static func baseLevel(spreadCelsius spread: Double) -> DewRiskLevel {
        if spread > lowAbove { return .low }
        if spread > moderateAbove { return .moderate }
        if spread > highAbove { return .high }
        return .veryHigh
    }

    static func favoursRadiativeCooling(_ conditions: DewConditions) -> Bool {
        conditions.cloudCover < clearBelowCloudCover
            && conditions.windKilometersPerHour < calmBelowKilometersPerHour
    }

    /// Only ever raises the base level, never lowers it: cloud and wind
    /// withhold the extra step, but a spread of a couple of degrees is very
    /// high risk whatever the sky is doing.
    static func level(for conditions: DewConditions) -> DewRiskLevel {
        let base = baseLevel(spreadCelsius: conditions.spreadCelsius)
        return favoursRadiativeCooling(conditions) ? base.raised : base
    }

    static func conditions(of sample: NightSample) -> DewConditions? {
        guard sample.hasWeather, sample.dewSpread.isFinite, sample.windSpeed.isFinite else { return nil }
        return DewConditions(spreadCelsius: sample.dewSpread,
                             cloudCover: sample.cloudCover,
                             windKilometersPerHour: sample.windSpeed)
    }

    static func level(of sample: NightSample) -> DewRiskLevel? {
        conditions(of: sample).map(level(for:))
    }

    /// The session's rating: the worst it gets between `window.start` and
    /// `window.end`, when that starts, and the tightest spread.
    struct Assessment: Sendable {
        var level: DewRiskLevel
        /// When the worst level is first reached, and last seen.
        var peakStart: Date
        var peakEnd: Date
        /// True when every moment of the session is at the worst level.
        var isWorstThroughout: Bool
        /// True when the worst level comes from the clear, calm sky rather
        /// than from the spread alone — worth saying, since it is the case
        /// where the air temperature looks safe.
        var peakIsRadiative: Bool
        var spreadAtPeak: Double
        var minimumSpread: Double
        var minimumSpreadTime: Date
        var sessionStart: Date
    }

    static func assess(samples: [NightSample], over window: TimeWindow) -> Assessment? {
        let rated = samples
            .filter { $0.date >= window.start && $0.date <= window.end }
            .compactMap { sample in conditions(of: sample).map { (sample, $0, level(for: $0)) } }
        guard let worst = rated.map(\.2).max(),
              let peak = rated.first(where: { $0.2 == worst }),
              let lastPeak = rated.last(where: { $0.2 == worst }),
              let tightest = rated.min(by: { $0.1.spreadCelsius < $1.1.spreadCelsius })
        else { return nil }
        return Assessment(level: worst,
                          peakStart: peak.0.date,
                          peakEnd: lastPeak.0.date,
                          isWorstThroughout: rated.allSatisfy { $0.2 == worst },
                          peakIsRadiative: baseLevel(spreadCelsius: peak.1.spreadCelsius) < worst,
                          spreadAtPeak: peak.1.spreadCelsius,
                          minimumSpread: tightest.1.spreadCelsius,
                          minimumSpreadTime: tightest.0.date,
                          sessionStart: window.start)
    }
}
