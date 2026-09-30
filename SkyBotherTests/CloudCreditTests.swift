import XCTest

/// Cloud over the limit costs gradually: half for every six points over.
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

    func testEverySixPointsOverHalvesIt() {
        XCTAssertEqual(preferences.cloudCredit(cloudCover: 26), 0.5, accuracy: 1e-9)
        XCTAssertEqual(preferences.cloudCredit(cloudCover: 32), 0.25, accuracy: 1e-9)
        XCTAssertEqual(preferences.cloudCredit(cloudCover: 38), 0.125, accuracy: 1e-9)
    }

    func testNoCliffJustOverTheLimit() {
        // A point either side of where the old band ended changes little.
        let at29 = preferences.cloudCredit(cloudCover: 29)
        let at31 = preferences.cloudCredit(cloudCover: 31)
        XCTAssertGreaterThan(at31, 0.2)
        XCTAssertLessThan(at29 - at31, 0.1)
    }

    func testFarOverCountsForNothing() {
        XCTAssertEqual(preferences.cloudCredit(cloudCover: 50), 0)
        XCTAssertEqual(preferences.cloudCredit(cloudCover: 80), 0)
    }
}
