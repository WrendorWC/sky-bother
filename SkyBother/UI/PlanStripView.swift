import SwiftUI

/// The session as a Gantt strip on the night timeline's own time axis, and —
/// when editing — the surface you build it on: drag a block along the night,
/// drag either edge to change how long you spend there.
///
/// Editing happens here rather than in a list of start and end times because
/// the question being answered is a shape question. "Is there a gap after
/// M31?", "does this block run past the point the target clears the tree?" —
/// those are answered by looking, and answered badly by reading twelve
/// timestamps.
struct PlanStripView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.uiTextScale) private var uiTextScale

    var plan: NightPlan
    var segments: [PlanSegment]
    var isEditing: Bool
    /// Called once per gesture, on release — not continuously, so a drag
    /// doesn't write to disk sixty times a second.
    var onCommit: ([PlanSegment]) -> Void

    /// How close to an edge counts as grabbing the edge rather than the block.
    private static let edgeGrabWidth: CGFloat = 10

    private enum Grip { case move, start, end }

    private struct Drag {
        var id: UUID
        var grip: Grip
        var original: [PlanSegment]
    }

    @State private var drag: Drag?
    /// The plan as it looks mid-gesture. Kept separate from the stored one so
    /// an in-flight drag is never what gets persisted.
    @State private var preview: [PlanSegment]?

    private var displayed: [PlanSegment] { (preview ?? segments).chronological }

    var body: some View {
        GeometryReader { geometry in
            let axis = TimeAxis(window: plan.chartWindow, width: geometry.size.width)
            Canvas { context, size in
                draw(context: context, size: size, axis: axis)
            }
            .contentShape(Rectangle())
            .gesture(gesture(axis: axis))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.panelBorder))
    }

    // MARK: - Drawing

    private func draw(context: GraphicsContext, size: CGSize, axis: TimeAxis) {
        context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6),
                     with: .color(Palette.spaceTop))

        // Two consecutive targets often land within a point or two of each
        // other on the score colour scale, so a shared edge alone can vanish
        // entirely. A real gap reads as a boundary no matter how close the
        // colours are, which a same-colour stroke never reliably does.
        let gap: CGFloat = 3

        for segment in displayed {
            let targetPlan = targetPlan(for: segment)
            let startX = axis.x(for: segment.window.start)
            let endX = axis.x(for: segment.window.end)
            let rect = CGRect(x: startX + gap / 2, y: 0,
                              width: max(2, (endX - startX) - gap), height: size.height)
            let isSelected = state.selectedTargetID == segment.targetID
            // No target plan means the target has dropped out of tonight
            // entirely — clouded over, or now behind the horizon. There's no
            // score to colour it by, and it isn't a neutral state either.
            let color = targetPlan.map { Palette.score($0.score) } ?? Palette.skip
            let shape = Path(roundedRect: rect, cornerRadius: 5)

            context.fill(shape, with: .color(color.opacity(isSelected ? 0.95 : 0.75)))

            // Time the target can't actually be shot in is hatched rather than
            // recoloured: the block keeps its own identity and score colour,
            // and the hatching reads as "this part is a problem" instead of
            // the whole block looking like a different target.
            drawHatching(context: context, shape: shape, axis: axis, height: size.height,
                         fragments: segment.unusableFragments(against: targetPlan))

            context.stroke(shape, with: .color(isSelected ? Palette.accent : color),
                           lineWidth: isSelected ? 2 : 1)

            if isEditing && rect.width > Self.edgeGrabWidth * 3 {
                drawGrips(context: context, rect: rect)
            }

            if rect.width > 50 {
                context.draw(Text(segment.targetName)
                                .font(.system(size: 11 * uiTextScale, weight: .semibold))
                                .foregroundColor(.white),
                             at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }
        }
    }

    private func drawHatching(context: GraphicsContext, shape: Path, axis: TimeAxis,
                              height: CGFloat, fragments: [TimeWindow]) {
        guard !fragments.isEmpty else { return }
        var context = context
        context.clip(to: shape)
        for fragment in fragments {
            let from = axis.x(for: fragment.start)
            let to = axis.x(for: fragment.end)
            guard to > from else { continue }
            var stripes = Path()
            // Diagonals rather than a flat wash, so this survives being drawn
            // over any of the score colours without becoming its own colour.
            var x = from - height
            while x < to {
                stripes.move(to: CGPoint(x: x, y: height))
                stripes.addLine(to: CGPoint(x: x + height, y: 0))
                x += 7
            }
            context.clip(to: Path(CGRect(x: from, y: 0, width: to - from, height: height)))
            context.stroke(stripes, with: .color(.black.opacity(0.45)), lineWidth: 2)
        }
    }

    /// Two pale bars at the ends of a block, marking the parts of it that
    /// resize rather than move. Without them the two gestures are
    /// indistinguishable until you've already done the wrong one.
    private func drawGrips(context: GraphicsContext, rect: CGRect) {
        for x in [rect.minX + 4, rect.maxX - 4] {
            let bar = CGRect(x: x - 1, y: rect.height * 0.28, width: 2, height: rect.height * 0.44)
            context.fill(Path(roundedRect: bar, cornerRadius: 1), with: .color(.white.opacity(0.75)))
        }
    }

    // MARK: - Editing

    private func gesture(axis: TimeAxis) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if drag == nil { drag = beginDrag(at: value.startLocation, axis: axis) }
                guard let drag, isEditing else { return }
                preview = applying(translation: value.translation.width, drag: drag, axis: axis)
            }
            .onEnded { value in
                defer { self.drag = nil; self.preview = nil }
                // A press that never really moved is a selection, not an edit.
                if abs(value.translation.width) < 3 {
                    if let hit = segment(at: value.location.x, axis: axis) {
                        state.selectedTargetID = hit.targetID
                    }
                    return
                }
                guard let drag, isEditing else { return }
                onCommit(applying(translation: value.translation.width, drag: drag, axis: axis))
            }
    }

    private func beginDrag(at location: CGPoint, axis: TimeAxis) -> Drag? {
        guard isEditing, let hit = segment(at: location.x, axis: axis) else { return nil }
        let startX = axis.x(for: hit.window.start)
        let endX = axis.x(for: hit.window.end)
        let grip: Grip
        if location.x - startX <= Self.edgeGrabWidth {
            grip = .start
        } else if endX - location.x <= Self.edgeGrabWidth {
            grip = .end
        } else {
            grip = .move
        }
        return Drag(id: hit.id, grip: grip, original: segments.chronological)
    }

    private func applying(translation: CGFloat, drag: Drag, axis: TimeAxis) -> [PlanSegment] {
        // Points to seconds through the axis itself rather than a stored
        // scale, so this stays correct when the window is resized mid-plan.
        let secondsPerPoint = plan.chartWindow.duration / Double(max(1, axis.width))
        let delta = Double(translation) * secondsPerPoint

        var result = drag.original
        guard let index = result.firstIndex(where: { $0.id == drag.id }) else { return result }
        let others = result.filter { $0.id != drag.id }
        let segment = result[index]

        switch drag.grip {
        case .move:
            result[index] = SessionPlanRules.moved(segment, by: delta, among: others,
                                                   within: plan.chartWindow)
        case .start:
            result[index] = SessionPlanRules.resized(segment, movingStart: true, by: delta,
                                                     among: others, within: plan.chartWindow)
        case .end:
            result[index] = SessionPlanRules.resized(segment, movingStart: false, by: delta,
                                                     among: others, within: plan.chartWindow)
        }
        return result
    }

    private func segment(at x: CGFloat, axis: TimeAxis) -> PlanSegment? {
        displayed.first { x >= axis.x(for: $0.window.start) && x <= axis.x(for: $0.window.end) }
    }

    private func targetPlan(for segment: PlanSegment) -> TargetPlan? {
        plan.targets.first { $0.id == segment.targetID }
    }
}
