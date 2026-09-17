import SwiftUI

struct NearbySpotSearchKey: Hashable, Sendable {
    var goal: SpotGoal
    var latitude: Double
    var longitude: Double
    var radiusKilometers: Double
}

enum NearbySpotState {
    case idle
    case searching(NearbySpotSearchKey)
    case found(NearbySpotSearchResult)
    case failed(String)
}

struct SpotComparison: Hashable, Sendable {
    /// Targets scoring "Good" or better tonight from each place.
    var targetsHere: Int
    var targetsThere: Int
    /// Tonight's forecast rules out imaging anyway, so the counts describe what
    /// would be worth shooting if it cleared.
    var isCloudedOut: Bool
}

/// "Better Spot Nearby" — the sidebar section that suggests a real place a
/// short drive away that's better to observe from than the current site:
/// either a darker sky, or a more open horizon when the trouble is trees. Two
/// small choices (what to improve, how far to go) and an automatic answer;
/// everything else about the search is decided for you.
struct NearbySpotPanel: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    // View settings rather than planning thresholds, so they live in
    // UserDefaults instead of `Preferences`.
    @AppStorage("nearbySpotGoal") private var goal: SpotGoal = .darkerSky
    @AppStorage("darkSkyDistanceStep") private var darkSkyDistanceStep = 1
    @AppStorage("openHorizonDistanceStep") private var openHorizonDistanceStep = 1
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
        switch (goal, usesMiles) {
        case (.darkerSky, true):
            return [.init(label: "5 mi", kilometers: 8.05), .init(label: "15 mi", kilometers: 24.1), .init(label: "30 mi", kilometers: 48.3)]
        case (.darkerSky, false):
            return [.init(label: "10 km", kilometers: 10), .init(label: "25 km", kilometers: 25), .init(label: "50 km", kilometers: 50)]
        // Getting clear of trees rarely takes more than a few minutes' drive,
        // and land cover is downloaded for the whole search area.
        case (.openHorizon, true):
            return [.init(label: "1 mi", kilometers: 1.61), .init(label: "3 mi", kilometers: 4.83), .init(label: "5 mi", kilometers: 8.05)]
        case (.openHorizon, false):
            return [.init(label: "2 km", kilometers: 2), .init(label: "5 km", kilometers: 5), .init(label: "8 km", kilometers: 8)]
        }
    }

    private var distanceStep: Binding<Int> {
        goal == .darkerSky ? $darkSkyDistanceStep : $openHorizonDistanceStep
    }

    private var selectedDistance: DistanceOption {
        distanceOptions[min(max(distanceStep.wrappedValue, 0), distanceOptions.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Better spot nearby")
                Spacer(minLength: 4)
                goalMenu
            }

            Picker("Distance", selection: distanceStep) {
                ForEach(distanceOptions.indices, id: \.self) { index in
                    Text(distanceOptions[index].label).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .hoverTooltip(goal == .darkerSky ? "How far you're willing to drive" : "How far you're willing to go")

            content

            if let home = state.spotReturnSite {
                Button {
                    state.returnFromNearbySpot()
                } label: {
                    Label("Back to \(home.name)", systemImage: "arrow.uturn.backward")
                        .font(.scaled(.caption, scale: uiTextScale))
                }
                .buttonStyle(.link)
            }
        }
        .task(id: NearbySpotSearchKey(goal: goal,
                                      latitude: state.site.latitude,
                                      longitude: state.site.longitude,
                                      radiusKilometers: selectedDistance.kilometers)) {
            selectedSpotID = nil
            state.findNearbySpots(goal: goal, radiusKilometers: selectedDistance.kilometers, shorterRadii: distanceOptions.map(\.kilometers))
        }
    }

    private var goalMenu: some View {
        Menu {
            ForEach(SpotGoal.allCases) { option in
                Button {
                    goal = option
                } label: {
                    if option == goal {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Text(goal.title)
                .font(.scaled(.caption, scale: uiTextScale))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .hoverTooltip("What should the spot improve on?")
    }

    @ViewBuilder
    private var content: some View {
        switch state.nearbySpots {
        case .idle, .searching:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(goal == .darkerSky ? "Checking satellite night lights…" : "Checking satellite land cover…")
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
                    state.retryNearbySpots(goal: goal, radiusKilometers: selectedDistance.kilometers, shorterRadii: distanceOptions.map(\.kilometers))
                }
                .buttonStyle(.link)
                .font(.scaled(.caption, scale: uiTextScale))
            }

        case .found(let result):
            if result.goal == .darkerSky { settingHint(result) }
            if let featured = result.spots.first(where: { $0.id == selectedSpotID }) ?? result.spots.first {
                spotCard(featured, result: result)
                let alternates = result.spots.filter { $0.id != featured.id }
                if !alternates.isEmpty {
                    // Alternates are always closer and not as good — anything
                    // further and no better never gets suggested at all.
                    Text(featured.id == result.spots.first?.id
                         ? (result.goal == .darkerSky ? "Closer, not as dark" : "Closer, not as open")
                         : "Other options")
                        .font(.scaled(.caption2, scale: uiTextScale).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    ForEach(alternates) { alternate in
                        alternateRow(alternate, goal: result.goal)
                    }
                }
                Text(result.goal == .darkerSky
                     ? "Bortle classes are estimated from NASA satellite night lights. Check it's open and safe after dark."
                     : "Open view estimated from ESA WorldCover satellite land cover, assuming trees about 15 m tall. Check it's open and safe after dark.")
                    .font(.scaled(.caption2, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                message(emptyMessage(for: result))
            }
        }
    }

    private func emptyMessage(for result: NearbySpotSearchResult) -> String {
        switch result.goal {
        case .darkerSky where result.siteEstimatedBortleClass <= 3:
            return "Your sky is already dark — about Bortle \(result.siteEstimatedBortleClass). An open spot with a low horizon is the only upgrade left."
        case .darkerSky:
            return "Nothing noticeably darker within \(selectedDistance.label). Try a longer drive — or just an open spot away from direct lights."
        case .openHorizon:
            return "No public spot within \(selectedDistance.label) looks at least 5° more open than your \(Format.degrees(result.anchor.typicalHorizonAltitude)) horizon. Try a longer distance."
        }
    }

    /// The darker-sky comparison leans on the site's own Bortle class being
    /// roughly right, and it's the number beginners most often guess. Two
    /// classes is well outside the model's own scatter, so a gap that size is
    /// worth a word.
    @ViewBuilder
    private func settingHint(_ result: NearbySpotSearchResult) -> some View {
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

    private func spotCard(_ spot: NearbySpot, result: NearbySpotSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(spot.name)
                .font(.scaled(.body, scale: uiTextScale).weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(detailLine(spot, result: result))
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ParkHoursLine(spot: spot)

            switch result.goal {
            case .darkerSky:
                ComparisonLine(spot: spot)
            case .openHorizon:
                if let horizon = spot.horizonAltitude {
                    skyGainLine(spotHorizon: horizon, siteHorizon: result.anchor.typicalHorizonAltitude)
                }
            }

            HStack(spacing: 10) {
                Button("Use This Spot") {
                    state.useNearbySpot(spot)
                }
                .hoverTooltip(result.goal == .darkerSky
                              ? "Plan from here instead — saved alongside your current site"
                              : "Plan from here with its estimated horizon — saved alongside your current site")
                if let url = spot.mapsURL {
                    Link(destination: url) {
                        Label("Map", systemImage: "map")
                    }
                    .hoverTooltip(result.goal == .darkerSky
                                  ? "Open in Maps for directions"
                                  : "Open the most open spot in Maps")
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

    /// How much more of the sky a lower horizon uncovers. The good-target count
    /// used for darker skies doesn't work here: with the usual 30° minimum
    /// altitude in Planning settings, a horizon anywhere below that changes no
    /// target's score, so it reads "same" even when the trees are the whole
    /// problem. The visible fraction of the sky above an altitude h is
    /// 1 − sin h, which is always meaningful.
    private func skyGainLine(spotHorizon: Double, siteHorizon: Double) -> some View {
        let visibleThere = 1 - sinDeg(max(spotHorizon, 0))
        let visibleHere = max(1 - sinDeg(max(siteHorizon, 0)), 0.01)
        let gain = Int(((visibleThere / visibleHere - 1) * 100).rounded())
        return Label {
            Text("\(gain)% more sky than your \(Format.degrees(siteHorizon)) horizon")
        } icon: {
            Image(systemName: "sparkles")
        }
        .foregroundStyle(gain > 0 ? Palette.go : Color.secondary)
        .font(.scaled(.caption, scale: uiTextScale))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func detailLine(_ spot: NearbySpot, result: NearbySpotSearchResult) -> String {
        let whereItIs = "\(distanceText(spot.distanceKilometers)) \(spot.direction)"
        switch result.goal {
        case .darkerSky:
            return "\(whereItIs) · Bortle \(spot.estimatedBortleClass) (here: \(result.siteEstimatedBortleClass))"
        case .openHorizon:
            var parts = [whereItIs]
            if let horizon = spot.horizonAltitude {
                parts.append("open above \(Format.degrees(horizon)) (yours: \(Format.degrees(result.anchor.typicalHorizonAltitude)))")
            }
            if let clearest = spot.clearestDirection {
                parts.append("clearest to the \(clearest)")
            }
            return parts.joined(separator: " · ")
        }
    }

    private func alternateRow(_ spot: NearbySpot, goal: SpotGoal) -> some View {
        Button {
            selectedSpotID = spot.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle")
                    .foregroundStyle(Palette.accent)
                Text(spot.name)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(goal == .darkerSky
                     ? "\(distanceText(spot.distanceKilometers)) · B\(spot.estimatedBortleClass)"
                     : "\(distanceText(spot.distanceKilometers)) · \(Format.degrees(spot.horizonAltitude ?? .nan))")
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

/// Posted hours, when they're actually known, and a link to check them.
///
/// Apple Maps gives apps no opening hours at all, and OpenStreetMap has them
/// for only a minority of parks, so most spots show just the link — or
/// nothing, leaving the panel's "check it's open after dark" note to do the
/// job. A label only ever appears when the hours are mapped, never as a guess.
private struct ParkHoursLine: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    var spot: NearbySpot
    @State private var info: ParkInfo?

    /// Closing this long after astronomical dusk leaves time to set up, align
    /// and actually image; anything less is effectively "closes at dark".
    private static let usefulDarkMinutes = 90.0

    var body: some View {
        let website = spot.website ?? info?.website
        HStack(spacing: 8) {
            if let hours = info?.hours {
                let (text, good) = describe(hours)
                Label(text, systemImage: good ? "moon.stars" : "clock")
                    .foregroundStyle(good ? Palette.go : Palette.marginal)
                    .hoverTooltip("Posted hours: \(hours.raw) — from OpenStreetMap")
            }
            if let website {
                Link("Check hours", destination: website)
                    .hoverTooltip("Open this place's website")
            }
        }
        .font(.scaled(.caption, scale: uiTextScale))
        .fixedSize(horizontal: false, vertical: true)
        .task(id: spot.id) {
            info = nil
            let found = await state.parkInfo(for: spot)
            guard !Task.isCancelled else { return }
            info = found
        }
    }

    /// The label, and whether it leaves real observing time tonight.
    private func describe(_ hours: PostedHours) -> (String, Bool) {
        switch hours.closing {
        case .never:
            return ("Open 24 hours", true)
        case .sunset:
            return ("Closes at sunset", false)
        case .time(let hour, let minute, let crossesMidnight):
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            let formatter = DateFormatter()
            formatter.timeZone = state.site.timeZone
            formatter.setLocalizedDateFormatFromTemplate(minute == 0 ? "j" : "j:mm")
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = state.site.timeZone
            let closingText = calendar.date(from: components).map { formatter.string(from: $0) } ?? String(format: "%02d:%02d", hour, minute)

            guard !crossesMidnight else { return ("Open until \(closingText)", true) }
            // Judge against tonight's actual darkness, which moves by hours
            // across the year: 10 PM is well after dark in December and barely
            // dark at all in June.
            guard let dusk = state.tonight?.astronomicalDusk,
                  let closing = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dusk)
            else { return ("Closes at \(closingText)", false) }
            let darkMinutes = closing.timeIntervalSince(dusk) / 60
            return ("Closes at \(closingText)", darkMinutes >= Self.usefulDarkMinutes)
        }
    }
}

/// Tonight from the spot versus from the current site. Recomputed whenever the
/// rig, preferences or forecast change, since each of those moves the counts.
private struct ComparisonLine: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    var spot: NearbySpot
    @State private var comparison: SpotComparison?

    private struct Key: Hashable {
        var spot: NearbySpot
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
        .task(id: Key(spot: spot, site: state.site, rig: state.rig, preferences: state.preferences,
                      forecastRetrievedAt: state.forecast.retrievedAt,
                      customTargetCount: state.customTargets.count)) {
            comparison = nil
            let computed = await state.tonightComparison(for: spot)
            guard !Task.isCancelled else { return }
            comparison = computed
        }
    }

    private func summary(_ comparison: SpotComparison, gained: Int) -> String {
        let when = comparison.isCloudedOut ? "if it clears tonight" : "tonight"
        guard gained > 0 else {
            return "Same \(comparison.targetsThere) good targets \(when) as from here"
        }
        return "\(comparison.targetsThere) good targets \(when) — \(gained) more than from here"
    }
}
