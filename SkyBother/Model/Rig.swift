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

    /// 50mm f/5, Sony IMX462 (2.9um). ZWO give 1080 x 1920 and a 0.73 x
    /// 1.29 degree field: portrait, like every Seestar's main camera.
    static let seestarS50 = Rig(name: "ZWO Seestar S50",
                                apertureMillimeters: 50, focalLengthMillimeters: 250,
                                sensorWidthMillimeters: 3.13, sensorHeightMillimeters: 5.57,
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

    /// 30mm f/5, Sony IMX662 (2.9um, 1080 x 1920 portrait), 2.46 degrees
    /// across the diagonal.
    static let seestarS30 = Rig(name: "ZWO Seestar S30",
                                apertureMillimeters: 30, focalLengthMillimeters: 150,
                                sensorWidthMillimeters: 3.13, sensorHeightMillimeters: 5.57,
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

    // The wide-angle cameras beside the main optics, for starscape and
    // Milky Way planning. The S50 Pro and S30 Pro share one module, and ZWO
    // publish it: 6mm f/1.75 (3.4mm aperture), Sony IMX586 1/2", 1.6um
    // binned pixels, 2160 x 3840 portrait, 63 degrees. The chip's full
    // 6.4mm width at 16:9 is 6.4 x 3.6mm, which on a 6mm lens gives exactly
    // that 63 degree diagonal (33 x 56 degrees).
    static let seestarS50ProWide = Rig(name: "ZWO Seestar S50 Pro (wide)",
                                       apertureMillimeters: 3.4, focalLengthMillimeters: 6,
                                       sensorWidthMillimeters: 3.6, sensorHeightMillimeters: 6.4,
                                       pixelSizeMicrons: 1.6, mountType: .altAzimuth,
                                       hasNarrowbandFilter: false, supportsMosaic: false,
                                       zenithAvoidanceAltitude: 80)

    /// The plain S30's wide camera is its own, narrower one. ZWO give only
    /// its field, 23.2 degrees; the lens here is set to match that across
    /// the diagonal, on an estimated sensor.
    static let seestarS30Wide = Rig(name: "ZWO Seestar S30 (wide)",
                                    apertureMillimeters: 7, focalLengthMillimeters: 15.7,
                                    sensorWidthMillimeters: 5.6, sensorHeightMillimeters: 3.2,
                                    pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                                    hasNarrowbandFilter: false, supportsMosaic: false,
                                    zenithAvoidanceAltitude: 80)

    /// The same wide module as the S50 Pro's.
    static let seestarS30ProWide = Rig(name: "ZWO Seestar S30 Pro (wide)",
                                       apertureMillimeters: 3.4, focalLengthMillimeters: 6,
                                       sensorWidthMillimeters: 3.6, sensorHeightMillimeters: 6.4,
                                       pixelSizeMicrons: 1.6, mountType: .altAzimuth,
                                       hasNarrowbandFilter: false, supportsMosaic: false,
                                       zenithAvoidanceAltitude: 80)

    /// Presets whose figures were wrong when they shipped, with those old
    /// optics. A rig picked from one keeps a copy of its numbers, so it
    /// would never see the fix; one still carrying exactly the old numbers
    /// is brought up to date, and one you've edited is left alone.
    private static let correctedPresets: [(old: [Double], preset: Rig)] = [
        ([7, 16, 5.6, 3.2, 2.9], seestarS50ProWide),
        ([7, 16, 5.6, 3.2, 2.9], seestarS30Wide),
        ([7, 6, 6.4, 4.8, 0.8], seestarS30ProWide),
        ([50, 250, 5.6, 3.2, 2.9], seestarS50),
        ([30, 150, 5.6, 3.2, 2.9], seestarS30),
        ([114, 450, 7.4, 4.2, 2.9], unistellarEVscope2),
        ([114, 450, 7.31, 7.31, 2.9], unistellarEquinox2),
    ]

    /// This rig, or the corrected preset it was picked from.
    func updatingCorrectedPreset() -> Rig {
        let optics = [apertureMillimeters, focalLengthMillimeters, sensorWidthMillimeters,
                      sensorHeightMillimeters, pixelSizeMicrons]
        guard let fix = Self.correctedPresets.first(where: { $0.preset.name == name && $0.old == optics }) else {
            return self
        }
        var updated = fix.preset
        updated.id = id
        updated.mountType = mountType
        updated.zenithAvoidanceAltitude = zenithAvoidanceAltitude
        return updated
    }

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

    /// 114mm f/4, Sony IMX347 (2.9um). Unistellar quote a 47 x 34
    /// arcminute field, the part of the chip it uses: 6.15 x 4.45mm at 450mm.
    static let unistellarEVscope2 = Rig(name: "Unistellar eVscope 2",
                                        apertureMillimeters: 114, focalLengthMillimeters: 450,
                                        sensorWidthMillimeters: 6.15, sensorHeightMillimeters: 4.45,
                                        pixelSizeMicrons: 2.9, mountType: .altAzimuth,
                                        hasNarrowbandFilter: false, supportsMosaic: false,
                                        zenithAvoidanceAltitude: 80)

    /// Same 114mm f/4 tube and IMX347 as the eVscope 2, and the same quoted
    /// 47 x 34 arcminute field.
    static let unistellarEquinox2 = Rig(name: "Unistellar eQuinox 2",
                                        apertureMillimeters: 114, focalLengthMillimeters: 450,
                                        sensorWidthMillimeters: 6.15, sensorHeightMillimeters: 4.45,
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

    /// 90mm f/3.8 (340mm) folded optics, OmniVision OV50Q40 1/1.3" 50MP
    /// sensor. Deep-sky frames are 2x2 binned: 4096 x 3072 at 2.394um, which
    /// is 9.81 x 7.35mm. That computes to a 2.06-degree diagonal, matching the
    /// published figure. Alt-az with physical sensor rotation; Ha/OIII
    /// dual-band filter in both editions; mosaics up to 1.8x each way.
    /// Launched September 2026.
    static let dwarfDraco = Rig(name: "DwarfLab Dwarf Draco",
                                apertureMillimeters: 90, focalLengthMillimeters: 340,
                                sensorWidthMillimeters: 9.81, sensorHeightMillimeters: 7.35,
                                pixelSizeMicrons: 2.394, mountType: .altAzimuth,
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
        dwarfDraco, dwarf3, dwarf2, dwarfMini,
        cameraOnTracker, refractor80, sct8,
        apsc10mm, apsc16mm, fullFrame24mm,
        seestarS50ProWide, seestarS30Wide, seestarS30ProWide
    ].sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

extension Rig {
    /// How presets are grouped for choosing: one-box smart telescopes, and
    /// everything built from a separate camera and lens or telescope.
    enum PresetGroup: String, CaseIterable, Identifiable {
        case smartTelescope = "Smart telescopes"
        case cameraAndOptics = "Cameras, lenses and telescopes"
        var id: String { rawValue }
    }

    var presetGroup: PresetGroup {
        let smartMakers = ["ZWO Seestar", "Celestron Origin", "Unistellar", "Vaonis", "DwarfLab"]
        return smartMakers.contains { name.hasPrefix($0) } ? .smartTelescope : .cameraAndOptics
    }

    /// What's wrong with these numbers, in plain words — empty when they
    /// describe a rig the planner can work with.
    var validationProblems: [String] {
        var problems: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Give the rig a name.") }
        if apertureMillimeters <= 0 { problems.append("Aperture has to be more than 0 mm.") }
        if focalLengthMillimeters <= 0 { problems.append("Focal length has to be more than 0 mm.") }
        // Either side may be the longer one: smart telescopes like the
        // Seestar hold their sensor upright.
        if sensorWidthMillimeters <= 0 || sensorHeightMillimeters <= 0 {
            problems.append("Sensor width and height both have to be more than 0 mm.")
        }
        if pixelSizeMicrons <= 0 { problems.append("Pixel size has to be more than 0 µm.") }
        if apertureMillimeters > 0 && focalLengthMillimeters > 0 && !(0.5...40).contains(focalRatio) {
            problems.append(String(format: "f/%.1f is outside what real optics use — check aperture and focal length.", focalRatio))
        }
        return problems
    }

    /// The field of view in words a beginner can picture.
    var fieldOfViewInMoons: String {
        let moons = max(fieldOfViewWidthDegrees, fieldOfViewHeightDegrees) / 0.52
        return moons >= 1.5
            ? String(format: "about %.0f full Moons across the long side", moons)
            : "about one full Moon across the long side"
    }
}
