import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            LocationSettings()
                .tabItem { Label("Location", systemImage: "mappin.and.ellipse") }
            EquipmentSettings()
                .tabItem { Label("Equipment", systemImage: "camera.aperture") }
            PlanningSettings()
                .tabItem { Label("Planning", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 640, height: 580)
        .onChange(of: state.settings) { _, _ in
            state.requestReplan()
        }
    }
}

// MARK: - Location

private struct LocationSettings: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    @State private var query = ""
    @State private var results: [GeocodingResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var showsHorizonProfile = false

    var body: some View {
        Form {
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
                HStack {
                    TextField("Latitude", value: $state.site.latitude, format: .number.precision(.fractionLength(4)))
                    TextField("Longitude", value: $state.site.longitude, format: .number.precision(.fractionLength(4)))
                }
                TextField("Elevation (m)", value: $state.site.elevationMeters, format: .number.precision(.fractionLength(0)))

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
                Text("Bortle class decides whether galaxies are realistic from here. If you do not know yours, look your site up on a light pollution map — it is the single most useful number in this app.")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)

                horizonControls

                HStack {
                    Button("Refresh forecast for this site") {
                        Task { await state.refresh(force: true) }
                    }
                    Spacer()
                    Button("Save as a separate spot") {
                        state.duplicateCurrentSite()
                    }
                    .help("Copy this site — same place, same weather, same Bortle class — as a second entry with its own horizon, for a front yard and a back yard that see different amounts of sky")
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

    // MARK: - Horizon

    /// The baseline slider sets every direction at once; the disclosure below
    /// it is for the one tree that ruins the rest. That order matters — almost
    /// every site is "about this open all round, except over there", and
    /// asking for eight numbers up front to express that would be eight times
    /// the work for the same answer.
    @ViewBuilder
    private var horizonControls: some View {
        VStack(alignment: .leading) {
            Slider(value: baselineHorizon, in: 0...60, step: 1) {
                Text("Blocked horizon")
            }
            Text(baselineHorizonCaption)
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.secondary)
        }

        DisclosureGroup(isExpanded: $showsHorizonProfile) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Site.horizonDirections.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text(Site.horizonDirections[index])
                            .font(.scaled(.caption, scale: uiTextScale).weight(.semibold).monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .leading)
                        Slider(value: horizonBinding(forDirectionAt: index), in: 0...60, step: 1)
                        Text(Format.degrees(state.site.horizonByDirection[index]))
                            .font(.scaled(.caption, scale: uiTextScale).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                Text("Each direction covers the 45° of sky centred on it, so S also covers SSE through SSW. A target is ignored while it sits below the line for whichever direction it is in — it keeps the rest of its night.")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(.top, 4)
        } label: {
            Text("One direction is worse")
        }
        // Opened for you when this site already has a tree recorded, so it
        // isn't hidden behind a triangle you have no reason to click.
        .task(id: state.site.id) { showsHorizonProfile = state.site.hasDirectionalHorizon }
    }

    /// Flattens the horizon on every change: this is the "set them all at
    /// once" control, so it deliberately discards per-direction detail rather
    /// than trying to shift eight values while preserving their spacing, which
    /// falls apart the moment one of them hits an end of the range.
    private var baselineHorizon: Binding<Double> {
        Binding(get: { state.site.horizonAltitude },
                set: { state.site.setHorizonEverywhere(to: $0) })
    }

    private func horizonBinding(forDirectionAt index: Int) -> Binding<Double> {
        Binding(get: { state.site.horizonByDirection[index] },
                set: { state.site.setHorizon(to: $0, forDirectionAt: index) })
    }

    private var baselineHorizonCaption: String {
        let baseline = Format.degrees(state.site.horizonAltitude)
        guard state.site.hasDirectionalHorizon else {
            return "Trees, houses and hills block the sky below \(baseline) all the way round. Targets are ignored under this."
        }
        return "Your most open direction is \(baseline); the worst is \(Format.degrees(state.site.worstHorizonAltitude)). Dragging this levels every direction back to one number."
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
                    ForEach(Rig.presets) { preset in
                        Button(preset.name) { state.applyPreset(preset) }
                    }
                }
                Text("Presets use published optical specs and the standard dimensions of each model's sensor. Check them against your own unit — everything below is editable.")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            }

            Section("Your rigs") {
                if state.settings.savedRigs.isEmpty {
                    Text("Enter your numbers below, then save the rig here to switch back to it later. This is how you add an instrument that has no built-in preset.")
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
                Button(state.isCurrentRigSaved ? "Update saved rig" : "Save this rig") {
                    state.saveCurrentRig()
                }
            }

            Section("Optics") {
                TextField("Name", text: $state.rig.name)
                TextField("Aperture (mm)", value: $state.rig.apertureMillimeters, format: .number)
                TextField("Focal length (mm)", value: $state.rig.focalLengthMillimeters, format: .number)
                HStack {
                    TextField("Sensor width (mm)", value: $state.rig.sensorWidthMillimeters, format: .number)
                    TextField("Sensor height (mm)", value: $state.rig.sensorHeightMillimeters, format: .number)
                }
                TextField("Pixel size (µm)", value: $state.rig.pixelSizeMicrons, format: .number)
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
                            Text("Alt-az mounts rotate the field fastest overhead, and many smart telescopes stall near the zenith. Targets passing above \(Format.degrees(state.rig.zenithAvoidanceAltitude)) get a warning.")
                                .font(.scaled(.caption, scale: uiTextScale))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("What that gives you") {
                LabeledContent("Field of view", value: state.rig.fieldOfViewSummary)
                LabeledContent("Focal ratio", value: String(format: "f/%.1f", state.rig.focalRatio))
                LabeledContent("Sampling", value: String(format: "%.2f″/pixel", state.rig.arcsecondsPerPixel))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.spaceBackground)
    }
}

// MARK: - Planning

private struct PlanningSettings: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    @ObservedObject private var tiles = SkyTileStore.shared

    var body: some View {
        Form {
            Section("What counts as usable") {
                sliderRow(title: "Maximum cloud cover",
                          value: $state.preferences.maximumCloudCover,
                          range: 0...100, step: 5,
                          caption: "Hours cloudier than \(Int(state.preferences.maximumCloudCover))% are written off.")

                sliderRow(title: "Minimum darkness",
                          value: $state.preferences.minimumDarkness,
                          range: 0.1...1, step: 0.05,
                          caption: darknessCaption)

                sliderRow(title: "Minimum altitude",
                          value: $state.preferences.minimumUsefulAltitude,
                          range: 10...60, step: 5,
                          caption: "Ignore targets below \(Format.degrees(state.preferences.minimumUsefulAltitude)) — that is \(String(format: "%.1f", SkyCoordinates.airMass(altitude: state.preferences.minimumUsefulAltitude))) air masses.")

                sliderRow(title: "Integration goal",
                          value: $state.preferences.integrationGoalMinutes,
                          range: 30...480, step: 15,
                          caption: "A target scores full marks for time once it offers \(Format.duration(minutes: state.preferences.integrationGoalMinutes)).")

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

            Section("Offline sky imagery") {
                skyImagerySettings
            }

            Section("What to show") {
                sliderRow(title: "Hide below score",
                          value: $state.preferences.minimumScore,
                          range: 0...80, step: 5,
                          caption: "Targets scoring under \(Int(state.preferences.minimumScore)) are hidden.")

                Stepper("Plan \(state.preferences.forecastNights) nights ahead",
                        value: $state.preferences.forecastNights, in: 1...14)
                Text("Open-Meteo forecasts further out than this, but cloud cover past about a week is not worth acting on.")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)

                Toggle("Include star clusters", isOn: $state.preferences.includeStarClusters)
                Toggle("Include targets larger than the frame", isOn: $state.preferences.includeOversizedTargets)
                Toggle("Use Fahrenheit and mph", isOn: $state.preferences.usesImperialUnits)
            }

        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.spaceBackground)
    }

    // MARK: - Offline sky imagery

    /// How much of the survey to keep on disk.
    ///
    /// The whole thing at native resolution is about 157 GB, which is not an
    /// option worth offering. What is worth offering is a base layer: keep the
    /// wide views instant and offline, and let the fine detail arrive as it is
    /// needed. Anything deeper than the chosen order is fetched for whatever
    /// you happen to be looking at and kept, so browsing sharpens the cache
    /// where you actually go.
    @ViewBuilder
    private var skyImagerySettings: some View {
        Picker("Keep offline", selection: $state.preferences.offlineSkyOrder) {
            Text("Nothing — fetch as needed").tag(0)
            ForEach(3...7, id: \.self) { order in
                Text("\(Format.bytes(SkyTileStore.estimatedBytes(forOrder: order))) · sharp to \(Format.arcseconds(SkyTileStore.resolutionArcseconds(forOrder: order)))/px")
                    .tag(order)
            }
        }
        Text(offlineSkyCaption)
            .font(.scaled(.caption, scale: uiTextScale))
            .foregroundStyle(.secondary)

        HStack(spacing: 10) {
            if let downloading = tiles.downloadingOrder {
                ProgressView(value: Double(tiles.downloadedTiles),
                             total: Double(max(1, tiles.totalTiles)))
                    .frame(maxWidth: 180)
                Text("\(tiles.downloadedTiles) of \(tiles.totalTiles)")
                    .font(.scaled(.caption, scale: uiTextScale).monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Stop") { tiles.cancelDownload() }
                let _ = downloading
            } else if state.preferences.offlineSkyOrder > 0 {
                Button("Download now") { tiles.download(order: state.preferences.offlineSkyOrder) }
            }
            Spacer()
            Text("\(Format.bytes(tiles.bytesOnDisk)) on disk")
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.secondary)
            Button("Clear") { tiles.clear() }
                .disabled(tiles.bytesOnDisk == 0)
        }
        .task { tiles.refreshUsage() }
    }

    private var offlineSkyCaption: String {
        let order = state.preferences.offlineSkyOrder
        guard order > 0 else {
            return "Sky images are fetched as you look at them and kept afterwards, blended into one smooth picture. Nothing is downloaded in advance, so the first look at a patch of sky waits on the network."
        }
        return "Downloads the whole sky at this detail, plus every coarser level, so panning and zooming are instant and work with no network. Zooming in past it still fetches sharper tiles for wherever you are looking, and keeps them. Note that downloaded sky is drawn tile by tile rather than blended, and the survey's photographic plates differ enough in brightness that you can see where they join — this buys speed, not a better picture."
    }

    private var planEmphasisCaption: String {
        let cap = Format.duration(minutes: state.preferences.sessionCapMinutes)
        let floor = Format.duration(minutes: state.preferences.minimumSessionMinutes)
        switch state.preferences.planEmphasis {
        case .longerIntegration:
            return "No target is handed more than \(cap) before the others get a turn, and nothing under \(floor) is suggested at all — by the time the mount has slewed and refocused, a shorter slot is gone. Time nobody else wants is still given back afterwards."
        case .moreTargets:
            return "Half your Integration goal — \(cap) — so roughly twice as many targets fit, down to sessions of \(floor). Only changes what the app suggests; a plan you've edited is left alone."
        }
    }

    private var darknessCaption: String {
        // Invert the twilight curve to show which solar altitude this equals.
        let t = pow(clamp(state.preferences.minimumDarkness, 0, 1), 1 / 1.4)
        let sunAltitude = -(t * 12 + 6)
        return String(format: "Counts the sky as dark once the sun is below %.0f°. Moonlight is scored separately, per target.", sunAltitude)
    }

    private func sliderRow(title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double,
                           caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Slider(value: value, in: range, step: step) { Text(title) }
            Text(caption)
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
