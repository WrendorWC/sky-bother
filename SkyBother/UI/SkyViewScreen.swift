import SwiftUI

/// Sky View with room of its own: the whole dome, the time controls and the
/// selected target's state visible together, and the night's plan to step
/// through. Opened from Home or from the planner, and Back returns there.
///
/// It reads the plan — including the planner's unsaved draft — and never
/// changes it. Selecting a target here changes only what's selected.
struct SkyViewScreen: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    var plan: NightPlan

    @State private var scrubTime: Date
    @State private var isPlaying = false
    @State private var isShowingMoon = false
    /// Remembered between launches: how wide you like the side panel.
    /// 0 until you drag the divider: the default then follows the UI scale.
    @AppStorage("skyViewPanelWidth") private var panelWidth: Double = 0

    init(plan: NightPlan) {
        self.plan = plan
        // Darkness rather than sunset: the part of the night worth looking at.
        let start = plan.astronomicalDusk.flatMap { plan.chartWindow.contains($0) ? $0 : nil }
            ?? plan.chartWindow.start
        _scrubTime = State(initialValue: start)
    }

    private var segments: [PlanSegment] { state.displayedPlan(for: plan) }

    private var selectedTarget: TargetPlan? {
        guard let id = state.selectedTargetID else { return nil }
        return plan.targets.first { $0.id == id }
    }

    private var bestWindowTime: Date? { selectedTarget.flatMap { SkyViewTimeline.bestWindowTime(for: $0) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // Drag the divider to give the side panel more or less room; the
            // dome takes whatever is left.
            ResizableSplit(trailingWidth: Binding(get: { panelWidth > 0 ? panelWidth : 340 * uiTextScale },
                                                  set: { panelWidth = $0 }),
                           trailingRange: (280 * max(1, uiTextScale * 0.9))...1100,
                           leadingMinimum: 480) {
                SkyView(plan: plan, scrubTime: $scrubTime, isPlaying: $isPlaying, planSegments: segments)
                    .padding(18)
            } trailing: {
                sidePanel
            }
        }
        .spaceBackground()
        .navigationTitle("Sky View")
        .onEscapeKey { back() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: back) {
                Label(state.skyViewReturn == .planner ? "Planner" : "Home", systemImage: "chevron.left")
                    .font(.scaled(.body, scale: uiTextScale))
            }
            .help("Back (Esc)")

            VStack(alignment: .leading, spacing: 3) {
                Text("Sky View")
                    .font(.scaled(.title3, scale: uiTextScale).weight(.bold))
                Text([Format.longDate(plan.date, in: plan.timeZone), selectedTarget?.target.displayName]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Label(plan.site.name, systemImage: "mappin.and.ellipse")
                Label(state.rig.name, systemImage: "camera.aperture")
            }
            .font(.scaled(.callout, scale: uiTextScale))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            jumpButton
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Palette.spaceTop)
    }

    private var jumpButton: some View {
        Button {
            guard let bestWindowTime else { return }
            isPlaying = false
            scrubTime = bestWindowTime
        } label: {
            Label("Jump to best window", systemImage: "scope")
                .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
        }
        .disabled(bestWindowTime == nil)
        .help(selectedTarget == nil
              ? "Select a target first"
              : "Move to the best time in \(selectedTarget?.target.displayName ?? "this target")'s best window")
    }

    private func back() {
        isPlaying = false
        state.closeSkyView()
    }

    // MARK: - Side panel

    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader("Current view")
                        Text(Format.time(scrubTime, in: plan.timeZone))
                            .font(.scaled(.largeTitle, scale: uiTextScale).monospacedDigit().weight(.semibold))
                    }
                    Spacer()
                    // The night's Moon, beside the clock it's drawn against
                    // on the dome. Click for the full Moon card.
                    MoonPhaseDisc(illuminatedFraction: plan.moon.illuminatedFraction,
                                  isWaxing: plan.moon.isWaxing, diameter: 38 * uiTextScale)
                        .contentShape(Circle())
                        .onTapGesture { isShowingMoon = true }
                        .hoverTooltip("\(plan.moon.illuminationPercent)% \(plan.moon.phaseName.lowercased())")
                        .accessibilityLabel("Moon, \(plan.moon.illuminationPercent)% \(plan.moon.phaseName.lowercased())")
                        .accessibilityAddTraits(.isButton)
                        .sheet(isPresented: $isShowingMoon) { MoonCard(plan: plan) }
                }

                if let selectedTarget {
                    targetState(selectedTarget)
                } else {
                    noSelection
                }

                planList
            }
            .padding(18)
        }
        .scrollIndicators(.visible)
    }

    private var noSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Selected target")
            Text("Nothing selected.")
                .font(.scaled(.callout, scale: uiTextScale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let best = plan.bestTarget {
                Button { state.selectedTargetID = best.id } label: {
                    Text("Select \(best.target.displayName)").font(.scaled(.callout, scale: uiTextScale))
                }
            }
        }
    }

    private func position(of target: Target, at date: Date) -> HorizontalCoordinate {
        SkyCoordinates.horizontal(target.coordinate, daysSinceJ2000: date.daysSinceJ2000,
                                  latitude: plan.site.latitude, longitude: plan.site.longitude)
    }

    /// Where the selected target is now, whether it can be shot, and if not,
    /// why and until when.
    private func targetState(_ targetPlan: TargetPlan) -> some View {
        let target = targetPlan.target
        let now = position(of: target, at: scrubTime)
        let later = position(of: target, at: scrubTime.addingTimeInterval(10 * 60))
        let motion = later.altitude >= now.altitude ? "rising" : "setting"
        let reason = Shootability.reason(for: target, at: scrubTime, in: plan,
                                         minimumAltitude: state.preferences.minimumUsefulAltitude)
        let usableNow = targetPlan.windows.first { $0.contains(scrubTime) }
        let next = SkyViewTimeline.nextUsable(after: scrubTime, for: targetPlan)
        let blocks = segments.filter { $0.targetID == targetPlan.id }

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Selected target")
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayName)
                        .font(.scaled(.title2, scale: uiTextScale).weight(.semibold))
                    Text("\(target.designation) · \(target.type.displayName)")
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ScoreBadge(score: targetPlan.score, size: 40)
            }

            Label(now.altitude > 0
                  ? "Altitude \(Format.degrees(now.altitude)) · \(now.compassPoint) · \(motion)"
                  : "Below the horizon · \(motion)",
                  systemImage: "location.north.line")
                .font(.scaled(.body, scale: uiTextScale).weight(.medium))

            Group {
                if let usableNow {
                    Label("Shootable now, until \(Format.time(usableNow.end, in: plan.timeZone))",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.go)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Not shootable now — \(reason?.phrase ?? "outside its usable time")",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.marginal)
                        if let next {
                            Text("Usable from \(Format.time(next.start, in: plan.timeZone)) to \(Format.time(next.end, in: plan.timeZone))")
                                .foregroundStyle(.secondary)
                        } else if targetPlan.windows.isEmpty {
                            Text("No usable time at all this night.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Its usable time this night is over.")
                                .foregroundStyle(.secondary)
                        }
                        if bestWindowTime != nil {
                            jumpButton
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .font(.scaled(.callout, scale: uiTextScale))
            .fixedSize(horizontal: false, vertical: true)

            if !blocks.isEmpty {
                Label("Planned · " + blocks.map { times($0.window) }.joined(separator: ", "),
                      systemImage: "checkmark.circle")
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(Palette.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("In your frame")
                FramingPreview(target: target, rig: state.rig)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(targetPlan.fit.framingNote)
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The plan, with the block running now marked; clicking one moves the
    /// clock to its middle and selects its target.
    @ViewBuilder
    private var planList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionHeader("The plan")
                // What's saved, with the draft's unsaved state beside it —
                // the same pair the planner's action bar shows.
                PlanOriginBadge(isManual: state.isManualPlan(for: plan))
                if state.planDraft?.isDirty == true {
                    Text("unsaved changes")
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(Palette.marginal)
                }
            }
            if segments.isEmpty {
                Text("Nothing planned for this night.")
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            } else {
                let current = segments.first { $0.window.contains(scrubTime) }
                VStack(spacing: 0) {
                    ForEach(segments.chronological) { segment in
                        planRow(segment, isCurrent: segment.id == current?.id)
                    }
                }
                .panelStyle()
                if let current {
                    currentBlockNote(current)
                }
            }
        }
    }

    private func planRow(_ segment: PlanSegment, isCurrent: Bool) -> some View {
        Button {
            isPlaying = false
            scrubTime = segment.window.midpoint
            state.selectedTargetID = segment.targetID
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCurrent ? "play.circle.fill" : "circle")
                    .foregroundStyle(isCurrent ? Palette.accent : .secondary)
                Text(times(segment.window))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(segment.targetName)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.scaled(.callout, scale: uiTextScale))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isCurrent ? Palette.accent.opacity(0.16) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Jump to the middle of this block and select \(segment.targetName)")
        .accessibilityLabel("\(segment.targetName), \(times(segment.window))\(isCurrent ? ", running now" : "")")
    }

    /// When the block running now can't actually be shot at this moment,
    /// says why — horizon, darkness or cloud.
    @ViewBuilder
    private func currentBlockNote(_ segment: PlanSegment) -> some View {
        if let targetPlan = plan.targets.first(where: { $0.id == segment.targetID }),
           !targetPlan.windows.contains(where: { $0.contains(scrubTime) }) {
            let reason = Shootability.reason(for: targetPlan.target, at: scrubTime, in: plan,
                                             minimumAltitude: state.preferences.minimumUsefulAltitude)
            Label("\(segment.targetName) is planned now but can't be shot — \(reason?.phrase ?? "outside its usable time").",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(Palette.marginal)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func times(_ window: TimeWindow) -> String {
        "\(Format.time(window.start, in: plan.timeZone))–\(Format.time(window.end, in: plan.timeZone))"
    }
}
