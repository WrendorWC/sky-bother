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
