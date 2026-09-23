import Foundation

/// Where tonight's plan stands at a given moment — what's on now, what's
/// next — worked out from the clock alone, so the session view needs nothing
/// from you to stay right.
struct SessionClock: Equatable {
    enum Phase: Equatable {
        /// Before the first block.
        case notStarted
        /// Inside a block.
        case running
        /// Between two blocks.
        case between
        /// After the last block.
        case finished
    }

    var phase: Phase
    var current: PlanSegment?
    var next: PlanSegment?
    /// Blocks still to come after `current`, or after now when there's none.
    var upcoming: [PlanSegment]

    init(at now: Date, plan segments: [PlanSegment]) {
        // Worked out in locals first: closures can't read `self` until every
        // stored property is set.
        let ordered = segments.chronological
        let running = ordered.first { $0.window.contains(now) }
        let from = running?.window.end ?? now
        let later = ordered.filter { $0.window.start >= from && $0.id != running?.id }
        current = running
        upcoming = later
        next = later.first
        if running != nil {
            phase = .running
        } else if let first = ordered.first, now < first.window.start {
            phase = .notStarted
        } else if next != nil {
            phase = .between
        } else {
            phase = .finished
        }
    }
}
