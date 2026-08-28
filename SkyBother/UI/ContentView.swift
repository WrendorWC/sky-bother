import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if state.needsLocationSetup {
            LocationOnboardingView()
                .navigationTitle("Sky Bother?")
        } else {
            NavigationSplitView {
                NightListView()
                    .navigationSplitViewColumnWidth(min: 214, ideal: 244, max: 320)
            } content: {
                if let plan = state.selectedPlan {
                    NightDetailView(plan: plan)
                        .navigationSplitViewColumnWidth(min: 460, ideal: 620)
                } else {
                    EmptyStateView(title: "No nights planned",
                                   message: "Set a location in Settings, then refresh.",
                                   systemImage: "moon.stars")
                }
            } detail: {
                if let plan = state.selectedPlan,
                   let selectedID = state.selectedTargetID,
                   let targetPlan = plan.targets.first(where: { $0.id == selectedID }) {
                    TargetDetailView(plan: plan, targetPlan: targetPlan)
                        .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 460)
                } else {
                    EmptyStateView(title: "Pick a target",
                                   message: "Select something from the list to see how it sits in your frame tonight.",
                                   systemImage: "scope")
                }
            }
            .navigationTitle("Sky Bother?")
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

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
