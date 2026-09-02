import Foundation

/// Right ascension / declination, both in degrees, epoch J2000.
struct EquatorialCoordinate: Codable, Hashable, Sendable {
    var rightAscension: Double
    var declination: Double

    init(rightAscension: Double, declination: Double) {
        self.rightAscension = rightAscension
        self.declination = declination
    }

    /// Convenience initialiser taking sexagesimal RA (h/m) and Dec (deg/arcmin).
    /// Declination minutes are always given as a positive magnitude; the sign of
    /// `degrees` sets the hemisphere (so -00 49 is written as (-0, 49)).
    init(raHours: Double, raMinutes: Double, decDegrees: Double, decMinutes: Double, decNegative: Bool = false) {
        self.rightAscension = (raHours + raMinutes / 60.0) * 15.0
        let magnitude = abs(decDegrees) + decMinutes / 60.0
        let isNegative = decNegative || decDegrees < 0
        self.declination = isNegative ? -magnitude : magnitude
    }
}

/// Altitude above the horizon and azimuth measured east from north, in degrees.
struct HorizontalCoordinate: Hashable, Sendable {
    var altitude: Double
    var azimuth: Double

    /// Compass point for the azimuth, e.g. "SE".
    var compassPoint: String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((normalize360(azimuth) / 22.5).rounded()) % 16
        return points[index]
    }

    /// Great-circle separation from another point in the sky, in degrees —
    /// the same spherical law of cosines `SkyCoordinates.separation` uses
    /// for equatorial coordinates, just with altitude/azimuth standing in
    /// for declination/right ascension.
    func separation(to other: HorizontalCoordinate) -> Double {
        let cosSep = sinDeg(altitude) * sinDeg(other.altitude)
            + cosDeg(altitude) * cosDeg(other.altitude) * cosDeg(azimuth - other.azimuth)
        return acosDeg(cosSep)
    }
}

enum SkyCoordinates {

    /// Mean obliquity of the ecliptic, degrees.
    static func obliquity(daysSinceJ2000 d: Double) -> Double {
        23.439291 - 3.563e-7 * d
    }

    /// Greenwich mean sidereal time in degrees.
    static func greenwichMeanSiderealTime(daysSinceJ2000 d: Double) -> Double {
        normalize360(280.46061837 + 360.98564736629 * d)
    }

    /// Local mean sidereal time in degrees. Longitude is east-positive.
    static func localSiderealTime(daysSinceJ2000 d: Double, longitude: Double) -> Double {
        normalize360(greenwichMeanSiderealTime(daysSinceJ2000: d) + longitude)
    }

    /// Converts ecliptic longitude/latitude to equatorial coordinates.
    static func equatorial(eclipticLongitude lambda: Double,
                           eclipticLatitude beta: Double,
                           obliquity eps: Double) -> EquatorialCoordinate {
        let ra = atan2Deg(sinDeg(lambda) * cosDeg(eps) - tanDeg(beta) * sinDeg(eps), cosDeg(lambda))
        let dec = asinDeg(sinDeg(beta) * cosDeg(eps) + cosDeg(beta) * sinDeg(eps) * sinDeg(lambda))
        return EquatorialCoordinate(rightAscension: normalize360(ra), declination: dec)
    }

    /// Converts equatorial coordinates to the observer's horizon frame.
    /// Returns *geometric* altitude — apply `refractedAltitude` for the apparent value.
    static func horizontal(_ coordinate: EquatorialCoordinate,
                           daysSinceJ2000 d: Double,
                           latitude: Double,
                           longitude: Double) -> HorizontalCoordinate {
        let lst = localSiderealTime(daysSinceJ2000: d, longitude: longitude)
        let hourAngle = normalize360(lst - coordinate.rightAscension)
        let dec = coordinate.declination

        let sinAlt = sinDeg(latitude) * sinDeg(dec)
            + cosDeg(latitude) * cosDeg(dec) * cosDeg(hourAngle)
        let altitude = asinDeg(sinAlt)

        let azimuth = atan2Deg(-cosDeg(dec) * sinDeg(hourAngle),
                               sinDeg(dec) * cosDeg(latitude) - cosDeg(dec) * sinDeg(latitude) * cosDeg(hourAngle))
        return HorizontalCoordinate(altitude: altitude, azimuth: normalize360(azimuth))
    }

    /// Hour angle at which an object reaches `altitude`, in degrees, or nil if it
    /// never does (circumpolar above, or never rises).
    static func hourAngleAtAltitude(_ altitude: Double, declination: Double, latitude: Double) -> Double? {
        let numerator = sinDeg(altitude) - sinDeg(latitude) * sinDeg(declination)
        let denominator = cosDeg(latitude) * cosDeg(declination)
        guard abs(denominator) > 1e-9 else { return nil }
        let cosH = numerator / denominator
        guard cosH >= -1, cosH <= 1 else { return nil }
        return acosDeg(cosH)
    }

    /// Bennett's refraction formula. Input and output in degrees.
    static func refractedAltitude(_ trueAltitude: Double) -> Double {
        guard trueAltitude > -2 else { return trueAltitude }
        let r = 1.02 / tanDeg(trueAltitude + 10.3 / (trueAltitude + 5.11)) / 60.0
        return trueAltitude + r
    }

    /// Kasten & Young (1989) relative air mass. Returns a large value near and
    /// below the horizon so callers can treat it as "unusable" without branching.
    static func airMass(altitude: Double) -> Double {
        guard altitude > 0.5 else { return 40 }
        let denominator = sinDeg(altitude) + 0.50572 * pow(altitude + 6.07995, -1.6364)
        return min(40, 1.0 / denominator)
    }

    /// Great-circle separation between two equatorial positions, in degrees.
    static func separation(_ a: EquatorialCoordinate, _ b: EquatorialCoordinate) -> Double {
        let cosSep = sinDeg(a.declination) * sinDeg(b.declination)
            + cosDeg(a.declination) * cosDeg(b.declination) * cosDeg(a.rightAscension - b.rightAscension)
        return acosDeg(cosSep)
    }

    /// Field rotation rate in degrees per hour for an alt-azimuth mount.
    /// This is what limits sub-exposure length on a smart telescope.
    static func fieldRotationRate(altitude: Double, azimuth: Double, latitude: Double) -> Double {
        guard altitude > 1 else { return 0 }
        return abs(15.041 * cosDeg(latitude) * cosDeg(azimuth) / cosDeg(altitude))
    }
}
