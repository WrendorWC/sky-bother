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
    /// What the main window last fitted its UI scale to — see
    /// `reportOneLineFit(_:column:)`. Not saved: it's a fact about the
    /// window's current size, worked out again on every launch.
    @Published var fittedTextScale: Double?

    /// Each column's latest report: the scale it was measured at and how
    /// much room its tightest row had then.
    private var fitReports: [String: (scale: Double, ratio: Double)] = [:]

    /// Bigger than the slider goes, for large displays; the floor stops a
    /// very narrow window shrinking text to unreadable.
    static let autoTextScaleRange: ClosedRange<Double> = 0.8...1.8

    /// Grows or shrinks the automatic UI scale until the tightest row in any
    /// column just fits on one line.
    ///
    /// Each report is turned into the scale that column could take — the
    /// scale it was measured at times how much room it had — which keeps a
    /// column that hasn't re-measured since the last change from being
    /// counted twice. Text grows in proportion to the scale and padding
    /// doesn't, so that estimate is close rather than exact and a few passes
    /// settle it; the dead band around an exact fit stops it hunting.
    func reportOneLineFit(_ ratio: CGFloat, column: String) {
        guard ratio.isFinite, ratio > 0 else {
            fitReports[column] = nil
            return
        }
        fitReports[column] = (effectiveTextScale, Double(ratio))
        refitTextScale()
    }

    /// The main window's width, for the comfortable size below.
    var mainWindowWidth: Double = 0 {
        didSet { if abs(mainWindowWidth - oldValue) >= 1 { refitTextScale() } }
    }

    /// The size that reads comfortably at a given window width — not the
    /// most that fits, which on a laptop was a good deal bigger than wanted.
    /// Set from what reads right in practice: 120% filling a 1512pt laptop
    /// screen, about 145% filling a 3008pt 4K one, and in proportion between
    /// and beyond.
    static func comfortableTextScale(forWindowWidth width: Double) -> Double {
        1.20 + (width - 1512) * (0.25 / 1496)
    }

    func refitTextScale() {
        guard preferences.autoFitsText, mainWindowWidth > 0 else { return }
        let current = effectiveTextScale
        let comfortable = Self.comfortableTextScale(forWindowWidth: mainWindowWidth)
        // The comfortable size unless something wouldn't fit at it, in which
        // case the most that does.
        var limit = min(comfortable, current * 1.2)
        if let tightest = fitReports.values.map({ $0.scale * $0.ratio }).min() {
            limit = min(limit, tightest * 0.985)
        }
        let next = (min(max(limit, Self.autoTextScaleRange.lowerBound),
                        Self.autoTextScaleRange.upperBound) * 100).rounded() / 100
        let tooBig = fitReports.values.contains { $0.ratio < 0.995 && abs($0.scale - current) < 0.005 }
            || current > comfortable + 0.005
        if (tooBig && next < current) || next > current + 0.02 {
            fittedTextScale = next
        }
    }

    /// The UI scale every window uses: fitted to the main window when that's
    /// on, the slider's value otherwise.
    var effectiveTextScale: Double {
        preferences.autoFitsText ? (fittedTextScale ?? preferences.textScale) : preferences.textScale
    }
    @Published private(set) var nearbySpots: NearbySpotState = .idle
    /// Where "Use This Spot" switched away from, so the sidebar can offer the
    /// way back while that spot is still the site in use.
    @Published private(set) var spotDetour: (from: Site, toSiteID: UUID)?

    @Published var selectedNightID: Date?
    @Published var selectedTargetID: String?

    /// What fills the main window. Not a set of tabs: each view other than
    /// Home is entered by an action (Plan session, …) and left by its own
    /// Back, Cancel or Done.
    enum MainView: Equatable {
        case home
        case planner
        case skyView
        case session
    }

    @Published private(set) var mainView: MainView = .home
    /// Where Sky View's Back button goes: Home, or the planner it was opened
    /// from with its draft still open.
    @Published private(set) var skyViewReturn: MainView = .home
    @Published var searchText: String = ""
    @Published var typeFilter: Set<TargetType> = []

    private let weatherClient = OpenMeteoClient()
    private let backupWeatherClient = MetNorwayClient()
    private let cloudMapClient = CloudMapClient()
    private let darkSkyFinder = DarkSkyFinder()
    private let openHorizonFinder = OpenHorizonFinder(landCover: LandCoverClient())
    private let parkHoursClient = ParkHoursClient()
    private var nearbySpotTask: Task<Void, Never>?
    /// Finished searches for this session, so flicking between goals and
    /// distances doesn't re-run Apple Maps searches — which MapKit throttles.
    private var nearbySpotResults: [NearbySpotSearchKey: NearbySpotSearchResult] = [:]
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
    private var lastCloudMapFetchAt: Date?
    /// A much shorter gate than the weather forecast's — GOES imagery
    /// itself only meaningfully changes every several minutes (see
    /// CloudMapClient's own ~40-minute GIBS-latency note), so there's no
    /// benefit to refetching more often than this, but no reason to tie it
    /// to the forecast's full hour either; they're unrelated resources.
    private static let minimumCloudMapFetchInterval: TimeInterval = 600

    init() {
        settings = SettingsStore.shared.load()
        // Restores both the data and the timestamp the once-an-hour throttle
        // above depends on — without this, `lastWeatherFetchAt` starts every
        // single launch as nil, so the throttle it's supposed to enforce
        // never actually held across a relaunch, only within one running
        // session. `retrievedAt` older than the throttle window is left
        // alone; the first `refresh()` call fetches fresh data as normal.
        if let cached = WeatherCacheStore.shared.load(nearLatitude: settings.site.latitude, longitude: settings.site.longitude),
           Date().timeIntervalSince(cached.retrievedAt) < Self.minimumAutomaticFetchInterval {
            forecast = cached
            lastWeatherFetchAt = cached.retrievedAt
        }
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
            // Keep the saved copy in step. Without this, every edit made here
            // — a corrected Bortle class, a horizon profile built slider by
            // slider — lived only in `site` and was thrown away the moment you
            // switched to another saved site and pressed Use to come back.
            // Folded into the same single assignment rather than calling
            // `saveCurrentSite()` afterwards, so this still publishes once.
            if let index = updated.savedSites.firstIndex(where: { $0.id == newValue.id }) {
                updated.savedSites[index] = newValue
            }
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
    // MARK: Guided setup

    /// True until guided setup has been finished (or skipped to the end).
    /// Always true without a site: nothing can be planned for nowhere.
    var needsSetup: Bool { !settings.hasSetLocation || settings.setupStep != nil }

    static let setupStepCount = 5

    /// The step to show, saved as it changes so a relaunch resumes there.
    var setupStep: Int {
        get { min(max(settings.setupStep ?? 0, 0), Self.setupStepCount - 1) }
        set { settings.setupStep = min(max(newValue, 0), Self.setupStepCount - 1) }
    }

    /// Setup is done: back to Home, on the best night coming up and its best
    /// target, so the first thing seen is a real recommendation.
    func finishSetup() {
        settings.setupStep = nil
        mainView = .home
        if let best = bestUpcomingNight {
            selectedNightID = best.id
            selectedTargetID = best.bestTarget?.id
        }
    }

    /// Walks through setup again, starting from what's already set.
    func restartSetup() {
        guard planDraft == nil else { return }
        mainView = .home
        settings.setupStep = 0
    }

    /// The best-scoring night in the forecast, for setup's first plan.
    var bestUpcomingNight: NightPlan? { plans.max { $0.score < $1.score } }

    func applyGoalPreset(_ preset: GoalPreset) {
        preset.apply(to: &settings.preferences)
    }

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
        // Its own gate, independent of the weather throttle below — every
        // *other* call site already passes force: true (the Refresh button,
        // a setting change, picking a new site), so the one non-forced call
        // is app launch itself. Once the weather forecast started being
        // restored from its own on-disk cache (see WeatherCacheStore),
        // launch routinely took the throttled branch below and skipped this
        // entirely, so the cloud map silently never appeared until
        // something forced a real refresh — not what "cached, not skipped"
        // was supposed to mean for a completely separate resource.
        maybeRefreshCloudMap(force: force)

        if !force, let lastWeatherFetchAt,
           Date().timeIntervalSince(lastWeatherFetchAt) < Self.minimumAutomaticFetchInterval {
            await rebuildPlans()
            return
        }
        lastWeatherFetchAt = Date()

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
        // Only a real result — an empty one is a failed fetch, not a fresh
        // one, and would otherwise overwrite a still-usable cache from
        // whatever the last successful fetch was with something useless.
        if !forecast.isEmpty {
            WeatherCacheStore.shared.save(forecast, latitude: site.latitude, longitude: site.longitude)
        }

        isLoading = false
        await rebuildPlans()
    }

    /// Own gate (`minimumCloudMapFetchInterval`), independent of the weather
    /// forecast's — see the note on `refresh` for why this can't just live
    /// inside that throttle's non-cached branch. Runs independently of the
    /// weather fetch's own success or failure either way, and fails
    /// silently — it's a decorative sidebar panel, not core planning data,
    /// so a second error banner alongside the weather one would be noise.
    /// Outside GOES-East's coverage, or if a network hiccup drops the one
    /// request, the panel just doesn't appear.
    private func maybeRefreshCloudMap(force: Bool) {
        if !force, let lastCloudMapFetchAt,
           Date().timeIntervalSince(lastCloudMapFetchAt) < Self.minimumCloudMapFetchInterval {
            return
        }
        lastCloudMapFetchAt = Date()
        refreshCloudMap()
    }

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

    // MARK: - Better spot nearby

    /// Searches for a better place to observe from within `radiusKilometers` of
    /// the current site — darker, or with a more open horizon, per `goal`. A
    /// repeat call for the same site, goal and distance is a no-op, so the
    /// sidebar can call this every time it appears. Like the cloud map, a
    /// failure here stays inside its own panel rather than raising an alert.
    ///
    /// `shorterRadii` are the panel's smaller distance choices. Their searches
    /// run (or come from cache) first and their candidates are folded in, so
    /// what's suggested at 30 miles is never a further spot than what 15 miles
    /// would suggest unless it's clearly better — each search only ever sees
    /// its own handful of Apple Maps results, and a wider one can miss a close
    /// place a narrower one found.
    func findNearbySpots(goal: SpotGoal, radiusKilometers: Double, shorterRadii: [Double]) {
        let anchor = site
        let key = NearbySpotSearchKey(goal: goal, latitude: anchor.latitude, longitude: anchor.longitude,
                                      radiusKilometers: radiusKilometers)
        let radii = (shorterRadii.filter { $0 < radiusKilometers } + [radiusKilometers]).sorted()
        func keyFor(_ radius: Double) -> NearbySpotSearchKey {
            NearbySpotSearchKey(goal: goal, latitude: anchor.latitude, longitude: anchor.longitude, radiusKilometers: radius)
        }

        if let combined = combinedResult(for: radii.map(keyFor)) {
            nearbySpotTask?.cancel()
            nearbySpots = .found(combined)
            return
        }
        if case .searching(let searchingKey) = nearbySpots, searchingKey == key {
            return
        }

        nearbySpotTask?.cancel()
        nearbySpots = .searching(key)
        nearbySpotTask = Task { [weak self, darkSkyFinder, openHorizonFinder] in
            do {
                for radius in radii {
                    guard let self else { return }
                    let radiusKey = keyFor(radius)
                    guard self.nearbySpotResults[radiusKey] == nil else { continue }
                    let result: NearbySpotSearchResult
                    switch goal {
                    case .darkerSky:
                        result = try await darkSkyFinder.search(around: anchor, radiusKilometers: radius)
                    case .openHorizon:
                        result = try await openHorizonFinder.search(around: anchor, radiusKilometers: radius)
                    }
                    guard !Task.isCancelled else { return }
                    self.nearbySpotResults[radiusKey] = result
                }
                guard let self, !Task.isCancelled, let combined = self.combinedResult(for: radii.map(keyFor)) else { return }
                self.nearbySpots = .found(combined)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self?.nearbySpots = .failed(error.localizedDescription)
            }
        }
    }

    /// The widest search's result with every shorter search's candidates
    /// folded in, or nil until all of them are cached.
    private func combinedResult(for keys: [NearbySpotSearchKey]) -> NearbySpotSearchResult? {
        let results = keys.compactMap { nearbySpotResults[$0] }
        guard results.count == keys.count, let widest = results.last else { return nil }
        return widest.including(results.dropLast())
    }

    func retryNearbySpots(goal: SpotGoal, radiusKilometers: Double, shorterRadii: [Double]) {
        nearbySpots = .idle
        findNearbySpots(goal: goal, radiusKilometers: radiusKilometers, shorterRadii: shorterRadii)
    }

    /// Plans tonight from a spot and from the current site, with the same rig,
    /// preferences and forecast, and counts the good targets from each — "Good"
    /// or better, a score of 60 up. That's the level sky darkness visibly moves:
    /// the everything-above-the-filter count barely changes between Bortle 7 and
    /// Bortle 3, while this one nearly doubles.
    ///
    /// The spot uses its own estimated Bortle class, and its estimated horizon
    /// where land cover was checked; otherwise the horizon is assumed to be the
    /// same as the current site's.
    func tonightComparison(for spot: NearbySpot) async -> SpotComparison {
        let here = site
        let there = makeSite(for: spot, from: here)
        var tonightOnly = preferences
        tonightOnly.forecastNights = 1
        let catalog = BuiltInCatalog.all + customTargets
        let rig = rig
        let forecast = forecast
        let goodScore = 60.0

        return await Task.detached(priority: .utility) {
            func goodTargets(from site: Site) -> (count: Int, cloudedOut: Bool) {
                guard let night = Planner(site: site, rig: rig, preferences: tonightOnly,
                                          catalog: catalog, forecast: forecast).plan().first
                else { return (0, false) }
                let count = night.targets.filter { $0.usableMinutes > 0 && $0.score >= goodScore }.count
                return (count, night.isCloudedOut)
            }
            let fromHere = goodTargets(from: here)
            let fromThere = goodTargets(from: there)
            return SpotComparison(targetsHere: fromHere.count,
                                  targetsThere: fromThere.count,
                                  isCloudedOut: fromHere.cloudedOut)
        }.value
    }

    /// Posted hours and a website for a spot, where OpenStreetMap has them.
    func parkInfo(for spot: NearbySpot) async -> ParkInfo? {
        await parkHoursClient.info(for: spot)
    }

    /// Adopts the satellite estimate as the current site's Bortle class, keeping
    /// its saved copy in step so switching away and back doesn't undo it.
    func useEstimatedBortleClass(_ bortleClass: Int) {
        site.bortleClass = bortleClass
        if settings.savedSites.contains(where: { $0.id == site.id }) {
            saveCurrentSite()
        }
        requestReplan()
    }

    /// Switches planning to a nearby spot, saving it alongside the site it came
    /// from so either is one click away in Settings → Saved sites.
    func useNearbySpot(_ spot: NearbySpot) {
        let previous = site
        // Written back, not merely appended when absent: the saved copy can be
        // older than what you have been editing, and this is the moment that
        // difference would otherwise be thrown away.
        if let index = settings.savedSites.firstIndex(where: { $0.id == previous.id }) {
            settings.savedSites[index] = previous
        } else {
            settings.savedSites.append(previous)
        }
        // Picking the same place twice reuses the saved entry, including any
        // Bortle class or horizon the user has since corrected by hand.
        let newSite = settings.savedSites.first {
            abs($0.latitude - spot.latitude) < 0.002 && abs($0.longitude - spot.longitude) < 0.002
        } ?? makeSite(for: spot, from: previous)
        if !settings.savedSites.contains(where: { $0.id == newSite.id }) {
            settings.savedSites.append(newSite)
        }
        spotDetour = (previous, newSite.id)
        settings.site = newSite
        settings.hasSetLocation = true
        Task { await refresh(force: true) }
    }

    /// The site "Back" returns to, while a spot chosen from the sidebar is still
    /// the site in use.
    var spotReturnSite: Site? {
        guard let spotDetour, spotDetour.toSiteID == site.id else { return nil }
        return settings.savedSites.first { $0.id == spotDetour.from.id } ?? spotDetour.from
    }

    func returnFromNearbySpot() {
        guard let destination = spotReturnSite else { return }
        spotDetour = nil
        settings.site = destination
        Task { await refresh(force: true) }
    }

    private func makeSite(for spot: NearbySpot, from base: Site) -> Site {
        Site(name: spot.name,
             latitude: spot.latitude,
             longitude: spot.longitude,
             // Within a few tens of kilometres, the current site's elevation and
             // time zone are close enough; both are editable in Settings.
             elevationMeters: base.elevationMeters,
             timeZoneIdentifier: base.timeZoneIdentifier,
             bortleClass: spot.estimatedBortleClass,
             horizonAltitude: spot.horizonAltitude ?? base.horizonAltitude)
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
        // The night being planned has dropped out of the forecast window —
        // it's in the past now — so there's nothing left to plan.
        if let planDraft, !computed.contains(where: { $0.planKey == planDraft.planKey }) {
            closePlanner()
        }
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

    // MARK: - Session plans

    /// The hand-built plan for a night, or nil when that night is still
    /// following the app's own suggestion. An empty array is a real answer —
    /// a night deliberately cleared — and is not the same as nil.
    func storedPlan(for night: NightPlan) -> [PlanSegment]? {
        settings.sessionPlans[night.planKey]
    }

    func isManualPlan(for night: NightPlan) -> Bool { storedPlan(for: night) != nil }

    /// The app's own running order for a night. Nothing for a night that's
    /// clouded out: `Planner` keeps a target list for such a night on purpose
    /// — re-planned ignoring cloud, so the list can say "this is what you'd
    /// have had" rather than look broken — but a schedule built out of those
    /// is for a night that isn't happening.
    func suggestedSlots(for night: NightPlan) -> [AutoPlanSlot] {
        guard !night.isCloudedOut else { return [] }
        return AutoPlanner.plan(for: night, minimumScore: preferences.minimumScore,
                                sessionCapMinutes: preferences.sessionCapMinutes,
                                minimumSlotMinutes: preferences.minimumSessionMinutes)
    }

    func suggestedPlan(for night: NightPlan) -> [PlanSegment] {
        suggestedSlots(for: night).map {
            PlanSegment.suggested(targetID: $0.targetPlan.id,
                                  targetName: $0.targetPlan.target.displayName,
                                  window: $0.window)
        }
    }

    /// What a night's plan looks like right now: the open draft while it's
    /// being edited, then your own plan once you have one, and the app's
    /// suggestion until then.
    func displayedPlan(for night: NightPlan) -> [PlanSegment] {
        if let planDraft, planDraft.planKey == night.planKey { return planDraft.segments.chronological }
        return (storedPlan(for: night) ?? suggestedPlan(for: night)).chronological
    }

    // MARK: Editing

    /// The plan being edited, if any. Edits change only this until Done.
    @Published private(set) var planDraft: PlanDraft?

    func isEditingPlan(for night: NightPlan) -> Bool { planDraft?.planKey == night.planKey }

    /// Opens a night's plan for editing, starting from whatever it shows now.
    /// Starting from the suggestion rather than blank is the point: the
    /// scheduler has usually got the shape of the night right, and the edits
    /// worth making are moving one block and splitting another. Nothing is
    /// saved by opening it.
    func beginEditingPlan(for night: NightPlan) {
        guard !isEditingPlan(for: night) else { return }
        planDraft = PlanDraft(planKey: night.planKey,
                              displayed: storedPlan(for: night) ?? suggestedPlan(for: night),
                              isManual: isManualPlan(for: night))
    }

    /// Opens the planning workspace on a night, with its plan ready to edit.
    func openPlanner(for night: NightPlan) {
        selectedNightID = night.id
        beginEditingPlan(for: night)
        mainView = .planner
    }

    /// Opens Sky View on a night, from Home or from the planner. Looking at
    /// the sky never touches the plan, the draft included.
    func openSkyView(for night: NightPlan) {
        if mainView != .planner { selectedNightID = night.id }
        skyViewReturn = mainView == .planner ? .planner : .home
        mainView = .skyView
    }

    func closeSkyView() {
        mainView = skyViewReturn == .planner && planDraft != nil ? .planner : .home
    }

    /// Back to Home. Whatever the draft held must already have been saved or
    /// discarded — this never decides that on the user's behalf.
    func closePlanner() {
        planDraft = nil
        mainView = .home
    }

    /// Keeps an untouched suggestion in step with the scheduler while it's
    /// open — a forecast refresh, or a change to what the plan favours. Once
    /// the draft has been edited, or started from a Manual plan, it's left
    /// alone.
    func reseedDraftIfPristine(for night: NightPlan) {
        guard let draft = planDraft, draft.planKey == night.planKey,
              !draft.isDirty, !draft.originalIsManual else { return }
        let fresh = suggestedPlan(for: night)
        guard !PlanDraft.isSemanticallyEqual(fresh, draft.original) else { return }
        planDraft = PlanDraft(planKey: night.planKey, displayed: fresh, isManual: false)
    }

    /// Replaces the draft's blocks — one finished drag or resize.
    func updateDraft(_ segments: [PlanSegment]) {
        planDraft?.segments = segments.chronological
        recentReset = nil
    }

    /// Adds a block for a target at the longest stretch of the night nothing
    /// has claimed yet, preferring time the target can actually be shot in.
    /// Returns the new block, or nil when there's no room left to put one.
    @discardableResult
    func addDraftSegment(for targetPlan: TargetPlan, in night: NightPlan) -> PlanSegment? {
        guard var draft = planDraft, draft.planKey == night.planKey,
              let window = SessionPlanRules.placement(for: targetPlan,
                                                      among: draft.segments,
                                                      within: night.chartWindow,
                                                      preferredMinutes: preferences.integrationGoalMinutes)
        else { return nil }
        let segment = PlanSegment(targetID: targetPlan.id,
                                  targetName: targetPlan.target.displayName,
                                  window: window)
        draft.segments = (draft.segments + [segment]).chronological
        planDraft = draft
        recentReset = nil
        return segment
    }

    /// Takes every block for a target out of the draft.
    func removeDraftSegments(forTarget targetID: String) {
        planDraft?.segments.removeAll { $0.targetID == targetID }
        recentReset = nil
    }

    func removeDraftSegment(id: UUID) {
        planDraft?.segments.removeAll { $0.id == id }
        recentReset = nil
    }

    /// Empties the draft. A cleared night, once saved, stays empty rather than
    /// quietly refilling itself with the suggestion; until then Cancel brings
    /// everything back.
    func clearDraft() {
        planDraft?.segments = []
        recentReset = nil
    }

    /// Undoes every change in the draft but keeps editing.
    func revertDraft() {
        planDraft?.revert()
    }

    /// Throws the draft away. Nothing was saved, so nothing needs undoing.
    func cancelEditingPlan() {
        planDraft = nil
    }

    /// Saves the draft as the night's Manual plan — but only if it's actually
    /// different. Otherwise the night stays exactly as it was, Suggested or
    /// Manual, and nothing is written.
    func finishEditingPlan() {
        guard let draft = planDraft else { return }
        planDraft = nil
        var plans = settings.sessionPlans
        if PlanBook.commit(draft, into: &plans) {
            settings.sessionPlans = plans
        }
    }

    // MARK: Reset

    /// The Manual plan the last Reset removed, kept so Undo can put it back.
    /// Cleared by the next plan edit, so Undo can never restore over newer work.
    struct PlanReset: Equatable {
        var planKey: String
        var segments: [PlanSegment]
    }

    @Published private(set) var recentReset: PlanReset?

    /// Drops a night's Manual plan so it follows the current suggestion again.
    /// If that night is open in the planner, the draft starts over from the
    /// fresh suggestion rather than carrying on from the removed plan.
    func resetPlanToSuggested(for night: NightPlan) {
        let wasEditing = isEditingPlan(for: night)
        var plans = settings.sessionPlans
        guard let removed = PlanBook.reset(night.planKey, in: &plans) else { return }
        settings.sessionPlans = plans
        if wasEditing {
            planDraft = PlanDraft(planKey: night.planKey, displayed: suggestedPlan(for: night), isManual: false)
        }
        recentReset = PlanReset(planKey: night.planKey, segments: removed)
    }

    func undoPlanReset() {
        guard let reset = recentReset else { return }
        recentReset = nil
        var plans = settings.sessionPlans
        PlanBook.undoReset(reset.planKey, restoring: reset.segments, in: &plans)
        settings.sessionPlans = plans
        if let draft = planDraft, draft.planKey == reset.planKey {
            planDraft = PlanDraft(planKey: reset.planKey, displayed: reset.segments, isManual: true)
        }
    }

    // MARK: Session mode

    /// The night shown in the session view.
    @Published private(set) var sessionNightKey: String?

    /// The session view only makes sense for the night that's happening.
    func canOpenSession(for night: NightPlan) -> Bool {
        tonight?.id == night.id && !displayedPlan(for: night).isEmpty
    }

    func openSession(for night: NightPlan) {
        guard planDraft == nil, canOpenSession(for: night) else { return }
        selectedNightID = night.id
        sessionNightKey = night.planKey
        mainView = .session
    }

    func leaveSession() {
        sessionNightKey = nil
        mainView = .home
    }

    // MARK: From the catalog

    /// The night the planner has open, if any — the one night a catalog
    /// action can't quietly switch away from.
    var nightBeingPlanned: NightPlan? {
        guard let planDraft else { return nil }
        return plans.first { $0.planKey == planDraft.planKey }
    }

    /// Something asking the catalog window to show a particular night, and
    /// optionally to search for something. The catalog applies it and clears it.
    struct CatalogRequest: Equatable {
        var nightID: Date?
        var search: String? = nil
    }

    @Published var catalogRequest: CatalogRequest?

    /// A block the catalog just added, for the planner to select and
    /// explain the way it does its own Adds. The planner clears it.
    @Published var blockAddedElsewhere: PlanSegment?

    enum CatalogAddResult: Equatable {
        case added(PlanSegment)
        /// Every stretch of the night is already taken.
        case noRoom
        /// The planner is open on a different night; that work comes first.
        case plannerBusy(otherNight: Date)
    }

    /// Adds a target to a night's plan from the catalog. The planner opens on
    /// that night with the new block in its draft — nothing is saved until
    /// Done there, same as any other edit.
    func addFromCatalog(_ targetPlan: TargetPlan, to night: NightPlan) -> CatalogAddResult {
        if let busy = nightBeingPlanned, busy.planKey != night.planKey {
            return .plannerBusy(otherNight: busy.date)
        }
        openPlanner(for: night)
        selectedTargetID = targetPlan.id
        guard let segment = addDraftSegment(for: targetPlan, in: night) else { return .noRoom }
        blockAddedElsewhere = segment
        return .added(segment)
    }

    /// Shows a target on a night in the main window — Home's Selected target
    /// panel, or the planner's if that night is being planned. Changes only
    /// what's selected. False when the planner is busy with another night.
    @discardableResult
    func showFromCatalog(_ targetID: String, on night: NightPlan) -> Bool {
        if let busy = nightBeingPlanned, busy.planKey != night.planKey { return false }
        if mainView == .skyView { closeSkyView() }
        if mainView == .home { selectedNightID = night.id }
        selectedTargetID = targetID
        return true
    }

    // MARK: Selection

    /// The blocks a target has in a night's plan, as currently shown.
    func plannedBlocks(for targetID: String, in night: NightPlan) -> [PlanSegment] {
        displayedPlan(for: night).filter { $0.targetID == targetID }
    }

    /// The best other night in the forecast for a target that has no usable
    /// time on this one, so "not tonight" can come with "try Saturday".
    func nearestUsefulNight(for targetID: String, after night: NightPlan) -> (night: NightPlan, target: TargetPlan)? {
        plans
            .filter { $0.id != night.id }
            .compactMap { other -> (NightPlan, TargetPlan)? in
                guard let candidate = other.targets.first(where: { $0.id == targetID }),
                      candidate.usableMinutes >= preferences.minimumSessionMinutes,
                      candidate.score >= preferences.minimumScore else { return nil }
                return (other, candidate)
            }
            .min { abs($0.0.date.timeIntervalSince(night.date)) < abs($1.0.date.timeIntervalSince(night.date)) }
            .map { (night: $0.0, target: $0.1) }
    }

    // MARK: - Site and rig management

    func apply(_ result: GeocodingResult) {
        let previousHorizon = settings.hasSetLocation ? site.horizonAltitude : Site.unset.horizonAltitude
        // Keep the id stable if this is the same place, so saved sites do not
        // duplicate. With more than one spot saved at one address, though,
        // "the saved site near these coordinates" is ambiguous — a front yard
        // and a back yard are metres apart — so the one already in use wins.
        // Searching your own town again should leave you where you are rather
        // than silently move you to the other end of the house.
        let nearby = settings.savedSites.filter {
            abs($0.latitude - result.latitude) < 0.01 && abs($0.longitude - result.longitude) < 0.01
        }
        let existing = nearby.first { $0.id == site.id } ?? nearby.first
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
            // Re-picking a place you already have keeps what you told the app
            // about it — its name and its horizon, profile and all — rather
            // than resetting them from the geocoder and the baseline of
            // wherever you happened to be standing. That mattered little when
            // a horizon was one number; it matters a lot once it is eight and
            // named "Back yard".
            newSite.name = existing.name
            newSite.horizonAltitude = existing.horizonAltitude
            newSite.horizonProfile = existing.horizonProfile
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

    /// Switches to a saved site, writing the outgoing one back first.
    ///
    /// That write-back is the whole point. A site is only ever saved when you
    /// leave it, so the copy in the list lags whatever you have been editing;
    /// switching away without saving first is exactly the moment those edits
    /// would be lost, and coming back via Use would quietly restore an older
    /// version of the site as though nothing had happened.
    func switchToSavedSite(_ saved: Site) {
        var updated = settings
        if let index = updated.savedSites.firstIndex(where: { $0.id == site.id }) {
            updated.savedSites[index] = site
        } else if settings.hasSetLocation {
            updated.savedSites.append(site)
        }
        updated.site = saved
        settings = updated

        Task { await refresh(force: true) }
    }

    /// Saves the current site a second time as an independent entry at the
    /// same place. The front yard and the back yard share coordinates, weather,
    /// elevation and Bortle class, and differ only in what is in the way — so
    /// the copy takes all of that and gets its own horizon.
    ///
    /// The copy becomes the site in use, because the name field and the horizon
    /// sliders are directly above the button that makes it: the next thing you
    /// want to do is describe the spot you just created, not hunt for it in the
    /// list below.
    func duplicateCurrentSite() {
        var updated = settings
        // The original may never have been saved (nothing saves a site until
        // you switch away from it), and may hold edits newer than its saved
        // copy, so it is written back first.
        if let index = updated.savedSites.firstIndex(where: { $0.id == site.id }) {
            updated.savedSites[index] = site
        } else {
            updated.savedSites.append(site)
        }

        // Named only now, against the list *after* that write-back. Taking the
        // names beforehand meant checking against a stale one — a site renamed
        // "Back yard" still listed under the town it was found in — so the
        // copy saw no collision and came out sharing its original's name,
        // which is precisely the confusion the unique name exists to avoid.
        var copy = site
        copy.id = UUID()
        copy.name = Site.uniqueName(basedOn: site.name, avoiding: updated.savedSites.map(\.name))
        updated.savedSites.append(copy)
        updated.site = copy
        updated.hasSetLocation = true
        settings = updated

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

    /// Keeps the current numbers as a new saved rig, leaving any rig they
    /// started from untouched.
    func saveCurrentRigAsNew() {
        var copy = rig
        copy.id = UUID()
        let names = settings.savedRigs.map(\.name)
        if names.contains(copy.name) {
            var n = 2
            while names.contains("\(rig.name) \(n)") { n += 1 }
            copy.name = "\(rig.name) \(n)"
        }
        settings.savedRigs.append(copy)
        settings.rig = copy
    }

    /// True when the active rig is exactly one of the built-in presets.
    var rigIsUnchangedPreset: Bool {
        Rig.presets.contains { preset in
            var candidate = rig
            candidate.id = preset.id
            return candidate == preset
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
