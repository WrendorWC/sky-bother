import Foundation

/// One block of a night pointed at one target.
///
/// The thing that makes this different from `AutoPlanSlot` is that it carries
/// its own identity rather than borrowing its target's. A slot is keyed by the
/// target it holds, so a target can only ever appear once in a suggested plan;
/// a segment can appear as many times as you like, which is what makes
/// "M31 for ninety minutes, NGC 1514 for two hours, then back to M31"
/// expressible at all.
struct PlanSegment: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var targetID: String
    /// Kept beside the id so a block still reads as itself when its target is
    /// no longer in tonight's plan at all. A cloudier forecast or a raised
    /// horizon can drop a target out of `NightPlan.targets` entirely, and a
    /// block labelled with a bare catalogue id would be unreadable at exactly
    /// the moment you need to decide what to do about it.
    var targetName: String
    var window: TimeWindow
}

extension PlanSegment {
    /// The parts of this block during which the target isn't actually
    /// shootable — below the horizon, not dark enough, or forecast cloudy.
    /// Empty when the whole block is good.
    ///
    /// Blocks are deliberately allowed to cover such time: the forecast is a
    /// forecast, and someone who wants to point at a target through a cloud
    /// band the app doesn't believe in is entitled to. Marking it is the job
    /// here, not preventing it.
    func unusableFragments(against targetPlan: TargetPlan?) -> [TimeWindow] {
        guard let targetPlan else { return [window] }
        var fragments = [window]
        for usable in targetPlan.windows {
            fragments = fragments.flatMap { $0.subtracting(usable) }
            if fragments.isEmpty { return [] }
        }
        return fragments
    }

    func unusableMinutes(against targetPlan: TargetPlan?) -> Double {
        unusableFragments(against: targetPlan).totalMinutes
    }
}

extension Array where Element == PlanSegment {
    /// In the order they'll actually be shot.
    var chronological: [PlanSegment] { sorted { $0.window.start < $1.window.start } }

    var totalMinutes: Double { reduce(0) { $0 + $1.window.durationMinutes } }
}

/// Rules shared by every edit to a hand-built plan, so dragging a block,
/// resizing one and dropping a new one in all agree about what a legal plan
/// looks like.
enum SessionPlanRules {
    /// Below this a block isn't a session, it's a mis-drag.
    static let minimumMinutes: Double = 10

    /// Edits land on a round number of minutes. Dragging is a pixel-precision
    /// gesture over a scale of several hours, where one pixel is worth about a
    /// minute — without snapping, every block would read 9:43–11:07 and no two
    /// would ever line up.
    static let snapMinutes: Double = 5

    static func snapped(_ date: Date) -> Date {
        let step = snapMinutes * 60
        return Date(timeIntervalSince1970: (date.timeIntervalSince1970 / step).rounded() * step)
    }

    /// Moves a block bodily, keeping its length, bounded only by the night
    /// itself. What happens where it lands is `resolve`'s problem — a block is
    /// free to be dragged over its neighbours, and stopping it dead at the
    /// first one is exactly what made reordering impossible.
    static func moved(_ segment: PlanSegment,
                      by seconds: TimeInterval,
                      within night: TimeWindow) -> PlanSegment {
        let length = segment.window.duration
        var start = snapped(segment.window.start.addingTimeInterval(seconds))
        start = max(night.start, min(start, night.end.addingTimeInterval(-length)))
        var moved = segment
        moved.window = TimeWindow(start: start, end: start.addingTimeInterval(length))
        return moved
    }

    /// Drags one edge, leaving the other where it is.
    static func resized(_ segment: PlanSegment,
                        movingStart: Bool,
                        by seconds: TimeInterval,
                        within night: TimeWindow) -> PlanSegment {
        let minimum = minimumMinutes * 60
        var resized = segment
        if movingStart {
            var start = snapped(segment.window.start.addingTimeInterval(seconds))
            start = max(night.start, min(start, segment.window.end.addingTimeInterval(-minimum)))
            resized.window = TimeWindow(start: start, end: segment.window.end)
        } else {
            var end = snapped(segment.window.end.addingTimeInterval(seconds))
            end = min(night.end, max(end, segment.window.start.addingTimeInterval(minimum)))
            resized.window = TimeWindow(start: segment.window.start, end: end)
        }
        return resized
    }

    /// Works out what the rest of the night looks like once one block has been
    /// dragged somewhere, or returns nil if it can't be made to work — in which
    /// case the caller holds the last layout that did, so the block simply
    /// stops rather than snapping back to where the drag began.
    ///
    /// A block dragged into its neighbour shortens that neighbour from the
    /// side being encroached on, the way dropping a clip onto a video timeline
    /// does. Keep pushing and the neighbour would eventually vanish, which is
    /// never what was meant — so at the point it would drop below the minimum
    /// length it hops to the *other* side of the dragged block instead, at its
    /// original length. That is what reordering is here: push a block far
    /// enough into its neighbour and the two change places.
    ///
    /// Resizing trims the same way but never swaps. Dragging an edge is a
    /// statement about how long you spend on *this* target, and having a
    /// neighbour jump across the night in response would be absurd.
    static func resolve(dragged: PlanSegment,
                        against original: [PlanSegment],
                        within night: TimeWindow,
                        allowSwap: Bool) -> [PlanSegment]? {
        let minimum = minimumMinutes * 60
        var placed: [PlanSegment] = [dragged]

        for var other in original.filter({ $0.id != dragged.id }).chronological {
            guard other.window.intersection(with: dragged.window) != nil else {
                placed.append(other)
                continue
            }
            let length = other.window.duration
            // Which way it gets pushed is decided by where its middle sits
            // relative to the dragged block's, not by which edge happens to
            // overlap: that stays stable as the overlap grows, where an
            // edge test flips the moment the dragged block covers it.
            let isLeft = other.window.midpoint < dragged.window.midpoint
            let trimmed = isLeft
                ? TimeWindow(start: other.window.start, end: dragged.window.start)
                : TimeWindow(start: dragged.window.end, end: other.window.end)

            if trimmed.duration >= minimum {
                other.window = trimmed
                placed.append(other)
                continue
            }

            guard allowSwap else { return nil }
            // Everything the displaced block has to miss: what's already been
            // placed, plus the original positions of the ones not looked at
            // yet. Using their originals is pessimistic — some will end up
            // trimmed and leave more room — but it can only ever refuse a
            // layout, never produce an overlapping one.
            let pending = original
                .filter { $0.id != dragged.id && $0.id != other.id }
                .filter { o in !placed.contains { $0.id == o.id } }
                .map(\.window)
            let occupied = placed.map(\.window) + pending

            // Not simply the far side of the dragged block: that slot may
            // itself be taken, and then the honest answer is the next free one
            // out. That's what lets a block be dragged past two neighbours in
            // one gesture instead of jamming against the second.
            guard let swapped = nearestSlot(length: length,
                                            from: isLeft ? dragged.window.end : dragged.window.start,
                                            goingLeft: !isLeft,
                                            avoiding: occupied,
                                            within: night)
            else { return nil }
            other.window = swapped
            placed.append(other)
        }

        // A block that hopped across can land on one not yet considered.
        // Rejecting the whole layout is right: the alternative is silently
        // producing two blocks pointed at different targets at the same time.
        for i in placed.indices {
            for j in placed.indices where j > i {
                if placed[i].window.intersection(with: placed[j].window) != nil { return nil }
            }
        }
        return placed.chronological
    }

    /// Where a newly added block should go: the longest stretch of the night
    /// nothing has claimed yet that the target can actually use, falling back
    /// to the longest unclaimed stretch at all when the target has no usable
    /// time left — the block is still worth placing, it just gets marked as
    /// unshootable rather than silently refused.
    static func placement(for targetPlan: TargetPlan?,
                          among existing: [PlanSegment],
                          within night: TimeWindow,
                          preferredMinutes: Double) -> TimeWindow? {
        let free = freeStretches(among: existing, within: night)
            .filter { $0.durationMinutes >= minimumMinutes }
        guard !free.isEmpty else { return nil }

        let usable = (targetPlan.map { free.intersected(with: $0.windows) } ?? [])
            .filter { $0.durationMinutes >= minimumMinutes }
        guard let stretch = (usable.isEmpty ? free : usable).max(by: { $0.duration < $1.duration })
        else { return nil }

        let length = min(stretch.duration, max(preferredMinutes, minimumMinutes) * 60)
        // Anchored to the start of the gap rather than centred on the target's
        // best moment: a hand-built plan is a running order, and a new block
        // that lands flush against the one before it is what someone filling a
        // night actually wants. Dragging it elsewhere is one gesture away.
        return TimeWindow(start: stretch.start, end: stretch.start.addingTimeInterval(length))
    }

    /// The closest place a block of a given length fits, starting from
    /// `anchor` and searching one way only.
    private static func nearestSlot(length: TimeInterval,
                                    from anchor: Date,
                                    goingLeft: Bool,
                                    avoiding occupied: [TimeWindow],
                                    within night: TimeWindow) -> TimeWindow? {
        var free = [night]
        for window in occupied {
            free = free.flatMap { $0.subtracting(window) }
        }
        let roomy = free.filter { $0.duration >= length }

        if goingLeft {
            guard let stretch = roomy.filter({ $0.end <= anchor }).max(by: { $0.end < $1.end })
            else { return nil }
            // Flush against the right-hand end of that gap, so it ends up as
            // close to where it was pushed from as the gap allows.
            return TimeWindow(start: stretch.end.addingTimeInterval(-length), end: stretch.end)
        }
        guard let stretch = roomy.filter({ $0.start >= anchor }).min(by: { $0.start < $1.start })
        else { return nil }
        return TimeWindow(start: stretch.start, end: stretch.start.addingTimeInterval(length))
    }

    /// The night with every existing block cut out of it.
    static func freeStretches(among existing: [PlanSegment], within night: TimeWindow) -> [TimeWindow] {
        var free = [night]
        for segment in existing {
            free = free.flatMap { $0.subtracting(segment.window) }
        }
        return free
    }
}
