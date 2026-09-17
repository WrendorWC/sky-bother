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
    /// or hills, all the way round. Targets are only counted as observable
    /// above this — except where `horizonProfile` says one direction is worse.
    ///
    /// Kept as the all-round baseline even when a profile exists, where it is
    /// maintained as the profile's most open direction: everything that asks
    /// "how much sky does this site have?" in one number — the nearby-spot
    /// comparison, the cheap never-visible rejection in `Planner` — wants the
    /// best case, not an average that would wrongly write off a target that
    /// only ever clears the horizon to the north.
    var horizonAltitude: Double
    /// Per-direction blocked altitudes, one for each 45° compass sector
    /// starting at N and running clockwise (N, NE, E, SE, S, SW, W, NW).
    ///
    /// `nil` means a flat horizon at `horizonAltitude`, which is the common
    /// case and what every site starts as. It only becomes non-nil once you
    /// tell the app that one direction is worse than the rest — one big tree
    /// to the south, a house to the west — and each value is a hard floor for
    /// its own sector, exactly like `horizonAltitude` is for the whole sky.
    var horizonProfile: [Double]?

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    // MARK: - Horizon

    /// The compass sectors `horizonProfile` stores, in its own order.
    static let horizonDirections = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    /// `horizonProfile` only when it is actually usable. A settings file that
    /// somehow holds a profile of the wrong length is ignored in favour of the
    /// flat horizon rather than trusted and indexed into.
    private var usableHorizonProfile: [Double]? {
        guard let profile = horizonProfile, profile.count == Site.horizonDirections.count else { return nil }
        return profile
    }

    /// Every sector's blocked altitude, with a flat horizon expanded out to
    /// the same eight values — what the settings sliders and Sky View's rim
    /// both read, so neither has to care whether a profile exists yet.
    var horizonByDirection: [Double] {
        usableHorizonProfile ?? Array(repeating: horizonAltitude, count: Site.horizonDirections.count)
    }

    /// Whether any direction is blocked worse than the rest. False for a flat
    /// horizon, and false for a profile that happens to be level.
    var hasDirectionalHorizon: Bool {
        guard let profile = usableHorizonProfile, let first = profile.first else { return false }
        return profile.contains { $0 != first }
    }

    /// The most blocked direction — the tree.
    var worstHorizonAltitude: Double { horizonByDirection.max() ?? horizonAltitude }

    /// One number for how blocked this site is overall, averaged across all
    /// eight directions. This, not `horizonAltitude`, is what to compare
    /// against a nearby spot's own single all-round horizon figure: the
    /// most-open reading would quietly understate how much sky the tree costs
    /// and hide spots that really would be an improvement.
    var typicalHorizonAltitude: Double {
        let all = horizonByDirection
        return all.reduce(0, +) / Double(all.count)
    }

    /// How high your horizon is blocked looking a given way. Each of the eight
    /// values owns the 45° sector centred on its compass point, so "S is
    /// blocked to 55°" means the whole SSE-to-SSW wedge is, not just the one
    /// azimuth due south. A step rather than a smooth interpolation on
    /// purpose: it is what the eight sliders appear to promise, and a real
    /// tree line has edges.
    /// Which of the eight sectors an azimuth falls in.
    static func horizonDirectionIndex(azimuth: Double) -> Int {
        Int((normalize360(azimuth) / 45).rounded()) % horizonDirections.count
    }

    /// The compass name of the sector an azimuth falls in, e.g. "SW" — what a
    /// warning says when the tree is what cost you the time.
    static func horizonDirectionName(azimuth: Double) -> String {
        horizonDirections[horizonDirectionIndex(azimuth: azimuth)]
    }

    func blockedAltitude(azimuth: Double) -> Double {
        guard let profile = usableHorizonProfile else { return horizonAltitude }
        return profile[Site.horizonDirectionIndex(azimuth: azimuth)]
    }

    /// Flattens the horizon back to one altitude all the way round, dropping
    /// any per-direction detail. This is the "set them all at once" move the
    /// baseline slider makes, and the only way back to a flat horizon.
    mutating func setHorizonEverywhere(to altitude: Double) {
        horizonAltitude = altitude
        horizonProfile = nil
    }

    /// Raises or lowers one sector, materialising a profile from the current
    /// flat horizon if this is the first direction to differ.
    mutating func setHorizon(to altitude: Double, forDirectionAt index: Int) {
        var profile = horizonByDirection
        guard profile.indices.contains(index) else { return }
        profile[index] = altitude
        // `horizonAltitude` stays the most open direction: see its own note.
        horizonAltitude = profile.min() ?? altitude
        horizonProfile = profile.contains { $0 != horizonAltitude } ? profile : nil
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
                            horizonAltitude: 20,
                            horizonProfile: nil)
}
