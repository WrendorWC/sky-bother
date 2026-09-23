import Foundation

/// Why a target can't be shot at a given moment, in the order someone at the
/// telescope would check: is it up, is it clear of the trees, is it high
/// enough, is it dark, is it clear.
enum Shootability {
    enum Reason: Equatable {
        case belowHorizon
        case blockedHorizon(direction: String)
        case belowMinimumAltitude(Double)
        case notDark
        case cloud

        var phrase: String {
            switch self {
            case .belowHorizon: return "below the horizon"
            case .blockedHorizon(let direction): return "behind your blocked horizon to the \(direction)"
            case .belowMinimumAltitude(let minimum): return "below your \(Format.degrees(minimum)) minimum altitude"
            case .notDark: return "not dark enough"
            case .cloud: return "cloud forecast"
            }
        }
    }

    /// The first thing stopping the target at this moment, or nil when none
    /// of these do. Nil doesn't promise the planner counts the moment as
    /// usable — it also weighs things like a minimum session length.
    static func reason(for target: Target, at moment: Date, in plan: NightPlan,
                       minimumAltitude: Double) -> Reason? {
        let position = SkyCoordinates.horizontal(target.coordinate,
                                                 daysSinceJ2000: moment.daysSinceJ2000,
                                                 latitude: plan.site.latitude,
                                                 longitude: plan.site.longitude)
        if position.altitude <= 0 { return .belowHorizon }
        if position.altitude < plan.site.blockedAltitude(azimuth: position.azimuth) {
            return .blockedHorizon(direction: position.compassPoint)
        }
        if position.altitude < minimumAltitude { return .belowMinimumAltitude(minimumAltitude) }
        if !plan.darkWindows.contains(where: { $0.contains(moment) }) { return .notDark }
        if plan.hasWeather && !plan.clearDarkWindows.contains(where: { $0.contains(moment) }) { return .cloud }
        return nil
    }

    /// Why the unshootable stretches of a block are unshootable, checked
    /// every ten minutes across them — in the order the reasons first bite,
    /// at most two of them.
    static func causes(of fragments: [TimeWindow], for target: Target, in plan: NightPlan,
                       minimumAltitude: Double) -> String {
        var causes: [String] = []
        for fragment in fragments {
            var moment = fragment.start
            while moment < fragment.end {
                if let reason = reason(for: target, at: moment, in: plan, minimumAltitude: minimumAltitude),
                   !causes.contains(reason.phrase) {
                    causes.append(reason.phrase)
                }
                moment = moment.addingTimeInterval(10 * 60)
            }
        }
        guard !causes.isEmpty else { return "outside the target's usable time" }
        return causes.prefix(2).joined(separator: ", then ")
    }
}

/// Times Sky View moves to, kept apart from the view so they can be tested.
enum SkyViewTimeline {
    /// A labelled point on the scrubber.
    struct Mark: Equatable {
        var date: Date
        var label: String
        /// Lower is kept first when labels would collide.
        var priority: Int
    }

    /// Evening, darkness, midnight, the selected target's peak, dawn and
    /// morning — only those that fall inside the night's own span.
    static func marks(for plan: NightPlan, target: TargetPlan?) -> [Mark] {
        let window = plan.chartWindow
        var marks = [Mark(date: window.start, label: Format.time(window.start, in: plan.timeZone), priority: 0),
                     Mark(date: window.end, label: Format.time(window.end, in: plan.timeZone), priority: 0)]
        if let dusk = plan.astronomicalDusk {
            marks.append(Mark(date: dusk, label: "\(Format.time(dusk, in: plan.timeZone)) dark", priority: 1))
        }
        if let dawn = plan.astronomicalDawn {
            marks.append(Mark(date: dawn, label: "\(Format.time(dawn, in: plan.timeZone)) dawn", priority: 1))
        }
        if let peak = target?.transitTime {
            marks.append(Mark(date: peak, label: "\(Format.time(peak, in: plan.timeZone)) peak", priority: 2))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = plan.timeZone
        if let midnight = calendar.nextDate(after: window.start, matching: DateComponents(hour: 0, minute: 0),
                                            matchingPolicy: .nextTime) {
            marks.append(Mark(date: midnight, label: "midnight", priority: 3))
        }
        return marks
            .filter { $0.date >= window.start && $0.date <= window.end }
            .sorted { $0.date < $1.date }
    }

    /// Where "Jump to best window" lands: the target's best moment when it
    /// has one inside its best window, otherwise the start of that window.
    static func bestWindowTime(for target: TargetPlan) -> Date? {
        guard let window = target.bestWindow, !window.isEmpty else { return target.bestTime }
        if let best = target.bestTime, window.contains(best) { return best }
        return window.start
    }

    /// The block that should be selected at a moment while following the
    /// plan: the one running then, or the next one coming up if the moment
    /// falls in a gap. Nil before the first block starts and after the last
    /// one ends.
    static func block(at moment: Date, in segments: [PlanSegment]) -> PlanSegment? {
        let ordered = segments.chronological
        guard let first = ordered.first, let last = ordered.last,
              moment >= first.window.start, moment < last.window.end else { return nil }
        return ordered.first { $0.window.end > moment }
    }

    /// The next time a target becomes usable after a moment, if it does
    /// again this night.
    static func nextUsable(after moment: Date, for target: TargetPlan) -> TimeWindow? {
        target.windows.sorted { $0.start < $1.start }.first { $0.end > moment }
    }
}
