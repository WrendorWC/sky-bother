import Foundation

/// What actually happened on a night, kept apart from the plan so running
/// the night never rewrites what was intended.
struct SessionRecord: Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case waiting, imaging, complete, skipped
    }

    struct Entry: Codable, Hashable, Identifiable, Sendable {
        /// The plan block this entry was made from.
        var id: UUID
        var targetID: String
        var targetName: String
        var planned: TimeWindow
        var status: Status = .waiting
        var startedAt: Date?
        var finishedAt: Date?

        /// Time actually spent imaging, up to `now` while still running.
        func capturedSeconds(now: Date) -> TimeInterval {
            guard let startedAt else { return 0 }
            let end = finishedAt ?? (status == .imaging ? now : startedAt)
            return max(0, end.timeIntervalSince(startedAt))
        }
    }

    var planKey: String
    var startedAt: Date
    var endedAt: Date?
    var entries: [Entry]

    init(planKey: String, plan: [PlanSegment], startedAt: Date) {
        self.planKey = planKey
        self.startedAt = startedAt
        self.entries = plan.chronological.map {
            Entry(id: $0.id, targetID: $0.targetID, targetName: $0.targetName, planned: $0.window)
        }
    }

    var isActive: Bool { endedAt == nil }

    /// The entry being worked on: the one imaging, else the first waiting.
    var currentIndex: Int? {
        entries.firstIndex { $0.status == .imaging } ?? entries.firstIndex { $0.status == .waiting }
    }

    var upcoming: [Entry] {
        guard let currentIndex else { return [] }
        return entries[(currentIndex + 1)...].filter { $0.status == .waiting }
    }

    var finishedCount: Int { entries.filter { $0.status == .complete }.count }

    func capturedSeconds(now: Date) -> TimeInterval {
        entries.reduce(0) { $0 + $1.capturedSeconds(now: now) }
    }

    // MARK: Actions

    mutating func markStarted(now: Date) {
        guard let index = currentIndex, entries[index].status == .waiting else { return }
        entries[index].status = .imaging
        entries[index].startedAt = now
    }

    /// Completes the current target, starting its clock first if it was never
    /// marked started — the planned start stands in, capped at now.
    mutating func markComplete(now: Date) {
        guard let index = currentIndex else { return }
        if entries[index].startedAt == nil {
            entries[index].startedAt = min(entries[index].planned.start, now)
        }
        entries[index].status = .complete
        entries[index].finishedAt = now
    }

    mutating func skip(now: Date) {
        guard let index = currentIndex else { return }
        if entries[index].status == .imaging { entries[index].finishedAt = now }
        entries[index].status = .skipped
    }

    /// Stops the clock on anything still imaging and closes the record.
    /// Nothing recorded is thrown away.
    mutating func end(now: Date) {
        for index in entries.indices where entries[index].status == .imaging {
            entries[index].status = .complete
            entries[index].finishedAt = now
        }
        endedAt = now
    }
}
