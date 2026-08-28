import SwiftUI

struct NightDetailView: View {
    @EnvironmentObject private var state: AppState
    var plan: NightPlan

    private var targets: [TargetPlan] { state.visibleTargets(for: plan) }

    var body: some View {
        VStack(spacing: 0) {
            header
                // This column is a plain VStack, not a List/ScrollView, so it
                // doesn't get the automatic clearance those get under the
                // window's title bar — without extra top padding, the mission
                // summary panel renders under the title bar text.
                .padding(.horizontal, 20)
                .padding(.top, 34)
                .padding(.bottom, 20)
            Divider()
            filterBar
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            Divider()
            targetList
        }
        .spaceBackground()
        .navigationTitle(Format.longDate(plan.date, in: plan.timeZone))
        .navigationSubtitle(plan.site.name)
    }

    // MARK: - Header

    private var selectedTargetPlan: TargetPlan? {
        guard let id = state.selectedTargetID else { return nil }
        return plan.targets.first { $0.id == id }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            missionSummary

            if plan.isCloudedOut {
                Label("The forecast writes this night off. The list below shows what would have been up if it clears.",
                      systemImage: "cloud.rain.fill")
                    .font(.callout)
                    .foregroundStyle(Palette.marginal)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.marginal.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }

            statistics

            NightTimelineView(plan: plan, selectedTarget: selectedTargetPlan)
                .animation(.easeInOut(duration: 0.3), value: state.selectedTargetID)

            legend

            autoPlanSection
        }
    }

    // MARK: - Auto-plan

    private var autoPlan: [AutoPlanSlot] {
        AutoPlanner.plan(for: plan, minimumScore: state.preferences.minimumScore)
    }

    private var autoPlanSection: some View {
        let slots = autoPlan
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader("Tonight's plan")
                Spacer()
                if !slots.isEmpty {
                    Text("\(slots.count) target\(slots.count == 1 ? "" : "s") · \(Format.hours(slots.reduce(0) { $0 + $1.window.durationHours }))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if slots.isEmpty {
                Text("Nothing tonight clears your minimum score for long enough to build a session around.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                AutoPlanStripView(plan: plan, slots: slots)
                    .frame(height: 34)

                VStack(spacing: 0) {
                    ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                        autoPlanRow(slot)
                        if index < slots.count - 1 {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .panelStyle()
            }
        }
    }

    private func autoPlanRow(_ slot: AutoPlanSlot) -> some View {
        HStack(spacing: 12) {
            ScoreBadge(score: slot.targetPlan.score, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.targetPlan.target.displayName)
                    .font(.callout.weight(.semibold))
                Text(slot.targetPlan.fit.framingNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(Format.time(slot.window.start, in: plan.timeZone))–\(Format.time(slot.window.end, in: plan.timeZone))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Mission summary

    /// The 2-3-second answer: is tonight worth it, when, at what, and why
    /// not more. Everything below this is the detail that backs it up.
    private var missionSummary: some View {
        HStack(alignment: .center, spacing: 16) {
            ScoreBadge(score: plan.score, size: 58)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    Text(Format.longDate(plan.date, in: plan.timeZone))
                        .font(.title2.weight(.bold))
                    VerdictTag(verdict: plan.verdict)
                }
                Text(missionSummaryLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            MoonPhaseDisc(illuminatedFraction: plan.moon.illuminatedFraction, isWaxing: plan.moon.isWaxing, diameter: 34)
                .help("\(plan.moon.illuminationPercent)% \(plan.moon.phaseName.lowercased())")
        }
        .padding(16)
        .panelStyle(cornerRadius: 14)
        .animation(.easeInOut(duration: 0.3), value: plan.id)
    }

    private var missionSummaryLine: String {
        var parts: [String] = []
        if let window = plan.bestImagingWindow, !window.isEmpty {
            parts.append("best imaging \(Format.time(window.start, in: plan.timeZone))–\(Format.time(window.end, in: plan.timeZone))")
        } else {
            parts.append(plan.headline)
        }
        if let best = plan.bestTarget {
            parts.append("best target \(best.target.displayName) · \(Int(best.score.rounded()))")
        }
        if let limitation = nightLimitationPhrase(for: plan) {
            parts.append("main limitation: \(limitation)")
        }
        return parts.joined(separator: " · ")
    }

    private var statistics: some View {
        HStack(alignment: .top, spacing: 26) {
            LabelledValue(label: "Astronomical dark",
                          value: darkWindowText,
                          systemImage: "moon.stars")
            LabelledValue(label: "Moon down",
                          value: plan.moonlessDarkHours > 0.02 ? Format.hours(plan.moonlessDarkHours) : "none",
                          systemImage: plan.moon.symbolName)
            LabelledValue(label: "Moon",
                          value: "\(plan.moon.illuminationPercent)% \(plan.moon.phaseName.lowercased())",
                          systemImage: "circle.lefthalf.filled")
            if plan.hasWeather {
                LabelledValue(label: "Cloud in the dark",
                              value: "\(Int(plan.meanCloudDuringDark))%",
                              systemImage: "cloud")
                LabelledValue(label: "Low",
                              value: Format.temperature(celsius: plan.minimumTemperature,
                                                        imperial: state.preferences.usesImperialUnits),
                              systemImage: "thermometer.low")
                LabelledValue(label: "Dew spread",
                              value: Format.temperatureDelta(celsius: plan.minimumDewSpread,
                                                             imperial: state.preferences.usesImperialUnits),
                              systemImage: "humidity")
                LabelledValue(label: "Gusts",
                              value: Format.wind(kilometersPerHour: plan.maximumGust,
                                                 imperial: state.preferences.usesImperialUnits),
                              systemImage: "wind")
            }
            Spacer(minLength: 0)
        }
    }

    private var darkWindowText: String {
        guard let dusk = plan.astronomicalDusk, let dawn = plan.astronomicalDawn else {
            return plan.darkWindows.isEmpty ? "none" : Format.hours(plan.darkHours)
        }
        return "\(Format.time(dusk, in: plan.timeZone))–\(Format.time(dawn, in: plan.timeZone))"
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: Palette.cloud.opacity(0.7), label: "cloud from the top")
            legendItem(color: Palette.moonlight.opacity(0.8), label: "moonlight and its altitude")
            legendItem(color: Palette.astronomical, label: "darker background = darker sky")
            if let target = selectedTargetPlan {
                legendItem(color: .white, label: "\(target.target.displayName)'s altitude · dashed box = its best window")
            }
            Spacer()
            if let dewWarning = dewWarning {
                Label(dewWarning, systemImage: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.marginal)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var dewWarning: String? {
        guard plan.hasDewRisk else { return nil }
        return "Dew likely — bring a dew heater"
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 14, height: 9)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.primary.opacity(0.15)))
            Text(label)
        }
    }

    // MARK: - Filters

    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter targets", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 190)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.panelBorder))

            Menu {
                Button("All types") { state.typeFilter.removeAll() }
                Divider()
                ForEach(TargetType.allCases) { type in
                    Toggle(type.displayName, isOn: Binding(
                        get: { state.typeFilter.contains(type) },
                        set: { isOn in
                            if isOn { state.typeFilter.insert(type) } else { state.typeFilter.remove(type) }
                        }))
                }
            } label: {
                Label(state.typeFilter.isEmpty ? "All types" : "\(state.typeFilter.count) types",
                      systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            if state.isPlanning {
                ProgressView().controlSize(.small)
            }
            Text("\(targets.count) worth considering")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Targets

    @ViewBuilder
    private var targetList: some View {
        if targets.isEmpty {
            EmptyStateView(title: emptyTitle,
                           message: emptyMessage,
                           systemImage: "binoculars")
        } else {
            List(selection: $state.selectedTargetID) {
                ForEach(targets) { targetPlan in
                    TargetRowView(plan: plan, targetPlan: targetPlan)
                        .tag(targetPlan.id)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyTitle: String {
        plan.darkWindows.isEmpty ? "No darkness tonight" : "Nothing clears your thresholds"
    }

    private var emptyMessage: String {
        if plan.darkWindows.isEmpty {
            return "The sun never gets far enough below the horizon at this latitude and date."
        }
        if !state.searchText.isEmpty || !state.typeFilter.isEmpty {
            return "No targets match the current filter."
        }
        return "Try lowering the minimum altitude or minimum score in Settings."
    }
}

struct TargetRowView: View {
    @EnvironmentObject private var state: AppState
    var plan: NightPlan
    var targetPlan: TargetPlan

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ScoreBadge(score: targetPlan.score, size: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(targetPlan.target.displayName)
                        .font(.body.weight(.semibold))
                    if targetPlan.target.commonName != nil {
                        Text(targetPlan.target.designation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: targetPlan.target.type.symbolName)
                        .font(.caption)
                        .foregroundStyle(Palette.accent)
                    Text(targetPlan.target.type.shortName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Text(targetPlan.usableHoursText)
                        .font(.callout.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }

                TargetAvailabilityBar(plan: plan, targetPlan: targetPlan)

                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }

    private var summary: String {
        var parts: [String] = []
        if let best = targetPlan.bestTime {
            parts.append("best \(Format.time(best, in: plan.timeZone))")
        }
        parts.append("peaks \(Format.degrees(targetPlan.maximumAltitude))")
        parts.append(targetPlan.fit.framingNote.lowercased())
        // The mosaic warning repeats the framing note, so skip it here.
        if let warning = targetPlan.warnings.first(where: { $0 != targetPlan.fit.framingNote }) {
            parts.append("⚠ \(warning.lowercased())")
        }
        return parts.joined(separator: " · ")
    }
}

/// A Gantt-style strip of the auto-planned session, sharing the night
/// timeline's time axis so it lines up with everything above it.
private struct AutoPlanStripView: View {
    var plan: NightPlan
    var slots: [AutoPlanSlot]

    var body: some View {
        GeometryReader { geometry in
            let axis = TimeAxis(window: plan.chartWindow, width: geometry.size.width)
            Canvas { context, size in
                for slot in slots {
                    let startX = axis.x(for: slot.window.start)
                    let endX = axis.x(for: slot.window.end)
                    let rect = CGRect(x: startX, y: 0, width: max(2, endX - startX), height: size.height)
                    let color = Palette.score(slot.targetPlan.score)
                    context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(color.opacity(0.75)))
                    context.stroke(Path(roundedRect: rect, cornerRadius: 5), with: .color(color), lineWidth: 1)

                    if rect.width > 50 {
                        context.draw(Text(slot.targetPlan.target.displayName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white),
                                     at: CGPoint(x: rect.midX, y: rect.midY),
                                     anchor: .center)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.panelBorder))
    }
}
