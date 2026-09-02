import Foundation

/// An observing location. Bortle class is stored per-site because it is the one
/// number that most strongly decides which targets are worth attempting, and it
/// is the one number no API will reliably tell you.
struct Site: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var elevationMeters: Double
    var timeZoneIdentifier: String
    /// Bortle dark-sky class, 1 (pristine) to 9 (inner city).
    var bortleClass: Int
    /// Altitude in degrees below which your horizon is blocked by trees, houses
    /// or hills. Targets are only counted as observable above this.
    var horizonAltitude: Double

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    /// Typical zenith sky brightness in magnitudes per square arcsecond for the
    /// Bortle class. These are the widely used class midpoints.
    var zenithSkyBrightness: Double {
        switch bortleClass {
        case 1: return 21.9
        case 2: return 21.7
        case 3: return 21.4
        case 4: return 20.9
        case 5: return 20.3
        case 6: return 19.3
        case 7: return 18.6
        case 8: return 18.0
        default: return 17.5
        }
    }

    var bortleDescription: String { Site.bortleDescription(for: bortleClass) }

    static func bortleDescription(for bortleClass: Int) -> String {
        switch bortleClass {
        case 1: return "Excellent Dark Site"
        case 2: return "Truly Dark Site"
        case 3: return "Rural Sky"
        case 4: return "Rural/Suburban Transition"
        case 5: return "Suburban Sky"
        case 6: return "Bright Suburban Sky"
        case 7: return "Suburban/Urban Transition"
        case 8: return "City Sky"
        default: return "Inner-City Sky"
        }
    }

    var coordinateSummary: String {
        let latHemisphere = latitude >= 0 ? "N" : "S"
        let lonHemisphere = longitude >= 0 ? "E" : "W"
        return String(format: "%.3f°%@ %.3f°%@", abs(latitude), latHemisphere, abs(longitude), lonHemisphere)
    }

    /// Used only before the user has ever set a real site — see
    /// `StoredSettings.hasSetLocation`. Nothing should compute a plan against
    /// this; it exists so `Site` can stay non-optional in `StoredSettings`.
    static let unset = Site(name: "",
                            latitude: 0,
                            longitude: 0,
                            elevationMeters: 0,
                            timeZoneIdentifier: TimeZone.current.identifier,
                            bortleClass: 5,
                            horizonAltitude: 20)
}
