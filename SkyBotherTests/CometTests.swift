import XCTest

/// Comet positions from Minor Planet Center orbits, checked against JPL
/// Horizons (astrometric J2000 RA/Dec) for 2026-09-29 12:00 UT.
final class CometTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_790_683_200)

    private let lines = [
        "0010P         2026 08  2.1043  1.417740  0.537442  195.4606  117.7969   12.0271  20260929  13.1  4.0  10P/Tempel                                               MPC xxxxx",
        "0161P         2026 11 27.1769  1.265129  0.836196   47.0634    1.4736   95.7919  20260929  13.5  4.0  161P/Hartley-IRAS                                        MPEC 2026-SH8",
        "    CK26A020  2026 12 22.3522  1.937799  0.997669  155.9370  206.5879   82.3059  20260929  11.4  4.0  C/2026 A2 (Bok)                                          MPEC 2026-SH8",
    ]

    private func orbit(_ index: Int) throws -> CometOrbit {
        try XCTUnwrap(CometOrbit(mpcLine: lines[index]))
    }

    func testParsesDesignationsAndNames() throws {
        XCTAssertEqual(try orbit(0).designation, "10P")
        XCTAssertEqual(try orbit(0).name, "Tempel")
        XCTAssertEqual(try orbit(1).designation, "161P")
        XCTAssertEqual(try orbit(1).name, "Hartley-IRAS")
        XCTAssertEqual(try orbit(2).designation, "C/2026 A2")
        XCTAssertEqual(try orbit(2).name, "Bok")
    }

    func testPositionsMatchHorizons() throws {
        // (RA, Dec) from Horizons.
        let expected: [(Double, Double)] = [(341.46946, -33.91843), (355.85899, -7.88231), (268.71831, 69.24680)]
        for (index, (ra, dec)) in expected.enumerated() {
            let position = try orbit(index).position(at: when)
            let separation = SkyCoordinates.separation(position.coordinate,
                                                       EquatorialCoordinate(rightAscension: ra, declination: dec))
            XCTAssertLessThan(separation, 0.02, "comet \(index) is \(separation)° off")
        }
    }

    func testFaintCometsAreLeftOut() throws {
        // C/2026 A2 is predicted near magnitude 16 on this date.
        XCTAssertNil(try orbit(2).target(at: when))
        // 161P is predicted at about 13.8, inside the limit.
        let hartley = try XCTUnwrap(try orbit(1).target(at: when))
        XCTAssertEqual(hartley.type, .comet)
        XCTAssertEqual(hartley.displayName, "Comet Hartley-IRAS")
    }
}
