import SwiftUI

struct NightListView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            // Each section gets the same accent header the middle column uses,
            // with a hairline between sections — without them the night list,
            // the spot finder and the satellite image ran together as one
            // undifferentiated column of small grey text.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader("Nights")
                    Spacer(minLength: 4)
                    Text(state.site.name)
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(state.plans) { plan in
                        NightRow(plan: plan,
                                isTonight: plan.id == state.plans.first?.id,
                                isSelected: state.selectedNightID == plan.id)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .onTapGesture { state.selectedNightID = plan.id }
                    }
                }

                SidebarDivider()

                NearbySpotPanel()
                    .padding(.horizontal, 14)

                if state.cloudMapImage != nil {
                    SidebarDivider()
                    cloudMapPanel
                        .padding(.horizontal, 14)
                }

                SidebarDivider()

                footer
                    .padding(.horizontal, 14)
            }
            .padding(.bottom, 14)
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
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Sky overhead")
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

    /// Auto sizes the UI to the window; turning it off hands over to the
    /// slider, starting from whatever size Auto had reached so nothing jumps.
    private var textSizeControl: some View {
        let isAuto = Binding(
            get: { state.preferences.autoFitsText },
            set: { auto in
                if !auto {
                    state.preferences.textScale = min(max((Double(uiTextScale) / 0.05).rounded() * 0.05, 0.85), 1.5)
                }
                state.preferences.autoFitsText = auto
                if auto { state.refitTextScale() }
            })
        return HStack(spacing: 8) {
            Text("UI Scale")
            if isAuto.wrappedValue {
                Spacer(minLength: 0)
            } else {
                Slider(value: $state.preferences.textScale, in: 0.85...1.5, step: 0.05)
                    .controlSize(.small)
            }
            Text("\(Int((uiTextScale * 100).rounded()))%")
                .monospacedDigit()
                .frame(minWidth: 34, alignment: .trailing)
            Toggle("Auto", isOn: isAuto)
                .toggleStyle(.checkbox)
                .controlSize(.small)
        }
        .font(.scaled(.caption, scale: uiTextScale))
        .foregroundStyle(.secondary)
    }

    /// Status and housekeeping, deliberately quieter than the sections above.
    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            textSizeControl
                .padding(.bottom, 4)
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
            HStack(spacing: 6) {
                Text("Bortle \(state.site.bortleClass) · \(state.rig.name)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button("Guided Setup") { state.restartSetup() }
                    .buttonStyle(.link)
                    .disabled(state.planDraft != nil)
                    .help("Run Guided Setup")
            }
            .font(.scaled(.caption, scale: uiTextScale))
        }
    }
}

/// A hairline between sidebar sections, in the same faint violet as panel borders.
private struct SidebarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.panelBorder)
            .frame(height: 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
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

                // One line: squeezed, each stat wrapped mid-value ("1h" over
                // "50m", "35" over "%"). The sidebar's minimum width is set so
                // these fit at normal UI scales; past that they truncate
                // rather than pushing the whole column wider than the sidebar.
                HStack(spacing: 8) {
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
                .lineLimit(1)
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
        .reportsOneLineFit()
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
