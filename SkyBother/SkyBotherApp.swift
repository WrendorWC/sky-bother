import SwiftUI
import AppKit

@main
struct SkyBotherApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1240, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Forecast") {
                    Task { await state.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
        }

        MenuBarExtra {
            MenuBarSummaryView()
                .environmentObject(state)
        } label: {
            Image(systemName: "moon.stars.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

/// The glanceable answer: is tonight worth it, and what would you point at?
struct MenuBarSummaryView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let plan = state.tonight {
                HStack(alignment: .top, spacing: 10) {
                    ScoreBadge(score: plan.score, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Tonight")
                                .font(.headline)
                            VerdictTag(verdict: plan.verdict)
                        }
                        Text(plan.headline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                NightTimelineView(plan: plan, height: 62, showsHourLabels: false)

                let picks = Array(state.visibleTargets(for: plan).prefix(3))
                if picks.isEmpty {
                    Text("Nothing clears your thresholds tonight.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Best bets")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(picks) { pick in
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(Palette.score(pick.score))
                                    .frame(width: 7, height: 7)
                                Text(pick.target.displayName)
                                    .font(.caption)
                                Spacer(minLength: 6)
                                Text(pick.usableHoursText)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    if state.isLoading { ProgressView().controlSize(.small) }
                    Text(state.isLoading ? "Loading forecast…" : "No plan yet.")
                        .font(.callout)
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
            .font(.callout)
        }
        .padding(12)
        .frame(width: 290)
    }
}
