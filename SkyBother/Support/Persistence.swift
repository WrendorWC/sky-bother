import Foundation

/// Everything the app remembers between launches.
struct StoredSettings: Codable, Hashable, Sendable {
    var site: Site
    var rig: Rig
    var preferences: Preferences
    var savedSites: [Site]
    var savedRigs: [Rig]

    static let initial = StoredSettings(site: .placeholder,
                                        rig: .seestarS50,
                                        preferences: .default,
                                        savedSites: [.placeholder],
                                        savedRigs: [])
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
