import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    /// Shown inside guided setup as its Advanced setup sheet, where offering
    /// to run guided setup would be circular.
    var isInGuidedSetup = false

    private enum Pane: String, CaseIterable, Identifiable {
        case location = "Location", equipment = "Equipment", planning = "Planning"
        var id: String { rawValue }
    }
    @State private var pane: Pane = .location

    var body: some View {
        if isInGuidedSetup {
            // A settings-style tab bar doesn't draw inside a sheet, so the
            // same three panes sit behind a segmented control there.
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(Pane.allCases) { option in
                        Button {
                            pane = option
                        } label: {
                            Text(option.rawValue)
                                .fontWeight(pane == option ? .semibold : .regular)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(pane == option ? Palette.accent.opacity(0.3) : Color.clear,
                                            in: Capsule())
                                .overlay(Capsule().strokeBorder(pane == option ? Palette.accent : Palette.panelBorder))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(pane == option ? .isSelected : [])
                    }
                }
                .padding(10)
                Group {
                    switch pane {
                    case .location: LocationSettings(isInGuidedSetup: true)
                    case .equipment: EquipmentSettings()
                    case .planning: PlanningSettings()
                    }
                }
            }
            .frame(width: 640, height: 580)
            .onChange(of: state.settings) { _, _ in state.requestReplan() }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView {
            LocationSettings(isInGuidedSetup: isInGuidedSetup)
                .tabItem { Label("Location", systemImage: "mappin.and.ellipse") }
            EquipmentSettings()
                .tabItem { Label("Equipment", systemImage: "camera.aperture") }
            PlanningSettings()
                .tabItem { Label("Planning", systemImage: "slider.horizontal.3") }
        }
        // Resizable both ways: the panes scroll, so a smaller window only
        // means less at once.
        .frame(minWidth: 560, idealWidth: 640, maxWidth: .infinity,
               minHeight: 320, idealHeight: 580, maxHeight: .infinity)
        .background(ResizableWindow())
        .onChange(of: state.settings) { _, _ in
            state.requestReplan()
        }
    }
}

// MARK: - Location

private struct LocationSettings: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    var isInGuidedSetup = false
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""
    @State private var results: [GeocodingResult] = []
    @State private var isSearching = false
    @State private var searchError: String?

    var body: some View {
        Form {
            if !isInGuidedSetup {
            Section {
                HStack {
                    Text("Step through site, horizon, rig and goal.")
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Run Guided Setup…") {
                        state.restartSetup()
                        // Setup appears in the main window; Settings would
                        // otherwise sit on top of it.
                        NSApp.keyWindow?.close()
                        MainWindow.bringForward(using: openWindow)
                    }
                    .disabled(state.planDraft != nil)
                }
            }
            }
            Section("Find a site") {
                HStack {
                    TextField("Town, city or landmark", text: $query)
                        .onSubmit { Task { await search() } }
                    Button("Search") { Task { await search() } }
                        .disabled(query.trimmingCharacters(in: .whitespaces).count < 2 || isSearching)
                    if isSearching { ProgressView().controlSize(.small) }
                }
                if let searchError {
                    Text(searchError)
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(Palette.skip)
                }
                ForEach(results) { result in
                    Button {
                        state.apply(result)
                        results = []
                        query = ""
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.name)
                            Text(result.subtitle)
                                .font(.scaled(.caption, scale: uiTextScale))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Current site") {
                TextField("Name", text: $state.site.name)

                Picker("Time zone", selection: $state.site.timeZoneIdentifier) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
                        Text(identifier).tag(identifier)
                    }
                }

                Picker("Light pollution", selection: $state.site.bortleClass) {
                    ForEach(1...9, id: \.self) { value in
                        Text("Bortle \(value) — \(Site.bortleDescription(for: value))")
                            .tag(value)
                    }
                }

                // Search sets these; typing them is the exception.
                DisclosureGroup("Coordinates and elevation") {
                    HStack {
                        TextField("Latitude (°)", value: $state.site.latitude, format: .number.precision(.fractionLength(4)))
                        TextField("Longitude (°)", value: $state.site.longitude, format: .number.precision(.fractionLength(4)))
                    }
                    TextField("Elevation (m)", value: $state.site.elevationMeters, format: .number.precision(.fractionLength(0)))
                }

                HStack {
                    Button("Refresh forecast for this site") {
                        Task { await state.refresh(force: true) }
                    }
                    Spacer()
                    Button("Save as a separate spot") {
                        state.duplicateCurrentSite()
                    }
                    .help("Copy this site with its own horizon, for a second spot at the same place")
                }
            }

            Section("Horizon") {
                HorizonEditor(site: $state.site)
                    .padding(.vertical, 4)
            }

            if state.settings.savedSites.count > 1 {
                Section("Saved sites") {
                    ForEach(sortedSavedSites) { saved in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(saved.name)
                                Text("\(saved.coordinateSummary) · Bortle \(saved.bortleClass)")
                                    .font(.scaled(.caption, scale: uiTextScale))
                                    .foregroundStyle(.secondary)
                                // The line that tells two spots at one address
                                // apart — everything above it is identical for
                                // a front yard and a back yard.
                                Text(saved.horizonSummary)
                                    .font(.scaled(.caption, scale: uiTextScale))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if saved.id == state.site.id {
                                Text("in use")
                                    .font(.scaled(.caption, scale: uiTextScale))
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Use") {
                                    state.switchToSavedSite(saved)
                                }
                            }
                            Button {
                                state.removeSite(saved)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this saved site")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.spaceBackground)
    }

    /// Sorted for reading rather than left in the order they happened to be
    /// created, which told you only which one you set up first. Compared the
    /// way Finder compares filenames, so the numbers in the names that
    /// "Save as a separate spot" generates run 2, 3 … 10 instead of 10, 2, 3.
    private var sortedSavedSites: [Site] {
        state.settings.savedSites.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func search() async {
        isSearching = true
        searchError = nil
        do {
            results = try await GeocodingClient().search(query)
            if results.isEmpty { searchError = "Nothing found for “\(query)”." }
        } catch {
            searchError = error.localizedDescription
        }
        isSearching = false
    }
}

// MARK: - Equipment

private struct EquipmentSettings: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("Presets") {
                Menu("Load a preset") {
                    ForEach(Rig.PresetGroup.allCases) { group in
                        Section(group.rawValue) {
                            ForEach(Rig.presets.filter { $0.presetGroup == group }) { preset in
                                Button(preset.name) { state.applyPreset(preset) }
                            }
                        }
                    }
                }
                Text("Presets fill in every number below.")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            }

            Section("Your rigs") {
                if state.settings.savedRigs.isEmpty {
                    Text("Enter your numbers below, then save the rig to switch back to it later.")
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                }
                ForEach(state.settings.savedRigs) { saved in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(saved.name)
                            Text(saved.opticalSummary)
                                .font(.scaled(.caption, scale: uiTextScale))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if saved.id == state.rig.id {
                            Text("in use")
                                .font(.scaled(.caption, scale: uiTextScale))
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Use") { state.useSavedRig(saved) }
                        }
                        Button {
                            state.removeRig(saved)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this saved rig")
                    }
                }
                HStack {
                    if state.isCurrentRigSaved {
                        Button("Update saved rig") { state.saveCurrentRig() }
                            .help("Overwrite the saved copy of this rig with the numbers below")
                    }
                    Button(state.isCurrentRigSaved ? "Save as new rig" : "Save this rig") { state.saveCurrentRigAsNew() }
                        .help("Keep these numbers as a separate saved rig")
                }
                .disabled(!state.rig.validationProblems.isEmpty)
                Text("Edits apply now. The saved copy changes only with Update saved rig.")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            }

            Section("Optics") {
                TextField("Name", text: $state.rig.name)
                // A preset's numbers are right as they are; tucked away so
                // they aren't edited by accident. Custom rigs keep them open.
                if state.rigIsUnchangedPreset {
                    DisclosureGroup("Advanced: optics numbers") { opticsFields }
                } else {
                    opticsFields
                }
            }

            Section("Mount and filters") {
                Picker("Mount", selection: $state.rig.mountType) {
                    ForEach(MountType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Toggle("Dual-band / narrowband filter", isOn: $state.rig.hasNarrowbandFilter)
                Toggle("Can shoot mosaics", isOn: $state.rig.supportsMosaic)
                if state.rig.mountType.rotatesField {
                    Toggle("Show zenith risk warnings", isOn: $state.preferences.showsZenithRiskWarnings)
                    if state.preferences.showsZenithRiskWarnings {
                        VStack(alignment: .leading) {
                            Slider(value: $state.rig.zenithAvoidanceAltitude, in: 60...90, step: 1) {
                                Text("Warn above")
                            }
                            Text("Targets passing above \(Format.degrees(state.rig.zenithAvoidanceAltitude)) get a warning.")
                                .font(.scaled(.caption, scale: uiTextScale))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("What that gives you") {
                let problems = state.rig.validationProblems
                if problems.isEmpty {
                    LabeledContent("Field of view", value: "\(state.rig.fieldOfViewSummary) — \(state.rig.fieldOfViewInMoons)")
                    LabeledContent("Focal ratio", value: String(format: "f/%.1f", state.rig.focalRatio))
                    LabeledContent("Image scale", value: String(format: "%.2f″ per pixel", state.rig.arcsecondsPerPixel))
                } else {
                    ForEach(problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.marginal)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.spaceBackground)
    }

    @ViewBuilder
    private var opticsFields: some View {
        TextField("Aperture (mm)", value: $state.rig.apertureMillimeters, format: .number)
        TextField("Focal length (mm)", value: $state.rig.focalLengthMillimeters, format: .number)
        HStack {
            TextField("Sensor width (mm)", value: $state.rig.sensorWidthMillimeters, format: .number)
            TextField("Sensor height (mm)", value: $state.rig.sensorHeightMillimeters, format: .number)
        }
        TextField("Pixel size (µm)", value: $state.rig.pixelSizeMicrons, format: .number)
    }
}

// MARK: - Planning

private struct PlanningSettings: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("Goal") {
                Picker("Kind of night", selection: goalBinding) {
                    ForEach(GoalPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                Text(GoalPreset.matching(state.preferences).summary + " Changing the values below makes it Custom.")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("What counts as usable") {
                sliderRow(title: "Maximum cloud cover",
                          value: $state.preferences.maximumCloudCover,
                          range: 0...100, step: 5,
                          display: "\(Int(state.preferences.maximumCloudCover))%",
                          caption: "Hours cloudier than this are written off.")

                sliderRow(title: "Minimum darkness",
                          value: $state.preferences.minimumDarkness,
                          range: 0.1...1, step: 0.05,
                          display: String(format: "Sun below %.0f°", darknessSunAltitude),
                          caption: "−18° is full astronomical darkness. Moonlight is scored separately.")

                sliderRow(title: "Minimum altitude",
                          value: $state.preferences.minimumUsefulAltitude,
                          range: 10...60, step: 5,
                          display: Format.degrees(state.preferences.minimumUsefulAltitude),
                          caption: "Targets lower than this are ignored — there you look through \(String(format: "%.1f", SkyCoordinates.airMass(altitude: state.preferences.minimumUsefulAltitude))) times as much air as straight up.")

                sliderRow(title: "Integration goal",
                          value: $state.preferences.integrationGoalMinutes,
                          range: 30...480, step: 15,
                          display: Format.duration(minutes: state.preferences.integrationGoalMinutes),
                          caption: "Full marks for time once a target is usable this long.")

                VStack(alignment: .leading, spacing: 4) {
                    Picker("Suggested plan favours", selection: $state.preferences.planEmphasis) {
                        ForEach(PlanEmphasis.allCases, id: \.self) { emphasis in
                            Text(emphasis.title).tag(emphasis)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(planEmphasisCaption)
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                }
            }

            Section("What to show") {
                sliderRow(title: "Hide below score",
                          value: $state.preferences.minimumScore,
                          range: 0...80, step: 5,
                          display: "\(Int(state.preferences.minimumScore)) · \(Verdict.forScore(state.preferences.minimumScore).rawValue)",
                          caption: hiddenCaption)

                Stepper("Plan \(state.preferences.forecastNights) night\(state.preferences.forecastNights == 1 ? "" : "s") ahead",
                        value: $state.preferences.forecastNights, in: 1...14)

                Toggle("Include star clusters", isOn: $state.preferences.includeStarClusters)
                Toggle("Include targets larger than the frame", isOn: $state.preferences.includeOversizedTargets)
                Toggle("Use Fahrenheit and mph", isOn: $state.preferences.usesImperialUnits)
            }

        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.spaceBackground)
    }

    private var planEmphasisCaption: String {
        let cap = Format.duration(minutes: state.preferences.sessionCapMinutes)
        let floor = Format.duration(minutes: state.preferences.minimumSessionMinutes)
        switch state.preferences.planEmphasis {
        case .longerIntegration:
            return "At most \(cap) per target, and nothing shorter than \(floor)."
        case .moreTargets:
            return "At most \(cap) per target, so about twice as many fit, down to \(floor)."
        }
    }

    /// The stored darkness is a 0–1 value on the twilight curve; shown as the
    /// solar altitude it stands for, by inverting that curve.
    private var darknessSunAltitude: Double {
        let t = pow(clamp(state.preferences.minimumDarkness, 0, 1), 1 / 1.4)
        return -(t * 12 + 6)
    }

    private var goalBinding: Binding<GoalPreset> {
        Binding(get: { GoalPreset.matching(state.preferences) },
                set: { state.applyGoalPreset($0) })
    }

    /// What the threshold means, and what it's hiding right now.
    private var hiddenCaption: String {
        let threshold = Int(state.preferences.minimumScore)
        guard let night = state.selectedPlan ?? state.tonight else {
            return "Targets scoring under \(threshold) are hidden."
        }
        let hidden = night.targets.filter { $0.score < state.preferences.minimumScore }.count
        let day = Format.weekday(night.date, in: night.timeZone)
        return "Hides \(hidden) of \(night.targets.count) targets on \(day)."
    }

    private func sliderRow(title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double,
                           display: String,
                           caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(display)
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            Slider(value: value, in: range, step: step) { Text(title) }
                .labelsHidden()
                .accessibilityValue(display)
            Text(caption)
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
