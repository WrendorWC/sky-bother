import SwiftUI

enum DarkSkyState {
    case idle
    case searching(radiusKilometers: Double, site: Site)
    case found(DarkSkySearchResult)
    case failed(String)
}

struct DarkSpotComparison: Hashable, Sendable {
    /// Targets scoring "Good" or better tonight from each place.
    var targetsHere: Int
    var targetsThere: Int
    /// Tonight's forecast rules out imaging anyway, so the counts describe what
    /// would be worth shooting if it cleared.
    var isCloudedOut: Bool
}

/// "Darker Sky Nearby" — the sidebar panel that suggests a real place within
/// driving distance with less light pollution than the current site. One
/// control (how far you're willing to go) and an automatic answer; everything
/// else about the search is decided for you.
struct DarkerSkyPanel: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    /// Index into `distanceOptions`. Kept in UserDefaults rather than
    /// `Preferences`, since it's a view setting and not a planning threshold.
    @AppStorage("darkSkyDistanceStep") private var distanceStep = 1
    @State private var selectedSpotID: String?

    private struct DistanceOption: Hashable {
        var label: String
        var kilometers: Double
    }

    /// Driving distance follows the Mac's region, not the app's Fahrenheit/mph
    /// setting — plenty of US astronomers keep temperatures in Celsius but
    /// still think about a drive in miles. The UK counts road distance in
    /// miles too, despite being otherwise metric.
    private var usesMiles: Bool {
        Locale.current.measurementSystem != .metric
    }

    private var distanceOptions: [DistanceOption] {
        if usesMiles {
            return [DistanceOption(label: "5 mi", kilometers: 8.05),
                    DistanceOption(label: "15 mi", kilometers: 24.1),
                    DistanceOption(label: "30 mi", kilometers: 48.3)]
        }
        return [DistanceOption(label: "10 km", kilometers: 10),
                DistanceOption(label: "25 km", kilometers: 25),
                DistanceOption(label: "50 km", kilometers: 50)]
    }

    private var selectedDistance: DistanceOption {
        distanceOptions[min(max(distanceStep, 0), distanceOptions.count - 1)]
    }

    private struct SearchKey: Hashable {
        var latitude: Double
        var longitude: Double
        var radiusKilometers: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Darker Sky Nearby")
                .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Distance", selection: $distanceStep) {
                ForEach(distanceOptions.indices, id: \.self) { index in
                    Text(distanceOptions[index].label).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .hoverTooltip("How far you're willing to drive")

            content

            if let home = state.darkSpotReturnSite {
                Button {
                    state.returnFromDarkSpot()
                } label: {
                    Label("Back to \(home.name)", systemImage: "arrow.uturn.backward")
                        .font(.scaled(.caption, scale: uiTextScale))
                }
                .buttonStyle(.link)
            }
        }
        .task(id: SearchKey(latitude: state.site.latitude,
                            longitude: state.site.longitude,
                            radiusKilometers: selectedDistance.kilometers)) {
            selectedSpotID = nil
            state.findDarkerSky(radiusKilometers: selectedDistance.kilometers)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.darkSky {
        case .idle, .searching:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking satellite night lights…")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

        case .failed(let error):
            VStack(alignment: .leading, spacing: 4) {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(Palette.marginal)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") {
                    state.retryDarkerSky(radiusKilometers: selectedDistance.kilometers)
                }
                .buttonStyle(.link)
                .font(.scaled(.caption, scale: uiTextScale))
            }

        case .found(let result):
            settingHint(result)
            if let featured = result.spots.first(where: { $0.id == selectedSpotID }) ?? result.spots.first {
                spotCard(featured, siteEstimate: result.siteEstimatedBortleClass)
                ForEach(result.spots.filter { $0.id != featured.id }) { alternate in
                    alternateRow(alternate)
                }
                Text("Bortle classes are estimated from NASA satellite night lights. Check it's open and safe after dark.")
                    .font(.scaled(.caption2, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if result.siteEstimatedBortleClass <= 3 {
                message("Your sky is already dark — about Bortle \(result.siteEstimatedBortleClass). An open spot with a low horizon is the only upgrade left.")
            } else {
                message("Nothing noticeably darker within \(selectedDistance.label). Try a longer drive — or just an open spot away from direct lights.")
            }
        }
    }

    /// The whole comparison leans on the site's own Bortle class being roughly
    /// right, and it's the number beginners most often guess. Two classes is
    /// well outside the model's own scatter, so a gap that size is worth a word.
    @ViewBuilder
    private func settingHint(_ result: DarkSkySearchResult) -> some View {
        let estimate = result.siteEstimatedBortleClass
        if result.anchor.id == state.site.id, abs(state.site.bortleClass - estimate) >= 2 {
            VStack(alignment: .leading, spacing: 2) {
                Text("Satellite data puts \(state.site.name) nearer Bortle \(estimate) than the \(state.site.bortleClass) it's set to.")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(Palette.marginal)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Use Bortle \(estimate)") {
                    state.useEstimatedBortleClass(estimate)
                }
                .buttonStyle(.link)
                .font(.scaled(.caption, scale: uiTextScale))
                .hoverTooltip("Changes Light pollution in Settings → Location for this site")
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.scaled(.caption, scale: uiTextScale))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func spotCard(_ spot: DarkSpot, siteEstimate: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(spot.name)
                .font(.scaled(.body, scale: uiTextScale).weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(distanceText(spot.distanceKilometers)) \(spot.direction) · Bortle \(spot.estimatedBortleClass) (here: \(siteEstimate))")
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ComparisonLine(spot: spot)

            HStack(spacing: 10) {
                Button("Use This Spot") {
                    state.useDarkSpot(spot)
                }
                .hoverTooltip("Plan from here instead — saved alongside your current site")
                if let url = spot.mapsURL {
                    Link(destination: url) {
                        Label("Map", systemImage: "map")
                    }
                    .hoverTooltip("Open in Maps for directions")
                }
            }
            .controlSize(.small)
            .font(.scaled(.caption, scale: uiTextScale))
            .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }

    private func alternateRow(_ spot: DarkSpot) -> some View {
        Button {
            selectedSpotID = spot.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle")
                    .foregroundStyle(Palette.accent)
                Text(spot.name)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(distanceText(spot.distanceKilometers)) · B\(spot.estimatedBortleClass)")
                    .foregroundStyle(.secondary)
            }
            .font(.scaled(.caption, scale: uiTextScale))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    private func distanceText(_ kilometers: Double) -> String {
        let value = usesMiles ? kilometers * 0.621371 : kilometers
        let unit = usesMiles ? "mi" : "km"
        return value < 10 ? String(format: "%.1f %@", value, unit) : String(format: "%.0f %@", value, unit)
    }
}

/// Tonight from the spot versus from the current site. Recomputed whenever the
/// rig, preferences or forecast change, since each of those moves the counts.
private struct ComparisonLine: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    var spot: DarkSpot
    @State private var comparison: DarkSpotComparison?

    private struct Key: Hashable {
        var spotID: String
        var site: Site
        var rig: Rig
        var preferences: Preferences
        var forecastRetrievedAt: Date
        var customTargetCount: Int
    }

    var body: some View {
        Group {
            if let comparison {
                let gained = comparison.targetsThere - comparison.targetsHere
                Label {
                    Text(summary(comparison, gained: gained))
                } icon: {
                    Image(systemName: "sparkles")
                }
                .foregroundStyle(gained > 0 ? Palette.go : Color.secondary)
            } else {
                Text(" ")
            }
        }
        .font(.scaled(.caption, scale: uiTextScale))
        .fixedSize(horizontal: false, vertical: true)
        .task(id: Key(spotID: spot.id, site: state.site, rig: state.rig, preferences: state.preferences,
                      forecastRetrievedAt: state.forecast.retrievedAt,
                      customTargetCount: state.customTargets.count)) {
            comparison = nil
            let computed = await state.tonightComparison(for: spot)
            guard !Task.isCancelled else { return }
            comparison = computed
        }
    }

    private func summary(_ comparison: DarkSpotComparison, gained: Int) -> String {
        let when = comparison.isCloudedOut ? "if it clears tonight" : "tonight"
        guard gained > 0 else {
            return "Same \(comparison.targetsThere) good targets \(when) as from here"
        }
        return "\(comparison.targetsThere) good targets \(when) — \(gained) more than from here"
    }
}
