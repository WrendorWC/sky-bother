import SwiftUI

struct NightListView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List(selection: $state.selectedNightID) {
            Section {
                ForEach(state.plans) { plan in
                    NightRow(plan: plan, isTonight: plan.id == state.plans.first?.id)
                        .tag(plan.id)
                }
            } header: {
                Text(state.site.name)
            } footer: {
                footer
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if state.plans.isEmpty && state.isLoading {
                ProgressView("Loading forecast…")
                    .controlSize(.small)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await state.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(state.isLoading)
                .help("Fetch the latest forecast")
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let message = state.weatherErrorMessage {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.caption2)
                    .foregroundStyle(Palette.marginal)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let age = state.forecastAgeDescription {
                Text("Forecast updated \(age)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("Bortle \(state.site.bortleClass) · \(state.rig.name)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

private struct NightRow: View {
    var plan: NightPlan
    var isTonight: Bool

    var body: some View {
        HStack(spacing: 10) {
            ScoreBadge(score: plan.score, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(isTonight ? "Tonight" : Format.weekday(plan.date, in: plan.timeZone))
                        .font(.subheadline.weight(.semibold))
                    Text(Format.dayAndMonth(plan.date, in: plan.timeZone))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Label {
                        Text(Format.hours(plan.clearDarkHours))
                    } icon: {
                        Image(systemName: "moon.stars.fill")
                    }

                    Label {
                        Text("\(plan.moon.illuminationPercent)%")
                    } icon: {
                        Image(systemName: plan.moon.symbolName)
                    }

                    if plan.hasWeather {
                        Label {
                            Text("\(Int(plan.meanCloudDuringDark))%")
                        } icon: {
                            Image(systemName: "cloud.fill")
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
