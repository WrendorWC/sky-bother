import Foundation

enum MountType: String, CaseIterable, Identifiable, Sendable {
    case altAzimuth  // smart telescopes, dobsonians — field rotates
    case equatorial  // tracked, guided or not — field doesn't rotate either way

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .altAzimuth: return "Alt-Azimuth"
        case .equatorial: return "Equatorial"
        }
    }

    var rotatesField: Bool { self == .altAzimuth }
}

extension MountType: Codable {
    /// Guided vs. unguided equatorial used to be two separate cases, kept
    /// distinct on the theory that guiding might someday matter to the
    /// score — it never ended up affecting anything (both only ever fed
    /// `rotatesField`, identically false for either), so the distinction
    /// was just a picker choice with no effect. Decoding both old raw
    /// values into the merged `.equatorial` case means a settings.json
    /// saved before this change still loads cleanly instead of failing to
    /// decode.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "altAzimuth": self = .altAzimuth
        case "equatorial", "equatorialTracked", "equatorialGuided": self = .equatorial
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath, debugDescription: "Unknown MountType raw value: \(raw)"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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

    /// 30mm f/5.3 telephoto unit, 160mm focal length, Sony IMX585 (2.9um,
    /// 2160 x 3840 portrait — same sensor and orientation as the S50 Pro's
    /// telephoto camera, just behind a shorter, smaller-aperture lens).
    static let seestarS30Pro = Rig(name: "ZWO Seestar S30 Pro",
                                   apertureMillimeters: 30, focalLengthMillimeters: 160,
                                   sensorWidthMillimeters: 6.26, sensorHeightMillimeters: 11.14,
                                   pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                                   hasNarrowbandFilter: true, supportsMosaic: true,
                                   zenithAvoidanceAltitude: 80)

    // The S50 Pro and S30 each also carry a second, wide-angle camera
    // alongside their main imaging optics — used on the device for
    // framing/context, and here for starscape/Milky Way planning, which
    // wants a much shorter focal length than either main camera offers.
    // ZWO doesn't publish detailed specs for these the way they do the
    // main optics, so these numbers are a best estimate rather than a
    // manufacturer figure — check them against your own unit.
    static let seestarS50ProWide = Rig(name: "ZWO Seestar S50 Pro (wide)",
                                       apertureMillimeters: 7, focalLengthMillimeters: 16,
                                       sensorWidthMillimeters: 5.6, sensorHeightMillimeters: 3.2,
                                       pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                                       hasNarrowbandFilter: false, supportsMosaic: false,
                                       zenithAvoidanceAltitude: 80)

    static let seestarS30Wide = Rig(name: "ZWO Seestar S30 (wide)",
                                    apertureMillimeters: 7, focalLengthMillimeters: 16,
                                    sensorWidthMillimeters: 5.6, sensorHeightMillimeters: 3.2,
                                    pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                                    hasNarrowbandFilter: false, supportsMosaic: false,
                                    zenithAvoidanceAltitude: 80)

    /// The S30 Pro's wide camera is a different sensor generation from the
    /// other Seestars' wide cameras (Sony IMX586, 0.8um native pixels, a
    /// 1/2" sensor — 8000 x 6000 native, physically 6.4 x 4.8mm) rather
    /// than a rescaled copy of the main camera's sensor. Aperture and focal
    /// ratio aren't published for this lens; the 6mm focal length is.
    static let seestarS30ProWide = Rig(name: "ZWO Seestar S30 Pro (wide)",
                                       apertureMillimeters: 7, focalLengthMillimeters: 6,
                                       sensorWidthMillimeters: 6.4, sensorHeightMillimeters: 4.8,
                                       pixelSizeMicrons: 0.8, mountType: .altAzimuth,
                                       hasNarrowbandFilter: false, supportsMosaic: false,
                                       zenithAvoidanceAltitude: 80)

    static let celestronOrigin = Rig(name: "Celestron Origin",
                                     apertureMillimeters: 152, focalLengthMillimeters: 335,
                                     sensorWidthMillimeters: 7.4, sensorHeightMillimeters: 5.0,
                                     pixelSizeMicrons: 2.4, mountType: .altAzimuth,
                                     hasNarrowbandFilter: false, supportsMosaic: false,
                                     zenithAvoidanceAltitude: 80)

    /// Same 6" f/2.2 RASA optical tube as the original Origin — the Mark II
    /// upgrade (announced March 2026) is a camera swap, Sony IMX178 to
    /// IMX678 (Starvis 2, 2.0um, 3840 x 2160), for better sampling and
    /// sensitivity.
    static let celestronOriginMarkII = Rig(name: "Celestron Origin Mark II",
                                           apertureMillimeters: 152, focalLengthMillimeters: 335,
                                           sensorWidthMillimeters: 7.68, sensorHeightMillimeters: 4.32,
                                           pixelSizeMicrons: 2.0, mountType: .altAzimuth,
                                           hasNarrowbandFilter: false, supportsMosaic: false,
                                           zenithAvoidanceAltitude: 80)

    static let unistellarEVscope2 = Rig(name: "Unistellar eVscope 2",
                                        apertureMillimeters: 114, focalLengthMillimeters: 450,
                                        sensorWidthMillimeters: 7.4, sensorHeightMillimeters: 4.2,
                                        pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                                        hasNarrowbandFilter: false, supportsMosaic: false,
                                        zenithAvoidanceAltitude: 80)

    /// Same 114mm f/4 optical tube as the eVscope 2, with a newer Sony
    /// IMX347 sensor (2.9um, 2520 x 2520 — square).
    static let unistellarEquinox2 = Rig(name: "Unistellar eQuinox 2",
                                        apertureMillimeters: 114, focalLengthMillimeters: 450,
                                        sensorWidthMillimeters: 7.31, sensorHeightMillimeters: 7.31,
                                        pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                                        hasNarrowbandFilter: false, supportsMosaic: false,
                                        zenithAvoidanceAltitude: 80)

    /// 85mm f/3.9 reflector, 320mm focal length. Unistellar publishes a
    /// 33.6 x 45 arcmin field of view rather than raw sensor dimensions —
    /// these are worked back from that (pixel size, 1.45um, is the one
    /// number they do publish directly). Odyssey and Odyssey Pro share
    /// identical optics; Pro only adds a Nikon-made electronic eyepiece,
    /// which doesn't change anything this app models.
    static let unistellarOdyssey = Rig(name: "Unistellar Odyssey",
                                       apertureMillimeters: 85, focalLengthMillimeters: 320,
                                       sensorWidthMillimeters: 4.19, sensorHeightMillimeters: 3.13,
                                       pixelSizeMicrons: 1.45, mountType: .altAzimuth,
                                       hasNarrowbandFilter: false, supportsMosaic: false,
                                       zenithAvoidanceAltitude: 80)

    /// 50mm f/5 quadruplet APO, Sony IMX585 (2.9um, 3840 x 2160). The
    /// sensor dimensions here were previously specified against the
    /// smaller IMX462 the original Vespera used — Vespera II actually
    /// ships with IMX585, which is physically larger (11.14 x 6.26mm, not
    /// 8.4 x 4.7mm), giving a noticeably wider real field of view.
    static let vesperaII = Rig(name: "Vaonis Vespera II",
                               apertureMillimeters: 50, focalLengthMillimeters: 250,
                               sensorWidthMillimeters: 11.14, sensorHeightMillimeters: 6.26,
                               pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                               hasNarrowbandFilter: false, supportsMosaic: true,
                               zenithAvoidanceAltitude: 80)

    /// 50mm f/4.9 quadruplet APO, same Sony IMX585 as the Vespera II but a
    /// shorter 245mm focal length. Currently sold alongside the Vespera II
    /// and Vespera Pro 2 as Vaonis's mid-tier model.
    static let vespera3 = Rig(name: "Vaonis Vespera 3",
                              apertureMillimeters: 50, focalLengthMillimeters: 245,
                              sensorWidthMillimeters: 11.14, sensorHeightMillimeters: 6.26,
                              pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                              hasNarrowbandFilter: false, supportsMosaic: true,
                              zenithAvoidanceAltitude: 80)

    /// 50mm f/4.9, Sony IMX676 (2.0um, 3536 x 3536 — square). Vaonis's
    /// current top-tier Vespera, highest resolution of the line.
    static let vesperaPro2 = Rig(name: "Vaonis Vespera Pro 2",
                                 apertureMillimeters: 50, focalLengthMillimeters: 245,
                                 sensorWidthMillimeters: 7.07, sensorHeightMillimeters: 7.07,
                                 pixelSizeMicrons: 2.0, mountType: .altAzimuth,
                                 hasNarrowbandFilter: false, supportsMosaic: true,
                                 zenithAvoidanceAltitude: 80)

    /// 80mm f/5 refractor-reflector (Nasmyth focus), Sony back-illuminated
    /// CMOS at 2.4um, 3096 x 2080. Vaonis's original flagship, before the
    /// Vespera line; still commonly owned even though Vaonis's own site
    /// now lists it only as a past product.
    static let stellina = Rig(name: "Vaonis Stellina",
                              apertureMillimeters: 80, focalLengthMillimeters: 400,
                              sensorWidthMillimeters: 7.43, sensorHeightMillimeters: 4.99,
                              pixelSizeMicrons: 2.4, mountType: .altAzimuth,
                              hasNarrowbandFilter: false, supportsMosaic: true,
                              zenithAvoidanceAltitude: 80)

    static let dwarf3 = Rig(name: "DwarfLab Dwarf 3",
                            apertureMillimeters: 35, focalLengthMillimeters: 150,
                            sensorWidthMillimeters: 7.7, sensorHeightMillimeters: 4.3,
                            pixelSizeMicrons: 2.0, mountType: .altAzimuth,
                            hasNarrowbandFilter: true, supportsMosaic: true,
                            zenithAvoidanceAltitude: 80)

    /// 24mm f/4.2 telephoto lens, Sony IMX415 (1.45um, 3840 x 2160).
    /// Replaced by the Dwarf 3 in late 2024 but still widely owned.
    static let dwarf2 = Rig(name: "DwarfLab Dwarf II",
                            apertureMillimeters: 24, focalLengthMillimeters: 100,
                            sensorWidthMillimeters: 5.57, sensorHeightMillimeters: 3.13,
                            pixelSizeMicrons: 1.45, mountType: .altAzimuth,
                            hasNarrowbandFilter: true, supportsMosaic: false,
                            zenithAvoidanceAltitude: 80)

    /// 30mm f/5, Sony IMX662 (2.9um, 1920 x 1080). DwarfLab's smallest and
    /// lightest model, at the same budget tier as the Seestar S30.
    static let dwarfMini = Rig(name: "DwarfLab Dwarf Mini",
                               apertureMillimeters: 30, focalLengthMillimeters: 150,
                               sensorWidthMillimeters: 5.57, sensorHeightMillimeters: 3.13,
                               pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                               hasNarrowbandFilter: true, supportsMosaic: false,
                               zenithAvoidanceAltitude: 80)

    static let cameraOnTracker = Rig(name: "Camera + 135mm lens on tracker",
                                     apertureMillimeters: 48, focalLengthMillimeters: 135,
                                     sensorWidthMillimeters: 23.5, sensorHeightMillimeters: 15.6,
                                     pixelSizeMicrons: 3.9, mountType: .equatorial,
                                     hasNarrowbandFilter: false, supportsMosaic: false,
                                     zenithAvoidanceAltitude: 90)

    // Wide-field starscape rigs — a Milky Way/landscape composition is just
    // a very short, very fast "telescope" in this model, so these need no
    // new equipment concept, only new numbers.
    static let apsc10mm = Rig(name: "APS-C + 10mm lens",
                              apertureMillimeters: 3.6, focalLengthMillimeters: 10,
                              sensorWidthMillimeters: 23.5, sensorHeightMillimeters: 15.6,
                              pixelSizeMicrons: 3.9, mountType: .equatorial,
                              hasNarrowbandFilter: false, supportsMosaic: false,
                              zenithAvoidanceAltitude: 90)

    static let apsc16mm = Rig(name: "APS-C + 16mm lens",
                              apertureMillimeters: 5.7, focalLengthMillimeters: 16,
                              sensorWidthMillimeters: 23.5, sensorHeightMillimeters: 15.6,
                              pixelSizeMicrons: 3.9, mountType: .equatorial,
                              hasNarrowbandFilter: false, supportsMosaic: false,
                              zenithAvoidanceAltitude: 90)

    static let fullFrame24mm = Rig(name: "Full-frame + 24mm lens",
                                   apertureMillimeters: 17.1, focalLengthMillimeters: 24,
                                   sensorWidthMillimeters: 36, sensorHeightMillimeters: 24,
                                   pixelSizeMicrons: 4.3, mountType: .equatorial,
                                   hasNarrowbandFilter: false, supportsMosaic: false,
                                   zenithAvoidanceAltitude: 90)

    static let refractor80 = Rig(name: "80mm refractor + APS-C",
                                 apertureMillimeters: 80, focalLengthMillimeters: 480,
                                 sensorWidthMillimeters: 23.5, sensorHeightMillimeters: 15.7,
                                 pixelSizeMicrons: 3.76, mountType: .equatorial,
                                 hasNarrowbandFilter: true, supportsMosaic: false,
                                 zenithAvoidanceAltitude: 90)

    static let sct8 = Rig(name: "8\" SCT + cooled mono",
                          apertureMillimeters: 203, focalLengthMillimeters: 1280,
                          sensorWidthMillimeters: 11.3, sensorHeightMillimeters: 11.3,
                          pixelSizeMicrons: 3.76, mountType: .equatorial,
                          hasNarrowbandFilter: true, supportsMosaic: false,
                          zenithAvoidanceAltitude: 90)

    /// Sorted by name rather than hand-ordered, so a preset added here
    /// later doesn't also need manually slotting into the right place —
    /// `localizedStandardCompare` is Finder's own "natural" ordering,
    /// which keeps "S30" before "S50" before "S30 Pro" reading the way a
    /// person actually expects instead of raw character-code order.
    static let presets: [Rig] = [
        seestarS50Pro, seestarS50, seestarS30, seestarS30Pro,
        celestronOrigin, celestronOriginMarkII,
        unistellarEVscope2, unistellarEquinox2, unistellarOdyssey,
        vesperaII, vespera3, vesperaPro2, stellina,
        dwarf3, dwarf2, dwarfMini,
        cameraOnTracker, refractor80, sct8,
        apsc10mm, apsc16mm, fullFrame24mm,
        seestarS50ProWide, seestarS30Wide, seestarS30ProWide
    ].sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}
