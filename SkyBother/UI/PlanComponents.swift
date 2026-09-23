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
                  ? "Manual plan: you changed this night's plan and saved it. It stays exactly as you left it — forecast updates won't replace it."
                  : "Suggested plan: the app's own schedule. It updates with the forecast and your settings until you change it and press Done.")
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
