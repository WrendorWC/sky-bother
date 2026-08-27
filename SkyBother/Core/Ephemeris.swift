import Foundation

/// Numerical event finding. Rather than solving each rise/set analytically —
/// which needs special cases for the moon's fast motion, circumpolar objects and
/// polar summer — everything here samples an altitude function on a fixed grid
/// and refines the crossings by bisection. It is uniform, hard to get wrong, and
/// fast enough to run the whole catalogue for a week of nights.
enum Ephemeris {

    /// Finds every interval in [start, end] where `altitude(date) >= threshold`.
    static func windows(above threshold: Double,
                        from start: Date,
                        to end: Date,
                        stepMinutes: Double = 2,
                        altitude: (Date) -> Double) -> [TimeWindow] {
        guard end > start, stepMinutes > 0 else { return [] }

        var result: [TimeWindow] = []
        var openedAt: Date? = nil

        var previousDate = start
        var previousValue = altitude(start) - threshold
        if previousValue >= 0 { openedAt = start }

        let totalMinutes = end.timeIntervalSince(start) / 60
        let stepCount = max(1, Int((totalMinutes / stepMinutes).rounded(.up)))

        for i in 1...stepCount {
            let date = min(end, start.addingMinutes(Double(i) * stepMinutes))
            let value = altitude(date) - threshold

            if previousValue < 0 && value >= 0 {
                let crossing = refineCrossing(threshold: threshold,
                                              earlier: previousDate,
                                              later: date,
                                              altitude: altitude)
                openedAt = crossing
            } else if previousValue >= 0 && value < 0 {
                let crossing = refineCrossing(threshold: threshold,
                                              earlier: previousDate,
                                              later: date,
                                              altitude: altitude)
                if let opened = openedAt, crossing > opened {
                    result.append(TimeWindow(start: opened, end: crossing))
                }
                openedAt = nil
            }

            previousDate = date
            previousValue = value
            if date >= end { break }
        }

        if let opened = openedAt, end > opened {
            result.append(TimeWindow(start: opened, end: end))
        }
        return result
    }

    /// Bisection refinement of a bracketed crossing. Twenty iterations over a
    /// bracket of a few minutes lands well inside a second.
    private static func refineCrossing(threshold: Double,
                                       earlier: Date,
                                       later: Date,
                                       altitude: (Date) -> Double) -> Date {
        var low = earlier
        var high = later
        let lowValue = altitude(low) - threshold
        for _ in 0..<20 {
            let middle = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            let middleValue = altitude(middle) - threshold
            if (middleValue < 0) == (lowValue < 0) {
                low = middle
            } else {
                high = middle
            }
        }
        return low.addingTimeInterval(high.timeIntervalSince(low) / 2)
    }

    /// First time in the range at which the altitude crosses `threshold` in the
    /// given direction, or nil if it never does.
    static func firstCrossing(threshold: Double,
                              rising: Bool,
                              from start: Date,
                              to end: Date,
                              stepMinutes: Double = 2,
                              altitude: (Date) -> Double) -> Date? {
        guard end > start else { return nil }
        var previousDate = start
        var previousValue = altitude(start) - threshold
        let stepCount = max(1, Int((end.timeIntervalSince(start) / 60 / stepMinutes).rounded(.up)))

        for i in 1...stepCount {
            let date = min(end, start.addingMinutes(Double(i) * stepMinutes))
            let value = altitude(date) - threshold
            let crossedUp = previousValue < 0 && value >= 0
            let crossedDown = previousValue >= 0 && value < 0
            if (rising && crossedUp) || (!rising && crossedDown) {
                return refineCrossing(threshold: threshold, earlier: previousDate, later: date, altitude: altitude)
            }
            previousDate = date
            previousValue = value
            if date >= end { break }
        }
        return nil
    }

    /// Highest altitude reached in the range and when it happens (transit, for an
    /// object that culminates during the night).
    static func maximum(from start: Date,
                        to end: Date,
                        stepMinutes: Double = 5,
                        altitude: (Date) -> Double) -> (date: Date, altitude: Double) {
        var bestDate = start
        var bestAltitude = altitude(start)
        guard end > start else { return (bestDate, bestAltitude) }

        let stepCount = max(1, Int((end.timeIntervalSince(start) / 60 / stepMinutes).rounded(.up)))
        for i in 1...stepCount {
            let date = min(end, start.addingMinutes(Double(i) * stepMinutes))
            let value = altitude(date)
            if value > bestAltitude {
                bestAltitude = value
                bestDate = date
            }
            if date >= end { break }
        }
        return (bestDate, bestAltitude)
    }
}
