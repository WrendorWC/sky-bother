import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    // Column minimums, shared with the window's own minimum width in
    // SkyBotherApp. If the window can get narrower than these add up to,
    // the split view squeezes the sidebar and detail columns below their
    // minimums anyway while their content still lays out at full width —
    // the sidebar gets clipped on its left edge and the detail column loses
    // its right margin off the edge of the window.
    // 270 rather than 250: with scroll bars set to always show, 250 left the
    // night rows' stats no room to sit on one line.
    static let sidebarMinWidth: CGFloat = 270
    static let contentMinWidth: CGFloat = 540
    static let detailMinWidth: CGFloat = 360
    /// Room for the two column dividers on top of the columns themselves.
    static let minWindowWidth = sidebarMinWidth + contentMinWidth + detailMinWidth + 10

    /// Wide enough for the night rows at the current UI scale. Fixed, the
    /// sidebar was what stopped the automatic scale growing on a big window:
    /// its rows filled it at about 115% however much room the rest had.
    /// Measured: a row needs about 86pt plus 131pt per unit of scale, and the
    /// column adds its own padding around that.
    private var sidebarWidth: CGFloat {
        max(Self.sidebarMinWidth, 130 + 135 * CGFloat(state.effectiveTextScale))
    }

    var body: some View {
        if state.needsLocationSetup {
            LocationOnboardingView()
                .navigationTitle("Sky Bother?")
        } else if state.mainView == .skyView, let plan = skyViewNight {
            SkyViewScreen(plan: plan)
                .id(plan.id)
                .toolbarTitleDisplayMode(.inline)
                .forcedToolbarBackground(Palette.spaceTop)
                .toolbar { windowToolbar }
        } else if state.mainView == .planner, let plan = plannerNight {
            PlannerWorkspaceView(plan: plan)
                .toolbarTitleDisplayMode(.inline)
                .forcedToolbarBackground(Palette.spaceTop)
                .toolbar { windowToolbar }
        } else {
            NavigationSplitView {
                NightListView()
                    .reportsFitsToAutoScale(state, column: "sidebar")
                    .navigationSplitViewColumnWidth(min: sidebarWidth, ideal: max(290, sidebarWidth),
                                                    max: max(380, sidebarWidth + 60))
            } content: {
                // The width constraint has to apply regardless of which
                // branch renders — it was only on the "has a plan" branch,
                // so the column snapped to a new width the instant a plan
                // (or target, below) got selected instead of staying put.
                Group {
                    if let plan = state.selectedPlan {
                        // Without an explicit identity, switching nights
                        // updates the same NightDetailView instance in place
                        // rather than creating a new one — so its @State
                        // (scrubTime chief among them) carries over from
                        // whichever night was open before instead of
                        // resetting for the one just selected. Keying on the
                        // date makes each night's detail view, and its whole
                        // state tree, genuinely its own.
                        NightDetailView(plan: plan)
                            .id(plan.id)
                            .reportsFitsToAutoScale(state, column: "night")
                    } else {
                        EmptyStateView(title: "No nights planned",
                                       message: "Set a location in Settings, then refresh.",
                                       systemImage: "moon.stars")
                    }
                }
                .navigationSplitViewColumnWidth(min: Self.contentMinWidth, ideal: 720)
            } detail: {
                Group {
                    if let plan = state.selectedPlan,
                       let selectedID = state.selectedTargetID,
                       let targetPlan = plan.targets.first(where: { $0.id == selectedID }) {
                        TargetDetailView(plan: plan, targetPlan: targetPlan)
                    } else {
                        EmptyStateView(title: "No target selected",
                                       message: "Click the best target or a planned block to see it here, or press Plan session to browse every candidate.",
                                       systemImage: "scope")
                    }
                }
                .navigationSplitViewColumnWidth(min: Self.detailMinWidth, ideal: 440, max: 560)
            }
            .navigationTitle("Sky Bother?")
            // The automatic UI scale's comfortable size depends on this.
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { state.mainWindowWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, width in state.mainWindowWidth = width }
                }
            )
            .toolbarTitleDisplayMode(.inline)
            .forcedToolbarBackground(Palette.spaceTop)
            .toolbar { windowToolbar }
            .task {
                await state.refresh()
            }
        }
    }
}

extension ContentView {
    /// The night open in the planner, looked up afresh so a forecast refresh
    /// hands the planner the rebuilt night rather than a stale copy.
    private var plannerNight: NightPlan? {
        guard let draft = state.planDraft else { return nil }
        return state.plans.first { $0.planKey == draft.planKey }
    }

    /// The night Sky View is showing: the planner's while it was opened from
    /// there, otherwise the one selected on Home.
    private var skyViewNight: NightPlan? {
        state.skyViewReturn == .planner ? plannerNight : state.selectedPlan
    }

    /// The same three buttons in the same places whichever view fills the
    /// window.
    @ToolbarContentBuilder
    private var windowToolbar: some ToolbarContent {
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
