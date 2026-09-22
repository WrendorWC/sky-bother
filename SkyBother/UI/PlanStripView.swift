import SwiftUI
import AppKit

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

    /// What the pointer is currently over, so the cursor can say which of the
    /// two gestures a press would start before you commit to one. Tracked as
    /// a case rather than an `NSCursor` so "unchanged" is a value comparison
    /// and the cursor is only actually set when it really changes.
    private enum Hover: Equatable { case none, body, edge, dragging }

    @State private var drag: Drag?
    /// The plan as it looks mid-gesture. Kept separate from the stored one so
    /// an in-flight drag is never what gets persisted.
    @State private var preview: [PlanSegment]?
    @State private var hover: Hover = .none
    /// The most recent layout this drag produced that was actually legal.
    @State private var lastValid: [PlanSegment]?

    private var displayed: [PlanSegment] { (preview ?? segments).chronological }

    var body: some View {
        GeometryReader { geometry in
            let axis = TimeAxis(window: plan.chartWindow, width: geometry.size.width)
            Canvas { context, size in
                draw(context: context, size: size, axis: axis)
            }
            .contentShape(Rectangle())
            .gesture(gesture(axis: axis))
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard isEditing else { return }
                switch phase {
                case .active(let location): apply(hover: hover(at: location, axis: axis))
                case .ended: apply(hover: .none)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // The strip is the same height in both modes, so this border is the
        // only thing saying whether the blocks under the pointer are live.
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isEditing ? Palette.accent : Palette.panelBorder,
                              lineWidth: isEditing ? 2 : 1)
        )
        .animation(.easeInOut(duration: 0.18), value: isEditing)
        // Leaving edit mode with the pointer still over a block would
        // otherwise strand whichever cursor was last set.
        .onChange(of: isEditing) { _, editing in if !editing { apply(hover: .none) } }
        .onDisappear { apply(hover: .none) }
    }

    // MARK: - Cursor

    /// Which gesture the pointer is currently in range of. A drag in progress
    /// outranks position: once you have hold of a block the cursor shouldn't
    /// flicker back to the arrow just because the pointer ran ahead of where
    /// the block is allowed to go.
    private func hover(at location: CGPoint, axis: TimeAxis) -> Hover {
        if let drag { return drag.grip == .move ? .dragging : .edge }
        guard let hit = segment(at: location.x, axis: axis) else { return .none }
        let startX = axis.x(for: hit.window.start)
        let endX = axis.x(for: hit.window.end)
        let atEdge = location.x - startX <= Self.edgeGrabWidth || endX - location.x <= Self.edgeGrabWidth
        return atEdge ? .edge : .body
    }

    private func apply(hover newValue: Hover) {
        guard newValue != hover else { return }
        hover = newValue
        switch newValue {
        // Both ends of a block resize along one axis, and a block only ever
        // travels along that axis too, so the standard horizontal-resize
        // cursor is the honest one for an edge.
        case .edge: NSCursor.resizeLeftRight.set()
        // The open/closed hand pair is what macOS uses for picking something
        // up and moving it, which is exactly what dragging a block's body is.
        case .body: NSCursor.openHand.set()
        case .dragging: NSCursor.closedHand.set()
        case .none: NSCursor.arrow.set()
        }
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
        var block = context
        block.clip(to: shape)
        for fragment in fragments {
            let from = axis.x(for: fragment.start)
            let to = axis.x(for: fragment.end)
            guard to > from else { continue }
            // A fresh copy per fragment. Clipping the shared context instead
            // narrowed it to the first fragment for every one after, and two
            // fragments never overlap — so a block unshootable at both ends,
            // as dragging one end out of its window easily makes it, only
            // ever showed the hatching at one of them.
            var context = block
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
                if drag == nil {
                    drag = beginDrag(at: value.startLocation, axis: axis)
                    // Set from the gesture rather than waiting for the next
                    // hover event, so the hand closes on the press itself.
                    if let drag { apply(hover: drag.grip == .move ? .dragging : .edge) }
                }
                guard let drag, isEditing else { return }
                preview = applying(translation: value.translation.width, drag: drag, axis: axis)
            }
            .onEnded { value in
                defer {
                    self.drag = nil
                    self.preview = nil
                    self.lastValid = nil
                    // Dropped: back to whatever the pointer is now over,
                    // which the next hover event decides.
                    apply(hover: .none)
                }
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

    /// The whole plan as it would be with this drag applied, or the last
    /// layout that worked when this one can't be resolved. Holding the last
    /// good one is what makes an over-dragged block stop at the limit instead
    /// of springing back to where the gesture started.
    private func applying(translation: CGFloat, drag: Drag, axis: TimeAxis) -> [PlanSegment] {
        // Points to seconds through the axis itself rather than a stored
        // scale, so this stays correct when the window is resized mid-plan.
        let secondsPerPoint = plan.chartWindow.duration / Double(max(1, axis.width))
        let delta = Double(translation) * secondsPerPoint

        guard let segment = drag.original.first(where: { $0.id == drag.id }) else { return drag.original }
        let night = plan.chartWindow

        let moved: PlanSegment
        switch drag.grip {
        case .move: moved = SessionPlanRules.moved(segment, by: delta, within: night)
        case .start: moved = SessionPlanRules.resized(segment, movingStart: true, by: delta, within: night)
        case .end: moved = SessionPlanRules.resized(segment, movingStart: false, by: delta, within: night)
        }

        if let resolved = SessionPlanRules.resolve(dragged: moved,
                                                   against: drag.original,
                                                   within: night,
                                                   allowSwap: drag.grip == .move) {
            lastValid = resolved
            return resolved
        }
        return lastValid ?? drag.original
    }

    private func segment(at x: CGFloat, axis: TimeAxis) -> PlanSegment? {
        displayed.first { x >= axis.x(for: $0.window.start) && x <= axis.x(for: $0.window.end) }
    }

    private func targetPlan(for segment: PlanSegment) -> TargetPlan? {
        plan.targets.first { $0.id == segment.targetID }
    }
}
