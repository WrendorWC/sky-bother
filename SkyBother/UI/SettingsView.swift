import SwiftUI
import CoreImage

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    /// Shown inside the Setup Wizard as its Advanced Setup sheet, where
    /// offering to run the wizard would be circular.
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
        // Sized on opening to the tallest pane, up to the screen.
        TabView {
            LocationSettings(isInGuidedSetup: isInGuidedSetup)
                .tabItem { Label("Location", systemImage: "mappin.and.ellipse") }
            EquipmentSettings()
                .tabItem { Label("Equipment", systemImage: "camera.aperture") }
            PlanningSettings()
                .tabItem { Label("Planning", systemImage: "slider.horizontal.3") }
            DisplaySettings()
                .tabItem { Label("Display", systemImage: "moon") }
            SyncSettings()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
        }
        .background(FitWindowToContent())
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
            if !isInGuidedSetup { SetupWizardBanner() }
            Section("Site in use") {
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
                    Button("Refresh Forecast for This Site") {
                        Task { await state.refresh(force: true) }
                    }
                    Spacer()
                    Button("Save as a Separate Spot") {
                        state.duplicateCurrentSite()
                    }
                    .help("Copy this site with its own horizon, for a second spot at the same place")
                }
            }

            Section("Change site") {
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
            Section("Horizon at \(state.site.name.isEmpty ? "this site" : state.site.name)") {
                HorizonEditor(site: $state.site)
                    .padding(.vertical, 4)
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
            Section("Telescope") {
                TextField("Name", text: $state.rig.name)
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
                Menu("Load a Preset") {
                    ForEach(Rig.PresetGroup.allCases) { group in
                        Section(group.rawValue) {
                            ForEach(Rig.presets.filter { $0.presetGroup == group }) { preset in
                                Button(preset.name) { state.applyPreset(preset) }
                            }
                        }
                    }
                }
                Text("Presets fill in every number for you.")
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
                        if state.isInUse(saved) {
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
                        Button("Update Saved Rig") { state.saveCurrentRig() }
                            .help("Overwrite the saved copy of this rig with the numbers below")
                    }
                    Button(state.isCurrentRigSaved ? "Save as New Rig" : "Save This Rig") { state.saveCurrentRigAsNew() }
                        .help("Keep these numbers as a separate saved rig")
                }
                .disabled(!state.rig.validationProblems.isEmpty)
                if state.isCurrentRigSaved {
                    Text("Edits apply now. The saved copy changes only with Update Saved Rig.")
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.secondary)
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

            Section("Optics") {
                // A preset's numbers are right as they are; tucked away so
                // they aren't edited by accident. Custom rigs keep them open.
                if state.rigIsUnchangedPreset {
                    DisclosureGroup("Optics numbers") { opticsFields }
                } else {
                    opticsFields
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
    @State private var isFineTuning = false

    var body: some View {
        Form {
            Section("Goal") {
                Picker("Kind of night", selection: goalBinding) {
                    ForEach(GoalPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                Text(GoalPreset.matching(state.preferences).summary)
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // The goal's own numbers: changing them makes it Custom.
                DisclosureGroup("Fine-tune", isExpanded: $isFineTuning) {
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
            }

            Section("What counts as usable") {
                sliderRow(title: "Maximum cloud cover",
                          value: $state.preferences.maximumCloudCover,
                          range: 0...100, step: 5,
                          display: "\(Int(state.preferences.maximumCloudCover))%",
                          caption: "Hours cloudier than this count less: half for every 6 points over.")

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
                Toggle("Show bright stars and doubles", isOn: $state.preferences.includeStars)
                    .help("Unticked, stars start hidden in the catalog and planner type filters")
                Toggle("Show visible comets", isOn: $state.preferences.includeComets)
                    .help("Unticked, comets start hidden in the catalog and planner type filters")
                Toggle("Include targets larger than the frame", isOn: $state.preferences.includeOversizedTargets)
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

/// The way back into the Setup Wizard, at the top of every Settings tab:
/// the quickest route to a sensible setup, for someone new or starting over.
// MARK: - Display

/// What suits this screen: the UI scale, night mode and units. They stay on
/// this Mac; sync leaves them alone.
private struct DisplaySettings: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section {
                Toggle(isOn: autoScale) {
                    Text("Size the UI to the window")
                        .font(.scaled(.body, scale: uiTextScale))
                    Text("Now \(Int((uiTextScale * 100).rounded()))%.")
                        .font(.scaled(.caption, scale: uiTextScale))
                }
                if !state.preferences.autoFitsText {
                    LabeledContent("UI scale") {
                        HStack {
                            Slider(value: $state.preferences.textScale, in: 0.85...1.5, step: 0.05)
                            Text("\(Int((state.preferences.textScale * 100).rounded()))%")
                                .monospacedDigit()
                                .frame(minWidth: 40, alignment: .trailing)
                        }
                    }
                }
                Toggle(isOn: $state.preferences.nightMode) {
                    Text("Night mode")
                        .font(.scaled(.body, scale: uiTextScale))
                    Text("Red light only, to keep your eyes dark-adapted at the scope.")
                        .font(.scaled(.caption, scale: uiTextScale))
                }
                Toggle(isOn: $state.preferences.usesImperialUnits) {
                    Text("Fahrenheit and mph")
                        .font(.scaled(.body, scale: uiTextScale))
                    Text("Off: Celsius and km/h.")
                        .font(.scaled(.caption, scale: uiTextScale))
                }
            } header: {
                Text("Display")
            } footer: {
                Text("These stay on this Mac; sync leaves them alone.")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.spaceBackground)
    }

    /// As the sidebar's Auto: turning it off starts the slider from
    /// whatever size Auto had reached, so nothing jumps.
    private var autoScale: Binding<Bool> {
        Binding(
            get: { state.preferences.autoFitsText },
            set: { auto in
                if !auto {
                    state.preferences.textScale = min(max((Double(uiTextScale) / 0.05).rounded() * 0.05, 0.85), 1.5)
                }
                state.preferences.autoFitsText = auto
                if auto { state.refitTextScale() }
            })
    }
}

private struct SetupWizardBanner: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var state: AppState

    var body: some View {
        Section {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("New here, or starting over?")
                        .font(.scaled(.body, scale: uiTextScale).weight(.semibold))
                    Text("The Setup Wizard walks you through your site, horizon, telescope and goal.")
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !state.canRestartSetup {
                        Label("Save or cancel the plan you're editing first.", systemImage: "exclamationmark.circle")
                            .font(.scaled(.callout, scale: uiTextScale))
                            .foregroundStyle(Palette.marginal)
                    }
                }
                Spacer(minLength: 12)
                Button {
                    state.restartSetup()
                    // The wizard runs in the main window; Settings would
                    // otherwise sit on top of it.
                    NSApp.keyWindow?.close()
                    MainWindow.bringForward(using: openWindow)
                } label: {
                    Label("Setup Wizard", systemImage: "wand.and.stars")
                        .font(.scaled(.body, scale: uiTextScale).weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!state.canRestartSetup)
                .help(state.canRestartSetup ? "Run the Setup Wizard" : "Save or cancel the plan you're editing first")
            }
            .padding(.vertical, 4)
        }
    }
}


// MARK: - Sync

/// Keeping this Mac, the web app and your phone in step with a sync code
/// (SyncController). No account; the server only holds an encrypted copy.
private struct SyncSettings: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    @ObservedObject private var sync = SyncController.shared
    @State private var typed = ""
    @State private var joinError: String?
    @State private var confirmingStop = false

    var body: some View {
        Form {
            if let code = sync.code {
                Section("This Mac is syncing") {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(code)
                                .font(.system(size: 18 * uiTextScale, weight: .bold, design: .monospaced))
                                .foregroundStyle(Palette.accent)
                                .textSelection(.enabled)
                            Text("Enter this code on your other devices — on the web, Settings → Sync at skybother.com — or scan the code with your phone. Keep it private: it's the key to your settings.")
                                .font(.scaled(.caption, scale: uiTextScale))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("Copy Code") { copy(code) }
                                if let link = sync.link { Button("Copy Link") { copy(link.absoluteString) } }
                                Button(sync.isSyncing ? "Syncing…" : "Sync Now") { sync.syncNow() }
                                    .disabled(sync.isSyncing)
                            }
                        }
                        if let link = sync.link, let qr = Self.qrCode(for: link.absoluteString) {
                            Image(nsImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 120, height: 120)
                                .padding(6)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                                .help("Scan with your phone's camera to sync it")
                        }
                    }
                    Text(sync.lastSynced.map { "Last synced \($0.formatted(.relative(presentation: .named)))." } ?? "Not synced yet.")
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                    if let error = sync.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.marginal)
                    }
                    HStack {
                        Button("Turn Off on This Mac") { sync.turnOff() }
                        Button("Stop Syncing Everywhere…", role: .destructive) { confirmingStop = true }
                    }
                }
            } else {
                Section("Sync") {
                    Text("Keep your sites, telescope, settings and plans the same here, in the web app and on your phone. No account: one device gets a sync code, the others enter it. Everything is encrypted on the device before it leaves.")
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Turn On Sync") { sync.turnOn() }
                }
                Section("I have a code") {
                    TextField("Sync code", text: $typed)
                        .font(.system(.body, design: .monospaced))
                    Button("Join") {
                        do {
                            try sync.join(typed)
                            typed = ""
                            joinError = nil
                        } catch {
                            joinError = error.localizedDescription
                        }
                    }
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("This Mac then takes on the synced settings.")
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                    if let joinError { Text(joinError).foregroundStyle(Palette.marginal) }
                    if let error = sync.errorMessage { Text(error).foregroundStyle(Palette.marginal) }
                }
            }

            Section("Setup link") {
                Text("A one-time link that gives the web app, your phone or a friend your site, telescope and settings. Unlike sync, it doesn't keep them in step afterwards.")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Copy Web Setup Link") {
                        if let link = state.settings.webSetupLink { copy(link.absoluteString) }
                    }
                    Button("Open on the Web") {
                        if let link = state.settings.webSetupLink { NSWorkspace.shared.open(link) }
                    }
                }
                .disabled(!state.settings.hasSetLocation)
            }

            Section("Settings file") {
                Text("Everything — sites, rigs, plans and settings — in one file, for a backup or the web app's Import Mac Settings File.")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Export Settings…") { SkyBotherApp.exportSettings(state.settings) }
                    .disabled(!state.settings.hasSetLocation)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.spaceBackground)
        .confirmationDialog("Stop syncing on every device?", isPresented: $confirmingStop) {
            Button("Stop Syncing Everywhere", role: .destructive) { sync.stopEverywhere() }
        } message: {
            Text("The synced copy is deleted. Each device keeps the settings it has now.")
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func qrCode(for text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
