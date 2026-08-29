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
/// one that doesn't overlap anything already claimed. The single best target on
/// a given night can therefore never lose its slot to a pile of worse ones —
/// the only thing that can bump a candidate is something that scores higher and
/// wants the same time.
enum AutoPlanner {
    /// Below this, a window isn't worth suggesting a setup change for.
    static let minimumSlotMinutes: Double = 20

    static func plan(for night: NightPlan, minimumScore: Double) -> [AutoPlanSlot] {
        let candidates = night.targets
            .filter { $0.score >= minimumScore }
            .compactMap { targetPlan -> (TargetPlan, TimeWindow)? in
                guard let window = targetPlan.bestWindow, window.durationMinutes >= minimumSlotMinutes else {
                    return nil
                }
                return (targetPlan, window)
            }
            .sorted { $0.0.score > $1.0.score }

        var chosen: [(TargetPlan, TimeWindow)] = []
        for candidate in candidates where !chosen.contains(where: { $0.1.intersection(with: candidate.1) != nil }) {
            chosen.append(candidate)
        }

        return chosen
            .sorted { $0.1.start < $1.1.start }
            .map { AutoPlanSlot(targetPlan: $0.0, window: $0.1) }
    }
}
