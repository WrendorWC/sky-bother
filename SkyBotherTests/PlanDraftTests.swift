import XCTest

/// Phase 0 of the implementation brief: opening the plan editor and leaving
/// it without a real change must never create or rewrite a Manual plan.
final class PlanDraftTests: XCTestCase {

    // 20:00 on an arbitrary night, on the five-minute grid.
    private let evening = Date(timeIntervalSince1970: 1_790_000_400)
    private let key = "2026-09-25"

    private func at(_ minutes: Double) -> Date { evening.addingTimeInterval(minutes * 60) }

    private func block(_ target: String, _ from: Double, _ to: Double) -> PlanSegment {
        PlanSegment(targetID: target, targetName: target.uppercased(),
                    window: TimeWindow(start: at(from), end: at(to)))
    }

    private var night: TimeWindow { TimeWindow(start: at(-60), end: at(660)) }

    private var suggestion: [PlanSegment] {
        [block("ngc7008", 0, 120), block("ngc2440", 120, 330), block("ic405", 330, 540)]
    }

    // MARK: - Unchanged edits write nothing

    func testUnchangedSuggestedPlanIsNotDirtyAndWritesNothing() {
        let draft = PlanDraft(planKey: key, displayed: suggestion, isManual: false)
        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(draft.outcome, .unchanged)

        var plans: [String: [PlanSegment]] = [:]
        XCTAssertFalse(PlanBook.commit(draft, into: &plans))
        XCTAssertNil(plans[key], "an unchanged suggestion must stay a suggestion")
    }

    /// The scheduler hands back times like 21:24:09. Opening the editor keeps
    /// them: rounding to the grid there pushed blocks past the edge of their
    /// target's usable time and marked them unshootable for no reason.
    func testOpeningASuggestionKeepsTheSchedulersTimes() {
        var offGrid = suggestion
        offGrid[0].window = TimeWindow(start: at(0.15), end: at(119.8))
        let draft = PlanDraft(planKey: key, displayed: offGrid, isManual: false)
        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(draft.segments[0].window, offGrid[0].window)
    }

    func testUnchangedManualPlanKeepsItsIdentifiersAndIsNotRewritten() {
        let manual = suggestion
        var plans = [key: manual]
        let draft = PlanDraft(planKey: key, displayed: manual, isManual: true)
        XCTAssertFalse(PlanBook.commit(draft, into: &plans))
        XCTAssertEqual(plans[key], manual)
        XCTAssertEqual(plans[key]?.map(\.id), manual.map(\.id))
    }

    /// Ids, stored names and the order edits happened in are bookkeeping.
    func testMetadataOnlyDifferencesAreNotChanges() {
        var draft = PlanDraft(planKey: key, displayed: suggestion, isManual: false)
        draft.segments = draft.segments.reversed().map { segment in
            var copy = segment
            copy.id = UUID()
            copy.targetName = "Renamed"
            return copy
        }
        XCTAssertFalse(draft.isDirty)
    }

    func testEditingBackToTheOriginalIsNotAChange() {
        var draft = PlanDraft(planKey: key, displayed: suggestion, isManual: false)
        let first = draft.segments[0]
        draft.segments[0] = SessionPlanRules.moved(first, by: 30 * 60, within: night)
        XCTAssertTrue(draft.isDirty)
        draft.segments[0] = first
        XCTAssertFalse(draft.isDirty)
    }

    // MARK: - Real edits

    func testMovingABlockMakesTheNightManual() {
        var draft = PlanDraft(planKey: key, displayed: suggestion, isManual: false)
        let last = draft.segments[2]
        draft.segments[2] = SessionPlanRules.moved(last, by: 60 * 60, within: night)
        XCTAssertTrue(draft.isDirty)

        var plans: [String: [PlanSegment]] = [:]
        XCTAssertTrue(PlanBook.commit(draft, into: &plans))
        XCTAssertEqual(plans[key]?.last?.window, TimeWindow(start: at(390), end: at(600)))
    }

    func testResizingABlockIsAChange() {
        var draft = PlanDraft(planKey: key, displayed: suggestion, isManual: false)
        draft.segments[1] = SessionPlanRules.resized(draft.segments[1], movingStart: false,
                                                     by: -30 * 60, within: night)
        XCTAssertTrue(draft.isDirty)
    }

    func testReorderingTargetsIsAChange() {
        var draft = PlanDraft(planKey: key, displayed: suggestion, isManual: false)
        let firstTarget = draft.segments[0].targetID
        draft.segments[0].targetID = draft.segments[1].targetID
        draft.segments[1].targetID = firstTarget
        XCTAssertTrue(draft.isDirty)
    }

    func testSplittingIntoADuplicateTargetIsAChange() {
        var draft = PlanDraft(planKey: key, displayed: suggestion, isManual: false)
        draft.segments[1].window = TimeWindow(start: at(120), end: at(220))
        draft.segments.append(block("ngc7008", 220, 330))
        XCTAssertTrue(draft.isDirty)

        var plans: [String: [PlanSegment]] = [:]
        PlanBook.commit(draft, into: &plans)
        XCTAssertEqual(plans[key]?.filter { $0.targetID == "ngc7008" }.count, 2)
        XCTAssertEqual(plans[key]?.map(\.window.start), plans[key]?.map(\.window.start).sorted(),
                       "saved plans are kept in running order")
    }

    func testDraggingIntoANeighbourUsesTheSharedRules() throws {
        let draft = PlanDraft(planKey: key, displayed: suggestion, isManual: false)
        let dragged = SessionPlanRules.moved(draft.segments[0], by: 60 * 60, within: night)
        let resolved = try XCTUnwrap(SessionPlanRules.resolve(dragged: dragged, against: draft.segments,
                                                              within: night, allowSwap: true))
        var edited = draft
        edited.segments = resolved
        XCTAssertTrue(edited.isDirty)
        for (a, b) in zip(resolved, resolved.dropFirst()) {
            XCTAssertLessThanOrEqual(a.window.end, b.window.start, "blocks must never overlap")
        }
    }

    // MARK: - Clear and Cancel

    func testClearOnlyAffectsTheDraft() {
        let manual = suggestion
        let plans = [key: manual]
        var draft = PlanDraft(planKey: key, displayed: manual, isManual: true)
        draft.segments = []
        XCTAssertTrue(draft.isDirty)
        // Cancel is simply never committing: the saved plan is untouched.
        XCTAssertEqual(plans[key], manual)
    }

    func testClearThenDoneSavesAnEmptyNightRatherThanReverting() {
        var draft = PlanDraft(planKey: key, displayed: suggestion, isManual: false)
        draft.segments = []
        var plans: [String: [PlanSegment]] = [:]
        XCTAssertTrue(PlanBook.commit(draft, into: &plans))
        XCTAssertEqual(plans[key], [])
    }

    func testClearingAnAlreadyEmptySuggestionIsNotAChange() {
        var draft = PlanDraft(planKey: key, displayed: [], isManual: false)
        draft.segments = []
        XCTAssertEqual(draft.outcome, .unchanged)
    }

    // MARK: - Reset and Undo

    func testResetRemovesTheManualPlanAndUndoRestoresItExactly() {
        let manual = suggestion
        var plans = [key: manual, "2026-09-26": [block("m31", 0, 60)]]
        let removed = PlanBook.reset(key, in: &plans)
        XCTAssertEqual(removed, manual)
        XCTAssertNil(plans[key])
        XCTAssertNotNil(plans["2026-09-26"], "reset touches only its own night")

        PlanBook.undoReset(key, restoring: try! XCTUnwrap(removed), in: &plans)
        XCTAssertEqual(plans[key], manual)
    }

    func testResetOnASuggestedNightChangesNothing() {
        var plans: [String: [PlanSegment]] = [:]
        XCTAssertNil(PlanBook.reset(key, in: &plans))
        XCTAssertTrue(plans.isEmpty)
    }

    // MARK: - Persistence

    func testASavedEditSurvivesARoundTrip() throws {
        var draft = PlanDraft(planKey: key, displayed: suggestion, isManual: false)
        draft.segments[1] = SessionPlanRules.resized(draft.segments[1], movingStart: true,
                                                     by: 15 * 60, within: night)
        var plans: [String: [PlanSegment]] = [:]
        PlanBook.commit(draft, into: &plans)

        let data = try JSONEncoder().encode(plans)
        let decoded = try JSONDecoder().decode([String: [PlanSegment]].self, from: data)
        XCTAssertEqual(decoded, plans)
    }

    /// Loading settings used to round every saved block to the five-minute
    /// grid, which pushed untouched blocks past their target's usable time.
    func testSavedPlansLoadExactlyAsSaved() throws {
        var settings = StoredSettings.initial
        settings.hasSetLocation = true
        let futureKey = "2099-01-01"
        var offGrid = suggestion
        offGrid[1].window = TimeWindow(start: at(120.97), end: at(330.97))
        settings.sessionPlans = [futureKey: offGrid]

        let data = try JSONEncoder().encode(settings)
        let loaded = try JSONDecoder().decode(StoredSettings.self, from: data)
        XCTAssertEqual(loaded.sessionPlans[futureKey], offGrid)
    }

    func testUnshootableSliversUnderAMinuteAreIgnored() {
        let block = PlanSegment(targetID: "ngc869", targetName: "Double Cluster",
                                window: TimeWindow(start: at(0), end: at(120)))
        let targetPlan = TargetPlan.fixture(id: "ngc869", windows: [TimeWindow(start: at(0.5), end: at(119.7))])
        XCTAssertEqual(block.unusableMinutes(against: targetPlan), 0)

        let late = TargetPlan.fixture(id: "ngc869", windows: [TimeWindow(start: at(5), end: at(120))])
        XCTAssertEqual(block.unusableMinutes(against: late), 5, accuracy: 0.01)
    }

    func testRevertRestoresTheOriginalAndKeepsEditing() {
        var draft = PlanDraft(planKey: key, displayed: suggestion, isManual: false)
        draft.segments.removeLast()
        draft.segments[0] = SessionPlanRules.moved(draft.segments[0], by: 20 * 60, within: night)
        XCTAssertTrue(draft.isDirty)
        draft.revert()
        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(draft.segments, draft.original)
    }

    /// The suggestion is rebuilt on every read, so its blocks need the same
    /// identity each time or nothing can tell which block is which.
    func testSuggestedBlocksKeepTheirIdentityAcrossReads() {
        let window = TimeWindow(start: at(0), end: at(120))
        let first = PlanSegment.suggested(targetID: "m31", targetName: "M31", window: window)
        let again = PlanSegment.suggested(targetID: "m31", targetName: "M31", window: window)
        let other = PlanSegment.suggested(targetID: "m33", targetName: "M33", window: window)
        let later = PlanSegment.suggested(targetID: "m31", targetName: "M31",
                                          window: TimeWindow(start: at(5), end: at(120)))
        XCTAssertEqual(first.id, again.id)
        XCTAssertNotEqual(first.id, other.id)
        XCTAssertNotEqual(first.id, later.id)
    }
}
