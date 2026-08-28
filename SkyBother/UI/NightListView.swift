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
        .scrollContentBackground(.hidden)
        .background(Palette.spaceBackground)
        .overlay {
            if state.plans.isEmpty && state.isLoading {
                ProgressView("Loading forecast…")
                    .controlSize(.regular)
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
        VStack(alignment: .leading, spacing: 5) {
            if let message = state.weatherErrorMessage {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Palette.marginal)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let age = state.forecastAgeDescription {
                Text("Forecast updated \(age)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Bortle \(state.site.bortleClass) · \(state.rig.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 5)
    }
}

private struct NightRow: View {
    var plan: NightPlan
    var isTonight: Bool

    private var isExceptional: Bool { plan.verdict == .exceptional }

    var body: some View {
        HStack(spacing: 12) {
            ScoreBadge(score: plan.score, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(isTonight ? "Tonight" : Format.weekday(plan.date, in: plan.timeZone))
                        .font(.body.weight(.semibold))
                    Text(Format.dayAndMonth(plan.date, in: plan.timeZone))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Label {
                        Text(Format.hours(plan.clearDarkHours))
                    } icon: {
                        Image(systemName: "moon.stars.fill")
                    }

                    Label {
                        Text("\(plan.moon.illuminationPercent)%")
                    } icon: {
                        MoonPhaseDisc(illuminatedFraction: plan.moon.illuminatedFraction,
                                     isWaxing: plan.moon.isWaxing, diameter: 12)
                    }

                    if plan.hasWeather {
                        Label {
                            Text("\(Int(plan.meanCloudDuringDark))%")
                        } icon: {
                            Image(systemName: "cloud.fill")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
            if isExceptional {
                Image(systemName: "sparkle")
                    .font(.caption)
                    .foregroundStyle(Palette.exceptional)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, isExceptional ? 6 : 0)
        .background {
            if isExceptional {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.exceptional.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.exceptional.opacity(0.45)))
            }
        }
    }
}
