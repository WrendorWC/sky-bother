import Foundation

/// One target assigned a slot in a suggested session plan.
struct AutoPlanSlot: Identifiable, Hashable, Sendable {
    var targetPlan: TargetPlan
    var window: TimeWindow

    var id: String { targetPlan.id }
}

/// Picks a session plan for the night: an ordered, non-overlapping sequence of
/// targets — since a single scope can only point at one thing at a time — that
/// maximises total quality. Each candidate's window already comes out of the
/// same score the rest of the app shows (time on target, sky darkness, clear
/// sky, framing, detectability, altitude), so "best combination" here means
/// exactly that same score, just scheduled instead of merely sorted.
///
/// This is the textbook weighted interval scheduling problem: sort candidates
/// by end time, and for each one decide whether including it (plus the best
/// plan that finishes before it starts) beats skipping it. It reliably finds
/// the actual optimum, not a greedy approximation — so it will correctly
/// prefer two shorter, better-scoring windows over one long mediocre one when
/// that combination scores higher, and vice versa.
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
            .sorted { $0.1.end < $1.1.end }

        guard !candidates.isEmpty else { return [] }

        // bestValue[k] = the best total score achievable using only
        // candidates[0..<k]. include[i] records whether the optimum at i+1
        // actually uses candidate i, so the chosen set can be walked back out.
        var bestValue = [Double](repeating: 0, count: candidates.count + 1)
        var include = [Bool](repeating: false, count: candidates.count)
        var predecessor = [Int](repeating: -1, count: candidates.count)

        for i in 0..<candidates.count {
            var p = -1
            for j in stride(from: i - 1, through: 0, by: -1) where candidates[j].1.end <= candidates[i].1.start {
                p = j
                break
            }
            predecessor[i] = p

            let withCandidate = candidates[i].0.score + bestValue[p + 1]
            let withoutCandidate = bestValue[i]
            if withCandidate > withoutCandidate {
                bestValue[i + 1] = withCandidate
                include[i] = true
            } else {
                bestValue[i + 1] = withoutCandidate
            }
        }

        var chosen: [(TargetPlan, TimeWindow)] = []
        var i = candidates.count - 1
        while i >= 0 {
            if include[i] {
                chosen.append(candidates[i])
                i = predecessor[i]
            } else {
                i -= 1
            }
        }

        return chosen.reversed().map { AutoPlanSlot(targetPlan: $0.0, window: $0.1) }
    }
}
