import AppKit
import Combine

/// What the Settings window edits: a copy of the settings, applied only on
/// Save. Every change used to apply, save and sync the moment it was made,
/// so nudging a horizon slider rewrote that site's horizon on every synced
/// device before you meant it to.
///
/// The Setup Wizard's panes use one with `appliesImmediately`, as before.
/// The Display tab (UI scale, night mode, units) isn't drafted: those stay
/// on this Mac, and the scale is easier to judge as it changes.
@MainActor
final class SettingsDraft: ObservableObject {
    @Published var settings: StoredSettings {
        didSet { if appliesImmediately && !isSaving { save() } }
    }
    /// What the draft started from.
    private var base: StoredSettings
    private unowned let app: AppState
    private let appliesImmediately: Bool
    private var isSaving = false
    /// True for a moment after Save, for the "Saved" confirmation.
    @Published private(set) var justSaved = false
    private var savedReset: Task<Void, Never>?
    private var watching: AnyCancellable?

    init(app: AppState, appliesImmediately: Bool = false) {
        self.app = app
        self.appliesImmediately = appliesImmediately
        settings = app.settings
        base = app.settings
        // Changed elsewhere (sync, the sidebar) with nothing edited here:
        // start again from it.
        watching = app.$settings.dropFirst().sink { [weak self] new in
            guard let self, !self.isDirty, !self.isSaving else { return }
            self.base = new
            self.settings = new
        }
    }

    var isDirty: Bool { settings != base }

    /// Only what changed here, onto what's saved now, so anything sync
    /// brought in meanwhile stays.
    func save() {
        guard isDirty else { return }
        isSaving = true
        defer { isSaving = false }
        let before = app.settings
        var next = before
        if settings.site != base.site { next.site = settings.site }
        if settings.hasSetLocation != base.hasSetLocation { next.hasSetLocation = settings.hasSetLocation }
        if settings.savedSites != base.savedSites { next.savedSites = settings.savedSites }
        if settings.rig != base.rig { next.rig = settings.rig }
        if settings.savedRigs != base.savedRigs { next.savedRigs = settings.savedRigs }
        if settings.customTargets != base.customTargets { next.customTargets = settings.customTargets }
        var preferences = before.preferences
        if settings.preferences != base.preferences {
            preferences = settings.preferences
            // Display's settings aren't drafted; keep whatever they are now.
            preferences.textScale = before.preferences.textScale
            preferences.autoFitsText = before.preferences.autoFitsText
            preferences.nightMode = before.preferences.nightMode
        }
        app.settings = next
        // Through the setter, which resets the type filters if stars or
        // comets were switched on or off.
        app.preferences = preferences

        let moved = next.site.latitude != before.site.latitude || next.site.longitude != before.site.longitude
            || next.site.timeZoneIdentifier != before.site.timeZoneIdentifier
            || preferences.forecastNights != before.preferences.forecastNights
        if moved {
            Task { await app.refresh(force: true) }
        } else {
            app.requestReplan()
        }
        base = app.settings
        settings = app.settings
        guard !appliesImmediately else { return }
        justSaved = true
        savedReset?.cancel()
        savedReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.justSaved = false
        }
    }

    func cancel() {
        settings = base
    }

    /// The Settings window closing with changes not saved: ask.
    func settingsWindowClosed() {
        guard isDirty else { return }
        let alert = NSAlert()
        alert.messageText = "Save your settings changes?"
        alert.informativeText = "If you don't, they're thrown away. Saved changes also go to your synced devices."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        if alert.runModal() == .alertFirstButtonReturn { save() } else { cancel() }
    }

    // MARK: - What the Settings panes use, as on AppState

    var site: Site {
        get { settings.site }
        set {
            var updated = settings
            updated.site = newValue
            updated.hasSetLocation = true
            // Keep the saved copy in step (AppState.site).
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
    var preferences: Preferences {
        get { settings.preferences }
        set { settings.preferences = newValue }
    }

    func apply(_ result: GeocodingResult) { settings.apply(result) }
    func switchToSavedSite(_ saved: Site) { settings.switchToSavedSite(saved) }
    func duplicateCurrentSite() { settings.duplicateCurrentSite() }
    func removeSite(_ target: Site) { settings.removeSite(target) }
    func applyPreset(_ preset: Rig) { settings.applyPreset(preset) }
    func applyGoalPreset(_ preset: GoalPreset) { preset.apply(to: &settings.preferences) }
    func saveCurrentRig() { settings.saveCurrentRig() }
    func saveCurrentRigAsNew() { settings.saveCurrentRigAsNew() }
    func removeRig(_ target: Rig) { settings.removeRig(target) }
    func useSavedRig(_ saved: Rig) { settings.rig = saved }
    var isCurrentRigSaved: Bool { settings.isCurrentRigSaved }
    func isInUse(_ saved: Rig) -> Bool { settings.isInUse(saved) }
    var rigIsUnchangedPreset: Bool { settings.rigIsUnchangedPreset }

    var selectedPlan: NightPlan? { app.selectedPlan }
    var tonight: NightPlan? { app.tonight }
    func refresh(force: Bool) async { await app.refresh(force: force) }
}

/// File → Export Settings… and Settings → Sync.
enum SettingsExport {
    /// File → Export Settings…: settings.json, saved where you choose, in
    /// the same form the app keeps it (and the web app imports).
    @MainActor
    static func run(_ settings: StoredSettings) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Sky Bother Settings.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(settings).write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
