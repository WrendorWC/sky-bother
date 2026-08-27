import Foundation

/// A half-open interval of time. Unlike `DateInterval` this never traps on an
/// inverted range — it just reports a zero duration — which matters because
/// several of these are built from numerically solved crossing times.
struct TimeWindow: Codable, Hashable, Identifiable, Sendable {
    var start: Date
    var end: Date

    var id: String { "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var durationMinutes: Double { duration / 60 }
    var durationHours: Double { duration / 3600 }
    var isEmpty: Bool { duration <= 0 }
    var midpoint: Date { start.addingTimeInterval(duration / 2) }

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    func intersection(with other: TimeWindow) -> TimeWindow? {
        let s = max(start, other.start)
        let e = min(end, other.end)
        guard e > s else { return nil }
        return TimeWindow(start: s, end: e)
    }

    /// Total overlap with a set of windows, in minutes.
    func overlapMinutes(with others: [TimeWindow]) -> Double {
        others.compactMap { intersection(with: $0)?.durationMinutes }.reduce(0, +)
    }
}

extension Array where Element == TimeWindow {
    var totalMinutes: Double { reduce(0) { $0 + $1.durationMinutes } }

    /// Intersects every window in this list with every window in another list.
    func intersected(with others: [TimeWindow]) -> [TimeWindow] {
        var result: [TimeWindow] = []
        for a in self {
            for b in others {
                if let overlap = a.intersection(with: b) { result.append(overlap) }
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// The single longest window, if any.
    var longest: TimeWindow? { self.max { $0.duration < $1.duration } }
}
