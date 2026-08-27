import Foundation

/// The thresholds that decide what counts as a usable night. These are the knobs
/// worth arguing with — everything else in the planner is derived.
struct Preferences: Codable, Hashable, Sendable {
    /// Cloud cover percentage above which an hour is written off.
    var maximumCloudCover: Double = 35
    /// How much total integration you want on a target before calling it a
    /// session. Drives the "enough time?" factor in the score.
    var integrationGoalMinutes: Double = 120
    /// How dark the sky must get before an interval counts as usable, 0...1,
    /// measured from the Sun alone. 1.0 is full astronomical darkness (-18°),
    /// 0.5 is about -13.5°, 0.35 is roughly nautical twilight.
    ///
    /// Moonlight deliberately does not gate this. A bright moon costs you image
    /// quality, not clock time, so it is scored as a quality penalty per target
    /// instead — otherwise a dual-band filter would appear to create hours out
    /// of nothing, and the night's hours would differ per target.
    var minimumDarkness: Double = 0.5
    /// How many nights ahead to plan. Open-Meteo forecasts up to 16 days but is
    /// only meaningfully accurate for about a week.
    var forecastNights: Int = 7
    /// Hide targets whose score falls below this.
    var minimumScore: Double = 15
    /// Only show targets that clear the horizon by this much. Separate from the
    /// site's horizon obstruction: this is about air mass, not trees.
    var minimumUsefulAltitude: Double = 30
    /// Include targets that need a mosaic on the current rig.
    var includeOversizedTargets: Bool = true
    /// Include star clusters, which some people don't count as targets.
    var includeStarClusters: Bool = true
    /// Warn when the temperature/dew-point spread falls below this many degrees C.
    var dewWarningSpread: Double = 2.5
    /// Show temperatures in Fahrenheit and wind in mph.
    var usesImperialUnits: Bool = false

    static let `default` = Preferences()
}

extension Preferences {
    /// Display units only; every stored value is metric.
    var temperatureUnit: UnitTemperature { usesImperialUnits ? .fahrenheit : .celsius }
}
