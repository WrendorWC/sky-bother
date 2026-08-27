import Foundation

struct MoonPosition: Sendable {
    var coordinate: EquatorialCoordinate
    var distanceKilometers: Double
    var eclipticLongitude: Double
    var eclipticLatitude: Double
}

/// Truncated ELP lunar theory. Position is good to a few arcminutes and phase
/// timing to roughly a quarter hour — validated against the 2026 solar and lunar
/// eclipses, which by definition occur at exact new and full moon.
enum Moon {

    static func position(daysSinceJ2000 d: Double) -> MoonPosition {
        let meanLongitude = normalize360(218.316 + 13.176396 * d)
        let meanAnomaly = normalize360(134.963 + 13.064993 * d)
        let argumentOfLatitude = normalize360(93.272 + 13.229350 * d)
        let meanElongation = normalize360(297.850 + 12.190749 * d)
        let sunMeanAnomaly = normalize360(357.529 + 0.98560028 * d)

        let longitude = meanLongitude
            + 6.289 * sinDeg(meanAnomaly)
            + 1.274 * sinDeg(2 * meanElongation - meanAnomaly)
            + 0.658 * sinDeg(2 * meanElongation)
            + 0.214 * sinDeg(2 * meanAnomaly)
            - 0.186 * sinDeg(sunMeanAnomaly)
            - 0.114 * sinDeg(2 * argumentOfLatitude)
            - 0.059 * sinDeg(2 * meanElongation - 2 * meanAnomaly)
            - 0.057 * sinDeg(2 * meanElongation - meanAnomaly - sunMeanAnomaly)

        let latitude = 5.128 * sinDeg(argumentOfLatitude)
            + 0.281 * sinDeg(meanAnomaly + argumentOfLatitude)
            - 0.278 * sinDeg(argumentOfLatitude - meanAnomaly)
            - 0.173 * sinDeg(2 * meanElongation - argumentOfLatitude)

        let distance = 385001.0
            - 20905.0 * cosDeg(meanAnomaly)
            - 3699.0 * cosDeg(2 * meanElongation - meanAnomaly)
            - 2956.0 * cosDeg(2 * meanElongation)
            - 570.0 * cosDeg(2 * meanAnomaly)

        let normalizedLongitude = normalize360(longitude)
        let coordinate = SkyCoordinates.equatorial(eclipticLongitude: normalizedLongitude,
                                                   eclipticLatitude: latitude,
                                                   obliquity: SkyCoordinates.obliquity(daysSinceJ2000: d))
        return MoonPosition(coordinate: coordinate,
                            distanceKilometers: distance,
                            eclipticLongitude: normalizedLongitude,
                            eclipticLatitude: latitude)
    }

    /// Geocentric elongation from the Sun, degrees. 0 at new moon, 180 at full.
    static func elongation(daysSinceJ2000 d: Double) -> Double {
        let sunLongitude = Sun.eclipticLongitude(daysSinceJ2000: d)
        let moon = position(daysSinceJ2000: d)
        return acosDeg(cosDeg(moon.eclipticLatitude) * cosDeg(moon.eclipticLongitude - sunLongitude))
    }

    /// Fraction of the lunar disc that is lit, 0...1.
    static func illuminatedFraction(daysSinceJ2000 d: Double) -> Double {
        (1 - cosDeg(elongation(daysSinceJ2000: d))) / 2
    }

    /// True when the moon is waxing, used to pick the right phase name and glyph.
    static func isWaxing(daysSinceJ2000 d: Double) -> Bool {
        let sunLongitude = Sun.eclipticLongitude(daysSinceJ2000: d)
        let moonLongitude = position(daysSinceJ2000: d).eclipticLongitude
        return normalize360(moonLongitude - sunLongitude) < 180
    }

    /// Phase names follow the usual convention: a "quarter" moon is half lit.
    static func phaseName(daysSinceJ2000 d: Double) -> String {
        let fraction = illuminatedFraction(daysSinceJ2000: d)
        let waxing = isWaxing(daysSinceJ2000: d)
        switch fraction {
        case ..<0.02: return "New moon"
        case ..<0.45: return waxing ? "Waxing crescent" : "Waning crescent"
        case ..<0.55: return waxing ? "First quarter" : "Last quarter"
        case ..<0.98: return waxing ? "Waxing gibbous" : "Waning gibbous"
        default: return "Full moon"
        }
    }

    /// SF Symbol name that matches the current phase.
    static func symbolName(daysSinceJ2000 d: Double) -> String {
        let fraction = illuminatedFraction(daysSinceJ2000: d)
        let waxing = isWaxing(daysSinceJ2000: d)
        switch fraction {
        case ..<0.04: return "moonphase.new.moon"
        case ..<0.45: return waxing ? "moonphase.waxing.crescent" : "moonphase.waning.crescent"
        case ..<0.55: return waxing ? "moonphase.first.quarter" : "moonphase.last.quarter"
        case ..<0.96: return waxing ? "moonphase.waxing.gibbous" : "moonphase.waning.gibbous"
        default: return "moonphase.full.moon"
        }
    }

    static func altitude(daysSinceJ2000 d: Double, latitude: Double, longitude: Double) -> Double {
        SkyCoordinates.horizontal(position(daysSinceJ2000: d).coordinate,
                                  daysSinceJ2000: d,
                                  latitude: latitude,
                                  longitude: longitude).altitude
    }

    /// Standard altitude for moonrise/moonset: horizontal parallax (~0.95 deg)
    /// less refraction (~0.57) less semidiameter (~0.25).
    static let riseSetAltitude: Double = 0.125
}
