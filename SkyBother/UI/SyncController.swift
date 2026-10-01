import AppKit
import Combine
import Foundation

/// Runs sync for the app (see SyncClient.swift): on launch, a few seconds
/// after any settings change, when the app comes to the front, and every two
/// minutes. What comes back from other devices replaces the settings here and
/// re-plans. Its own state (the code and the last synced document) is kept in
/// sync.json beside settings.json, not in the settings themselves.
@MainActor
final class SyncController: ObservableObject {
    static let shared = SyncController()

    @Published private(set) var code: String?
    @Published private(set) var lastSynced: Date?
    @Published private(set) var isSyncing = false
    @Published private(set) var errorMessage: String?

    private var document: SyncDocument?
    private weak var state: AppState?
    private var watch: AnyCancellable?
    private var timer: Timer?
    private var pending: Task<Void, Never>?
    private let client = SyncClient()

    private struct Stored: Codable {
        var code: String?
        var document: SyncDocument?
        var lastSynced: Date?
    }

    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SkyBother", isDirectory: true)
            .appendingPathComponent("sync.json")
    }

    private init() {
        if let url = Self.fileURL, let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            code = stored.code
            document = stored.document
            lastSynced = stored.lastSynced
        }
    }

    private func persist() {
        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(Stored(code: code, document: document, lastSynced: lastSynced))
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Hooks up to the app's state; call once at launch.
    func attach(to state: AppState) {
        guard self.state == nil else { return }
        self.state = state
        watch = state.$settings
            .dropFirst()
            .debounce(for: .seconds(3), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncNow() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        }
        syncNow()
    }

    // MARK: Turning it on and off

    /// A new code for this Mac's settings.
    func turnOn() {
        code = SyncCode.generate()
        document = nil
        lastSynced = nil
        persist()
        syncNow()
    }

    /// Joins a code from another device: this Mac takes on the synced settings.
    func join(_ text: String) throws {
        guard SyncCode.isValid(text) else { throw SyncError.badCode }
        code = SyncCode.format(text)
        document = nil
        lastSynced = nil
        persist()
        syncNow(joining: true)
    }

    func turnOff() {
        code = nil
        document = nil
        lastSynced = nil
        errorMessage = nil
        persist()
    }

    func stopEverywhere() {
        guard let code else { return }
        Task {
            try? await client.forget(code: code)
            turnOff()
        }
    }

    var link: URL? {
        code.flatMap { URL(string: "https://skybother.com/#sync=\(SyncCode.normalize($0))") }
    }

    // MARK: Syncing

    func syncNow(joining: Bool = false) {
        guard let code, let state, pending == nil else { return }
        let local = joining ? nil : SyncDocument.from(state.settings, previous: document)
        isSyncing = true
        errorMessage = nil
        pending = Task {
            defer { isSyncing = false; pending = nil }
            do {
                let merged = try await client.syncOnce(code: code, local: local)
                guard self.code == code else { return }
                document = merged
                lastSynced = Date()
                persist()
                apply(merged)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ merged: SyncDocument) {
        guard let state else { return }
        let updated = merged.applied(to: state.settings)
        guard updated != state.settings else { return }
        let moved = updated.site.latitude != state.settings.site.latitude || updated.site.longitude != state.settings.site.longitude
        state.settings = updated
        if moved {
            Task { await state.refresh(force: true) }
        } else {
            state.requestReplan()
        }
    }
}
