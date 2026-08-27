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
        .frame(width: 520, height: 470)
        .onChange(of: state.settings) { _, _ in
            state.requestReplan()
        }
    }
}

// MARK: - Location

private struct LocationSettings: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""
    @State private var results: [GeocodingResult] = []
    @State private var isSearching = false
    @State private var searchError: String?

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
                        .font(.caption)
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
                                .font(.caption)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading) {
                    Slider(value: $state.site.horizonAltitude, in: 0...45, step: 1) {
                        Text("Blocked horizon")
                    }
                    Text("Trees, houses and hills block the sky below \(Format.degrees(state.site.horizonAltitude)). Targets are ignored under this.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Refresh forecast for this site") {
                    Task { await state.refresh() }
                }
            }

            if state.settings.savedSites.count > 1 {
                Section("Saved sites") {
                    ForEach(state.settings.savedSites) { saved in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(saved.name)
                                Text("\(saved.coordinateSummary) · Bortle \(saved.bortleClass)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if saved.id != state.site.id {
                                Button("Use") {
                                    state.site = saved
                                    Task { await state.refresh() }
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("Preset") {
                Menu("Load a preset") {
                    ForEach(Rig.presets) { preset in
                        Button(preset.name) { state.applyPreset(preset) }
                    }
                }
                Text("Presets use published optical specs and the standard dimensions of each model's sensor. Check them against your own unit — everything below is editable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    VStack(alignment: .leading) {
                        Slider(value: $state.rig.zenithAvoidanceAltitude, in: 60...90, step: 1) {
                            Text("Warn above")
                        }
                        Text("Alt-az mounts rotate the field fastest overhead, and many smart telescopes stall near the zenith. Targets passing above \(Format.degrees(state.rig.zenithAvoidanceAltitude)) get a warning.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
    }
}

// MARK: - Planning

private struct PlanningSettings: View {
    @EnvironmentObject private var state: AppState

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
            }

            Section("What to show") {
                sliderRow(title: "Hide below score",
                          value: $state.preferences.minimumScore,
                          range: 0...80, step: 5,
                          caption: "Targets scoring under \(Int(state.preferences.minimumScore)) are hidden.")

                Stepper("Plan \(state.preferences.forecastNights) nights ahead",
                        value: $state.preferences.forecastNights, in: 1...14)
                Text("Open-Meteo forecasts further out than this, but cloud cover past about a week is not worth acting on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Include star clusters", isOn: $state.preferences.includeStarClusters)
                Toggle("Include targets larger than the frame", isOn: $state.preferences.includeOversizedTargets)
                Toggle("Use Fahrenheit and mph", isOn: $state.preferences.usesImperialUnits)
            }
        }
        .formStyle(.grouped)
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
