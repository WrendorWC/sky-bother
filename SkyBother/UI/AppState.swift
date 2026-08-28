import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {

    @Published var settings: StoredSettings {
        didSet { scheduleSave() }
    }

    @Published private(set) var plans: [NightPlan] = []
    @Published private(set) var forecast: WeatherForecast = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var isPlanning = false
    @Published var weatherErrorMessage: String?

    @Published var selectedNightID: Date?
    @Published var selectedTargetID: String?
    @Published var searchText: String = ""
    @Published var typeFilter: Set<TargetType> = []

    private let weatherClient = OpenMeteoClient()
    private let store = SettingsStore.shared
    private var saveTask: Task<Void, Never>?
    private var planTask: Task<Void, Never>?

    init() {
        settings = SettingsStore.shared.load()
    }

    // MARK: - Convenience accessors

    var site: Site {
        get { settings.site }
        set { settings.site = newValue }
    }

    var rig: Rig {
        get { settings.rig }
        set { settings.rig = newValue }
    }

    var preferences: Preferences {
        get { settings.preferences }
        set { settings.preferences = newValue }
    }

    var selectedPlan: NightPlan? {
        guard let selectedNightID else { return plans.first }
        return plans.first { $0.id == selectedNightID } ?? plans.first
    }

    var tonight: NightPlan? { plans.first }

    var forecastAgeDescription: String? {
        guard forecast.retrievedAt != .distantPast else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: forecast.retrievedAt, relativeTo: Date())
    }

    // MARK: - Loading

    /// Fetches the forecast then rebuilds the plans. Safe to call repeatedly.
    func refresh() async {
        isLoading = true
        weatherErrorMessage = nil

        do {
            forecast = try await weatherClient.fetch(latitude: site.latitude,
                                                     longitude: site.longitude,
                                                     days: min(16, max(2, preferences.forecastNights + 1)))
        } catch {
            forecast = .empty
            weatherErrorMessage = error.localizedDescription
        }

        isLoading = false
        await rebuildPlans()
    }

    /// Recomputes plans from the forecast already in hand. Called whenever a
    /// setting changes, which is cheap enough to do on every keystroke.
    func rebuildPlans() async {
        planTask?.cancel()

        let planner = Planner(site: site,
                              rig: rig,
                              preferences: preferences,
                              catalog: BuiltInCatalog.all,
                              forecast: forecast)

        isPlanning = true
        let computed = await Task.detached(priority: .userInitiated) {
            planner.plan()
        }.value
        isPlanning = false

        plans = computed
        if let selectedNightID, computed.contains(where: { $0.id == selectedNightID }) {
            // keep the current selection
        } else {
            selectedNightID = computed.first?.id
        }
    }

    /// Debounced replan for controls that change rapidly, like sliders.
    func requestReplan() {
        planTask?.cancel()
        planTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await self?.rebuildPlans()
        }
    }

    // MARK: - Filtering

    func visibleTargets(for plan: NightPlan) -> [TargetPlan] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return plan.targets.filter { candidate in
            guard candidate.score >= preferences.minimumScore else { return false }
            if !typeFilter.isEmpty && !typeFilter.contains(candidate.target.type) { return false }
            if !query.isEmpty && !candidate.target.searchText.contains(query) { return false }
            return true
        }
    }

    // MARK: - Site and rig management

    func apply(_ result: GeocodingResult) {
        var newSite = result.makeSite(bortleClass: site.bortleClass, horizonAltitude: site.horizonAltitude)
        // Keep the id stable if this is the same place, so saved sites do not duplicate.
        if let existing = settings.savedSites.first(where: {
            abs($0.latitude - newSite.latitude) < 0.01 && abs($0.longitude - newSite.longitude) < 0.01
        }) {
            newSite.id = existing.id
        }
        settings.site = newSite
        if !settings.savedSites.contains(where: { $0.id == newSite.id }) {
            settings.savedSites.append(newSite)
        }
        Task { await refresh() }
    }

    func saveCurrentSite() {
        if let index = settings.savedSites.firstIndex(where: { $0.id == site.id }) {
            settings.savedSites[index] = site
        } else {
            settings.savedSites.append(site)
        }
    }

    func removeSite(_ target: Site) {
        settings.savedSites.removeAll { $0.id == target.id }
    }

    func applyPreset(_ preset: Rig) {
        var copy = preset
        copy.id = UUID()
        settings.rig = copy
        Task { await rebuildPlans() }
    }

    /// Keeps the current rig in the saved list so you can switch between several
    /// instruments without re-typing their numbers.
    func saveCurrentRig() {
        if let index = settings.savedRigs.firstIndex(where: { $0.id == rig.id }) {
            settings.savedRigs[index] = rig
        } else {
            settings.savedRigs.append(rig)
        }
    }

    func removeRig(_ target: Rig) {
        settings.savedRigs.removeAll { $0.id == target.id }
    }

    /// Switches to a saved rig, keeping its identity so edits update in place.
    func useSavedRig(_ saved: Rig) {
        settings.rig = saved
        Task { await rebuildPlans() }
    }

    var isCurrentRigSaved: Bool {
        settings.savedRigs.contains { $0.id == rig.id }
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = settings
        saveTask = Task { [store] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            store.save(snapshot)
        }
    }
}
