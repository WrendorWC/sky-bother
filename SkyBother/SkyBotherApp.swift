import SwiftUI
import AppKit

/// The whole theme is hardcoded dark with no light variant, so the app always
/// needs dark mode regardless of the system setting. Forcing it via
/// `.preferredColorScheme(.dark)` as a view modifier fights with
/// NavigationSplitView's title bar layout on macOS — the title area stops
/// reserving real space and draws as a floating overlay instead, which is
/// what was overlapping the mission summary panel and the sidebar's first
/// row. Setting the appearance at the application level instead avoids that
/// — but `NSApp` isn't safe to touch inside `App.init()` (it traps), so this
/// has to happen from an actual AppKit lifecycle callback.
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Toolbars/title bars materialize with whatever appearance is active at
    // window-creation time and don't always repaint themselves if it changes
    // later — willFinishLaunching runs before SwiftUI creates the first
    // window, so the appearance is already set by the time that happens.
    func applicationWillFinishLaunching(_ notification: Notification) {
        terminateIfAlreadyRunning()
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    /// A second launch (double-clicking the built app while a debug build is
    /// still running, or vice versa) hands you a confusing pair of
    /// windows/menu-bar icons and, worse, a second process quietly holding
    /// its own stale in-memory state. Checked before any window exists, so a
    /// duplicate launch just hands off to the original and exits cleanly —
    /// nothing to tear down yet.
    private func terminateIfAlreadyRunning() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != mine }
        guard let existing = others.first else { return }
        existing.activate(options: [.activateAllWindows])
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

@main
struct SkyBotherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(state)
                .tint(Palette.accent)
                .frame(minWidth: 1120, minHeight: 720)
                .background(TitleBarZoomAndDragFix())
        }
        .defaultSize(width: 1500, height: 920)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Forecast") {
                    Task { await state.refresh(force: true) }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                CatalogWindowButton()
            }
            CommandGroup(replacing: .help) {
                HelpWindowButton()
            }
        }

        WindowGroup(id: "catalog") {
            TargetCatalogView()
                .environmentObject(state)
                .tint(Palette.accent)
        }
        .defaultSize(width: 980, height: 720)

        WindowGroup(id: "help") {
            HelpView()
                .tint(Palette.accent)
        }
        .defaultSize(width: 900, height: 700)

        Settings {
            SettingsView()
                .environmentObject(state)
                .tint(Palette.accent)
        }

        MenuBarExtra {
            MenuBarSummaryView()
                .environmentObject(state)
                .tint(Palette.accent)
        } label: {
            MenuBarScoreIcon()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// A menu command needs a view to read `openWindow` from the environment —
/// `App` itself can't.
private struct CatalogWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Target Catalog") { openWindow(id: "catalog") }
            .keyboardShortcut("k", modifiers: .command)
    }
}

private struct HelpWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Sky Bother Help") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}

/// The menu bar icon becomes tonight's own score badge — same ring, same
/// colour, same number as everywhere else in the app — so the answer to
/// "is tonight worth it" is visible without opening anything. Falls back to
/// a plain glyph before a plan exists yet (no location set, still loading).
///
/// Rendered to a bitmap with `ImageRenderer` rather than handed to
/// `MenuBarExtra` as plain SwiftUI shape content — a `Circle().stroke(...)`
/// placed directly in a status-item label doesn't reliably get the frame it
/// asks for from the menu bar's own layout host, so the ring collapses away
/// and only the text survives. Rendering it ourselves sidesteps that: we
/// hand the menu bar a finished, exactly-sized image instead of a layout to
/// resolve.
private struct MenuBarScoreIcon: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let plan = state.tonight {
            Image(nsImage: Self.badgeImage(score: plan.score))
        } else {
            Image(systemName: "moon.stars.fill")
        }
    }

    @MainActor
    private static func badgeImage(score: Double) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarBadge(score: score))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage ?? NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: nil) ?? NSImage()
    }
}

private struct MenuBarBadge: View {
    var score: Double
    private var color: Color { Palette.score(score) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.4), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, score / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(score.rounded()))")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(width: 18, height: 18)
    }
}

/// The glanceable answer: is tonight worth it, and what would you point at?
struct MenuBarSummaryView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let plan = state.tonight {
                HStack(alignment: .top, spacing: 12) {
                    ScoreBadge(score: plan.score, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tonight")
                            .font(.title3.weight(.semibold))
                        // Stacked rather than inline with the title — the verdict
                        // text can run long ("You should be outside tonight"),
                        // and this popup is only 340pt wide.
                        VerdictTag(verdict: plan.verdict)
                        Text(plan.headline)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                NightTimelineView(plan: plan, height: 72, showsHourLabels: false)

                let picks = Array(state.visibleTargets(for: plan).prefix(3))
                if picks.isEmpty {
                    Text("Nothing clears your thresholds tonight.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Best bets")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(picks) { pick in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Palette.score(pick.score))
                                    .frame(width: 8, height: 8)
                                Text(pick.target.displayName)
                                    .font(.callout)
                                Spacer(minLength: 6)
                                Text(pick.usableHoursText)
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    if state.isLoading { ProgressView().controlSize(.small) }
                    Text(state.isLoading ? "Loading forecast…" : "No plan yet.")
                        .font(.body)
                }
            }

            Divider()

            HStack {
                Button("Open main window") { openWindow(id: "main") }
                Spacer()
                Button {
                    Task { await state.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(state.isLoading)
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.body)
        }
        .padding(14)
        .frame(width: 340)
        .spaceBackground()
    }
}
