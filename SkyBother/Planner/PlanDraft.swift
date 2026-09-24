import Foundation

/// One night's plan while it is open for editing.
///
/// Edits live here, in memory, until Done, so opening and closing the editor
/// without a real change never turns the suggestion into a Manual plan (which
/// would then stop following the forecast).
struct PlanDraft: Equatable, Sendable {
    /// Which night this is — `NightPlan.planKey`.
    let planKey: String
    /// The plan as it stood when editing began, and what Cancel returns to.
    let original: [PlanSegment]
    /// Whether `original` was a saved Manual plan rather than the suggestion.
    let originalIsManual: Bool
    var segments: [PlanSegment]

    /// Starts from exactly what was on screen — a Manual plan as saved,
    /// identifiers included, and a suggestion at the scheduler's own times. Not
    /// snapped to the five-minute grid: that can push a block past the edge of
    /// its target's usable time and mark it unshootable. Blocks go onto the
    /// grid when dragged.
    init(planKey: String, displayed: [PlanSegment], isManual: Bool) {
        self.planKey = planKey
        self.originalIsManual = isManual
        self.original = displayed.chronological
        self.segments = original
    }

    /// True when Done would save something. Only what gets shot and when
    /// counts — block identifiers, stored names and the order edits were made
    /// in don't.
    var isDirty: Bool { !Self.isSemanticallyEqual(original, segments) }

    /// Back to the plan as it was when editing began, still editing.
    mutating func revert() {
        segments = original
    }

    enum Outcome: Equatable {
        /// Nothing to save; whatever was there before stays as it was.
        case unchanged
        /// Save these as the night's Manual plan.
        case save([PlanSegment])
    }

    var outcome: Outcome { isDirty ? .save(segments.chronological) : .unchanged }

    /// The same targets over the same times, in the same running order.
    static func isSemanticallyEqual(_ a: [PlanSegment], _ b: [PlanSegment]) -> Bool {
        a.chronological.map(Key.init) == b.chronological.map(Key.init)
    }

    private struct Key: Equatable {
        var targetID: String
        var start: Date
        var end: Date

        init(_ segment: PlanSegment) {
            targetID = segment.targetID
            start = segment.window.start
            end = segment.window.end
        }
    }
}

/// What the saved plans look like after each editing action. Kept apart from
/// `AppState` so the rules — above all "no change, no write" — can be tested
/// without the app around them.
enum PlanBook {
    /// Applies a finished draft. Returns false, leaving `plans` untouched,
    /// when the draft holds nothing new.
    @discardableResult
    static func commit(_ draft: PlanDraft, into plans: inout [String: [PlanSegment]]) -> Bool {
        guard case .save(let segments) = draft.outcome else { return false }
        plans[draft.planKey] = segments
        return true
    }

    /// Removes a night's Manual plan so it follows the suggestion again.
    /// Returns what was removed, for Undo; nil when there was no Manual plan
    /// and so nothing changed.
    static func reset(_ planKey: String, in plans: inout [String: [PlanSegment]]) -> [PlanSegment]? {
        plans.removeValue(forKey: planKey)
    }

    /// Puts back a plan that `reset` removed.
    static func undoReset(_ planKey: String, restoring segments: [PlanSegment],
                          in plans: inout [String: [PlanSegment]]) {
        plans[planKey] = segments
    }
}
