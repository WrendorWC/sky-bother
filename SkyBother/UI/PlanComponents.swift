import SwiftUI

/// "Suggested" or "Manual" — whose plan this is. The two look identical
/// otherwise, and the difference decides whether the plan still follows the
/// forecast.
struct PlanOriginBadge: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var isManual: Bool

    var body: some View {
        Text(isManual ? "Manual" : "Suggested")
            .font(.scaled(.caption2, scale: uiTextScale).weight(.semibold))
            .foregroundStyle(isManual ? Palette.accent : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(isManual ? Palette.accent.opacity(0.16) : Color.primary.opacity(0.07))
            )
            .overlay(
                Capsule().strokeBorder(isManual ? Palette.accent.opacity(0.45) : Color.clear)
            )
            .help(isManual
                  ? "You edited this plan. Forecast updates won't change it."
                  : "Updates with the forecast and your settings until you edit it.")
    }
}

/// One block of a plan as a row: score, target, what's wrong with the block if
/// anything, and its times.
struct PlanBlockRow: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    var plan: NightPlan
    var segment: PlanSegment
    /// Nil highlights the row whenever its target is the selected one.
    var isSelected: Bool? = nil
    var onRemove: (() -> Void)? = nil

    @State private var isShowingCatalogDetail = false

    private var targetPlan: TargetPlan? { plan.targets.first { $0.id == segment.targetID } }

    var body: some View {
        let unshootable = segment.unusableMinutes(against: targetPlan)
        let selected = isSelected ?? (state.selectedTargetID == segment.targetID)
        HStack(spacing: 12) {
            ScoreBadge(score: targetPlan?.score ?? 0, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.targetName)
                    .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                Group {
                    if targetPlan == nil {
                        Label("Not up, dark or clear at all this night", systemImage: "exclamationmark.triangle.fill")
                    } else if unshootable > 0 {
                        Label("\(Format.duration(minutes: unshootable)) unshootable — \(unshootableCause)",
                              systemImage: "exclamationmark.triangle.fill")
                    } else {
                        Text(targetPlan?.fit.framingNote ?? "")
                    }
                }
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(unshootable > 0 || targetPlan == nil ? Palette.marginal : .secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Format.time(segment.window.start, in: plan.timeZone))–\(Format.time(segment.window.end, in: plan.timeZone))")
                    .font(.scaled(.callout, scale: uiTextScale).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(Format.duration(minutes: segment.window.durationMinutes))
                    .font(.scaled(.caption, scale: uiTextScale).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // The same picture, and the same catalog card on a click, as the
            // other targets listed under the plan.
            if let target = targetPlan?.target {
                TargetThumbnail(designation: target.designation)
                    .frame(width: 44 * uiTextScale, height: 44 * uiTextScale)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.panelBorder))
                    .contentShape(Rectangle())
                    .onTapGesture { isShowingCatalogDetail = true }
                    .help("Open \(target.displayName) in the catalog")
                    .sheet(isPresented: $isShowingCatalogDetail) {
                        TargetCatalogDetail(target: target, night: plan)
                    }
            }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove block")
                .accessibilityLabel("Remove block for \(segment.targetName)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selected ? Palette.accent.opacity(0.18) : Color.clear)
        .overlay(alignment: .leading) {
            // A bar as well as the tint, so selection doesn't rest on colour
            // alone and still reads when the window isn't key.
            if selected {
                Rectangle().fill(Palette.accent).frame(width: 3)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Why the hatched part of the block can't be shot, in the words someone
    /// at the telescope would use.
    private var unshootableCause: String {
        guard let targetPlan else { return "target not available" }
        let fragments = segment.unusableFragments(against: targetPlan)
        return Shootability.causes(of: fragments, for: targetPlan.target, in: plan,
                                   minimumAltitude: state.preferences.minimumUsefulAltitude)
    }
}

/// Hour labels on the same axis as the plan strip and availability bars.
struct HourAxisLabels: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var window: TimeWindow
    var timeZone: TimeZone

    var body: some View {
        GeometryReader { geometry in
            let axis = TimeAxis(window: window, width: geometry.size.width)
            let ticks = axis.hourTicks(timeZone: timeZone)
            // Every hour when there's room, every other hour when there isn't.
            let step = geometry.size.width / CGFloat(max(1, ticks.count)) < 44 * uiTextScale ? 2 : 1
            ForEach(Array(ticks.enumerated()), id: \.offset) { index, tick in
                if index % step == 0 {
                    Text(Format.time(tick, in: timeZone))
                        .font(.scaled(.caption2, scale: uiTextScale).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: axis.x(for: tick), y: geometry.size.height / 2)
                }
            }
        }
        .frame(height: 14 * uiTextScale)
        .accessibilityHidden(true)
    }
}

/// View Session, the same on Home and in the planner. Quiet but plainly a
/// button outside the night's session; while a session is on, or should be
/// (a block running, or the gap between two), as bold as Plan Session with a
/// slow green pulse round it, since that's when it's the thing to press.
struct ViewSessionButton: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var state: AppState
    var plan: NightPlan
    var fillsWidth = false
    var action: () -> Void

    @State private var isPulsing = false

    var body: some View {
        // Once a minute is plenty to notice a block starting.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let phase = SessionClock(at: context.date, plan: state.displayedPlan(for: plan)).phase
            let isOn = phase == .running || phase == .between
            button(isOn: isOn)
        }
    }

    @ViewBuilder
    private func button(isOn: Bool) -> some View {
        let base = Button(action: action) {
            Label("View Session", systemImage: "play.circle.fill")
                .font(.scaled(.body, scale: uiTextScale).weight(.semibold))
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .help(isOn ? "Your session is on now: what's up and what's next, in large type, for use at the telescope"
                   : "What's on now and next, in large type, for use at the telescope")
        if isOn {
            base
                .buttonStyle(.borderedProminent)
                .overlay {
                    Capsule()
                        .strokeBorder(Palette.exceptional, lineWidth: 2)
                        .padding(-4)
                        .opacity(reduceMotion ? 0.9 : (isPulsing ? 1 : 0.25))
                        .shadow(color: Palette.exceptional.opacity(isPulsing ? 0.7 : 0), radius: 6)
                        .allowsHitTesting(false)
                }
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { isPulsing = true }
                }
                .onDisappear { isPulsing = false }
        } else {
            // Plan Session's fill at partial strength: same shape and size,
            // clearly a button, clearly second to it.
            base
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent.opacity(0.26))
        }
    }
}
