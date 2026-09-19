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

    /// How far a block may extend in each direction: up to its neighbours, and
    /// no further than the night being planned.
    ///
    /// One telescope can only point at one thing, so blocks never overlap —
    /// the bounds here are what enforce that, rather than a validation pass
    /// afterwards that would have to decide which of two overlapping blocks
    /// was the wrong one.
    static func bounds(for segment: PlanSegment,
                       among others: [PlanSegment],
                       within night: TimeWindow) -> (earliest: Date, latest: Date) {
        let before = others
            .filter { $0.id != segment.id && $0.window.start < segment.window.end }
            .map(\.window.end)
            .filter { $0 <= segment.window.start }
            .max()
        let after = others
            .filter { $0.id != segment.id && $0.window.end > segment.window.start }
            .map(\.window.start)
            .filter { $0 >= segment.window.end }
            .min()
        return (max(night.start, before ?? night.start),
                min(night.end, after ?? night.end))
    }

    /// Moves a block bodily, keeping its length, stopping against whatever is
    /// on either side of it rather than pushing through.
    static func moved(_ segment: PlanSegment,
                      by seconds: TimeInterval,
                      among others: [PlanSegment],
                      within night: TimeWindow) -> PlanSegment {
        let (earliest, latest) = bounds(for: segment, among: others, within: night)
        let length = segment.window.duration
        guard latest.timeIntervalSince(earliest) >= length else { return segment }

        var start = snapped(segment.window.start.addingTimeInterval(seconds))
        start = max(earliest, min(start, latest.addingTimeInterval(-length)))
        var moved = segment
        moved.window = TimeWindow(start: start, end: start.addingTimeInterval(length))
        return moved
    }

    /// Drags one edge, leaving the other where it is.
    static func resized(_ segment: PlanSegment,
                        movingStart: Bool,
                        by seconds: TimeInterval,
                        among others: [PlanSegment],
                        within night: TimeWindow) -> PlanSegment {
        let (earliest, latest) = bounds(for: segment, among: others, within: night)
        let minimum = minimumMinutes * 60
        var resized = segment

        if movingStart {
            var start = snapped(segment.window.start.addingTimeInterval(seconds))
            start = max(earliest, min(start, segment.window.end.addingTimeInterval(-minimum)))
            resized.window = TimeWindow(start: start, end: segment.window.end)
        } else {
            var end = snapped(segment.window.end.addingTimeInterval(seconds))
            end = min(latest, max(end, segment.window.start.addingTimeInterval(minimum)))
            resized.window = TimeWindow(start: segment.window.start, end: end)
        }
        return resized
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

    /// The night with every existing block cut out of it.
    static func freeStretches(among existing: [PlanSegment], within night: TimeWindow) -> [TimeWindow] {
        var free = [night]
        for segment in existing {
            free = free.flatMap { $0.subtracting(segment.window) }
        }
        return free
    }
}
