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
        }
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

    var sizeSummary: String {
        if abs(majorAxisArcminutes - minorAxisArcminutes) < 0.05 {
            return String(format: "%g′", majorAxisArcminutes)
        }
        return String(format: "%g′ × %g′", majorAxisArcminutes, minorAxisArcminutes)
    }

    /// Mean surface brightness in magnitudes per square arcsecond, derived from
    /// the integrated magnitude spread over the catalogued ellipse. Meaningless
    /// for star fields, which is why callers check `type.isStarField` first.
    var surfaceBrightness: Double {
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
