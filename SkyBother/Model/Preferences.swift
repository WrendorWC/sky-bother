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
    /// Whether to mark zenith-risk spans (Sky View's amber path, the
    /// segmented time bar, ranked-row and Tonight's Plan warning triangles).
    /// Already irrelevant for an equatorial mount — `Planner` only ever
    /// computes a zenith-risk window for an alt-az rig in the first place —
    /// this is for turning it off even on one, if it's just noise to you.
    var showsZenithRiskWarnings: Bool = true
    /// Multiplies every font size in the app, 1.0 being what it's always
    /// been. Exists for high-resolution displays where the default point
    /// sizes read as genuinely small — a "more space" scaled 4K/5K display
    /// being the common case, not an unusual one.
    var textScale: Double = 1.0
    /// Size the UI to the window instead: as large as it can be with the
    /// rows that must stay on one line still fitting. `textScale` is then
    /// only where the slider picks up if this is turned off.
    var autoFitsText: Bool = true

    /// What the suggested plan does with a night that can't give every target
    /// a full session. It only shapes the suggestion — a plan you've edited by
    /// hand is yours, and nothing here rearranges it.
    var planEmphasis: PlanEmphasis = .longerIntegration

    static let `default` = Preferences()
}

/// Which way the suggested plan leans when the night is shorter than the
/// targets that want it.
enum PlanEmphasis: String, Codable, CaseIterable, Hashable, Sendable {
    /// Each target gets up to the full Integration Goal.
    case longerIntegration
    /// Each gets up to half of it, so roughly twice as many fit.
    case moreTargets

    var title: String {
        switch self {
        case .longerIntegration: return "Longer integration"
        case .moreTargets: return "More targets"
        }
    }
}

extension Preferences {
    /// The most of a night any one target may claim on the suggested plan's
    /// first pass. Whatever is left over afterwards still gets handed back to
    /// whoever can use it, so this caps the opening bid rather than the final
    /// session: a night with only one real target keeps the whole thing
    /// either way.
    var sessionCapMinutes: Double {
        switch planEmphasis {
        case .longerIntegration: return integrationGoalMinutes
        case .moreTargets: return max(20, integrationGoalMinutes / 2)
        }
    }

    /// The shortest block worth putting in a suggested plan.
    ///
    /// This has to move with the emphasis, not sit at a fixed floor. Asking
    /// for longer integration and then being handed a twenty-minute slot is a
    /// contradiction — by the time the mount has slewed, settled and refocused
    /// there is nothing left of it — and that is exactly what happened: a
    /// night would come back with 30, 35 and 20 minute blocks scattered among
    /// the real ones, because the scheduler's floor knew nothing about what
    /// you had asked for. A third of the cap keeps the floor in proportion to
    /// it however the Integration Goal is set.
    var minimumSessionMinutes: Double {
        switch planEmphasis {
        case .longerIntegration: return max(30, sessionCapMinutes / 3)
        // Short sessions are the whole point here, so this stays at the
        // scheduler's own floor: below twenty minutes it isn't a session.
        case .moreTargets: return 20
        }
    }
}

extension Preferences {
    // Every field decoded leniently, falling back to its own declared
    // default. Without this, adding any preference makes today's settings
    // file un-decodable, and `SettingsStore.load` answers that by discarding
    // the whole file — site, saved sites, rigs, custom targets, session plans
    // and all — and starting from scratch. Decoding must never be the reason
    // someone loses their setup.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Preferences()
        func value<T: Decodable>(_ key: CodingKeys, _ defaultValue: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? defaultValue
        }
        maximumCloudCover = value(.maximumCloudCover, fallback.maximumCloudCover)
        integrationGoalMinutes = value(.integrationGoalMinutes, fallback.integrationGoalMinutes)
        minimumDarkness = value(.minimumDarkness, fallback.minimumDarkness)
        forecastNights = value(.forecastNights, fallback.forecastNights)
        minimumScore = value(.minimumScore, fallback.minimumScore)
        minimumUsefulAltitude = value(.minimumUsefulAltitude, fallback.minimumUsefulAltitude)
        includeOversizedTargets = value(.includeOversizedTargets, fallback.includeOversizedTargets)
        includeStarClusters = value(.includeStarClusters, fallback.includeStarClusters)
        dewWarningSpread = value(.dewWarningSpread, fallback.dewWarningSpread)
        usesImperialUnits = value(.usesImperialUnits, fallback.usesImperialUnits)
        showsZenithRiskWarnings = value(.showsZenithRiskWarnings, fallback.showsZenithRiskWarnings)
        textScale = value(.textScale, fallback.textScale)
        autoFitsText = value(.autoFitsText, fallback.autoFitsText)
        planEmphasis = value(.planEmphasis, fallback.planEmphasis)
    }
}

extension Preferences {
    /// Display units only; every stored value is metric.
    var temperatureUnit: UnitTemperature { usesImperialUnits ? .fahrenheit : .celsius }
}
