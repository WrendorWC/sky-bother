import Foundation

/// Sky-brightness modelling.
///
/// These are deliberately simple, documented heuristics rather than a physical
/// radiative-transfer model. Every constant is chosen so the *ordering* of
/// nights and targets matches what an experienced imager would decide, which is
/// what the app is for. Nothing here claims to predict an SQM reading.
enum SkyQuality {

    /// How dark the sky is from the Sun alone, 0...1.
    /// Zero at civil twilight, one at full astronomical darkness (-18 deg).
    /// The curve is weighted so that -15 deg still scores well: plenty of useful
    /// imaging happens in late nautical twilight, especially in summer at high
    /// latitudes where it never gets properly dark at all.
    static func twilightFactor(sunAltitude: Double) -> Double {
        guard sunAltitude < -6 else { return 0 }
        let t = clamp((-sunAltitude - 6) / 12, 0, 1)
        return pow(t, 1.4)
    }

    /// How much the moon is lighting up the sky, 0...1.
    /// Scales super-linearly with phase because lunar surface brightness rises
    /// sharply near full (the opposition surge), and with altitude because a low
    /// moon shines through far more atmosphere.
    static func moonBrightness(illuminatedFraction: Double, moonAltitude: Double) -> Double {
        guard moonAltitude > -0.5 else { return 0 }
        let phaseTerm = pow(clamp(illuminatedFraction, 0, 1), 2.2)
        let altitudeTerm = pow(clamp(sinDeg(max(moonAltitude, 0)), 0, 1), 0.5)
        return clamp(phaseTerm * altitudeTerm, 0, 1)
    }

    /// Overall darkness of the sky, 0...1, ignoring where you are pointing.
    static func darkness(sunAltitude: Double, moonBrightness: Double) -> Double {
        clamp(twilightFactor(sunAltitude: sunAltitude) * (1 - 0.9 * moonBrightness), 0, 1)
    }

    /// Darkness as experienced by one particular target, which depends on how far
    /// it sits from the moon and whether a dual-band filter is rejecting the
    /// moonlight in the first place.
    /// Moonlight as it actually affects one target: reduced by distance from the
    /// moon, and largely rejected outright if a dual-band filter is in the train
    /// and the target emits in narrow lines.
    static func effectiveMoonBrightness(moonBrightness: Double,
                                        separationFromMoon: Double,
                                        targetRespondsToNarrowband: Bool,
                                        rigHasNarrowbandFilter: Bool) -> Double {
        // Close to the Moon is far worse than the other side of the sky, and
        // the glow climbs steeply in the last few tens of degrees, so inside
        // 30° the penalty grows past the Moon's own brightness.
        let separationFactor: Double
        if separationFromMoon < 30 {
            separationFactor = 1 + 0.8 * pow((30 - max(separationFromMoon, 0)) / 30, 1.5)
        } else {
            separationFactor = 1 - 0.55 * clamp((separationFromMoon - 30) / 90, 0, 1)
        }
        var effective = moonBrightness * separationFactor

        // A dual/tri-band filter rejects most of the scattered continuum, so an
        // emission target under a gibbous moon is genuinely still worth
        // shooting — away from the Moon. Near it the glow is bright enough to
        // come through the filter's bands too (a Seestar's are fairly wide),
        // so the filter's help fades inside about 40°.
        if targetRespondsToNarrowband && rigHasNarrowbandFilter {
            let closeness = clamp((40 - separationFromMoon) / 30, 0, 1)
            effective *= 0.4 + 0.45 * closeness
        }
        return clamp(effective, 0, 1)
    }

    static func targetDarkness(sunAltitude: Double, effectiveMoonBrightness: Double) -> Double {
        clamp(twilightFactor(sunAltitude: sunAltitude) * (1 - 0.9 * effectiveMoonBrightness), 0, 1)
    }

    static func targetDarkness(sunAltitude: Double,
                               moonBrightness: Double,
                               separationFromMoon: Double,
                               targetRespondsToNarrowband: Bool,
                               rigHasNarrowbandFilter: Bool) -> Double {
        let effective = effectiveMoonBrightness(moonBrightness: moonBrightness,
                                                separationFromMoon: separationFromMoon,
                                                targetRespondsToNarrowband: targetRespondsToNarrowband,
                                                rigHasNarrowbandFilter: rigHasNarrowbandFilter)
        return targetDarkness(sunAltitude: sunAltitude, effectiveMoonBrightness: effective)
    }

    /// Fraction of light surviving the atmosphere at a given altitude, taking a
    /// typical extinction coefficient of 0.2 magnitudes per air mass.
    static func extinctionFactor(altitude: Double) -> Double {
        guard altitude > 0 else { return 0 }
        let airMass = SkyCoordinates.airMass(altitude: altitude)
        return clamp(pow(10, -0.4 * 0.20 * (airMass - 1)), 0, 1)
    }

    /// Effective sky background in magnitudes per square arcsecond, combining the
    /// site's light pollution, the extra glow toward the horizon, and the moon.
    static func skyBrightness(site: Site,
                              altitude: Double,
                              effectiveMoonBrightness: Double) -> Double {
        var brightness = site.zenithSkyBrightness
        // Light pollution and airglow both pile up toward the horizon.
        brightness -= clamp(1.6 * (1 - sinDeg(max(altitude, 5))), 0, 1.6)
        // Moonlight adds to the glow already there. A high full Moon alone
        // makes a sky of about 17.8 mag/arcsec²: four magnitudes brighter
        // than a dark site, but less than one on top of a city sky that's
        // already bright. It used to be taken off as a flat 4.2 whatever the
        // sky, which put a moonlit Bortle 7 sky near 14 and made even the
        // Orion Nebula undetectable.
        let moon = clamp(effectiveMoonBrightness, 0, 2)
        guard moon > 0.001 else { return brightness }
        let moonSky = 17.8 - 2.5 * log10(moon)
        return -2.5 * log10(pow(10, -0.4 * brightness) + pow(10, -0.4 * moonSky))
    }

    /// How readily this target separates from the sky background on this rig,
    /// 0...1. Extended objects are judged on surface-brightness contrast; star
    /// fields on integrated magnitude, since they are collections of point
    /// sources and contrast does not apply to them the same way.
    static func detectability(target: Target,
                              site: Site,
                              rig: Rig,
                              altitude: Double,
                              effectiveMoonBrightness: Double,
                              integrationMinutes: Double) -> Double {
        let sky = skyBrightness(site: site,
                                altitude: altitude,
                                effectiveMoonBrightness: effectiveMoonBrightness)

        if target.type.isStarField {
            // Clusters stay visible in far worse skies than nebulae do.
            let reach = smoothstep(12.5, 3.5, target.magnitude)
            let skyPenalty = smoothstep(17.0, 20.5, sky) * 0.4 + 0.6
            return clamp(reach * skyPenalty, 0, 1)
        }

        // Positive contrast means the target is brighter than the background it
        // sits on, per square arcsecond. A galaxy is judged on the central
        // area holding half its light — about a third of its catalogued
        // diameter, some 1.9 magnitudes brighter than the whole ellipse's
        // average — since that's what a short stack records; averaged over
        // the faint outer disk, M31 read as hopeless from a suburb.
        let surface = target.type == .galaxy ? target.surfaceBrightness - 1.9 : target.surfaceBrightness
        let contrast = sky - surface

        // A faster system delivers more signal per unit time on an extended
        // object; f-ratio, not aperture, is what governs that.
        let speedBonus = 5 * log10(clamp(5.0 / max(1.0, rig.focalRatio), 0.2, 5.0))

        // Stacking buys real depth, but with diminishing returns.
        let hours = max(0.15, integrationMinutes / 60)
        let integrationBonus = clamp(2.5 * log10(hours), -1.5, 2.0)

        // A dual-band filter raises contrast on emission targets dramatically by
        // throwing away the sky continuum but keeping the line emission.
        var filterBonus = 0.0
        if target.type.respondsToNarrowband && rig.hasNarrowbandFilter {
            filterBonus = 2.2
        }

        let effective = contrast + speedBonus + integrationBonus + filterBonus
        return smoothstep(-4.5, 1.5, effective)
    }
}
