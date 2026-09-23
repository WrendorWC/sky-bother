import XCTest

/// Running a night: actual timing is recorded apart from the plan, and
/// skipping or ending never loses what was recorded.
final class SessionRecordTests: XCTestCase {

    private let evening = Date(timeIntervalSince1970: 1_790_013_600)
    private func at(_ minutes: Double) -> Date { evening.addingTimeInterval(minutes * 60) }

    private var plan: [PlanSegment] {
        [PlanSegment(targetID: "a", targetName: "A", window: TimeWindow(start: at(0), end: at(120))),
         PlanSegment(targetID: "b", targetName: "B", window: TimeWindow(start: at(120), end: at(240))),
         PlanSegment(targetID: "c", targetName: "C", window: TimeWindow(start: at(240), end: at(300)))]
    }

    func testStartsOnTheFirstTargetWithNothingRecorded() {
        let record = SessionRecord(planKey: "k", plan: plan, startedAt: at(-5))
        XCTAssertEqual(record.currentIndex, 0)
        XCTAssertEqual(record.upcoming.map(\.targetID), ["b", "c"])
        XCTAssertEqual(record.capturedSeconds(now: at(10)), 0)
    }

    func testActualTimingIsRecordedApartFromThePlan() {
        var record = SessionRecord(planKey: "k", plan: plan, startedAt: at(0))
        record.markStarted(now: at(10))
        XCTAssertEqual(record.capturedSeconds(now: at(40)), 30 * 60)
        record.markComplete(now: at(100))
        XCTAssertEqual(record.entries[0].status, .complete)
        XCTAssertEqual(record.entries[0].capturedSeconds(now: at(500)), 90 * 60)
        XCTAssertEqual(record.entries[0].planned, plan[0].window, "the plan's times are untouched")
        XCTAssertEqual(record.currentIndex, 1)
    }

    func testSkippingMovesOnAndKeepsTheEntry() {
        var record = SessionRecord(planKey: "k", plan: plan, startedAt: at(0))
        record.skip(now: at(5))
        XCTAssertEqual(record.entries[0].status, .skipped)
        XCTAssertEqual(record.entries.count, 3)
        XCTAssertEqual(record.currentIndex, 1)
        XCTAssertEqual(record.finishedCount, 0)
    }

    func testCompletingWithoutMarkingStartedUsesThePlannedStart() {
        var record = SessionRecord(planKey: "k", plan: plan, startedAt: at(0))
        record.markComplete(now: at(60))
        XCTAssertEqual(record.entries[0].startedAt, at(0))
        XCTAssertEqual(record.entries[0].capturedSeconds(now: at(60)), 60 * 60)
    }

    func testEndingStopsTheClockAndKeepsEverything() {
        var record = SessionRecord(planKey: "k", plan: plan, startedAt: at(0))
        record.markComplete(now: at(120))
        record.markStarted(now: at(125))
        record.end(now: at(185))
        XCTAssertFalse(record.isActive)
        XCTAssertEqual(record.finishedCount, 2)
        XCTAssertEqual(record.capturedSeconds(now: at(999)), (120 + 60) * 60)
    }

    func testAllDoneLeavesNoCurrentTarget() {
        var record = SessionRecord(planKey: "k", plan: plan, startedAt: at(0))
        for _ in 0..<3 { record.markComplete(now: at(300)) }
        XCTAssertNil(record.currentIndex)
    }

    func testRecordsSurviveSavingAndOlderFilesLoadWithout() throws {
        var settings = StoredSettings.initial
        settings.sessionRecords["k"] = SessionRecord(planKey: "k", plan: plan, startedAt: at(0))
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(StoredSettings.self, from: data).sessionRecords, settings.sessionRecords)

        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "sessionRecords")
        let old = try JSONDecoder().decode(StoredSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.sessionRecords.isEmpty)
    }

    /// Very large previews ask the survey for a capped size, which it can
    /// answer before the request times out.
    func testCutoutRequestsAreCapped() {
        let big = SkyCutout(rightAscensionDegrees: 314, declinationDegrees: 31.7, widthDegrees: 3.3,
                            pixelWidth: 2864, pixelHeight: 1910)
        XCTAssertLessThanOrEqual(max(big.pixelWidth, big.pixelHeight), SkyCutout.maximumPixels)
        XCTAssertEqual(Double(big.pixelWidth) / Double(big.pixelHeight), 2864.0 / 1910.0, accuracy: 0.05)

        let small = SkyCutout(rightAscensionDegrees: 314, declinationDegrees: 31.7, widthDegrees: 3.3,
                              pixelWidth: 640, pixelHeight: 448)
        XCTAssertEqual(small.pixelWidth, 640)
        XCTAssertEqual(small.pixelHeight, 448)
    }
}
