import SwiftUI
import AppKit

/// The app's colour vocabulary. Everything is tuned for a dark room: the chart
/// backgrounds go genuinely black at astronomical darkness so the timeline reads
/// the way the night actually looks.
enum Palette {
    static let daylight = Color(red: 0.42, green: 0.62, blue: 0.86)
    static let civil = Color(red: 0.18, green: 0.24, blue: 0.45)
    static let nautical = Color(red: 0.07, green: 0.10, blue: 0.22)
    static let astronomical = Color(red: 0.025, green: 0.03, blue: 0.075)
    static let moonlight = Color(red: 0.98, green: 0.93, blue: 0.74)
    static let cloud = Color(red: 0.86, green: 0.89, blue: 0.94)

    static let go = Color(red: 0.24, green: 0.78, blue: 0.47)
    static let worthwhile = Color(red: 0.30, green: 0.66, blue: 0.90)
    static let marginal = Color(red: 0.95, green: 0.70, blue: 0.24)
    static let skip = Color(red: 0.85, green: 0.36, blue: 0.34)

    static func verdict(_ verdict: Verdict) -> Color {
        switch verdict {
        case .go: return go
        case .worthwhile: return worthwhile
        case .marginal: return marginal
        case .skip: return skip
        }
    }

    static func score(_ score: Double) -> Color {
        verdict(Verdict.forScore(score))
    }

    /// Sky colour for a given solar altitude, matching the twilight boundaries.
    static func sky(sunAltitude: Double) -> Color {
        switch sunAltitude {
        case 0...: return daylight
        case -6..<0: return blend(daylight, civil, smoothstep(0, -6, sunAltitude))
        case -12..<(-6): return blend(civil, nautical, smoothstep(-6, -12, sunAltitude))
        case -18..<(-12): return blend(nautical, astronomical, smoothstep(-12, -18, sunAltitude))
        default: return astronomical
        }
    }

    static func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let clamped = clamp(t, 0, 1)
        let first = NSColor(a).usingColorSpace(.sRGB) ?? .black
        let second = NSColor(b).usingColorSpace(.sRGB) ?? .black
        return Color(red: first.redComponent + (second.redComponent - first.redComponent) * clamped,
                     green: first.greenComponent + (second.greenComponent - first.greenComponent) * clamped,
                     blue: first.blueComponent + (second.blueComponent - first.blueComponent) * clamped)
    }
}

/// Maps dates onto horizontal positions for every chart in the app, so the night
/// timeline and each target's availability bar share one time axis.
struct TimeAxis {
    var window: TimeWindow
    var width: CGFloat

    func x(for date: Date) -> CGFloat {
        let span = window.duration
        guard span > 0 else { return 0 }
        let fraction = clamp(date.timeIntervalSince(window.start) / span, 0, 1)
        return CGFloat(fraction) * width
    }

    /// Whole-hour tick marks inside the window, in the site's local time.
    func hourTicks(timeZone: TimeZone) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard var cursor = calendar.nextDate(after: window.start,
                                             matching: DateComponents(minute: 0),
                                             matchingPolicy: .nextTime) else { return [] }
        var ticks: [Date] = []
        while cursor < window.end && ticks.count < 40 {
            ticks.append(cursor)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
            cursor = next
        }
        return ticks
    }
}

struct ScoreBadge: View {
    var score: Double
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.score(score).opacity(0.18))
            Circle()
                .strokeBorder(Palette.score(score).opacity(0.55), lineWidth: 1.5)
            Text("\(Int(score.rounded()))")
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.score(score))
        }
        .frame(width: size, height: size)
    }
}

struct VerdictTag: View {
    var verdict: Verdict

    var body: some View {
        Text(verdict.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Palette.verdict(verdict).opacity(0.16), in: Capsule())
            .foregroundStyle(Palette.verdict(verdict))
    }
}

/// A labelled 0-100% bar, used for score factors and conditions.
struct FactorBar: View {
    var factor: ScoreFactor

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(factor.name)
                    .font(.callout)
                Spacer()
                Text("\(factor.percentage)%")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("×\(String(format: "%.2f", factor.weight))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 38, alignment: .trailing)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Palette.score(factor.value * 100))
                        .frame(width: max(2, geometry.size.width * factor.value))
                }
            }
            .frame(height: 6)
            Text(factor.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct LabelledValue: View {
    var label: String
    var value: String
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.body.weight(.medium))
                .monospacedDigit()
        }
    }
}

struct WarningRow: View {
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Palette.marginal)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
