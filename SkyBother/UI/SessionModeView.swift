import SwiftUI

/// Running the night at the telescope: the target in hand, what's next, and
/// only the warnings worth acting on. Large type on a dim red-black
/// background, so it can be read at a glance without spoiling dark
/// adaptation more than a screen must.
///
/// It follows what you do — Mark started, Mark complete, Skip — rather than
/// the clock, so running late or early never leaves it pointing at the wrong
/// target. What happens is recorded apart from the plan.
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

    private var record: SessionRecord? { state.sessionRecord(for: plan) }

    var body: some View {
        // Once a second is plenty for elapsed and remaining minutes.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                header
                Divider().overlay(Self.border)
                if let record {
                    HStack(alignment: .top, spacing: 18) {
                        currentPanel(record, now: context.date)
                            .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 14) {
                            conditions(now: context.date)
                            upNext(record)
                            progress(record, now: context.date)
                        }
                        .frame(width: 360 * uiTextScale)
                    }
                    .padding(20)
                    Spacer(minLength: 0)
                }
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
            .help("Back to Home. The session keeps going; resume it from Home.")

            VStack(alignment: .leading, spacing: 2) {
                Text("Session in progress")
                    .font(.scaled(.title3, scale: uiTextScale).weight(.bold))
                Text("\(Format.longDate(plan.date, in: plan.timeZone)) · \(plan.site.name)")
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(Self.muted)
            }
            Spacer()
            Button {
                state.endSession()
            } label: {
                Text("End session")
                    .font(.scaled(.body, scale: uiTextScale).weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Self.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Finish the night. Everything recorded is kept.")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Self.panel)
    }

    // MARK: - Current target

    @ViewBuilder
    private func currentPanel(_ record: SessionRecord, now: Date) -> some View {
        if let index = record.currentIndex {
            let entry = record.entries[index]
            let targetPlan = plan.targets.first { $0.id == entry.targetID }
            let elapsed = entry.capturedSeconds(now: now)
            let plannedSeconds = entry.planned.duration
            VStack(alignment: .leading, spacing: 14) {
                Text(entry.status == .imaging ? "NOW IMAGING" : "UP NOW")
                    .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                    .kerning(0.8)
                    .foregroundStyle(Self.accent)
                Text(entry.targetName)
                    .font(.system(size: 44 * uiTextScale, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(timesLine(entry, elapsed: elapsed))
                    .font(.scaled(.title3, scale: uiTextScale).monospacedDigit())
                    .foregroundStyle(Self.muted)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Self.border)
                        Capsule().fill(Self.accent)
                            .frame(width: geometry.size.width * CGFloat(min(1, elapsed / max(1, plannedSeconds))))
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)

                if let targetPlan {
                    // Grows with the window, keeping roughly a photo's shape.
                    FramingPreview(target: targetPlan.target, rig: state.rig)
                        .aspectRatio(1.5, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 620 * uiTextScale)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if let reason = Shootability.reason(for: targetPlan.target, at: now, in: plan,
                                                        minimumAltitude: state.preferences.minimumUsefulAltitude),
                       plan.chartWindow.contains(now) {
                        Label("Right now it's \(reason.phrase).", systemImage: "exclamationmark.triangle.fill")
                            .font(.scaled(.callout, scale: uiTextScale))
                            .foregroundStyle(Self.warning)
                    }
                }

                HStack(spacing: 12) {
                    Spacer()
                    sessionButton("Skip target", prominent: false) {
                        state.updateSession { $0.skip(now: Date()) }
                    }
                    .help("Move on without imaging this one. The plan stays as it was.")
                    if entry.status == .waiting {
                        sessionButton("Mark started", prominent: true) {
                            state.updateSession { $0.markStarted(now: Date()) }
                        }
                    } else {
                        sessionButton("Mark complete", prominent: true) {
                            state.updateSession { $0.markComplete(now: Date()) }
                        }
                    }
                }
            }
            .padding(20)
            .background(Self.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Self.border))
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("All targets done")
                    .font(.system(size: 36 * uiTextScale, weight: .bold))
                Text("\(record.finishedCount) of \(record.entries.count) completed · \(capturedText(record, now: now))")
                    .font(.scaled(.title3, scale: uiTextScale))
                    .foregroundStyle(Self.muted)
                HStack {
                    Spacer()
                    sessionButton("End session", prominent: true) { state.endSession() }
                }
            }
            .padding(20)
            .background(Self.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Self.border))
        }
    }

    private func timesLine(_ entry: SessionRecord.Entry, elapsed: TimeInterval) -> String {
        let planned = "\(Format.time(entry.planned.start, in: plan.timeZone))–\(Format.time(entry.planned.end, in: plan.timeZone))"
        guard entry.status == .imaging else {
            return "Planned \(planned) · \(Format.duration(minutes: entry.planned.durationMinutes))"
        }
        let remaining = max(0, entry.planned.duration - elapsed)
        return "\(planned) · \(Format.duration(minutes: elapsed / 60)) elapsed · \(Format.duration(minutes: remaining / 60)) remaining"
    }

    private func sessionButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.scaled(.title3, scale: uiTextScale).weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .foregroundStyle(prominent ? Color.white : Self.text)
                .background(prominent ? Self.accent : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(prominent ? Color.clear : Self.border))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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

    private func upNext(_ record: SessionRecord) -> some View {
        sidePanel("Up next") {
            if record.upcoming.isEmpty {
                Text("Nothing after this.")
                    .foregroundStyle(Self.muted)
            } else {
                ForEach(record.upcoming) { entry in
                    HStack(spacing: 10) {
                        if let targetPlan = plan.targets.first(where: { $0.id == entry.targetID }) {
                            ScoreBadge(score: targetPlan.score, size: 30)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.targetName).fontWeight(.semibold)
                            Text("\(Format.time(entry.planned.start, in: plan.timeZone))–\(Format.time(entry.planned.end, in: plan.timeZone)) · \(Format.duration(minutes: entry.planned.durationMinutes))")
                                .monospacedDigit()
                                .foregroundStyle(Self.muted)
                        }
                    }
                }
            }
        }
        .font(.scaled(.callout, scale: uiTextScale))
    }

    private func capturedText(_ record: SessionRecord, now: Date) -> String {
        let seconds = record.capturedSeconds(now: now)
        return seconds < 60 ? "Nothing captured yet" : "\(Format.duration(minutes: seconds / 60)) captured"
    }

    private func progress(_ record: SessionRecord, now: Date) -> some View {
        let skipped = record.entries.filter { $0.status == .skipped }.count
        return sidePanel("Session progress") {
            Text("\(record.finishedCount) of \(record.entries.count) target\(record.entries.count == 1 ? "" : "s") done\(skipped > 0 ? " · \(skipped) skipped" : "")")
            Text(capturedText(record, now: now))
                .foregroundStyle(Self.muted)
        }
        .font(.scaled(.callout, scale: uiTextScale))
    }
}
