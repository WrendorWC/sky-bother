import SwiftUI

/// Finding a site by name, or by coordinates for anyone who'd rather type
/// them — the first step of guided setup. Choosing a result makes it the
/// active site straight away; nothing here falls back to an invented default.
struct SiteFinder: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.uiTextScale) private var uiTextScale

    @State private var query = ""
    @State private var results: [GeocodingResult] = []
    @State private var isSearching = false
    @State private var searchError: String?

    @State private var showsManualEntry = false
    @State private var manualName = ""
    @State private var manualLatitude = ""
    @State private var manualLongitude = ""
    @State private var manualTimeZone = TimeZone.current.identifier

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !showsManualEntry {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Town, city or landmark", text: $query)
                            .textFieldStyle(.roundedBorder)
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

                    if !results.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
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
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }

                    Button("Enter coordinates instead") { showsManualEntry = true }
                        .buttonStyle(.link)
                        .font(.scaled(.callout, scale: uiTextScale))
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Name", text: $manualName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("Latitude", text: $manualLatitude)
                            .textFieldStyle(.roundedBorder)
                        TextField("Longitude", text: $manualLongitude)
                            .textFieldStyle(.roundedBorder)
                    }
                    Picker("Time zone", selection: $manualTimeZone) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
                            Text(identifier).tag(identifier)
                        }
                    }
                    if let manualError {
                        Text(manualError)
                            .font(.scaled(.caption, scale: uiTextScale))
                            .foregroundStyle(Palette.skip)
                    }
                    HStack {
                        Button("Use these coordinates") { submitManualSite() }
                            .disabled(!manualEntryLooksValid)
                        Button("Search instead") { showsManualEntry = false }
                            .buttonStyle(.link)
                    }
                }
            }

        }
    }

    private var manualEntryLooksValid: Bool {
        guard !manualName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let lat = Double(manualLatitude), let lon = Double(manualLongitude) else { return false }
        return (-90...90).contains(lat) && (-180...180).contains(lon)
    }

    private var manualError: String? {
        guard !manualLatitude.isEmpty || !manualLongitude.isEmpty else { return nil }
        if Double(manualLatitude) == nil || Double(manualLongitude) == nil {
            return "Latitude and longitude must be numbers."
        }
        if let lat = Double(manualLatitude), !(-90...90).contains(lat) {
            return "Latitude must be between -90 and 90."
        }
        if let lon = Double(manualLongitude), !(-180...180).contains(lon) {
            return "Longitude must be between -180 and 180."
        }
        return nil
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

    private func submitManualSite() {
        guard let lat = Double(manualLatitude), let lon = Double(manualLongitude) else { return }
        let site = Site(name: manualName.trimmingCharacters(in: .whitespaces),
                        latitude: lat,
                        longitude: lon,
                        elevationMeters: 0,
                        timeZoneIdentifier: manualTimeZone,
                        bortleClass: Site.unset.bortleClass,
                        horizonAltitude: Site.unset.horizonAltitude)
        state.finishLocationSetup(withManualSite: site)
        showsManualEntry = false
    }
}
