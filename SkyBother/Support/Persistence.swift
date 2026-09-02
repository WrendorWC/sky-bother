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
    /// Whether the user has ever chosen a real site. False only until first-run
    /// onboarding finishes; `site` is meaningless while this is false and must
    /// not be used to fetch weather or build a plan.
    var hasSetLocation: Bool

    static let initial = StoredSettings(site: .unset,
                                        rig: .seestarS50,
                                        preferences: .default,
                                        savedSites: [],
                                        savedRigs: [],
                                        customTargets: [],
                                        hasSetLocation: false)

    // Custom Codable so settings files saved before `hasSetLocation` or
    // `customTargets` existed decode cleanly: any file that already has a
    // `site` was written after the user changed something, which only
    // happens once a real site is in use, so `hasSetLocation` defaults to
    // true rather than re-triggering onboarding for it; `customTargets`
    // simply defaults to empty.
    enum CodingKeys: String, CodingKey {
        case site, rig, preferences, savedSites, savedRigs, customTargets, hasSetLocation
    }

    init(site: Site, rig: Rig, preferences: Preferences, savedSites: [Site], savedRigs: [Rig],
         customTargets: [Target], hasSetLocation: Bool) {
        self.site = site
        self.rig = rig
        self.preferences = preferences
        self.savedSites = savedSites
        self.savedRigs = savedRigs
        self.customTargets = customTargets
        self.hasSetLocation = hasSetLocation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        site = try container.decode(Site.self, forKey: .site)
        rig = try container.decode(Rig.self, forKey: .rig)
        preferences = try container.decode(Preferences.self, forKey: .preferences)
        savedSites = try container.decode([Site].self, forKey: .savedSites)
        savedRigs = try container.decode([Rig].self, forKey: .savedRigs)
        customTargets = try container.decodeIfPresent([Target].self, forKey: .customTargets) ?? []
        hasSetLocation = try container.decodeIfPresent(Bool.self, forKey: .hasSetLocation) ?? true
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
