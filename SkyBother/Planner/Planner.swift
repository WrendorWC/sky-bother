import Foundation

/// Turns a site, a rig, a forecast and a catalogue into a week of night plans.
/// Pure and `Sendable` so it can be run off the main actor.
struct Planner: Sendable {
    var site: Site
    var rig: Rig
    var preferences: Preferences
    var catalog: [Target]
    var forecast: WeatherForecast

    /// Timeline resolution. Five minutes is finer than any forecast and finer
    /// than the eye can read off a night-long chart.
    private let sampleStepMinutes: Double = 5

    /// Declared explicitly: a private stored property would otherwise make the
    /// synthesized memberwise initialiser private too.
    init(site: Site, rig: Rig, preferences: Preferences, catalog: [Target], forecast: WeatherForecast) {
        self.site = site
        self.rig = rig
        self.preferences = preferences
        self.catalog = catalog
        self.forecast = forecast
    }

    /// Everything known about one instant, including the pieces the public
    /// `NightSample` does not need to carry.
    private struct SampleContext {
        var date: Date
        var daysSinceJ2000: Double
        var sunAltitude: Double
        var moonCoordinate: EquatorialCoordinate
        var moonAltitude: Double
        var moonBrightness: Double
        var darkness: Double
        var weather: HourlyWeather?
    }

    // MARK: - Entry point

    func plan(from referenceDate: Date = Date()) -> [NightPlan] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = site.timeZone

        // "Still inside last night" means before its actual sunrise, not
        // before some fixed clock hour — a flat noon cutoff kept calling a
        // plan opened well into a bright morning "tonight: yesterday" for
        // hours after the night it refers to had already fully ended.
        // Anchored to the real sunrise so the moment dawn breaks, "tonight"
        // rolls straight over to the night ahead.
        let midnight = calendar.startOfDay(for: referenceDate)
        let sunAltitude: (Date) -> Double = { date in
            Sun.altitude(daysSinceJ2000: date.daysSinceJ2000, latitude: site.latitude, longitude: site.longitude)
        }
        // Capped at noon, same as the cutoff this replaces — wide enough for
        // any realistic sunrise, narrow enough that it can't also run past
        // that day's sunset (which would hand back tomorrow's sunrise
        // instead) even on a short midwinter day at a high-latitude site.
        let morningSearchWindow = TimeWindow(start: midnight, end: midnight.addingTimeInterval(12 * 3600))
        let (_, thisMorningSunrise) = duskAndDawn(threshold: Sun.Event.sunset.altitude,
                                                   in: morningSearchWindow, altitude: sunAltitude)
        // No clean sunrise in that window (polar day/night, or any other
        // edge case) falls back to the old flat cutoff rather than guessing.
        let stillInLastNight = thisMorningSunrise.map { referenceDate < $0 }
            ?? (calendar.component(.hour, from: referenceDate) < 12)
        let anchor = stillInLastNight ? referenceDate.addingTimeInterval(-86400) : referenceDate

        let nightCount = max(1, min(16, preferences.forecastNights))
        var plans: [NightPlan] = []
        plans.reserveCapacity(nightCount)

        for offset in 0..<nightCount {
            guard let noon = localNoon(daysAfter: offset, from: anchor, calendar: calendar) else { continue }
            plans.append(buildNight(startingAtLocalNoon: noon, calendar: calendar))
        }
        return plans
    }

    private func localNoon(daysAfter offset: Int, from date: Date, calendar: Calendar) -> Date? {
        guard let shifted = calendar.date(byAdding: .day, value: offset, to: date) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: shifted)
        components.hour = 12
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    // MARK: - One night

    private func buildNight(startingAtLocalNoon noon: Date, calendar: Calendar) -> NightPlan {
        let searchWindow = TimeWindow(start: noon, end: noon.addingTimeInterval(86400))

        let latitude = site.latitude
        let longitude = site.longitude
        let sunAltitude: (Date) -> Double = { date in
            Sun.altitude(daysSinceJ2000: date.daysSinceJ2000,
                         latitude: latitude,
                         longitude: longitude)
        }

        let (sunset, sunrise) = duskAndDawn(threshold: Sun.Event.sunset.altitude,
                                            in: searchWindow, altitude: sunAltitude)
        let (civilDusk, civilDawn) = duskAndDawn(threshold: Sun.Event.civil.altitude,
                                                 in: searchWindow, altitude: sunAltitude)
        let (nauticalDusk, nauticalDawn) = duskAndDawn(threshold: Sun.Event.nautical.altitude,
                                                       in: searchWindow, altitude: sunAltitude)
        let (astroDusk, astroDawn) = duskAndDawn(threshold: Sun.Event.astronomical.altitude,
                                                 in: searchWindow, altitude: sunAltitude)

        let chartWindow = makeChartWindow(sunset: sunset, sunrise: sunrise, noon: noon)

        // Sample the night.
        let contexts = makeContexts(over: chartWindow)
        let samples = contexts.map { context in
            NightSample(date: context.date,
                        sunAltitude: context.sunAltitude,
                        moonAltitude: context.moonAltitude,
                        moonBrightness: context.moonBrightness,
                        darkness: context.darkness,
                        clearFactor: context.weather?.clearFactor ?? 0.6,
                        cloudCover: context.weather?.effectiveCloudCover ?? 40,
                        cloudLow: context.weather?.cloudCoverLow ?? 0,
                        cloudMid: context.weather?.cloudCoverMid ?? 0,
                        cloudHigh: context.weather?.cloudCoverHigh ?? 0,
                        transparency: context.weather?.transparency ?? 0.6,
                        seeing: context.weather?.seeing ?? 0.6,
                        temperature: context.weather?.temperatureCelsius ?? .nan,
                        dewSpread: context.weather?.dewPointSpread ?? .nan,
                        windSpeed: context.weather?.windSpeedKilometersPerHour ?? .nan,
                        hasWeather: context.weather != nil)
        }

        let hasWeather = samples.contains { $0.hasWeather }
        let clearThreshold = clamp(1 - preferences.maximumCloudCover / 100, 0, 1)

        // Darkness windows are set by the Sun alone. The moon reduces the quality
        // of those hours rather than removing them, and is scored per target.
        let isDark: (NightSample) -> Bool = { sample in
            SkyQuality.twilightFactor(sunAltitude: sample.sunAltitude) >= preferences.minimumDarkness
        }
        let darkWindows = windows(from: samples, where: isDark)
        let clearDarkWindows = windows(from: samples) { isDark($0) && $0.clearFactor >= clearThreshold }
        let moonlessDarkWindows = windows(from: samples) { isDark($0) && $0.moonAltitude <= 0 }

        let darkSamples = samples.filter(isDark)
        let meanCloud = darkSamples.isEmpty ? 100 : darkSamples.map(\.cloudCover).reduce(0, +) / Double(darkSamples.count)
        let temperatures = samples.map(\.temperature).filter { !$0.isNaN }
        let dewSpreads = samples.map(\.dewSpread).filter { !$0.isNaN }
        let gusts = contexts.compactMap { $0.weather?.windGustsKilometersPerHour }

        let moon = makeMoonSummary(contexts: contexts, chartWindow: chartWindow)

        var targets = makeTargetPlans(contexts: contexts,
                                      samples: samples,
                                      clearThreshold: clearThreshold,
                                      hasWeather: hasWeather,
                                      ignoreCloud: false)

        // If the cloud forecast eliminates everything, work out what *would*
        // have been up so the view can say "clouded out" over a real list
        // instead of showing nothing and looking broken.
        let isCloudedOut = targets.isEmpty && !darkWindows.isEmpty
        if isCloudedOut {
            targets = makeTargetPlans(contexts: contexts,
                                      samples: samples,
                                      clearThreshold: clearThreshold,
                                      hasWeather: hasWeather,
                                      ignoreCloud: true)
        }

        let factors = nightFactors(clearDarkWindows: clearDarkWindows,
                                   darkSamples: darkSamples,
                                   moon: moon,
                                   hasWeather: hasWeather,
                                   minimumDewSpread: dewSpreads.min() ?? .nan,
                                   maximumGust: gusts.max() ?? 0)

        return NightPlan(date: calendar.startOfDay(for: noon),
                         site: site,
                         chartWindow: chartWindow,
                         sunset: sunset,
                         sunrise: sunrise,
                         civilDusk: civilDusk,
                         civilDawn: civilDawn,
                         nauticalDusk: nauticalDusk,
                         nauticalDawn: nauticalDawn,
                         astronomicalDusk: astroDusk,
                         astronomicalDawn: astroDawn,
                         darkWindows: darkWindows,
                         clearDarkWindows: clearDarkWindows,
                         moonlessDarkWindows: moonlessDarkWindows,
                         isCloudedOut: isCloudedOut,
                         samples: samples,
                         moon: moon,
                         hasWeather: hasWeather,
                         meanCloudDuringDark: meanCloud,
                         minimumTemperature: temperatures.min() ?? .nan,
                         minimumDewSpread: dewSpreads.min() ?? .nan,
                         maximumGust: gusts.max() ?? 0,
                         score: weightedGeometricScore(factors),
                         factors: factors,
                         targets: targets)
    }

    // MARK: - Sun events

    /// Finds the evening and morning crossings of a sun altitude. Returns nil for
    /// either end when it does not happen — polar day, polar summer twilight, or
    /// a latitude where the sun never clears the threshold at all.
    private func duskAndDawn(threshold: Double,
                             in window: TimeWindow,
                             altitude: (Date) -> Double) -> (Date?, Date?) {
        let above = Ephemeris.windows(above: threshold,
                                      from: window.start,
                                      to: window.end,
                                      stepMinutes: 2,
                                      altitude: altitude)
        if above.count >= 2 {
            return (above[0].end, above[1].start)
        }
        if above.count == 1 {
            let only = above[0]
            let dusk = only.end < window.end.addingTimeInterval(-120) ? only.end : nil
            let dawn = only.start > window.start.addingTimeInterval(120) ? only.start : nil
            return (dusk, dawn)
        }
        return (nil, nil)
    }

    private func makeChartWindow(sunset: Date?, sunrise: Date?, noon: Date) -> TimeWindow {
        // Fall back to a fixed evening-to-morning span when the sun does not set,
        // so the timeline still renders somewhere sensible.
        let start = sunset ?? noon.addingTimeInterval(6 * 3600)      // 18:00 local
        var end = sunrise ?? noon.addingTimeInterval(20 * 3600)      // 08:00 next day
        if end <= start { end = start.addingTimeInterval(12 * 3600) }
        // Give the chart a little air on each side of the sun events.
        return TimeWindow(start: start.addingTimeInterval(-1800), end: end.addingTimeInterval(1800))
    }

    // MARK: - Sampling

    private func makeContexts(over window: TimeWindow) -> [SampleContext] {
        let stepSeconds = sampleStepMinutes * 60
        let count = max(2, Int((window.duration / stepSeconds).rounded()) + 1)
        var contexts: [SampleContext] = []
        contexts.reserveCapacity(count)

        for index in 0..<count {
            let date = window.start.addingTimeInterval(Double(index) * stepSeconds)
            let d = date.daysSinceJ2000

            let sunAltitude = Sun.altitude(daysSinceJ2000: d,
                                           latitude: site.latitude,
                                           longitude: site.longitude)

            let moonPosition = Moon.position(daysSinceJ2000: d)
            let moonHorizontal = SkyCoordinates.horizontal(moonPosition.coordinate,
                                                           daysSinceJ2000: d,
                                                           latitude: site.latitude,
                                                           longitude: site.longitude)
            let illumination = Moon.illuminatedFraction(daysSinceJ2000: d)
            let brightness = SkyQuality.moonBrightness(illuminatedFraction: illumination,
                                                       moonAltitude: moonHorizontal.altitude)

            contexts.append(SampleContext(
                date: date,
                daysSinceJ2000: d,
                sunAltitude: sunAltitude,
                moonCoordinate: moonPosition.coordinate,
                moonAltitude: moonHorizontal.altitude,
                moonBrightness: brightness,
                darkness: SkyQuality.darkness(sunAltitude: sunAltitude, moonBrightness: brightness),
                weather: forecast.interpolated(at: date)))
        }
        return contexts
    }

    /// Groups consecutive samples matching a predicate into time windows.
    private func windows(from samples: [NightSample], where predicate: (NightSample) -> Bool) -> [TimeWindow] {
        var result: [TimeWindow] = []
        var runStart: Date?
        let half = sampleStepMinutes * 30   // half a step, in seconds

        for sample in samples {
            if predicate(sample) {
                if runStart == nil { runStart = sample.date.addingTimeInterval(-half) }
            } else if let start = runStart {
                result.append(TimeWindow(start: start, end: sample.date.addingTimeInterval(-half)))
                runStart = nil
            }
        }
        if let start = runStart, let last = samples.last {
            result.append(TimeWindow(start: start, end: last.date.addingTimeInterval(half)))
        }
        return result.filter { $0.durationMinutes >= sampleStepMinutes }
    }

    // MARK: - Moon

    private func makeMoonSummary(contexts: [SampleContext], chartWindow: TimeWindow) -> MoonSummary {
        let middle = chartWindow.midpoint.daysSinceJ2000
        let illumination = Moon.illuminatedFraction(daysSinceJ2000: middle)

        let latitude = site.latitude
        let longitude = site.longitude
        let upWindows = Ephemeris.windows(above: Moon.riseSetAltitude,
                                          from: chartWindow.start,
                                          to: chartWindow.end,
                                          stepMinutes: 4) { date in
            Moon.altitude(daysSinceJ2000: date.daysSinceJ2000,
                          latitude: latitude,
                          longitude: longitude)
        }

        let maximumAltitude = contexts.map(\.moonAltitude).max() ?? -90

        // Only count the moon against nights that would otherwise be dark.
        let twilightWeights = contexts.map { SkyQuality.twilightFactor(sunAltitude: $0.sunAltitude) }
        let totalWeight = twilightWeights.reduce(0, +)
        var interference = 0.0
        if totalWeight > 0 {
            let weighted = zip(contexts, twilightWeights).reduce(0.0) { $0 + $1.0.moonBrightness * $1.1 }
            interference = clamp(weighted / totalWeight, 0, 1)
        }

        let minutesUp = contexts
            .filter { $0.moonAltitude > 0 && SkyQuality.twilightFactor(sunAltitude: $0.sunAltitude) > 0.2 }
            .count

        return MoonSummary(illuminatedFraction: illumination,
                           phaseName: Moon.phaseName(daysSinceJ2000: middle),
                           symbolName: Moon.symbolName(daysSinceJ2000: middle),
                           isWaxing: Moon.isWaxing(daysSinceJ2000: middle),
                           upWindows: upWindows,
                           maximumAltitude: maximumAltitude,
                           minutesUpDuringDarkness: Double(minutesUp) * sampleStepMinutes,
                           interference: interference)
    }

    // MARK: - Targets

    private func makeTargetPlans(contexts: [SampleContext],
                                 samples: [NightSample],
                                 clearThreshold: Double,
                                 hasWeather: Bool,
                                 ignoreCloud: Bool) -> [TargetPlan] {
        // The cheap rejection below only gets the site's *most open* direction,
        // since a target's peak altitude says nothing about which way it will
        // be when it gets there. Anything that survives it is then checked
        // sample by sample against the horizon in the direction it is actually
        // sitting — see `makeTargetPlan`.
        let bestCaseFloor = max(site.horizonAltitude, preferences.minimumUsefulAltitude)
        var plans: [TargetPlan] = []
        plans.reserveCapacity(catalog.count)

        for target in catalog {
            if target.type.isStarField && !preferences.includeStarClusters { continue }
            // Cheap rejection before doing any per-sample work.
            guard target.isEverVisible(latitude: site.latitude, aboveAltitude: bestCaseFloor) else { continue }

            if let plan = makeTargetPlan(target: target,
                                         contexts: contexts,
                                         samples: samples,
                                         clearThreshold: clearThreshold,
                                         hasWeather: hasWeather,
                                         ignoreCloud: ignoreCloud) {
                plans.append(plan)
            }
        }

        return plans.sorted { $0.score > $1.score }
    }

    private func makeTargetPlan(target: Target,
                                contexts: [SampleContext],
                                samples: [NightSample],
                                clearThreshold: Double,
                                hasWeather: Bool,
                                ignoreCloud: Bool) -> TargetPlan? {
        let fit = RigFit.evaluate(target: target, rig: rig, site: site)
        if fit.needsMosaic && !preferences.includeOversizedTargets { return nil }

        var altitudeTrace: [Double] = []
        altitudeTrace.reserveCapacity(contexts.count)

        var usableFlags: [Bool] = []
        usableFlags.reserveCapacity(contexts.count)

        // Tracked unconditionally, like altitudeTrace — zenith risk is about
        // mount physics (field rotation), not whether the sky happens to be
        // clear and dark right then, so it isn't gated on `isUsable` below.
        var zenithRiskFlags: [Bool] = []
        zenithRiskFlags.reserveCapacity(contexts.count)

        var usableCount = 0
        var darknessSum = 0.0
        var extinctionSum = 0.0
        // Tracked separately from clearSum/usableCount: this counts every
        // sample the target is actually above the horizon and the sky is
        // dark, regardless of whether cloud happened to clear the usability
        // bar right then. Averaging clearFactor over just the already-usable
        // samples would only ever measure "was the usable time clear?" —
        // trivially yes, since clearEnough is part of what makes a sample
        // usable — and could never reflect a mostly-cloudy night that only
        // offered a short clear break.
        var potentialWindowCount = 0
        var clearPotentialSum = 0.0
        var maximumAltitude = -90.0
        var altitudeAtBest = -90.0
        var azimuthAtBest = 0.0
        var bestTime: Date?
        var bestQuality = -1.0
        var transitTime: Date?
        var transitAltitude = -90.0
        var minimumSeparation = 180.0
        var maximumRotation = 0.0
        var effectiveMoonSum = 0.0
        // Time this target loses purely to something on the ground being in
        // the way, counted only where the sky itself was fine — so the warning
        // below can name the tree as the culprit and be right about it.
        var obstructedCount = 0
        var obstructedDirections: Set<Int> = []

        for (index, context) in contexts.enumerated() {
            let horizontal = SkyCoordinates.horizontal(target.coordinate,
                                                       daysSinceJ2000: context.daysSinceJ2000,
                                                       latitude: site.latitude,
                                                       longitude: site.longitude)
            altitudeTrace.append(horizontal.altitude)

            if horizontal.altitude > transitAltitude {
                transitAltitude = horizontal.altitude
                transitTime = context.date
            }
            maximumAltitude = max(maximumAltitude, horizontal.altitude)
            zenithRiskFlags.append(preferences.showsZenithRiskWarnings
                                   && rig.mountType.rotatesField
                                   && horizontal.altitude > rig.zenithAvoidanceAltitude)

            let sample = samples[index]
            let separation = SkyCoordinates.separation(target.coordinate, context.moonCoordinate)
            // The floor is the worse of your useful-altitude preference and
            // whatever blocks the horizon *in the direction the target is
            // currently in* — so a target that spends the first half of the
            // night behind the tree to the south and the rest of it clear to
            // the west keeps the half it can actually be shot in, instead of
            // the whole night being written off or wrongly counted.
            let floor = max(site.blockedAltitude(azimuth: horizontal.azimuth),
                            preferences.minimumUsefulAltitude)
            let aboveFloor = horizontal.altitude >= floor

            let effectiveMoon = SkyQuality.effectiveMoonBrightness(
                moonBrightness: context.moonBrightness,
                separationFromMoon: separation,
                targetRespondsToNarrowband: target.type.respondsToNarrowband,
                rigHasNarrowbandFilter: rig.hasNarrowbandFilter)
            let targetDarkness = SkyQuality.targetDarkness(sunAltitude: context.sunAltitude,
                                                           effectiveMoonBrightness: effectiveMoon)

            let darkEnough = SkyQuality.twilightFactor(sunAltitude: context.sunAltitude) >= preferences.minimumDarkness
            if aboveFloor && darkEnough {
                potentialWindowCount += 1
                clearPotentialSum += sample.clearFactor
            }

            let clearEnough = ignoreCloud || !hasWeather || sample.clearFactor >= clearThreshold
            let isUsable = aboveFloor && darkEnough && clearEnough
            usableFlags.append(isUsable)

            if !aboveFloor && darkEnough && clearEnough
                && horizontal.altitude >= preferences.minimumUsefulAltitude {
                obstructedCount += 1
                obstructedDirections.insert(Site.horizonDirectionIndex(azimuth: horizontal.azimuth))
            }

            guard isUsable else { continue }

            usableCount += 1
            darknessSum += targetDarkness
            effectiveMoonSum += effectiveMoon
            let extinction = SkyQuality.extinctionFactor(altitude: horizontal.altitude)
            extinctionSum += extinction
            minimumSeparation = min(minimumSeparation, separation)

            if rig.mountType.rotatesField {
                maximumRotation = max(maximumRotation,
                                      SkyCoordinates.fieldRotationRate(altitude: horizontal.altitude,
                                                                       azimuth: horizontal.azimuth,
                                                                       latitude: site.latitude))
            }

            // "Best" moment is the one combining darkness, transparency and altitude.
            let quality = targetDarkness * sample.clearFactor * extinction
            if quality > bestQuality {
                bestQuality = quality
                bestTime = context.date
                altitudeAtBest = horizontal.altitude
                azimuthAtBest = horizontal.azimuth
            }
        }

        guard usableCount > 0 else { return nil }

        let usableMinutes = Double(usableCount) * sampleStepMinutes
        let meanDarkness = darknessSum / Double(usableCount)
        // Over the target's whole potential dark, above-floor window — not
        // just the usable subset — so a target that only squeaked out a few
        // clear minutes in an otherwise cloudy night scores accordingly,
        // instead of Cloud cover reporting the usable time was clear (it was,
        // by definition) and missing how much of the night was not.
        let meanClear = potentialWindowCount > 0 ? clearPotentialSum / Double(potentialWindowCount) : 0
        let meanExtinction = extinctionSum / Double(usableCount)

        // Detectability is judged at the best moment, with the whole usable
        // window as the integration time you could actually collect.
        let meanEffectiveMoon = effectiveMoonSum / Double(usableCount)
        let detectability = SkyQuality.detectability(target: target,
                                                     site: site,
                                                     rig: rig,
                                                     altitude: max(altitudeAtBest, 5),
                                                     effectiveMoonBrightness: clamp(meanEffectiveMoon, 0, 1),
                                                     integrationMinutes: usableMinutes)

        let targetWindows = makeWindows(from: usableFlags, contexts: contexts)
        let zenithRiskWindows = makeWindows(from: zenithRiskFlags, contexts: contexts)

        let factors = targetFactors(usableMinutes: usableMinutes,
                                    meanDarkness: meanDarkness,
                                    meanClear: meanClear,
                                    meanExtinction: meanExtinction,
                                    framing: fit.framingScore,
                                    detectability: detectability,
                                    hasWeather: hasWeather)

        let warnings = targetWarnings(target: target,
                                      fit: fit,
                                      maximumAltitude: maximumAltitude,
                                      minimumSeparation: minimumSeparation,
                                      maximumRotation: maximumRotation,
                                      meanDarkness: meanDarkness,
                                      obstructedMinutes: Double(obstructedCount) * sampleStepMinutes,
                                      obstructedDirections: obstructedDirections,
                                      detectability: detectability)

        return TargetPlan(target: target,
                          windows: targetWindows,
                          usableMinutes: usableMinutes,
                          maximumAltitude: maximumAltitude,
                          altitudeAtBest: altitudeAtBest,
                          azimuthAtBest: azimuthAtBest,
                          bestTime: bestTime,
                          transitTime: transitTime,
                          meanDarkness: meanDarkness,
                          meanClear: meanClear,
                          meanExtinction: meanExtinction,
                          minimumMoonSeparation: minimumSeparation,
                          maximumFieldRotation: maximumRotation,
                          zenithRiskWindows: zenithRiskWindows,
                          fit: fit,
                          detectability: detectability,
                          score: weightedGeometricScore(factors),
                          factors: factors,
                          warnings: warnings,
                          altitudeTrace: altitudeTrace)
    }

    private func makeWindows(from flags: [Bool], contexts: [SampleContext]) -> [TimeWindow] {
        var result: [TimeWindow] = []
        var runStart: Date?
        let half = sampleStepMinutes * 30

        for (index, flag) in flags.enumerated() {
            let date = contexts[index].date
            if flag {
                if runStart == nil { runStart = date.addingTimeInterval(-half) }
            } else if let start = runStart {
                result.append(TimeWindow(start: start, end: date.addingTimeInterval(-half)))
                runStart = nil
            }
        }
        if let start = runStart, let last = contexts.last {
            result.append(TimeWindow(start: start, end: last.date.addingTimeInterval(half)))
        }
        return result
    }

    // MARK: - Scoring

    private func targetFactors(usableMinutes: Double,
                               meanDarkness: Double,
                               meanClear: Double,
                               meanExtinction: Double,
                               framing: Double,
                               detectability: Double,
                               hasWeather: Bool) -> [ScoreFactor] {
        let goal = max(15, preferences.integrationGoalMinutes)
        let timeValue = clamp(usableMinutes / goal, 0, 1)

        return [
            ScoreFactor(name: "Time on target",
                        value: timeValue,
                        weight: 0.26,
                        detail: "\(Int(usableMinutes)) min usable against a \(Int(goal)) min goal"),
            ScoreFactor(name: "Sky darkness",
                        value: meanDarkness,
                        weight: 0.18,
                        detail: "Twilight and moonlight, averaged over the window"),
            ScoreFactor(name: "Cloud cover",
                        value: hasWeather ? meanClear : 0.6,
                        weight: 0.18,
                        detail: hasWeather ? "Cloud forecast over the window" : "Beyond the forecast — assumed average"),
            ScoreFactor(name: "Altitude",
                        value: meanExtinction,
                        weight: 0.09,
                        detail: "Light lost to air mass at the altitudes it reaches"),
            // Floored low enough to be fatal, for the one framing outcome
            // that is: a target a handful of pixels across records no shape
            // at all with this rig, however bright it is. At the shared 0.02
            // floor a four-pixel planetary nebula still scored in the fifties
            // — above M13 — because its light is packed into those pixels and
            // every other factor liked it.
            ScoreFactor(name: "Framing",
                        value: framing,
                        weight: 0.15,
                        detail: "How the target sits in this rig's field of view",
                        floor: 0.001),
            // Weighted heavier than the other quality factors, and floored two
            // orders of magnitude lower, because it is the only one that can
            // be *fatal*: an hour of cloud or an awkward framing costs you
            // some of a night, but a target fainter than the sky it sits on
            // returns nothing at all, however long you leave the shutter open.
            // At the old 0.14 and the shared 0.02 floor, a completely
            // undetectable target still scored around 40 on a typical night
            // and 58 on a perfect one — comfortably past the default minimum
            // score, and presented as Marginal or Good. It now lands in Poor,
            // which is what it is.
            ScoreFactor(name: "Detectability",
                        value: detectability,
                        weight: 0.22,
                        detail: "Surface brightness against the sky background",
                        floor: 0.001)
        ]
    }

    private func nightFactors(clearDarkWindows: [TimeWindow],
                              darkSamples: [NightSample],
                              moon: MoonSummary,
                              hasWeather: Bool,
                              minimumDewSpread: Double,
                              maximumGust: Double) -> [ScoreFactor] {
        // A night is judged by its best unbroken stretch of clear, dark sky —
        // the same "best imaging" window the header shows — not by its total
        // or its average. Four clear hours make a night worth going out for
        // however bad the rest of it is, while a whole night of scattered
        // cloud only makes a lot of data to throw away. So both the time and
        // the clarity are taken from that one window, and what happens
        // outside it doesn't count.
        let goalHours = max(0.5, preferences.integrationGoalMinutes / 60)
        let bestWindow = clearDarkWindows.longest
        let clearDarkHours = (bestWindow?.durationMinutes ?? 0) / 60
        let timeValue = clamp(clearDarkHours / goalHours, 0, 1)

        let clarity: Double
        let inWindow = bestWindow.map { window in darkSamples.filter { window.contains($0.date) } } ?? []
        if hasWeather && !inWindow.isEmpty {
            clarity = clamp(inWindow.map(\.clearFactor).reduce(0, +) / Double(inWindow.count), 0, 1)
        } else if hasWeather {
            // No clear stretch at all: the night's own average, so a clouded-out
            // night still reads as cloudy rather than as neutral.
            clarity = darkSamples.isEmpty ? 0
                : clamp(darkSamples.map(\.clearFactor).reduce(0, +) / Double(darkSamples.count), 0, 1)
        } else {
            clarity = 0.6
        }

        var comfort = 1.0
        if hasWeather {
            let dewTerm = minimumDewSpread.isNaN ? 1 : smoothstep(0, 4, minimumDewSpread)
            let windTerm = 1 - clamp(maximumGust / 55, 0, 1)
            comfort = clamp(0.6 * dewTerm + 0.4 * windTerm, 0.05, 1)
        }

        return [
            ScoreFactor(name: "Clear dark time",
                        value: timeValue,
                        weight: 0.35,
                        detail: String(format: "Longest clear stretch %.1f h against a %.1f h goal", clearDarkHours, goalHours)),
            ScoreFactor(name: "Sky clarity",
                        value: clarity,
                        weight: 0.30,
                        detail: hasWeather ? "Cloud cover during the longest clear stretch" : "Beyond the forecast"),
            ScoreFactor(name: "Moon",
                        value: clamp(1 - moon.interference, 0, 1),
                        weight: 0.25,
                        detail: "\(moon.illuminationPercent)% lit, \(moon.phaseName.lowercased())"),
            ScoreFactor(name: "Conditions",
                        value: comfort,
                        weight: 0.10,
                        detail: hasWeather
                            ? String(format: "Dew spread %.1f°C, gusts to %.0f km/h", minimumDewSpread, maximumGust)
                            : "Beyond the forecast")
        ]
    }

    private func targetWarnings(target: Target,
                                fit: RigFit,
                                maximumAltitude: Double,
                                minimumSeparation: Double,
                                maximumRotation: Double,
                                meanDarkness: Double,
                                obstructedMinutes: Double,
                                obstructedDirections: Set<Int>,
                                detectability: Double) -> [String] {
        var warnings: [String] = []

        // The score alone can't carry this. A geometric mean over six factors
        // still reads as a middling number when five of them are fine, and
        // nothing about "48" tells you the problem is unfixable by waiting for
        // a better night — which is exactly what it is. So it gets said.
        if detectability < 0.12 {
            let sky = "your Bortle \(site.bortleClass) sky"
            if target.type.isStarField {
                warnings.append("At magnitude \(String(format: "%.1f", target.magnitude)) this is faint for \(sky) — expect few stars to come through")
            } else {
                warnings.append(String(format: "Surface brightness %.1f mag/arcsec² against %.1f for %@ — expect little or nothing, however long you integrate",
                                       target.surfaceBrightness, site.zenithSkyBrightness, sky))
            }
        }

        // Only worth saying when the horizon is uneven: with a flat horizon
        // this would fire on nearly every target in the list, which is just
        // restating the setting back at you. Half an hour is the floor —
        // below that it is noise, not a reason to plan differently.
        if site.hasDirectionalHorizon && obstructedMinutes >= 30 && !obstructedDirections.isEmpty {
            let named = obstructedDirections
                .sorted()
                .map { Site.horizonDirections[$0] }
                .joined(separator: "/")
            warnings.append("\(Format.duration(minutes: obstructedMinutes)) of otherwise good sky lost behind your blocked horizon to the \(named)")
        }

        if maximumAltitude < 35 {
            warnings.append(String(format: "Never rises above %.0f° — you are shooting through %.1f air masses at best",
                                   maximumAltitude, SkyCoordinates.airMass(altitude: maximumAltitude)))
        }

        if rig.mountType.rotatesField && maximumAltitude > rig.zenithAvoidanceAltitude {
            warnings.append(String(format: "Passes within %.0f° of the zenith, where field rotation peaks at %.1f°/h and many alt-az mounts stall",
                                   90 - maximumAltitude, maximumRotation))
        }

        if minimumSeparation < 35 && meanDarkness < 0.75 {
            warnings.append(String(format: "Comes within %.0f° of the moon", minimumSeparation))
        }

        if fit.needsMosaic {
            warnings.append(fit.framingNote)
        }

        warnings.append(contentsOf: fit.notes)
        return warnings
    }
}
