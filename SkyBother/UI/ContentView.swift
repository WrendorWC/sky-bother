import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if state.needsLocationSetup {
            LocationOnboardingView()
                .navigationTitle("Sky Bother?")
        } else {
            NavigationSplitView {
                NightListView()
                    .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 380)
            } content: {
                // The width constraint has to apply regardless of which
                // branch renders — it was only on the "has a plan" branch,
                // so the column snapped to a new width the instant a plan
                // (or target, below) got selected instead of staying put.
                Group {
                    if let plan = state.selectedPlan {
                        NightDetailView(plan: plan)
                    } else {
                        EmptyStateView(title: "No nights planned",
                                       message: "Set a location in Settings, then refresh.",
                                       systemImage: "moon.stars")
                    }
                }
                .navigationSplitViewColumnWidth(min: 540, ideal: 720)
            } detail: {
                Group {
                    if let plan = state.selectedPlan,
                       let selectedID = state.selectedTargetID,
                       let targetPlan = plan.targets.first(where: { $0.id == selectedID }) {
                        TargetDetailView(plan: plan, targetPlan: targetPlan)
                    } else {
                        EmptyStateView(title: "Pick a target",
                                       message: "Select something from the list to see how it sits in your frame tonight.",
                                       systemImage: "scope")
                    }
                }
                .navigationSplitViewColumnWidth(min: 360, ideal: 440, max: 560)
            }
            .navigationTitle("Sky Bother?")
            .toolbarTitleDisplayMode(.inline)
            .forcedToolbarBackground(Palette.spaceTop)
            .toolbar {
                // A duplicate of the app menu's Settings item (and Cmd-,) —
                // this is the one settings-adjacent thing that isn't already
                // one click away from the main window otherwise.
                ToolbarItem {
                    Button {
                        openSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Site, rig and planning preferences")
                }
                ToolbarItem {
                    Button {
                        openWindow(id: "catalog")
                    } label: {
                        Label("Target Catalog", systemImage: "photo.on.rectangle.angled")
                    }
                    .help("Browse the target catalog with photos")
                }
                ToolbarItem {
                    Button {
                        openWindow(id: "help")
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                    .help("What the scores, colours and charts mean")
                }
            }
            .task {
                await state.refresh()
            }
        }
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String

    @Environment(\.uiTextScale) private var uiTextScale

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 44 * uiTextScale))
                .foregroundStyle(Palette.accent.opacity(0.7))
            Text(title)
                .font(.scaled(.title3, scale: uiTextScale).weight(.semibold))
            Text(message)
                .font(.scaled(.body, scale: uiTextScale))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .spaceBackground()
    }
}
