import SwiftUI

/// Tonight's plan at the telescope: what's on now, how long is left, what's
/// next, and only the warnings worth acting on. Large type on a dim
/// red-black background, readable at a glance without spoiling dark
/// adaptation more than a screen must.
///
/// It follows the clock and the plan and needs nothing from you — your
/// telescope's own app is where the night is actually run.
struct SessionModeView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    var plan: NightPlan

    private static let background = Color(red: 0.035, green: 0.02, blue: 0.03)
    private static let panel = Color(red: 0.09, green: 0.05, blue: 0.06)
    private static let border = Color(red: 0.27, green: 0.15, blue: 0.18)
    private static let text = Color(red: 1.0, green: 0.93, blue: 0.93)
    private static let muted = Color(red: 0.80, green: 0.66, blue: 0.68)
    private static let accent = Color(red: 0.86, green: 0.30, blue: 0.30)
    private static let warning = Color(red: 0.95, green: 0.70, blue: 0.40)

    private var segments: [PlanSegment] { state.displayedPlan(for: plan) }

    var body: some View {
        // Once a second is plenty for elapsed and remaining minutes.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                header
                Divider().overlay(Self.border)
                let clock = SessionClock(at: context.date, plan: segments)
                HStack(alignment: .top, spacing: 18) {
                    mainPanel(clock, now: context.date)
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 14) {
                        conditions(now: context.date)
                        upNext(clock)
                        tonightSummary(now: context.date)
                    }
                    .frame(width: 360 * uiTextScale)
                }
                .padding(20)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(Self.text)
        .background(Self.background)
        .navigationTitle("Session")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: state.leaveSession) {
                Label("Home", systemImage: "chevron.left")
                    .font(.scaled(.body, scale: uiTextScale))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Self.muted)
            .help("Back to Home")

            VStack(alignment: .leading, spacing: 2) {
                Text("Session")
                    .font(.scaled(.title3, scale: uiTextScale).weight(.bold))
                Text("\(Format.longDate(plan.date, in: plan.timeZone)) · \(plan.site.name)")
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(Self.muted)
            }
            Spacer()
            Text(Format.time(Date(), in: plan.timeZone))
                .font(.scaled(.title2, scale: uiTextScale).monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Self.panel)
    }

    // MARK: - Now

    @ViewBuilder
    private func mainPanel(_ clock: SessionClock, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch clock.phase {
            case .running:
                if let block = clock.current { blockDetail(block, heading: "NOW", now: now, isRunning: true) }
            case .notStarted, .between:
                if let block = clock.next {
                    blockDetail(block, heading: "NEXT · STARTS IN \(countdown(to: block.window.start, from: now))",
                                now: now, isRunning: false)
                }
            case .finished:
                Text("Tonight's plan is finished")
                    .font(.system(size: 40 * uiTextScale, weight: .bold))
                Text("The last block ended at \(segments.last.map { Format.time($0.window.end, in: plan.timeZone) } ?? "").")
                    .font(.scaled(.title3, scale: uiTextScale))
                    .foregroundStyle(Self.muted)
            }
        }
        .padding(20)
        .background(Self.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Self.border))
    }

    @ViewBuilder
    private func blockDetail(_ block: PlanSegment, heading: String, now: Date, isRunning: Bool) -> some View {
        let targetPlan = plan.targets.first { $0.id == block.targetID }
        let times = "\(Format.time(block.window.start, in: plan.timeZone))–\(Format.time(block.window.end, in: plan.timeZone))"
        Text(heading)
            .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
            .kerning(0.8)
            .foregroundStyle(Self.accent)
        Text(block.targetName)
            .font(.system(size: 44 * uiTextScale, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        if isRunning {
            let elapsed = now.timeIntervalSince(block.window.start)
            Text("\(times) · \(Format.duration(minutes: max(0, block.window.end.timeIntervalSince(now)) / 60)) left")
                .font(.scaled(.title3, scale: uiTextScale).monospacedDigit())
                .foregroundStyle(Self.muted)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Self.border)
                    Capsule().fill(Self.accent)
                        .frame(width: geometry.size.width * CGFloat(min(1, max(0, elapsed / max(1, block.window.duration)))))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        } else {
            Text("\(times) · \(Format.duration(minutes: block.window.durationMinutes))")
                .font(.scaled(.title3, scale: uiTextScale).monospacedDigit())
                .foregroundStyle(Self.muted)
        }
        if let targetPlan {
            // Grows with the window, keeping roughly a photo's shape.
            FramingPreview(target: targetPlan.target, rig: state.rig)
                .aspectRatio(1.5, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 620 * uiTextScale)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if isRunning,
               let reason = Shootability.reason(for: targetPlan.target, at: now, in: plan,
                                                minimumAltitude: state.preferences.minimumUsefulAltitude) {
                Label("Right now it's \(reason.phrase).", systemImage: "exclamationmark.triangle.fill")
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(Self.warning)
            }
        }
    }

    private func countdown(to date: Date, from now: Date) -> String {
        Format.duration(minutes: max(1, date.timeIntervalSince(now) / 60))
    }

    // MARK: - Side

    private func sidePanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                .kerning(0.7)
                .foregroundStyle(Self.accent)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Self.border))
    }

    /// Only what you might act on: dew, cloud now, and wind.
    private func conditions(now: Date) -> some View {
        let session = TimeWindow(start: plan.chartWindow.contains(now) ? now : plan.chartWindow.start,
                                 end: plan.chartWindow.end)
        let dew = plan.hasWeather ? DewRisk.assess(samples: plan.samples, over: session) : nil
        let sample = plan.samples.min { abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now)) }
        let cloudNow = plan.chartWindow.contains(now) ? sample.map { Int($0.cloudCover) } : nil
        return sidePanel("Conditions") {
            if !plan.hasWeather {
                Text("No forecast for this night.")
                    .foregroundStyle(Self.muted)
            } else {
                if let cloudNow {
                    conditionLine("Cloud now", "\(cloudNow)%", warn: Double(cloudNow) > state.preferences.maximumCloudCover)
                }
                if let dew {
                    conditionLine("Dew", dew.level >= .high
                                  ? "\(dew.level.name) from \(Format.time(dew.peakStart, in: plan.timeZone)) — heater recommended"
                                  : dew.level.name,
                                  warn: dew.level >= .high)
                }
                conditionLine("Gusts", Format.wind(kilometersPerHour: plan.maximumGust,
                                                  imperial: state.preferences.usesImperialUnits),
                              warn: plan.maximumGust > 30)
            }
        }
        .font(.scaled(.callout, scale: uiTextScale))
    }

    private func conditionLine(_ label: String, _ value: String, warn: Bool) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(Self.muted)
            Spacer(minLength: 10)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(warn ? Self.warning : Self.text)
        }
    }

    private func upNext(_ clock: SessionClock) -> some View {
        // When the main panel is already showing the next block, list what
        // comes after it.
        let list = clock.phase == .running ? clock.upcoming : Array(clock.upcoming.dropFirst())
        return sidePanel("After that") {
            if list.isEmpty {
                Text("Nothing more planned.")
                    .foregroundStyle(Self.muted)
            } else {
                ForEach(list) { block in
                    HStack(spacing: 10) {
                        if let targetPlan = plan.targets.first(where: { $0.id == block.targetID }) {
                            ScoreBadge(score: targetPlan.score, size: 30)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.targetName).fontWeight(.semibold)
                            Text("\(Format.time(block.window.start, in: plan.timeZone))–\(Format.time(block.window.end, in: plan.timeZone)) · \(Format.duration(minutes: block.window.durationMinutes))")
                                .monospacedDigit()
                                .foregroundStyle(Self.muted)
                        }
                    }
                }
            }
        }
        .font(.scaled(.callout, scale: uiTextScale))
    }

    private func tonightSummary(now: Date) -> some View {
        let first = segments.first?.window.start
        let last = segments.last?.window.end
        return sidePanel("Tonight") {
            Text("\(segments.count) block\(segments.count == 1 ? "" : "s")\(first.flatMap { f in last.map { " · \(Format.time(f, in: plan.timeZone))–\(Format.time($0, in: plan.timeZone))" } } ?? "")")
            if let last, now < last {
                Text("\(Format.duration(minutes: last.timeIntervalSince(max(now, first ?? now)) / 60)) of imaging left")
                    .foregroundStyle(Self.muted)
            }
        }
        .font(.scaled(.callout, scale: uiTextScale))
    }
}
