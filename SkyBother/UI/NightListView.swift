import SwiftUI

struct NightListView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.site.name)
                    .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                ForEach(state.plans) { plan in
                    NightRow(plan: plan,
                            isTonight: plan.id == state.plans.first?.id,
                            isSelected: state.selectedNightID == plan.id)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { state.selectedNightID = plan.id }
                }

                cloudMapPanel
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                textSizeControl
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                footer
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }
            .padding(.bottom, 12)
        }
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
                    Task { await state.refresh(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(state.isLoading)
                .help("Fetch the latest forecast")
            }
        }
    }

    @ViewBuilder
    private var cloudMapPanel: some View {
        if let image = state.cloudMapImage {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sky Overhead")
                    .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                    .foregroundStyle(.secondary)
                Link(destination: URL(string: "https://www.star.nesdis.noaa.gov/GOES/conus_band.php?sat=G16&band=GEOCOLOR&length=12")!) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.panelBorder))
                }
                .buttonStyle(.plain)
                .hoverTooltip("Open the live GOES-East loop on NOAA's site")
                if let age = state.cloudMapAgeDescription {
                    Text("GOES-East satellite · \(age)")
                        .font(.scaled(.caption2, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var textSizeControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Slider(value: $state.preferences.textScale, in: 0.85...1.5, step: 0.05) {
                Text("UI Scale")
            }
            Text("\(Int((state.preferences.textScale * 100).rounded()))%")
                .font(.scaled(.caption2, scale: uiTextScale))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let message = state.weatherErrorMessage {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(Palette.marginal)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let age = state.forecastAgeDescription {
                Text(state.isUsingBackupWeather
                     ? "Forecast updated \(age) · backup source"
                     : "Forecast updated \(age)")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            }
            Text("Bortle \(state.site.bortleClass) · \(state.rig.name)")
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.secondary)
        }
    }
}

private struct NightRow: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var plan: NightPlan
    var isTonight: Bool
    var isSelected: Bool

    private var isExceptional: Bool { plan.verdict == .exceptional }

    var body: some View {
        HStack(spacing: 12) {
            ScoreBadge(score: plan.score, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(isTonight ? "Tonight" : Format.weekday(plan.date, in: plan.timeZone))
                        .font(.scaled(.body, scale: uiTextScale).weight(.semibold))
                    Text(Format.dayAndMonth(plan.date, in: plan.timeZone))
                        .font(.scaled(.body, scale: uiTextScale))
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
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
            if isExceptional {
                Image(systemName: "sparkle")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(Palette.exceptional)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(isSelected ? Palette.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Palette.accent.opacity(0.55) : .clear, lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.3), value: isExceptional)
    }
}
