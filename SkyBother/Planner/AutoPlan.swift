import Foundation

/// One target assigned a slot in a suggested session plan.
struct AutoPlanSlot: Identifiable, Hashable, Sendable {
    var targetPlan: TargetPlan
    var window: TimeWindow

    var id: String { targetPlan.id }
}

/// Picks a session plan for the night: an ordered, non-overlapping sequence of
/// targets — since a single scope can only point at one thing at a time.
///
/// This used to be solved as textbook weighted interval scheduling, maximising
/// the *sum* of the chosen targets' scores. That reliably backfired: a target's
/// score is a standalone 0–100 quality rating, not a currency meant to be added
/// up across picks, so summing let two mediocre targets (52 + 54 = 106) outbid
/// one genuinely excellent one (94) and quietly bump it from its own plan —
/// exactly the target the rest of the app was calling out as the night's best.
///
/// Instead this fills the night greedily, best score first: take the
/// highest-scoring candidate unconditionally, then keep taking the next-best
/// one — trimmed to whatever's left of it once every already-claimed window
/// is cut out, rather than dropped outright the moment it overlaps anything.
/// A target whose window is only partly claimed still gets the leftover part
/// of the night; only a target with nothing usable left anywhere (or less
/// than `minimumSlotMinutes` of it) is actually dropped. The single best
/// target on a given night can therefore never lose its slot to a pile of
/// worse ones — the only thing that can cost a candidate time is something
/// that scores higher and wants the same part of the night.
///
/// Every one of a target's usable windows is tried, not just its single
/// longest ("best") one — many targets peak at a similar time of night, so
/// the best window is exactly where contention is worst, and a target whose
/// best window loses out can easily still have a second, perfectly good
/// window elsewhere that nothing else wants. Only trying the best window
/// meant later, lower-priority candidates got squeezed out one after
/// another even when the night had free time they could have used.
enum AutoPlanner {
    /// Below this, a window isn't worth suggesting a setup change for.
    static let minimumSlotMinutes: Double = 20

    /// `restrictedTo`, when given, replaces the usual minimum-score filter
    /// entirely rather than narrowing it further — these are targets the
    /// user picked by hand, so the question is purely "what's the best
    /// schedule among exactly these," not "and do they also clear the usual
    /// bar." It's exactly this trimming behaviour that makes hand-picking
    /// worthwhile: every target the user checks gets the app's best attempt
    /// at fitting it in somewhere, rather than one silently vanishing the
    /// moment a higher-scoring pick wants the same part of the night.
    ///
    /// `sessionCapMinutes`, when given, additionally caps how much of the
    /// night any single target can claim on its first pass — without it, two
    /// picks whose windows are each most of the night (common: a lot of
    /// targets peak around the same time) can exhaust the whole thing
    /// between them, leaving nothing behind for anyone else to trim into, no
    /// matter how many windows they're each tried against. Only meaningful
    /// alongside `restrictedTo`: the usual score-ranked plan is deliberately
    /// allowed to give its best target as much of the night as it can use.
    ///
    /// With `restrictedTo` set, this runs in two passes:
    ///
    /// 1. **Coverage**, most-constrained target first (least total available
    ///    time across all its windows) rather than best score first. A
    ///    target with one narrow window is only ever going to fit there;
    ///    scheduling it before a flexible target — which has other options
    ///    regardless of what happens here — claims that narrow opportunity
    ///    while it still exists, instead of letting a more flexible target
    ///    take it just because it happened to score higher.
    /// 2. **Fill**, best score first: once everyone who fits has an initial
    ///    (session-capped) slot, extend each one into whatever's still
    ///    genuinely unclaimed immediately next to it — real usable darkness
    ///    that nothing else in the plan needs shouldn't sit idle just
    ///    because the first pass was conservative about handing it out.
    static func plan(for night: NightPlan, minimumScore: Double, restrictedTo allowedTargetIDs: Set<String>? = nil,
                     sessionCapMinutes: Double? = nil) -> [AutoPlanSlot] {
        let isCustom = allowedTargetIDs != nil
        let candidates = night.targets
            .filter { targetPlan in
                if let allowedTargetIDs {
                    return allowedTargetIDs.contains(targetPlan.id)
                }
                return targetPlan.score >= minimumScore
            }
            .filter { !$0.windows.isEmpty }

        let schedulingOrder = isCustom
            ? candidates.sorted { $0.windows.totalMinutes < $1.windows.totalMinutes }
            : candidates.sorted { $0.score > $1.score }

        var chosen: [(TargetPlan, TimeWindow)] = []
        for targetPlan in schedulingOrder {
            let claimed = chosen.map(\.1)
            let bestAvailableSlot = targetPlan.windows
                .compactMap { largestFreeFragment(of: $0, avoiding: claimed) }
                .max { $0.duration < $1.duration }
            guard var slot = bestAvailableSlot, slot.durationMinutes >= minimumSlotMinutes else { continue }
            if isCustom, let cap = sessionCapMinutes, slot.durationMinutes > cap {
                slot = capped(slot, toMinutes: cap, centeredOn: targetPlan.bestTime)
            }
            chosen.append((targetPlan, slot))
        }

        if isCustom {
            chosen = fillLeftoverTime(chosen)
        }

        return chosen
            .sorted { $0.1.start < $1.1.start }
            .map { AutoPlanSlot(targetPlan: $0.0, window: $0.1) }
    }

    /// Extends each already-chosen slot, best score first, into any free
    /// time immediately adjacent to it that still lies within that same
    /// target's own usable window — bounded on each side by whichever
    /// already-chosen slot is closest, so this can only ever fill genuinely
    /// unclaimed time, never create a new overlap.
    private static func fillLeftoverTime(_ chosen: [(TargetPlan, TimeWindow)]) -> [(TargetPlan, TimeWindow)] {
        var result = chosen
        for index in result.indices.sorted(by: { result[$0].0.score > result[$1].0.score }) {
            let (targetPlan, slot) = result[index]
            let others = result.enumerated().filter { $0.offset != index }.map { $0.element.1 }

            // The one window (of this target's own several) that the current
            // slot actually lives inside — that's the real ceiling on how
            // far it can grow, not the whole night.
            let ownWindow = targetPlan.windows.first { $0.start <= slot.start && slot.end <= $0.end }
                ?? targetPlan.windows.max { $0.duration < $1.duration }
            guard let ownWindow else { continue }

            let earlierBound = others.filter { $0.end <= slot.start }.map(\.end).max() ?? ownWindow.start
            let laterBound = others.filter { $0.start >= slot.end }.map(\.start).min() ?? ownWindow.end

            let expanded = TimeWindow(start: max(ownWindow.start, earlierBound),
                                      end: min(ownWindow.end, laterBound))
            if expanded.duration > slot.duration {
                result[index] = (targetPlan, expanded)
            }
        }
        return result
    }

    /// `window` with every already-claimed window cut out of it, keeping
    /// only the single largest remaining contiguous piece — a target still
    /// gets one coherent slot to point at, not two disjoint slivers before
    /// and after something else.
    private static func largestFreeFragment(of window: TimeWindow, avoiding claimed: [TimeWindow]) -> TimeWindow? {
        var fragments = [window]
        for other in claimed {
            fragments = fragments.flatMap { $0.subtracting(other) }
            if fragments.isEmpty { return nil }
        }
        return fragments.max { $0.duration < $1.duration }
    }

    /// Shrinks `window` to `cap` minutes, centred on `preferredCenter` (the
    /// target's own best moment, clamped into the window) when given, so the
    /// part that survives the cap is the good part rather than an arbitrary
    /// leading slice.
    private static func capped(_ window: TimeWindow, toMinutes cap: Double, centeredOn preferredCenter: Date?) -> TimeWindow {
        let capSeconds = cap * 60
        let center = (preferredCenter.map { max(window.start, min($0, window.end)) }) ?? window.midpoint
        var start = center.addingTimeInterval(-capSeconds / 2)
        var end = center.addingTimeInterval(capSeconds / 2)
        if start < window.start {
            start = window.start
            end = start.addingTimeInterval(capSeconds)
        }
        if end > window.end {
            end = window.end
            start = end.addingTimeInterval(-capSeconds)
        }
        return TimeWindow(start: start, end: end)
    }
}
