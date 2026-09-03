import AppKit
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
    @Published private(set) var cloudMapImage: NSImage?
    @Published private(set) var cloudMapCapturedAt: Date?

    @Published var selectedNightID: Date?
    @Published var selectedTargetID: String?
    @Published var searchText: String = ""
    @Published var typeFilter: Set<TargetType> = []

    private let weatherClient = OpenMeteoClient()
    private let backupWeatherClient = MetNorwayClient()
    private let cloudMapClient = CloudMapClient()
    private let store = SettingsStore.shared
    private var saveTask: Task<Void, Never>?
    private var planTask: Task<Void, Never>?
    private var lastWeatherFetchAt: Date?
    /// Open-Meteo asks for good citizenship, not a hard quota, but there's no
    /// reason to hit it more than once an hour outside of someone deliberately
    /// asking for the latest data — every automatic refresh (app launch,
    /// window reopen, a setting that happens to call refresh) respects this;
    /// the sidebar's Refresh button and Cmd-R always bypass it.
    private static let minimumAutomaticFetchInterval: TimeInterval = 3600

    init() {
        settings = SettingsStore.shared.load()
    }

    // MARK: - Convenience accessors

    var site: Site {
        get { settings.site }
        set {
            // A single assignment to `settings`, not two, so this only
            // publishes once — this setter fires from live TextField bindings,
            // and a second publish in the same pass trips SwiftUI's "publishing
            // changes from within view updates" check.
            var updated = settings
            updated.site = newValue
            // Any direct edit to the site (e.g. hand-typing coordinates in
            // Settings) counts as configuring a real location, same as picking
            // a search result.
            updated.hasSetLocation = true
            settings = updated
        }
    }

    var rig: Rig {
        get { settings.rig }
        set { settings.rig = newValue }
    }

    var customTargets: [Target] {
        get { settings.customTargets }
        set { settings.customTargets = newValue }
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

    /// True until the user has chosen a real site. While true, the main window
    /// shows onboarding instead of a plan — there is no sensible default
    /// location to compute one against.
    var needsLocationSetup: Bool { !settings.hasSetLocation }

    var forecastAgeDescription: String? {
        guard forecast.retrievedAt != .distantPast else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: forecast.retrievedAt, relativeTo: Date())
    }

    /// True once Open-Meteo has failed and the app has quietly switched to
    /// MET Norway. Surfaced in the sidebar so a lower-fidelity forecast is
    /// never mistaken for the primary source.
    var isUsingBackupWeather: Bool {
        !forecast.isEmpty && forecast.source != "Open-Meteo"
    }

    var cloudMapAgeDescription: String? {
        guard let cloudMapCapturedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: cloudMapCapturedAt, relativeTo: Date())
    }

    // MARK: - Loading

    /// Fetches the forecast then rebuilds the plans. Safe to call repeatedly.
    /// `force` skips the once-an-hour throttle on automatic calls — pass it
    /// for anything the user directly clicked (the Refresh button, Cmd-R) or
    /// that requires fresh data to make sense (picking a different site).
    func refresh(force: Bool = false) async {
        if !force, let lastWeatherFetchAt,
           Date().timeIntervalSince(lastWeatherFetchAt) < Self.minimumAutomaticFetchInterval {
            await rebuildPlans()
            return
        }
        lastWeatherFetchAt = Date()
        refreshCloudMap()

        isLoading = true
        weatherErrorMessage = nil

        do {
            forecast = try await weatherClient.fetch(latitude: site.latitude,
                                                     longitude: site.longitude,
                                                     days: min(16, max(2, preferences.forecastNights + 1)))
        } catch {
            // Open-Meteo down or unreachable — try the backup provider before
            // giving up. A silent trade to a lower-fidelity source beats an
            // empty plan, but the sidebar footer flags it via forecast.source
            // so it's never mistaken for the primary data.
            do {
                forecast = try await backupWeatherClient.fetch(latitude: site.latitude, longitude: site.longitude)
            } catch {
                forecast = .empty
                weatherErrorMessage = error.localizedDescription
            }
        }

        isLoading = false
        await rebuildPlans()
    }

    /// Fetches on the same cadence as the weather (`refresh` calls this, so
    /// it inherits the once-an-hour throttle and the manual-refresh bypass).
    /// Runs independently of the weather fetch's success or failure, and
    /// fails silently — it's a decorative sidebar panel, not core planning
    /// data, so a second error banner alongside the weather one would be
    /// noise. Outside GOES-East's coverage, or if a network hiccup drops the
    /// one request, the panel just doesn't appear.
    private func refreshCloudMap() {
        let latitude = site.latitude
        let longitude = site.longitude
        Task { [weak self] in
            guard let self else { return }
            do {
                let (data, capturedAt) = try await self.cloudMapClient.fetchLatestSnapshot(latitude: latitude, longitude: longitude)
                self.cloudMapImage = NSImage(data: data)
                self.cloudMapCapturedAt = capturedAt
            } catch {
                self.cloudMapImage = nil
                self.cloudMapCapturedAt = nil
            }
        }
    }

    /// Recomputes plans from the forecast already in hand. Called whenever a
    /// setting changes, which is cheap enough to do on every keystroke.
    func rebuildPlans() async {
        planTask?.cancel()

        let planner = Planner(site: site,
                              rig: rig,
                              preferences: preferences,
                              catalog: BuiltInCatalog.all + customTargets,
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
        let previousHorizon = settings.hasSetLocation ? site.horizonAltitude : Site.unset.horizonAltitude
        // Keep the id stable if this is the same place, so saved sites do not duplicate.
        let existing = settings.savedSites.first {
            abs($0.latitude - result.latitude) < 0.01 && abs($0.longitude - result.longitude) < 0.01
        }
        // A genuinely new site gets a first guess at its Bortle class from
        // the geocoder's population figure, rather than silently inheriting
        // whatever the previous site happened to be set to — population is a
        // loose proxy for light pollution, but it is better than a copy-paste
        // default the user has to remember to change. Re-picking a place
        // that is already saved keeps whatever Bortle class was set for it.
        let bortle = existing?.bortleClass
            ?? result.estimatedBortleClass
            ?? (settings.hasSetLocation ? site.bortleClass : Site.unset.bortleClass)
        var newSite = result.makeSite(bortleClass: bortle, horizonAltitude: previousHorizon)
        if let existing {
            newSite.id = existing.id
        }
        settings.site = newSite
        settings.hasSetLocation = true
        if !settings.savedSites.contains(where: { $0.id == newSite.id }) {
            settings.savedSites.append(newSite)
        }
        Task { await refresh(force: true) }
    }

    /// Completes first-run onboarding for someone entering coordinates by hand
    /// instead of searching.
    func finishLocationSetup(withManualSite newSite: Site) {
        var newSite = newSite
        if let existing = settings.savedSites.first(where: {
            abs($0.latitude - newSite.latitude) < 0.01 && abs($0.longitude - newSite.longitude) < 0.01
        }) {
            newSite.id = existing.id
        }
        settings.site = newSite
        settings.hasSetLocation = true
        if !settings.savedSites.contains(where: { $0.id == newSite.id }) {
            settings.savedSites.append(newSite)
        }
        Task { await refresh(force: true) }
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

    // MARK: - Custom targets

    /// Adds a new custom target, or — if its designation collides with an
    /// existing custom target — updates that one in place, since `Target.id`
    /// is the designation itself and a duplicate almost always means the
    /// user is editing rather than genuinely adding a second object.
    func addCustomTarget(_ target: Target) {
        if let index = settings.customTargets.firstIndex(where: { $0.id == target.id }) {
            settings.customTargets[index] = target
        } else {
            settings.customTargets.append(target)
        }
        Task { await rebuildPlans() }
    }

    /// Replaces an existing custom target, keyed by its original designation
    /// so the edit still lands correctly even if the designation itself changed.
    func updateCustomTarget(originalID: String, with target: Target) {
        settings.customTargets.removeAll { $0.id == originalID }
        settings.customTargets.append(target)
        Task { await rebuildPlans() }
    }

    func removeCustomTarget(_ target: Target) {
        settings.customTargets.removeAll { $0.id == target.id }
        Task { await rebuildPlans() }
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
