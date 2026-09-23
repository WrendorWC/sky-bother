import XCTest

/// Sky View's clock: where Jump to best window lands, which planned block is
/// selected while following the plan, and the labelled scrubber marks.
final class SkyViewTimelineTests: XCTestCase {

    // 18:00 UTC.
    private let evening = Date(timeIntervalSince1970: 1_790_013_600)
    private func at(_ hours: Double) -> Date { evening.addingTimeInterval(hours * 3600) }

    private func block(_ target: String, _ from: Double, _ to: Double) -> PlanSegment {
        PlanSegment(targetID: target, targetName: target, window: TimeWindow(start: at(from), end: at(to)))
    }

    // MARK: - Following the plan

    func testFollowingThePlanPicksTheRunningBlockThenTheNextOne() {
        let plan = [block("a", 2, 4), block("b", 5, 7), block("c", 7, 9)]
        XCTAssertNil(SkyViewTimeline.block(at: at(1), in: plan), "before the first block")
        XCTAssertEqual(SkyViewTimeline.block(at: at(3), in: plan)?.targetID, "a")
        XCTAssertEqual(SkyViewTimeline.block(at: at(4.5), in: plan)?.targetID, "b",
                       "a gap hands over to what's coming next, not what just ended")
        XCTAssertEqual(SkyViewTimeline.block(at: at(7), in: plan)?.targetID, "c",
                       "a shared boundary belongs to the block starting there")
        XCTAssertNil(SkyViewTimeline.block(at: at(9), in: plan), "after the last block")
    }

    func testClickingABlockLandsOnItsMidpoint() {
        XCTAssertEqual(block("a", 2, 5).window.midpoint, at(3.5))
    }

    // MARK: - Jump to best window

    func testJumpLandsOnTheBestMomentInsideTheBestWindow() {
        var target = TargetPlan.fixture(id: "m31", windows: [TimeWindow(start: at(3), end: at(8))])
        target.bestTime = at(6)
        XCTAssertEqual(SkyViewTimeline.bestWindowTime(for: target), at(6))
    }

    func testJumpFallsBackToTheWindowStartWhenTheBestMomentIsOutsideIt() {
        var target = TargetPlan.fixture(id: "m31", windows: [TimeWindow(start: at(1), end: at(2)),
                                                             TimeWindow(start: at(3), end: at(8))])
        target.bestTime = at(1.5)
        XCTAssertEqual(SkyViewTimeline.bestWindowTime(for: target), at(3), "the longest window is the best one")
    }

    func testNextUsableSkipsWindowsAlreadyOver() {
        let target = TargetPlan.fixture(id: "m31", windows: [TimeWindow(start: at(1), end: at(2)),
                                                             TimeWindow(start: at(5), end: at(8))])
        XCTAssertEqual(SkyViewTimeline.nextUsable(after: at(3), for: target)?.start, at(5))
        XCTAssertEqual(SkyViewTimeline.nextUsable(after: at(1.5), for: target)?.start, at(1), "still running")
        XCTAssertNil(SkyViewTimeline.nextUsable(after: at(9), for: target))
    }

    // MARK: - Scrubber marks

    func testMarksRunFromEveningToMorningWithDarknessMidnightAndPeak() {
        var target = TargetPlan.fixture(id: "m31", windows: [TimeWindow(start: at(3), end: at(8))])
        target.transitTime = at(7.25)
        let plan = NightPlan.fixture(evening: evening, targets: [target])
        let marks = SkyViewTimeline.marks(for: plan, target: target)

        XCTAssertEqual(marks.map(\.label), ["18:00", "20:00 dark", "midnight", "01:15 peak", "04:00 dawn", "06:00"])
        XCTAssertEqual(marks.map(\.date), marks.map(\.date).sorted())
    }

    func testAPeakOutsideTheNightIsLeftOff() {
        var target = TargetPlan.fixture(id: "m31", windows: [])
        target.transitTime = at(14)
        let marks = SkyViewTimeline.marks(for: NightPlan.fixture(evening: evening), target: target)
        XCTAssertFalse(marks.contains { $0.label.hasSuffix("peak") })
    }
}
