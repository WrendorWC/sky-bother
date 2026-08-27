import Foundation

/// One named contributor to a score, kept alongside the result so the UI can
/// show *why* something scored the way it did rather than just a number.
struct ScoreFactor: Identifiable, Hashable, Sendable {
    var name: String
    var value: Double      // 0...1
    var weight: Double
    var detail: String

    var id: String { name }
    var percentage: Int { Int((value * 100).rounded()) }
}

/// Combines factors as a weighted geometric mean, so a single near-zero factor
/// (no clear sky, no time above the horizon) drags the result down instead of
/// being averaged away by the others.
func weightedGeometricScore(_ factors: [ScoreFactor]) -> Double {
    let totalWeight = factors.reduce(0) { $0 + $1.weight }
    guard totalWeight > 0 else { return 0 }
    let sum = factors.reduce(0.0) { partial, factor in
        partial + factor.weight * log(max(factor.value, 0.02))
    }
    return clamp(exp(sum / totalWeight) * 100, 0, 100)
}

enum Verdict: String, Sendable {
    case go = "Go"
    case worthwhile = "Worth setting up"
    case marginal = "Marginal"
    case skip = "Skip it"

    static func forScore(_ score: Double) -> Verdict {
        switch score {
        case 68...: return .go
        case 45..<68: return .worthwhile
        case 22..<45: return .marginal
        default: return .skip
        }
    }
}

struct MoonSummary: Hashable, Sendable {
    var illuminatedFraction: Double
    var phaseName: String
    var symbolName: String
    var upWindows: [TimeWindow]
    var maximumAltitude: Double
    var minutesUpDuringDarkness: Double
    /// 0 = irrelevant, 1 = dominates the night.
    var interference: Double

    var illuminationPercent: Int { Int((illuminatedFraction * 100).rounded()) }
}

/// A single point on the night's timeline.
struct NightSample: Hashable, Sendable {
    var date: Date
    var sunAltitude: Double
    var moonAltitude: Double
    var moonBrightness: Double
    var darkness: Double
    var clearFactor: Double
    var cloudCover: Double
    var cloudLow: Double
    var cloudMid: Double
    var cloudHigh: Double
    var transparency: Double
    var seeing: Double
    var temperature: Double
    var dewSpread: Double
    var hasWeather: Bool

    var isDark: Bool { darkness >= 0.35 }
}

struct TargetPlan: Identifiable, Hashable, Sendable {
    var target: Target
    var windows: [TimeWindow]
    var usableMinutes: Double
    var maximumAltitude: Double
    var altitudeAtBest: Double
    var azimuthAtBest: Double
    var bestTime: Date?
    var transitTime: Date?
    var meanDarkness: Double
    var meanClear: Double
    var meanExtinction: Double
    var minimumMoonSeparation: Double
    var maximumFieldRotation: Double
    var fit: RigFit
    var detectability: Double
    var score: Double
    var factors: [ScoreFactor]
    var warnings: [String]
    /// Altitude trace across the whole night, for the detail chart.
    var altitudeTrace: [Double]

    var id: String { target.id }
    var verdict: Verdict { Verdict.forScore(score) }
    var bestWindow: TimeWindow? { windows.longest }

    var usableHoursText: String {
        let hours = Int(usableMinutes) / 60
        let minutes = Int(usableMinutes) % 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

struct NightPlan: Identifiable, Hashable, Sendable {
    var date: Date                 // local civil date of the evening
    var site: Site
    var chartWindow: TimeWindow    // sunset to sunrise, the x-axis domain
    var sunset: Date?
    var sunrise: Date?
    var civilDusk: Date?
    var civilDawn: Date?
    var nauticalDusk: Date?
    var nauticalDawn: Date?
    var astronomicalDusk: Date?
    var astronomicalDawn: Date?
    var darkWindows: [TimeWindow]
    var clearDarkWindows: [TimeWindow]
    /// Dark and with the moon below the horizon — the good stuff.
    var moonlessDarkWindows: [TimeWindow]
    /// True when the cloud forecast wipes out the night entirely. The target
    /// list is still populated (ignoring cloud) so the view can show what would
    /// have been up rather than an empty, apparently broken list.
    var isCloudedOut: Bool
    var samples: [NightSample]
    var moon: MoonSummary
    var hasWeather: Bool
    var meanCloudDuringDark: Double
    var minimumTemperature: Double
    var minimumDewSpread: Double
    var maximumGust: Double
    var score: Double
    var factors: [ScoreFactor]
    var targets: [TargetPlan]

    var id: Date { date }
    var verdict: Verdict { Verdict.forScore(score) }

    var darkHours: Double { darkWindows.totalMinutes / 60 }
    var clearDarkHours: Double { clearDarkWindows.totalMinutes / 60 }
    var moonlessDarkHours: Double { moonlessDarkWindows.totalMinutes / 60 }
    var hasDewRisk: Bool { hasWeather && minimumDewSpread < 2.5 }

    var timeZone: TimeZone { site.timeZone }

    /// The one-line answer to "should I bother tonight".
    var headline: String {
        guard hasWeather else {
            return "Beyond the forecast — \(formatHours(darkHours)) of darkness expected"
        }
        if darkWindows.isEmpty {
            return "No astronomical darkness at this latitude tonight"
        }
        if clearDarkHours < 0.5 {
            return "Clouded out — under 30 minutes of usable sky"
        }
        var parts = ["\(formatHours(clearDarkHours)) of clear dark sky"]
        if moon.interference > 0.35 {
            let moonless = moonlessDarkHours
            if moonless >= 0.5 {
                parts.append("\(formatHours(moonless)) of it with the moon down")
            } else {
                parts.append("moon \(moon.illuminationPercent)% and up throughout")
            }
        } else if moon.illuminatedFraction < 0.15 {
            parts.append("essentially no moon")
        }
        if hasDewRisk { parts.append("dew likely") }
        return parts.joined(separator: ", ")
    }

    private func formatHours(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Position of a date along the chart, 0 at the left edge, 1 at the right.
    func fraction(for date: Date) -> Double {
        let span = chartWindow.duration
        guard span > 0 else { return 0 }
        return clamp(date.timeIntervalSince(chartWindow.start) / span, 0, 1)
    }
}
