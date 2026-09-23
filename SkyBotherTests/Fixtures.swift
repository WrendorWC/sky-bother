import Foundation

extension TargetPlan {
    /// A target plan with just the parts a test cares about; everything else
    /// is a plausible constant.
    static func fixture(id: String, windows: [TimeWindow], score: Double = 70) -> TargetPlan {
        TargetPlan(target: Target(designation: id, commonName: nil, type: .galaxy,
                                  rightAscension: 10, declination: 41, magnitude: 8,
                                  majorAxisArcminutes: 20, minorAxisArcminutes: 10,
                                  constellation: "And"),
                   windows: windows,
                   usableMinutes: windows.totalMinutes,
                   maximumAltitude: 70, altitudeAtBest: 70, azimuthAtBest: 180,
                   bestTime: windows.first?.midpoint, transitTime: windows.first?.midpoint,
                   meanDarkness: 1, meanClear: 1, meanExtinction: 0,
                   minimumMoonSeparation: 90, maximumFieldRotation: 0,
                   zenithRiskWindows: [],
                   fit: RigFit(framingScore: 1, fillFraction: 0.5, mosaicPanels: 1,
                               framingNote: "Frames well", samplingNote: nil, notes: []),
                   detectability: 1, score: score, factors: [], warnings: [],
                   altitudeTrace: [])
    }
}

extension NightPlan {
    /// A night on UTC from 18:00 to 06:00, dark from 20:00 to 04:00 —
    /// enough shape for timing tests without running the planner.
    static func fixture(evening: Date, targets: [TargetPlan] = []) -> NightPlan {
        func at(_ hours: Double) -> Date { evening.addingTimeInterval(hours * 3600) }
        let dark = TimeWindow(start: at(2), end: at(10))
        return NightPlan(date: evening,
                         site: Site(name: "Test", latitude: 40, longitude: 0, elevationMeters: 0,
                                    timeZoneIdentifier: "UTC", bortleClass: 4,
                                    horizonAltitude: 0, horizonProfile: nil),
                         chartWindow: TimeWindow(start: at(0), end: at(12)),
                         sunset: at(0), sunrise: at(12),
                         civilDusk: at(0.5), civilDawn: at(11.5),
                         nauticalDusk: at(1.2), nauticalDawn: at(10.8),
                         astronomicalDusk: at(2), astronomicalDawn: at(10),
                         darkWindows: [dark], clearDarkWindows: [dark], moonlessDarkWindows: [dark],
                         isCloudedOut: false, samples: [],
                         moon: MoonSummary(illuminatedFraction: 0, phaseName: "New Moon", symbolName: "moon",
                                           isWaxing: true, upWindows: [], maximumAltitude: 0,
                                           minutesUpDuringDarkness: 0, interference: 0),
                         hasWeather: false, meanCloudDuringDark: 0, minimumTemperature: 10,
                         minimumDewSpread: 5, maximumGust: 5, score: 70, factors: [], targets: targets)
    }
}
