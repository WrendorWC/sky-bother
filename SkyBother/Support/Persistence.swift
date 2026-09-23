import Foundation

/// Everything the app remembers between launches.
struct StoredSettings: Codable, Hashable, Sendable {
    var site: Site
    var rig: Rig
    var preferences: Preferences
    var savedSites: [Site]
    var savedRigs: [Rig]
    /// Targets the user typed in by hand — anything the built-in catalog
    /// doesn't cover. Scored and planned exactly like a built-in target; see
    /// `AppState.rebuildPlans()`.
    var customTargets: [Target]
    /// Hand-built session plans, keyed by the night they belong to (see
    /// `NightPlan.planKey`). A night with no entry here is following the
    /// app's own suggestion; an entry that happens to be empty is a night you
    /// deliberately cleared, which is why absence and emptiness have to mean
    /// different things rather than both collapsing to "no plan".
    var sessionPlans: [String: [PlanSegment]]
    /// Whether the user has ever chosen a real site. False only until first-run
    /// onboarding finishes; `site` is meaningless while this is false and must
    /// not be used to fetch weather or build a plan.
    var hasSetLocation: Bool
    /// Which step of guided setup to resume at, or nil once setup is done.
    /// Absent from every settings file written before guided setup existed,
    /// and those decode as done: someone who already has a site shouldn't be
    /// walked through setup again on upgrade.
    var setupStep: Int?
    /// What actually happened on nights run in session mode, by night key.
    /// Absent from older files, which decode with none.
    var sessionRecords: [String: SessionRecord] = [:]

    /// Oldest night key worth keeping, as `NightPlan.planKey` formats them.
    /// Plain string comparison orders `yyyy-MM-dd` correctly, so callers can
    /// compare keys directly without parsing them back into dates.
    static func planCutoffKey(in timeZone: TimeZone, now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let parts = calendar.dateComponents([.year, .month, .day], from: yesterday)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static let initial = StoredSettings(site: .unset,
                                        rig: .seestarS50,
                                        preferences: .default,
                                        savedSites: [],
                                        savedRigs: [],
                                        customTargets: [],
                                        sessionPlans: [:],
                                        hasSetLocation: false)

    // Custom Codable so settings files saved before `hasSetLocation` or
    // `customTargets` existed decode cleanly: `customTargets` simply
    // defaults to empty, and `hasSetLocation` falls back to inspecting the
    // decoded site itself — see the reasoning in `init(from:)` below.
    enum CodingKeys: String, CodingKey {
        case site, rig, preferences, savedSites, savedRigs, customTargets, sessionPlans, hasSetLocation, setupStep, sessionRecords
    }

    init(site: Site, rig: Rig, preferences: Preferences, savedSites: [Site], savedRigs: [Rig],
         customTargets: [Target], sessionPlans: [String: [PlanSegment]] = [:], hasSetLocation: Bool,
         setupStep: Int? = nil) {
        self.site = site
        self.rig = rig
        self.preferences = preferences
        self.savedSites = savedSites
        self.savedRigs = savedRigs
        self.customTargets = customTargets
        self.sessionPlans = sessionPlans
        self.hasSetLocation = hasSetLocation
        self.setupStep = setupStep
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        site = try container.decode(Site.self, forKey: .site)
        rig = try container.decode(Rig.self, forKey: .rig)
        preferences = try container.decode(Preferences.self, forKey: .preferences)
        savedSites = try container.decode([Site].self, forKey: .savedSites)
        savedRigs = try container.decode([Rig].self, forKey: .savedRigs)
        customTargets = try container.decodeIfPresent([Target].self, forKey: .customTargets) ?? []
        // Built into a local first: referring to `site` from inside these
        // closures while `sessionPlans` is still uninitialised is what the
        // compiler objects to, not the work itself.
        let planCutoff = StoredSettings.planCutoffKey(in: site.timeZone)
        let storedPlans = try container.decodeIfPresent([String: [PlanSegment]].self, forKey: .sessionPlans) ?? [:]
        sessionPlans = storedPlans
            // Last night's plan and everything before it is dropped rather
            // than kept forever. This is a planner, not a logbook: nothing in
            // the app can navigate to a past night, so those entries were
            // unreachable weight in the file.
            //
            // The cutoff is yesterday, not today, because a session keyed to
            // one civil date runs into the small hours of the next one — at
            // 2am you are still working last night's plan, and deleting it out
            // from under yourself on a relaunch would be the one moment it
            // actually mattered.
            .filter { $0.key >= planCutoff }
            // Loaded exactly as saved. These used to be snapped to the
            // five-minute grid on the way in, but a saved plan keeps the
            // scheduler's own times for any block that was never dragged, and
            // rounding those pushed them a minute or two past the edge of the
            // target's usable time — marking them unshootable after every
            // relaunch, and quietly changing the plan without anyone editing it.

        // A settings file written before this flag existed cannot be taken to
        // imply the user ever chose a site. The file is rewritten on *any*
        // settings change — a slider, a rig swap, a unit toggle — so it can
        // perfectly well hold the hardcoded "Boston, MA" placeholder that
        // shipped before onboarding existed. Defaulting those to true would
        // leave exactly the people this feature is for stuck on Boston,
        // never once asked where they are.
        let looksLikeRetiredPlaceholder = site.name == "Boston, MA"
            && abs(site.latitude - 42.3601) < 0.0005
            && abs(site.longitude + 71.0589) < 0.0005
        let looksUnconfigured = site.name.trimmingCharacters(in: .whitespaces).isEmpty
            || (site.latitude == 0 && site.longitude == 0)

        hasSetLocation = try container.decodeIfPresent(Bool.self, forKey: .hasSetLocation)
            ?? !(looksLikeRetiredPlaceholder || looksUnconfigured)
        setupStep = try container.decodeIfPresent(Int.self, forKey: .setupStep)
        sessionRecords = try container.decodeIfPresent([String: SessionRecord].self, forKey: .sessionRecords) ?? [:]
    }
}

/// A small JSON file in Application Support. No database, no schema migration,
/// and a corrupt or missing file just falls back to defaults.
struct SettingsStore: Sendable {
    static let shared = SettingsStore()

    private var directoryURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("SkyBother", isDirectory: true)
    }

    private var fileURL: URL? {
        directoryURL?.appendingPathComponent("settings.json")
    }

    func load() -> StoredSettings {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return .initial }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var settings = try? decoder.decode(StoredSettings.self, from: data) else { return .initial }
        // Early versions seeded savedRigs with the built-in presets, which then
        // showed up as if the user had saved them. Drop any entry that is just a
        // preset under its own name; a genuinely custom rig differs somewhere.
        settings.savedRigs.removeAll { $0.matchesABuiltInPreset }
        return settings
    }

    func save(_ settings: StoredSettings) {
        guard let directoryURL, let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Losing preferences is not worth interrupting the user over; the
            // app keeps working with whatever is in memory.
            NSLog("Sky Bother: could not save settings — \(error.localizedDescription)")
        }
    }
}

private struct CachedForecast: Codable {
    var forecast: WeatherForecast
    var latitude: Double
    var longitude: Double
}

/// A separate small JSON file — not a field on `StoredSettings`, which is
/// rewritten on every preference change and would otherwise write a whole
/// multi-day forecast back out just because a slider moved — purely so the
/// once-an-hour weather throttle (see `AppState.minimumAutomaticFetchInterval`)
/// survives an app relaunch. The timestamp it depends on is in-memory only;
/// without a cache to restore it from, every relaunch looked like the first
/// launch ever, silently defeating the throttle. Cloud cover in particular
/// moves a lot between successive forecast-model runs, so those extra
/// fetches didn't just spend an unnecessary request — they could visibly
/// reshuffle Tonight's Plan with nothing actually different on the ground.
struct WeatherCacheStore: Sendable {
    static let shared = WeatherCacheStore()

    private var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("SkyBother", isDirectory: true).appendingPathComponent("weathercache.json")
    }

    /// Nil unless the cache is for essentially this same site — a fetch from
    /// a previous, different location isn't a valid stand-in for a fresh one
    /// just because it happens to still be within the hour.
    func load(nearLatitude latitude: Double, longitude: Double) -> WeatherForecast? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cached = try? decoder.decode(CachedForecast.self, from: data) else { return nil }
        guard abs(cached.latitude - latitude) < 0.01, abs(cached.longitude - longitude) < 0.01 else { return nil }
        return cached.forecast
    }

    func save(_ forecast: WeatherForecast, latitude: Double, longitude: Double) {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(CachedForecast(forecast: forecast, latitude: latitude, longitude: longitude))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Sky Bother: could not cache weather — \(error.localizedDescription)")
        }
    }
}
