import SwiftUI

/// Guided setup: a short path to a real first plan. Five steps — site,
/// horizon, rig, goal, first plan — each with a safe default, so only the
/// site is required. Progress is saved as it goes, so a relaunch comes back to
/// the same step, and it can be run again later from Settings or Home.
struct SetupFlowView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState

    private static let steps = ["Site", "Horizon", "Rig", "Goal", "First plan"]

    private var step: Int { state.setupStep }
    @State private var isShowingAdvanced = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 24) {
                    stepIndicator
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Step \(step + 1) of \(Self.steps.count)")
                            .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                            .foregroundStyle(Palette.accent)
                        stepContent
                    }
                    .padding(24)
                    .frame(maxWidth: 760, alignment: .leading)
                    .panelStyle(cornerRadius: 16)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .spaceBackground()
        .sheet(isPresented: $isShowingAdvanced) { advancedSheet }
    }

    /// Every detailed field, as in Settings. Changes apply straight away, so
    /// the steps behind it show them on return.
    private var advancedSheet: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advanced Setup")
                        .font(.scaled(.title3, scale: uiTextScale).weight(.bold))
                    Text("Changes apply immediately.")
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { isShowingAdvanced = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            SettingsView(isInGuidedSetup: true)
        }
        .environmentObject(state)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Image(systemName: "moon.stars.fill")
                .foregroundStyle(Palette.accent)
            Text("Set up Sky Bother")
                .font(.scaled(.title3, scale: uiTextScale).weight(.bold))
            Spacer()
            Button {
                isShowingAdvanced = true
            } label: {
                Label("Advanced Setup…", systemImage: "slider.horizontal.3")
            }
            .help("Enter every setting by hand")
            if state.settings.hasSetLocation {
                Button("Save and close") { state.finishSetup() }
                    .help("Finish setup with the current settings")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Palette.spaceTop)
    }

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(Self.steps.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle()
                        .fill(index <= step ? Palette.accent : Palette.panelBorder)
                        .frame(height: 2)
                        .frame(maxWidth: 90)
                }
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(index == step ? Palette.accent : (index < step ? Palette.accent.opacity(0.3) : Palette.panel))
                        Circle()
                            .strokeBorder(index <= step ? Palette.accent : Palette.panelBorder)
                        if index < step {
                            Image(systemName: "checkmark")
                                .font(.scaled(.callout, scale: uiTextScale).weight(.bold))
                        } else {
                            Text("\(index + 1)")
                                .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                        }
                    }
                    .frame(width: 34 * uiTextScale, height: 34 * uiTextScale)
                    .foregroundStyle(index == step ? Color.white : .primary)
                    Text(Self.steps[index])
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(index == step ? .primary : .secondary)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1), \(Self.steps[index])\(index < step ? ", done" : index == step ? ", current" : "")")
            }
        }
        .frame(maxWidth: 640)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Back") { state.setupStep = step - 1 }
                .disabled(step == 0)
            Spacer()
            Text("Progress saves automatically")
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.tertiary)
            Spacer()
            if step >= 1 && step <= 3 {
                Button("Skip") { state.setupStep = step + 1 }
                    .help("Keep the current setting")
            }
            if step < Self.steps.count - 1 {
                Button {
                    state.setupStep = step + 1
                } label: {
                    Text("Continue").frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
            } else {
                Button {
                    state.finishSetup()
                } label: {
                    Text("Go to my plan").frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.plans.isEmpty)
            }
        }
        .font(.scaled(.body, scale: uiTextScale))
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Palette.spaceTop)
    }

    private var canContinue: Bool {
        switch step {
        case 0: return state.settings.hasSetLocation
        case 2: return state.rig.validationProblems.isEmpty
        default: return true
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: SiteStep()
        case 1: HorizonStep()
        case 2: RigStep()
        case 3: GoalStep()
        default: FirstPlanStep()
        }
    }
}

// MARK: - Steps

private struct StepHeading: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.scaled(.title2, scale: uiTextScale).weight(.semibold))
            Text(detail)
                .font(.scaled(.body, scale: uiTextScale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SiteStep: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeading(title: "Choose your observing site",
                        detail: "Search by town, city or landmark.")
            SiteFinder()

            if state.settings.hasSetLocation {
                VStack(alignment: .leading, spacing: 10) {
                    Label(state.site.name, systemImage: "checkmark.circle.fill")
                        .font(.scaled(.headline, scale: uiTextScale))
                        .foregroundStyle(Palette.go)
                    Text(state.site.coordinateSummary)
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                    Picker("Time zone", selection: $state.site.timeZoneIdentifier) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
                            Text(identifier).tag(identifier)
                        }
                    }
                    Picker("Light pollution", selection: $state.site.bortleClass) {
                        ForEach(1...9, id: \.self) { value in
                            Text("Bortle \(value) — \(Site.bortleDescription(for: value))").tag(value)
                        }
                    }
                    Text("1 is a truly dark sky, 9 a city centre.")
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.accent.opacity(0.5)))
            }
        }
    }
}

private struct HorizonStep: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeading(title: "How much sky can you see?",
                        detail: "Roughly how high trees, houses and hills reach. Targets behind them are left out.")
            HorizonEditor(site: $state.site)
        }
    }
}

private struct RigStep: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    @State private var showsCustom = false

    /// A familiar target to show the frame on: the Orion Nebula.
    private var sampleTarget: Target? {
        BuiltInCatalog.all.first { $0.designation == "M42" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeading(title: "What are you imaging with?",
                        detail: "Pick your telescope or camera.")

            ForEach(Rig.PresetGroup.allCases) { group in
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(group.rawValue)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200 * uiTextScale), spacing: 8)], spacing: 8) {
                        ForEach(Rig.presets.filter { $0.presetGroup == group }) { preset in
                            presetButton(preset)
                        }
                    }
                }
            }

            DisclosureGroup(isExpanded: $showsCustom) {
                customFields.padding(.top, 8)
            } label: {
                Text("My equipment isn't listed")
                    .contentShape(Rectangle())
                    .onTapGesture { showsCustom.toggle() }
            }

            summary
        }
    }

    private func presetButton(_ preset: Rig) -> some View {
        let isChosen = state.rig.name == preset.name
        return Button {
            state.applyPreset(preset)
        } label: {
            HStack {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChosen ? Palette.accent : .secondary)
                Text(preset.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.scaled(.callout, scale: uiTextScale))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isChosen ? Palette.accent.opacity(0.18) : Palette.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isChosen ? Palette.accent : Palette.panelBorder))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private var customFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $state.rig.name)
            HStack {
                LabeledContent("Aperture (mm)") {
                    TextField("Aperture", value: $state.rig.apertureMillimeters, format: .number).labelsHidden()
                }
                LabeledContent("Focal length (mm)") {
                    TextField("Focal length", value: $state.rig.focalLengthMillimeters, format: .number).labelsHidden()
                }
            }
            HStack {
                LabeledContent("Sensor width (mm)") {
                    TextField("Sensor width", value: $state.rig.sensorWidthMillimeters, format: .number).labelsHidden()
                }
                LabeledContent("Sensor height (mm)") {
                    TextField("Sensor height", value: $state.rig.sensorHeightMillimeters, format: .number).labelsHidden()
                }
            }
            LabeledContent("Pixel size (µm)") {
                TextField("Pixel size", value: $state.rig.pixelSizeMicrons, format: .number).labelsHidden()
            }
            Picker("Mount", selection: $state.rig.mountType) {
                ForEach(MountType.allCases) { type in Text(type.displayName).tag(type) }
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.scaled(.callout, scale: uiTextScale))
    }

    @ViewBuilder
    private var summary: some View {
        let problems = state.rig.validationProblems
        if problems.isEmpty {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader("What this gives you")
                    Text("\(state.rig.fieldOfViewSummary) field of view — \(state.rig.fieldOfViewInMoons).")
                    Text(String(format: "f/%.1f · %.2f″ per pixel image scale.", state.rig.focalRatio, state.rig.arcsecondsPerPixel))
                        .foregroundStyle(.secondary)
                }
                .font(.scaled(.callout, scale: uiTextScale))
                Spacer(minLength: 0)
                if let sampleTarget {
                    VStack(alignment: .leading, spacing: 4) {
                        FramingPreview(target: sampleTarget, rig: state.rig)
                            .frame(width: 220 * uiTextScale, height: 150 * uiTextScale)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("\(sampleTarget.displayName) in your frame")
                            .font(.scaled(.caption, scale: uiTextScale))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                }
            }
            .font(.scaled(.callout, scale: uiTextScale))
            .foregroundStyle(Palette.marginal)
        }
    }
}

private struct GoalStep: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    /// Custom sets no values of its own, so choosing it just opens its
    /// controls, starting from whatever the values are now.
    @State private var choseCustom = false

    var body: some View {
        let matched = GoalPreset.matching(state.preferences)
        let current = choseCustom ? .custom : matched
        VStack(alignment: .leading, spacing: 18) {
            StepHeading(title: "What kind of night do you want?",
                        detail: "Shapes the suggested plan.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300 * uiTextScale), spacing: 10)], spacing: 10) {
                ForEach(GoalPreset.allCases) { preset in
                    goalCard(preset, isChosen: preset == current)
                }
            }
            if current == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Time per target")
                        Spacer()
                        Text(Format.duration(minutes: state.preferences.integrationGoalMinutes))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    Slider(value: $state.preferences.integrationGoalMinutes, in: 30...480, step: 15)
                        .accessibilityLabel("Time per target")
                        .accessibilityValue(Format.duration(minutes: state.preferences.integrationGoalMinutes))
                    Picker("Suggested plan favours", selection: $state.preferences.planEmphasis) {
                        ForEach(PlanEmphasis.allCases, id: \.self) { emphasis in
                            Text(emphasis.title).tag(emphasis)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .font(.scaled(.callout, scale: uiTextScale))
            }
        }
    }

    private func goalCard(_ preset: GoalPreset, isChosen: Bool) -> some View {
        Button {
            choseCustom = preset == .custom
            if preset != .custom { state.applyGoalPreset(preset) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: preset.systemImage)
                    .font(.scaled(.title2, scale: uiTextScale))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 30 * uiTextScale)
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.title)
                        .font(.scaled(.headline, scale: uiTextScale))
                    Text(preset.summary)
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChosen ? Palette.accent : .secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isChosen ? Palette.accent.opacity(0.18) : Palette.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isChosen ? Palette.accent : Palette.panelBorder))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(preset == .custom ? "Set your own time per target" : preset.summary)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

private struct FirstPlanStep: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeading(title: "Your first plan",
                        detail: "From this week's forecast.")
                .task { if state.plans.isEmpty && !state.isLoading { await state.refresh() } }
            if let night = state.bestUpcomingNight {
                nightSummary(night)
            } else if state.isLoading || state.isPlanning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Fetching the forecast…")
                        .foregroundStyle(.secondary)
                }
                .font(.scaled(.callout, scale: uiTextScale))
            } else {
                HStack(spacing: 10) {
                    Text("Couldn't fetch the forecast.")
                        .foregroundStyle(.secondary)
                    Button("Try again") { Task { await state.refresh(force: true) } }
                }
                .font(.scaled(.callout, scale: uiTextScale))
            }
        }
    }

    private func nightSummary(_ night: NightPlan) -> some View {
        let plan = state.suggestedPlan(for: night)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ScoreBadge(score: night.score, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best night coming up: \(Format.longDate(night.date, in: night.timeZone))")
                        .font(.scaled(.title3, scale: uiTextScale).weight(.semibold))
                    HStack(spacing: 8) {
                        VerdictTag(verdict: night.verdict)
                        if let limitation = nightLimitationPhrase(for: night) {
                            Text("Main limitation: \(limitation)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.scaled(.callout, scale: uiTextScale))
                }
            }
            if let best = night.bestTarget {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader("Top recommendation")
                    Text("\(best.target.displayName) · \(Int(best.score.rounded()))")
                        .font(.scaled(.headline, scale: uiTextScale))
                    Text(targetVerdictSentence(best))
                        .font(.scaled(.callout, scale: uiTextScale))
                    Text("\(best.usableHoursText) usable · \(best.fit.framingNote)")
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                }
            }
            if !plan.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader("Suggested plan")
                    ForEach(plan) { segment in
                        Text("\(Format.time(segment.window.start, in: night.timeZone))–\(Format.time(segment.window.end, in: night.timeZone))  \(segment.targetName)")
                            .font(.scaled(.callout, scale: uiTextScale).monospacedDigit())
                    }
                }
            }
        }
    }
}
