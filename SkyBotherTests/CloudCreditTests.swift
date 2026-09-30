import XCTest

/// Cloud over the limit costs in proportion, not all or nothing.
final class CloudCreditTests: XCTestCase {
    private var preferences: Preferences {
        var preferences = Preferences()
        preferences.maximumCloudCover = 20
        return preferences
    }

    func testAtOrUnderTheLimitCountsInFull() {
        XCTAssertEqual(preferences.cloudCredit(cloudCover: 0), 1)
        XCTAssertEqual(preferences.cloudCredit(cloudCover: 20), 1)
    }

    func testJustOverTheLimitStillCountsMost() {
        XCTAssertEqual(preferences.cloudCredit(cloudCover: 22), 0.8, accuracy: 1e-9)
        XCTAssertEqual(preferences.cloudCredit(cloudCover: 25), 0.5, accuracy: 1e-9)
    }

    func testTenPointsOverCountsForNothing() {
        XCTAssertEqual(preferences.cloudCredit(cloudCover: 30), 0)
        XCTAssertEqual(preferences.cloudCredit(cloudCover: 80), 0)
    }
}
