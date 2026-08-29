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
        NSApp.appearance = NSAppearance(named: .darkAqua)
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
                    Task { await state.refresh() }
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
            Image(systemName: "moon.stars.fill")
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
                    Task { await state.refresh() }
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
