import XCTest

/// The night score should say clearly whether to go out: a night hazy just
/// over your cloud limit reads well below a clear one, and dew — which a dew
/// heater handles — costs only a little.
final class NightScoreTests: XCTestCase {
    private let site = Site(name: "Test", latitude: 28.2, longitude: -82.3, elevationMeters: 30,
                            timeZoneIdentifier: "America/New_York", bortleClass: 6,
                            horizonAltitude: 20, horizonProfile: nil)
    /// Near new Moon, so the Moon stays out of it.
    private let start = ISO8601DateFormatter().date(from: "2026-10-11T12:00:00Z")!

    private func skyScore(cloud: Double, dewSpread: Double, visibility: Double = 24000) -> Double {
        weightedGeometricScore(night(cloud: cloud, dewSpread: dewSpread, visibility: visibility).factors)
    }

    private func night(cloud: Double, dewSpread: Double, visibility: Double) -> NightPlan {
        var preferences = Preferences()
        preferences.maximumCloudCover = 20
        preferences.integrationGoalMinutes = 240
        let hours = (0..<48).map { hour in
            HourlyWeather(date: start.addingTimeInterval(Double(hour) * 3600),
                          cloudCoverTotal: cloud, cloudCoverLow: cloud, cloudCoverMid: 0, cloudCoverHigh: 0,
                          temperatureCelsius: 20, dewPointCelsius: 20 - dewSpread, relativeHumidity: 70,
                          windSpeedKilometersPerHour: 5, windGustsKilometersPerHour: 10,
                          visibilityMeters: visibility, precipitationProbability: 0)
        }
        let forecast = WeatherForecast(hours: hours, timeZoneIdentifier: site.timeZoneIdentifier,
                                       elevationMeters: 30, retrievedAt: start)
        let planner = Planner(site: site, rig: .seestarS50, preferences: preferences,
                              catalog: BuiltInCatalog.messier, forecast: forecast)
        return planner.plan(from: start)[0]
    }

    func testHazeJustOverTheLimitReadsWellBelowAClearNight() {
        let clear = skyScore(cloud: 5, dewSpread: 10)
        let hazy = skyScore(cloud: 26, dewSpread: 10)
        XCTAssertGreaterThanOrEqual(clear, 90)
        XCTAssertLessThan(hazy, 80)
        XCTAssertGreaterThan(clear - hazy, 15)
    }

    func testDewCostsOnlyALittle() {
        let dry = skyScore(cloud: 5, dewSpread: 10)
        let damp = skyScore(cloud: 5, dewSpread: 0)
        XCTAssertLessThan(dry - damp, 6)
        XCTAssertGreaterThan(dry - damp, 0)
    }

    func testFogSinksAClearNightAndSaysSo() {
        let foggy = night(cloud: 0, dewSpread: 0, visibility: 500)
        XCTAssertLessThan(weightedGeometricScore(foggy.factors), 30)
        XCTAssertTrue(foggy.isMostlyHaze)
        XCTAssertTrue(nightLimitationPhrase(for: foggy)?.contains("fog") ?? false)
    }

    func testGoodVisibilityChangesNothing() {
        let weather = HourlyWeather(date: start, cloudCoverTotal: 20, cloudCoverLow: 20, cloudCoverMid: 0,
                                    cloudCoverHigh: 0, temperatureCelsius: 20, dewPointCelsius: 15,
                                    relativeHumidity: 70, windSpeedKilometersPerHour: 5,
                                    windGustsKilometersPerHour: 10, visibilityMeters: 9000,
                                    precipitationProbability: 0)
        XCTAssertEqual(weather.hazeCover, 0)
        XCTAssertEqual(weather.skyCover, 20, accuracy: 1e-9)
        var haze = weather
        haze.visibilityMeters = 4500
        XCTAssertEqual(haze.hazeCover, 50, accuracy: 1e-9)
        XCTAssertEqual(haze.skyCover, 60, accuracy: 1e-9)
    }
}
