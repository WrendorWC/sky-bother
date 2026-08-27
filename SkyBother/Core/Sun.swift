import Foundation

/// Low-precision solar ephemeris (Meeus). Accurate to about 0.01 degrees over
/// the years this app cares about — several orders of magnitude better than the
/// precision twilight planning needs.
enum Sun {

    /// Apparent geocentric ecliptic longitude, degrees.
    static func eclipticLongitude(daysSinceJ2000 d: Double) -> Double {
        let meanLongitude = normalize360(280.460 + 0.9856474 * d)
        let meanAnomaly = normalize360(357.528 + 0.9856003 * d)
        return normalize360(meanLongitude
            + 1.915 * sinDeg(meanAnomaly)
            + 0.020 * sinDeg(2 * meanAnomaly))
    }

    static func meanLongitude(daysSinceJ2000 d: Double) -> Double {
        normalize360(280.460 + 0.9856474 * d)
    }

    static func position(daysSinceJ2000 d: Double) -> EquatorialCoordinate {
        SkyCoordinates.equatorial(eclipticLongitude: eclipticLongitude(daysSinceJ2000: d),
                                  eclipticLatitude: 0,
                                  obliquity: SkyCoordinates.obliquity(daysSinceJ2000: d))
    }

    static func altitude(daysSinceJ2000 d: Double, latitude: Double, longitude: Double) -> Double {
        SkyCoordinates.horizontal(position(daysSinceJ2000: d),
                                  daysSinceJ2000: d,
                                  latitude: latitude,
                                  longitude: longitude).altitude
    }

    /// Standard altitudes used for the twilight boundaries, in degrees.
    enum Event: String, CaseIterable, Identifiable, Sendable {
        case sunrise, sunset, civil, nautical, astronomical

        var id: String { rawValue }

        /// Sun altitude that defines the boundary.
        var altitude: Double {
            switch self {
            case .sunrise, .sunset: return -0.833   // upper limb + refraction
            case .civil: return -6
            case .nautical: return -12
            case .astronomical: return -18
            }
        }

        var duskLabel: String {
            switch self {
            case .sunrise, .sunset: return "Sunset"
            case .civil: return "Civil dusk"
            case .nautical: return "Nautical dusk"
            case .astronomical: return "Astronomical dark"
            }
        }

        var dawnLabel: String {
            switch self {
            case .sunrise, .sunset: return "Sunrise"
            case .civil: return "Civil dawn"
            case .nautical: return "Nautical dawn"
            case .astronomical: return "Dark ends"
            }
        }
    }
}
