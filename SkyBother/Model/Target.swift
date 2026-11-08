import Foundation

enum TargetType: String, Codable, CaseIterable, Identifiable, Sendable {
    case emissionNebula
    case reflectionNebula
    case planetaryNebula
    case supernovaRemnant
    case galaxy
    case galaxyGroup
    case globularCluster
    case openCluster
    case starCloud
    case asterism
    case star
    case comet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .emissionNebula: return "Emission Nebula"
        case .reflectionNebula: return "Reflection Nebula"
        case .planetaryNebula: return "Planetary Nebula"
        case .supernovaRemnant: return "Supernova Remnant"
        case .galaxy: return "Galaxy"
        case .galaxyGroup: return "Galaxy Group"
        case .globularCluster: return "Globular Cluster"
        case .openCluster: return "Open Cluster"
        case .starCloud: return "Star Cloud"
        case .asterism: return "Asterism"
        case .star: return "Star"
        case .comet: return "Comet"
        }
    }

    /// How the type reads in the filter menus. Comets say "Visible" because
    /// only the few bright enough to image are listed, not every comet.
    var filterName: String {
        self == .comet ? "Visible Comets" : displayName
    }

    /// The filter menus' order: alphabetical by what they show.
    static var filterOrder: [TargetType] {
        allCases.sorted { $0.filterName.localizedCompare($1.filterName) == .orderedAscending }
    }

    var shortName: String {
        switch self {
        case .emissionNebula: return "Emission"
        case .reflectionNebula: return "Reflection"
        case .planetaryNebula: return "Planetary"
        case .supernovaRemnant: return "Remnant"
        case .galaxy: return "Galaxy"
        case .galaxyGroup: return "Group"
        case .globularCluster: return "Globular"
        case .openCluster: return "Open Cluster"
        case .starCloud: return "Star Cloud"
        case .asterism: return "Asterism"
        case .star: return "Star"
        case .comet: return "Comet"
        }
    }

    var symbolName: String {
        switch self {
        case .emissionNebula, .reflectionNebula: return "cloud.fill"
        case .planetaryNebula: return "circle.dotted"
        case .supernovaRemnant: return "burst.fill"
        case .galaxy, .galaxyGroup: return "hurricane"
        case .globularCluster: return "circle.hexagongrid.fill"
        case .openCluster, .asterism: return "sparkles"
        case .starCloud: return "sparkle"
        case .star: return "star.fill"
        case .comet: return "smoke.fill"
        }
    }

    /// Targets that emit most of their light in narrow lines, so a dual-band
    /// filter cuts moonlight and light pollution without cutting the signal.
    var respondsToNarrowband: Bool {
        switch self {
        case .emissionNebula, .planetaryNebula, .supernovaRemnant: return true
        default: return false
        }
    }

    /// A single bright star, or a double. Planned and scored like anything
    /// else, but on its own terms — see `Planner.targetFactors` — and never
    /// the night's best target or part of a suggested plan: a bright star is
    /// there for a moonlit night or a spare half hour, not to decide whether
    /// a night is worth going out for.
    var isStar: Bool { self == .star }

    /// Star fields are collections of point sources; their catalogued magnitude
    /// is an integrated value and the surface-brightness model does not apply.
    var isStarField: Bool {
        switch self {
        case .openCluster, .globularCluster, .asterism, .starCloud: return true
        default: return false
        }
    }
}

struct Target: Codable, Hashable, Identifiable, Sendable {
    var designation: String
    var commonName: String?
    var type: TargetType
    var rightAscension: Double   // degrees, J2000
    var declination: Double      // degrees, J2000
    var magnitude: Double        // integrated visual magnitude
    var majorAxisArcminutes: Double
    var minorAxisArcminutes: Double
    var constellation: String
    /// For the rare target whose catalogued magnitude says nothing about how it
    /// images. See `surfaceBrightness`.
    var surfaceBrightnessOverride: Double? = nil

    var id: String { designation }

    var coordinate: EquatorialCoordinate {
        EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
    }

    var displayName: String {
        if let commonName, !commonName.isEmpty { return commonName }
        return designation
    }

    /// "Andromeda Galaxy (M31)" or just "M108" when there is no common name.
    var fullName: String {
        if let commonName, !commonName.isEmpty { return "\(commonName) (\(designation))" }
        return designation
    }

    /// "Andromeda", not the stored "And" — the catalogue keeps the IAU
    /// three-letter abbreviation, which is the right thing to store but the
    /// wrong thing to show someone.
    var constellationName: String { Constellation.fullName(for: constellation) }

    /// " in Cygnus", or nothing for a comet, which moves between
    /// constellations and isn't placed in one.
    var inConstellation: String { constellation.isEmpty ? "" : " in \(constellationName)" }

    var sizeSummary: String {
        if abs(majorAxisArcminutes - minorAxisArcminutes) < 0.05 {
            return String(format: "%g′", majorAxisArcminutes)
        }
        return String(format: "%g′ × %g′", majorAxisArcminutes, minorAxisArcminutes)
    }

    /// Mean surface brightness in magnitudes per square arcsecond, derived from
    /// the integrated magnitude spread over the catalogued ellipse. Meaningless
    /// for star fields, which is why callers check `type.isStarField` first.
    ///
    /// A few emission targets carry a visual magnitude that badly misstates
    /// them, since their light is almost all hydrogen-alpha, outside the V band.
    /// The Jellyfish Nebula is listed at 12.0, which spread over its 50′ × 40′
    /// came to 28.9 mag/arcsec²: three magnitudes fainter than anything else in
    /// the catalogue, and scored as hopeless, when a Seestar with a dual-band
    /// filter pulls it in well from a Bortle 6 suburb. The Flame Nebula, at 10.0,
    /// came to 26.0 though it outshines the Horsehead beside it. Those take an
    /// override, set from how they actually image.
    var surfaceBrightness: Double {
        if let surfaceBrightnessOverride { return surfaceBrightnessOverride }
        let areaArcminutes = (Double.pi / 4) * max(0.01, majorAxisArcminutes) * max(0.01, minorAxisArcminutes)
        let areaArcseconds = areaArcminutes * 3600
        return magnitude + 2.5 * log10(areaArcseconds)
    }

    /// Highest altitude this target can ever reach from a given latitude.
    func maximumPossibleAltitude(latitude: Double) -> Double {
        90 - abs(latitude - declination)
    }

    func isEverVisible(latitude: Double, aboveAltitude: Double) -> Bool {
        maximumPossibleAltitude(latitude: latitude) > aboveAltitude
    }

    /// Searchable text for the filter field.
    var searchText: String {
        [designation, commonName ?? "", constellation, constellationName, type.displayName]
            .joined(separator: " ")
            .lowercased()
    }
}
