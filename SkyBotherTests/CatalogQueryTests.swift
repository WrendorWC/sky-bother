import XCTest

/// The catalog against a chosen night: filters that need the night's scores,
/// and night sorts that keep unscored targets out of the way.
final class CatalogQueryTests: XCTestCase {

    private func target(_ id: String, name: String? = nil, type: TargetType = .galaxy) -> Target {
        Target(designation: id, commonName: name, type: type, rightAscension: 10, declination: 41,
               magnitude: 8, majorAxisArcminutes: 20, minorAxisArcminutes: 10, constellation: "And")
    }

    private func scored(_ id: String, score: Double, hours: Double, fill: Double = 0.5, mosaic: Int = 1) -> TargetPlan {
        var plan = TargetPlan.fixture(id: id, windows: [], score: score)
        plan.usableMinutes = hours * 60
        plan.fit.fillFraction = fill
        plan.fit.mosaicPanels = mosaic
        return plan
    }

    private lazy var targets = [target("A"), target("B"), target("C"), target("D"), target("E")]
    private lazy var night: [String: TargetPlan] = [
        "A": scored("A", score: 82, hours: 5),
        "B": scored("B", score: 50, hours: 6),            // marginal
        "C": scored("C", score: 70, hours: 1, fill: 0.03), // tiny in frame
        "D": scored("D", score: 65, hours: 3, fill: 1.4, mosaic: 4),
        // E has no usable time this night.
    ]

    func testWithoutNightFiltersEveryTargetIsKept() {
        let result = CatalogQuery().apply(to: targets, scored: night)
        XCTAssertEqual(result.map(\.id), ["A", "B", "C", "D", "E"])
    }

    func testGoodOnlyKeepsGoodOrBetterAndDropsUnscored() {
        let result = CatalogQuery(goodOnly: true).apply(to: targets, scored: night)
        XCTAssertEqual(Set(result.map(\.id)), ["A", "C", "D"])
    }

    func testFitsFrameMatchesThePlannersRule() {
        let result = CatalogQuery(fitsFrameOnly: true).apply(to: targets, scored: night)
        XCTAssertEqual(Set(result.map(\.id)), ["A", "B"], "tiny and mosaic targets are out")
    }

    func testMinimumUsableTime() {
        let result = CatalogQuery(minimumUsableHours: 3).apply(to: targets, scored: night)
        XCTAssertEqual(Set(result.map(\.id)), ["A", "B", "D"])
    }

    func testBestOnNightPutsUnscoredLast() {
        let result = CatalogQuery(sort: .bestOnNight).apply(to: targets, scored: night)
        XCTAssertEqual(result.map(\.id), ["A", "C", "D", "B", "E"])
    }

    func testLongestWindowSortsByUsableTime() {
        let result = CatalogQuery(sort: .longestWindow).apply(to: targets, scored: night)
        XCTAssertEqual(result.map(\.id), ["B", "A", "D", "C", "E"])
    }

    func testSearchStillAppliesAlongsideNightFilters() {
        var withNames = targets
        withNames[0] = target("A", name: "Whirlpool Galaxy")
        let result = CatalogQuery(search: "whirlpool", goodOnly: true).apply(to: withNames, scored: night)
        XCTAssertEqual(result.map(\.id), ["A"])
    }
}
