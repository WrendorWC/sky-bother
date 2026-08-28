import Foundation

enum MountType: String, Codable, CaseIterable, Identifiable, Sendable {
    case altAzimuth        // smart telescopes, dobsonians — field rotates
    case equatorialTracked // tracked but unguided
    case equatorialGuided  // autoguided

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .altAzimuth: return "Alt-azimuth"
        case .equatorialTracked: return "Equatorial, unguided"
        case .equatorialGuided: return "Equatorial, guided"
        }
    }

    var rotatesField: Bool { self == .altAzimuth }
}

/// Everything about the imaging train that changes what is worth pointing at.
struct Rig: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var apertureMillimeters: Double
    var focalLengthMillimeters: Double
    var sensorWidthMillimeters: Double
    var sensorHeightMillimeters: Double
    var pixelSizeMicrons: Double
    var mountType: MountType
    /// A dual/tri-band filter transforms what a moonlit or light-polluted sky can
    /// still deliver on emission targets. Most smart telescopes ship with one.
    var hasNarrowbandFilter: Bool
    /// Whether the rig can automatically frame a target larger than one field.
    var supportsMosaic: Bool
    /// Alt-az mounts rotate the field fastest overhead; many smart telescopes
    /// also mechanically struggle near the zenith. Targets above this altitude
    /// are penalised. Set to 90 to disable.
    var zenithAvoidanceAltitude: Double

    var focalRatio: Double {
        apertureMillimeters > 0 ? focalLengthMillimeters / apertureMillimeters : 0
    }

    /// Field of view in degrees.
    var fieldOfViewWidthDegrees: Double {
        guard focalLengthMillimeters > 0 else { return 0 }
        return 2 * atan(sensorWidthMillimeters / (2 * focalLengthMillimeters)) * radiansToDegrees
    }

    var fieldOfViewHeightDegrees: Double {
        guard focalLengthMillimeters > 0 else { return 0 }
        return 2 * atan(sensorHeightMillimeters / (2 * focalLengthMillimeters)) * radiansToDegrees
    }

    var fieldOfViewWidthArcminutes: Double { fieldOfViewWidthDegrees * 60 }
    var fieldOfViewHeightArcminutes: Double { fieldOfViewHeightDegrees * 60 }

    /// The short side of the frame — the dimension a target has to fit inside.
    var fieldOfViewShortArcminutes: Double {
        min(fieldOfViewWidthArcminutes, fieldOfViewHeightArcminutes)
    }

    var fieldOfViewLongArcminutes: Double {
        max(fieldOfViewWidthArcminutes, fieldOfViewHeightArcminutes)
    }

    /// Arcseconds per pixel. Below ~1 is oversampled for most seeing; above ~3
    /// undersamples small targets like galaxies and planetary nebulae.
    var arcsecondsPerPixel: Double {
        guard focalLengthMillimeters > 0 else { return 0 }
        return 206.265 * pixelSizeMicrons / focalLengthMillimeters
    }

    var fieldOfViewSummary: String {
        String(format: "%.2f° × %.2f°", fieldOfViewWidthDegrees, fieldOfViewHeightDegrees)
    }

    var opticalSummary: String {
        String(format: "%.0fmm f/%.1f · %.0fmm FL · %.2f\"/px",
               apertureMillimeters, focalRatio, focalLengthMillimeters, arcsecondsPerPixel)
    }

    /// True when two rigs describe the same instrument, ignoring id and name.
    /// Used to tell a genuinely custom rig apart from a copy of a built-in one.
    func hasSameSpecs(as other: Rig) -> Bool {
        apertureMillimeters == other.apertureMillimeters
            && focalLengthMillimeters == other.focalLengthMillimeters
            && sensorWidthMillimeters == other.sensorWidthMillimeters
            && sensorHeightMillimeters == other.sensorHeightMillimeters
            && pixelSizeMicrons == other.pixelSizeMicrons
            && mountType == other.mountType
            && hasNarrowbandFilter == other.hasNarrowbandFilter
            && supportsMosaic == other.supportsMosaic
    }

    /// True when this is just one of the shipped presets under another name.
    var matchesABuiltInPreset: Bool {
        Rig.presets.contains { $0.hasSameSpecs(as: self) && $0.name == name }
    }

    // MARK: - Presets
    //
    // Manufacturer figures for the optics; sensor dimensions are the standard
    // sizes for the sensor each model uses. Check them against your own unit and
    // edit in Settings if anything differs — every number here is editable.

    static let seestarS50 = Rig(name: "ZWO Seestar S50",
                                apertureMillimeters: 50, focalLengthMillimeters: 250,
                                sensorWidthMillimeters: 5.6, sensorHeightMillimeters: 3.2,
                                pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                                hasNarrowbandFilter: true, supportsMosaic: true,
                                zenithAvoidanceAltitude: 80)

    /// 50mm f/5.2 four-element APO, 1/1.2" 4K sensor. ZWO quote the telephoto
    /// resolution as 2160 x 3840 portrait, so the frame is taller than it is
    /// wide: 2160 and 3840 pixels at 2.9um give 6.26 x 11.14mm. That geometry
    /// computes to a 2.816-degree diagonal, matching the published 2.8 degrees.
    /// Dual-band filter is OIII 30nm / Ha 20nm, telephoto only.
    static let seestarS50Pro = Rig(name: "ZWO Seestar S50 Pro",
                                   apertureMillimeters: 50, focalLengthMillimeters: 260,
                                   sensorWidthMillimeters: 6.26, sensorHeightMillimeters: 11.14,
                                   pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                                   hasNarrowbandFilter: true, supportsMosaic: true,
                                   zenithAvoidanceAltitude: 80)

    static let seestarS30 = Rig(name: "ZWO Seestar S30",
                                apertureMillimeters: 30, focalLengthMillimeters: 150,
                                sensorWidthMillimeters: 5.6, sensorHeightMillimeters: 3.2,
                                pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                                hasNarrowbandFilter: true, supportsMosaic: true,
                                zenithAvoidanceAltitude: 80)

    static let celestronOrigin = Rig(name: "Celestron Origin",
                                     apertureMillimeters: 152, focalLengthMillimeters: 335,
                                     sensorWidthMillimeters: 7.4, sensorHeightMillimeters: 5.0,
                                     pixelSizeMicrons: 2.4, mountType: .altAzimuth,
                                     hasNarrowbandFilter: false, supportsMosaic: false,
                                     zenithAvoidanceAltitude: 80)

    static let unistellarEVscope2 = Rig(name: "Unistellar eVscope 2",
                                        apertureMillimeters: 114, focalLengthMillimeters: 450,
                                        sensorWidthMillimeters: 7.4, sensorHeightMillimeters: 4.2,
                                        pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                                        hasNarrowbandFilter: false, supportsMosaic: false,
                                        zenithAvoidanceAltitude: 80)

    static let vesperaII = Rig(name: "Vaonis Vespera II",
                               apertureMillimeters: 50, focalLengthMillimeters: 250,
                               sensorWidthMillimeters: 8.4, sensorHeightMillimeters: 4.7,
                               pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                               hasNarrowbandFilter: false, supportsMosaic: true,
                               zenithAvoidanceAltitude: 80)

    static let dwarf3 = Rig(name: "DwarfLab Dwarf 3",
                            apertureMillimeters: 35, focalLengthMillimeters: 150,
                            sensorWidthMillimeters: 7.7, sensorHeightMillimeters: 4.3,
                            pixelSizeMicrons: 2.0, mountType: .altAzimuth,
                            hasNarrowbandFilter: true, supportsMosaic: true,
                            zenithAvoidanceAltitude: 80)

    static let cameraOnTracker = Rig(name: "Camera + 135mm lens on tracker",
                                     apertureMillimeters: 48, focalLengthMillimeters: 135,
                                     sensorWidthMillimeters: 23.5, sensorHeightMillimeters: 15.6,
                                     pixelSizeMicrons: 3.9, mountType: .equatorialTracked,
                                     hasNarrowbandFilter: false, supportsMosaic: false,
                                     zenithAvoidanceAltitude: 90)

    static let refractor80 = Rig(name: "80mm refractor + APS-C",
                                 apertureMillimeters: 80, focalLengthMillimeters: 480,
                                 sensorWidthMillimeters: 23.5, sensorHeightMillimeters: 15.7,
                                 pixelSizeMicrons: 3.76, mountType: .equatorialGuided,
                                 hasNarrowbandFilter: true, supportsMosaic: false,
                                 zenithAvoidanceAltitude: 90)

    static let sct8 = Rig(name: "8\" SCT + cooled mono",
                          apertureMillimeters: 203, focalLengthMillimeters: 1280,
                          sensorWidthMillimeters: 11.3, sensorHeightMillimeters: 11.3,
                          pixelSizeMicrons: 3.76, mountType: .equatorialGuided,
                          hasNarrowbandFilter: true, supportsMosaic: false,
                          zenithAvoidanceAltitude: 90)

    static let presets: [Rig] = [seestarS50Pro, seestarS50, seestarS30, celestronOrigin, unistellarEVscope2,
                                 vesperaII, dwarf3, cameraOnTracker, refractor80, sct8]
}
