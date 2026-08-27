import Foundation

/// How well a target suits the imaging train, independent of the weather.
struct RigFit: Hashable, Sendable {
    var framingScore: Double
    /// Target's long axis as a fraction of the frame's long dimension.
    var fillFraction: Double
    var mosaicPanels: Int
    var framingNote: String
    var samplingNote: String?
    var notes: [String]

    var needsMosaic: Bool { mosaicPanels > 1 }

    static func evaluate(target: Target, rig: Rig, site: Site) -> RigFit {
        let frameLong = rig.fieldOfViewLongArcminutes
        let frameShort = rig.fieldOfViewShortArcminutes
        guard frameLong > 0, frameShort > 0 else {
            return RigFit(framingScore: 0.5, fillFraction: 0, mosaicPanels: 1,
                          framingNote: "Set a focal length and sensor size in Settings",
                          samplingNote: nil, notes: [])
        }

        let major = max(0.1, target.majorAxisArcminutes)
        let minor = max(0.1, target.minorAxisArcminutes)
        let fillFraction = major / frameLong

        var notes: [String] = []
        var framingScore: Double
        var mosaicPanels = 1
        var framingNote: String

        // Allow a 10% margin so a target is not called "fitting" when it is
        // jammed against the frame edge with no room for framing error.
        let fitsInFrame = major <= frameLong * 0.9 && minor <= frameShort * 0.9

        if fitsInFrame {
            switch fillFraction {
            case 0.30...0.80:
                framingScore = 1.0
                framingNote = String(format: "Frames well — fills %.0f%% of the long side", fillFraction * 100)
            case ..<0.30:
                // Small targets still work, they just waste most of the sensor.
                framingScore = 0.35 + 0.65 * smoothstep(0.04, 0.30, fillFraction)
                framingNote = String(format: "Small in frame — %.0f%% of the long side", fillFraction * 100)
            default:
                framingScore = 0.85
                framingNote = "Tight fit — little margin for framing error"
            }
        } else {
            let panelsWide = Int(ceil(major / (frameLong * 0.8)))
            let panelsTall = Int(ceil(minor / (frameShort * 0.8)))
            mosaicPanels = max(2, panelsWide * panelsTall)
            if rig.supportsMosaic {
                framingScore = clamp(0.78 - 0.05 * Double(mosaicPanels - 1), 0.32, 0.78)
                framingNote = "Larger than the frame — \(mosaicPanels)-panel mosaic"
            } else {
                framingScore = clamp(0.45 - 0.08 * Double(mosaicPanels - 1), 0.12, 0.45)
                framingNote = "Overflows the frame — you'd get a portion of it"
                notes.append("This rig has no mosaic mode, so you would frame one part of the object.")
            }
        }

        // Sampling: how many pixels the target actually spans.
        var samplingNote: String?
        if rig.arcsecondsPerPixel > 0 {
            let pixelsAcross = (major * 60) / rig.arcsecondsPerPixel
            samplingNote = String(format: "%.0f px across at %.2f\"/px", pixelsAcross, rig.arcsecondsPerPixel)
            if pixelsAcross < 60 && !target.type.isStarField {
                notes.append("Only spans about \(Int(pixelsAcross)) pixels — undersampled, so expect a small, soft target.")
                framingScore = min(framingScore, 0.4)
            }
        }

        // A dual-band filter is the single biggest upgrade for emission targets
        // from a light-polluted site, so say so when it is missing.
        if target.type.respondsToNarrowband && !rig.hasNarrowbandFilter && site.bortleClass >= 5 {
            notes.append("A dual-band filter would make a large difference on this target from a Bortle \(site.bortleClass) sky.")
        }

        if target.type == .galaxy && site.bortleClass >= 7 && !target.type.isStarField {
            notes.append("Galaxies are broadband: no filter helps much against this level of light pollution.")
        }

        return RigFit(framingScore: clamp(framingScore, 0, 1),
                      fillFraction: fillFraction,
                      mosaicPanels: mosaicPanels,
                      framingNote: framingNote,
                      samplingNote: samplingNote,
                      notes: notes)
    }
}
