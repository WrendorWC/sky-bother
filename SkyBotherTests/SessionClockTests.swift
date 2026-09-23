import XCTest

/// The session view follows the clock: what's on now and what's next.
final class SessionClockTests: XCTestCase {
    private let evening = Date(timeIntervalSince1970: 1_790_013_600)
    private func at(_ minutes: Double) -> Date { evening.addingTimeInterval(minutes * 60) }

    private lazy var plan = [
        PlanSegment(targetID: "a", targetName: "A", window: TimeWindow(start: at(60), end: at(120))),
        PlanSegment(targetID: "b", targetName: "B", window: TimeWindow(start: at(150), end: at(240))),
        PlanSegment(targetID: "c", targetName: "C", window: TimeWindow(start: at(240), end: at(300)))]

    func testBeforeThePlanShowsTheFirstBlockAsNext() {
        let clock = SessionClock(at: at(10), plan: plan)
        XCTAssertEqual(clock.phase, .notStarted)
        XCTAssertNil(clock.current)
        XCTAssertEqual(clock.next?.targetID, "a")
        XCTAssertEqual(clock.upcoming.map(\.targetID), ["a", "b", "c"])
    }

    func testDuringABlockShowsItAndWhatFollows() {
        let clock = SessionClock(at: at(90), plan: plan)
        XCTAssertEqual(clock.phase, .running)
        XCTAssertEqual(clock.current?.targetID, "a")
        XCTAssertEqual(clock.upcoming.map(\.targetID), ["b", "c"])
    }

    func testInAGapShowsTheNextBlock() {
        let clock = SessionClock(at: at(130), plan: plan)
        XCTAssertEqual(clock.phase, .between)
        XCTAssertEqual(clock.next?.targetID, "b")
    }

    func testASharedBoundaryBelongsToTheBlockStartingThere() {
        XCTAssertEqual(SessionClock(at: at(240), plan: plan).current?.targetID, "c")
    }

    func testAfterThePlanIsFinished() {
        let clock = SessionClock(at: at(400), plan: plan)
        XCTAssertEqual(clock.phase, .finished)
        XCTAssertNil(clock.next)
    }
}
