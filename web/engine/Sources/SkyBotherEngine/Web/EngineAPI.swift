import Foundation

/// The web app's one door into the engine: JSON in, JSON out, one call per
/// week of nights so crossing between JavaScript and WebAssembly stays cheap.
/// The native `engine-cli` calls exactly this too, which is what makes the
/// Mac/web parity check meaningful.
public enum EngineAPI {

    /// What the page sends. Site, rig, preferences and custom targets are the
    /// same shapes the Mac app keeps in settings.json, so a setup moves
    /// between the two unchanged.
    struct PlanRequest: Decodable {
        var site: Site
        var rig: Rig
        var preferences: Preferences
        var customTargets: [Target]?
        /// Your own plans by night (StoredSettings.sessionPlans): a night with
        /// an entry shows it, an empty one is a night deliberately cleared,
        /// and one without follows the suggestion.
        var sessionPlans: [String: [PlanSegment]]?
        /// Raw Open-Meteo response body, fetched by the page — parsed here by
        /// the Mac app's own parser. Either this or `forecast`.
        var openMeteoResponse: String?
        /// MET Norway's locationforecast body, when Open-Meteo failed (the
        /// Mac app's backup), read by the Mac app's own MetNorwayClient.
        var metNorwayResponse: String?
        var forecast: WeatherForecast?
        /// MPC's CometEls.txt, if the page has it.
        var cometElements: String?
        var now: Date
    }

    struct NightSummary: Encodable {
        var planKey: String
        var date: Date
        var score: Double
        var verdict: String
        var headline: String
        var hasWeather: Bool
        var isCloudedOut: Bool
        var darkHours: Double
        var clearDarkHours: Double
        var moonIlluminatedFraction: Double
        var moonPhase: String
        var moonIsWaxing: Bool
        var sunset: Date?
        var sunrise: Date?
        var astronomicalDusk: Date?
        var astronomicalDawn: Date?
        var chartWindow: TimeWindow
        var bestImagingWindow: TimeWindow?
        var moonlessDarkHours: Double
        /// Weather values are null beyond the forecast (NaN in the planner).
        var meanCloudDuringDark: Double?
        var minimumTemperature: Double?
        var maximumGust: Double?
        /// "Main limitation: …", as Home words it; nil when nothing stands out.
        var limitation: String?
        var dew: Dew?
        /// The night's own factors' score, before the best-target cap.
        var skyScore: Double
        /// The target that caps the night below `skyScore`, if one does:
        /// Planner.nightScore's "only as good as the best thing you can shoot".
        var cappedBy: String?
        var factors: [Factor]
        /// Every five minutes from sunset to sunrise, for the timeline.
        var samples: [Sample]
        /// The app's suggested running order (AppState.suggestedPlan).
        var plan: [Block]
        /// True when `plan` is your own rather than the suggestion.
        var isManualPlan: Bool
        var targets: [TargetSummary]
    }

    struct Sample: Encodable {
        var date: Date
        var sunAltitude: Double
        var moonAltitude: Double
        var moonBrightness: Double
        var darkness: Double
        var cloudCover: Double?
        var cloudLow: Double?
        var cloudMid: Double?
        var cloudHigh: Double?
        /// Preferences.cloudCredit: what the score lets this cloud keep, 1
        /// under the cloud limit, halving past it.
        var cloudCredit: Double?
        var temperature: Double?
        /// Temperature minus dew point, °C, and sustained wind, km/h.
        var dewSpread: Double?
        var windSpeed: Double?
        var hasWeather: Bool
    }

    struct Block: Encodable {
        var id: String
        var targetID: String
        var targetName: String
        var window: TimeWindow
        var unusableMinutes: Double
    }

    struct Dew: Encodable {
        var level: String
        var advice: String
        var when: String
        var spreadAtPeak: Double
    }

    struct Factor: Encodable {
        var name: String
        var value: Double
        var weight: Double
        var detail: String
        /// Points the sky score loses to this factor (FactorBar's "−n").
        var impact: Double
    }

    struct TargetSummary: Encodable {
        var id: String
        var name: String
        var displayName: String
        var designation: String
        var commonName: String?
        var type: String
        var typeName: String
        var isStar: Bool
        var score: Double
        var usableMinutes: Double
        var maximumAltitude: Double
        var bestTime: Date?
        var windows: [TimeWindow]
        var bestWindow: TimeWindow?
        var zenithRisk: TimeWindow?
        var fillFraction: Double
        var needsMosaic: Bool
        var rightAscension: Double
        var declination: Double
        var majorAxisArcminutes: Double
        var minorAxisArcminutes: Double
        var framingNote: String
        /// Only for targets that are usable at all: the rest never show a bar.
        /// To 0.1°, finer than a pixel on either chart: at full precision a
        /// week of them was 6 MB of JSON.
        var altitudeTrace: [Double]?
    }

    struct Failure: Encodable { var error: String }

    /// The selected-target panel (TargetDetailView), worded by the same
    /// shared functions the Mac app uses.
    struct TargetDetail: Encodable {
        /// False for a target with no usable time on the night: the rest is
        /// then just the catalogue's card, and `verdictSentence` says why.
        var scored: Bool
        var rightAscension: Double
        var declination: Double
        var majorAxisArcminutes: Double
        var minorAxisArcminutes: Double
        var id: String
        var displayName: String
        var designation: String
        /// "M76 · Planetary Nebula in Perseus"
        var subtitle: String
        var score: Double
        var verdict: String
        /// "1h 9m usable, best around 04:00 at 61° in the NNW"
        var recommendation: String
        var verdictSentence: String
        var transitTime: Date?
        var maximumAltitude: Double
        var bestWindow: TimeWindow?
        var zenithRisk: TimeWindow?
        var framingNote: String
        var samplingNote: String?
        /// "ZWO Seestar S50 Pro · 1.38° × 2.45° · 50mm f/5.2"
        var rigSummary: String
        /// Only for Marginal and Poor, as the Mac shows it.
        var whyNot: [String]
        var warnings: [String]
        var facts: [String]
        var factors: [DetailFactor]
        var filterNote: String?
        var numbers: [Number]
    }

    struct DetailFactor: Encodable {
        var name: String
        var value: Double
        var detail: String
        /// Points the score loses to this factor (FactorBar's "−n").
        var impact: Double
    }

    struct Number: Encodable {
        var label: String
        var value: String
    }

    /// The last week planned, so a target's detail is a lookup, not a re-plan.
    nonisolated(unsafe) private static var lastNights: [NightPlan] = []
    nonisolated(unsafe) private static var lastRig: Rig?
    nonisolated(unsafe) private static var lastSite: Site?
    nonisolated(unsafe) private static var lastForecast: WeatherForecast = .empty
    nonisolated(unsafe) private static var lastStoredPlans: [String: [PlanSegment]] = [:]
    nonisolated(unsafe) private static var lastPreferences: Preferences?
    /// Every target the week was planned from, comets placed for `now`.
    nonisolated(unsafe) private static var lastCatalog: [Target] = []

    /// One row of the catalogue browser.
    struct CatalogEntry: Encodable {
        var id: String
        var displayName: String
        var designation: String
        var commonName: String?
        var type: String
        /// TargetType.filterName: what the type filter calls it.
        var typeName: String
        var constellation: String
        var magnitude: Double
        var majorAxisArcminutes: Double
        var searchText: String
    }

    /// The whole catalogue of the last week planned.
    public static func catalogEntries() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let entries = lastCatalog.map {
            CatalogEntry(id: $0.id, displayName: $0.displayName, designation: $0.designation,
                         commonName: $0.commonName, type: $0.type.rawValue, typeName: $0.type.filterName,
                         constellation: $0.constellationName, magnitude: $0.magnitude,
                         majorAxisArcminutes: $0.majorAxisArcminutes, searchText: $0.searchText)
        }
        return (try? encoder.encode(entries)) ?? Data()
    }

    /// The catalogue's extended part ships as JSON next to the page rather
    /// than inside the binary; `BuiltInCatalog.extended` reads it from the
    /// app bundle, which doesn't exist here. Same order as `BuiltInCatalog.all`.
    nonisolated(unsafe) private static var extendedCatalog: [Target] = []

    public static func loadExtendedCatalog(_ data: Data) -> Int {
        extendedCatalog = (try? JSONDecoder().decode([Target].self, from: data)) ?? []
        return extendedCatalog.count
    }

    static var catalog: [Target] {
        BuiltInCatalog.messier + BuiltInCatalog.showpieces + extendedCatalog + BuiltInCatalog.stars
    }

    struct Defaults: Encodable {
        var rig: Rig
        var rigPresets: [Rig]
        var preferences: Preferences
    }

    /// The Mac app's starting rig, rig presets and preferences, so the page
    /// doesn't keep a second copy of them.
    public static func defaults() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(Defaults(rig: .seestarS50, rigPresets: Rig.presets, preferences: .default))) ?? Data()
    }

    /// A week of night plans, or `{"error": …}`.
    public static func planNights(_ requestJSON: Data) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let request = try decoder.decode(PlanRequest.self, from: requestJSON)

            let forecast: WeatherForecast
            if let body = request.openMeteoResponse {
                forecast = try OpenMeteoClient.decode(Data(body.utf8))
            } else if let body = request.metNorwayResponse {
                forecast = try MetNorwayClient.decode(Data(body.utf8))
            } else {
                forecast = request.forecast ?? .empty
            }
            let planner = Planner(site: request.site,
                                  rig: request.rig,
                                  preferences: request.preferences,
                                  catalog: catalog + (request.customTargets ?? []),
                                  forecast: forecast,
                                  comets: request.cometElements.map(CometOrbit.parse) ?? [])
            let plans = planner.plan(from: request.now)
            lastNights = plans
            lastForecast = forecast
            lastRig = request.rig
            lastSite = request.site
            lastPreferences = request.preferences
            let comets = request.cometElements.map(CometOrbit.parse) ?? []
            lastCatalog = catalog + (request.customTargets ?? []) + comets.compactMap { $0.target(at: request.now) }
            lastStoredPlans = request.sessionPlans ?? [:]
            return try encoder.encode(plans.map {
                summary($0, preferences: request.preferences, stored: request.sessionPlans?[$0.planKey])
            })
        } catch {
            return (try? encoder.encode(Failure(error: String(describing: error)))) ?? Data()
        }
    }

    static func summary(_ night: NightPlan, preferences: Preferences, stored: [PlanSegment]? = nil) -> NightSummary {
        let skyScore = weightedGeometricScore(night.factors)
        let factors = night.factors.map {
            Factor(name: $0.name, value: $0.value, weight: $0.weight, detail: $0.detail,
                   impact: scoreImpact(of: $0, in: night.factors, actualScore: skyScore))
        }
        let cappedBy = night.isCloudedOut ? nil : night.bestTarget.flatMap { $0.score < skyScore - 0.5 ? $0.id : nil }
        let segments = stored?.chronological ?? suggestedPlan(for: night, preferences: preferences)
        let ranked = night.targets.sorted { a, b in a.score != b.score ? a.score > b.score : a.id < b.id }
        let planned = Set(segments.map(\.targetID))
        let targets = ranked.map { (plan: TargetPlan) -> TargetSummary in
            TargetSummary(id: plan.id, name: plan.target.fullName, displayName: plan.target.displayName,
                          designation: plan.target.designation, commonName: plan.target.commonName,
                          type: plan.target.type.rawValue, typeName: plan.target.type.shortName,
                          isStar: plan.target.type.isStar, score: plan.score,
                          usableMinutes: plan.usableMinutes, maximumAltitude: plan.maximumAltitude,
                          bestTime: plan.bestTime, windows: plan.windows, bestWindow: plan.bestWindow,
                          zenithRisk: plan.bestWindowZenithRisk, fillFraction: plan.fit.fillFraction,
                          needsMosaic: plan.fit.needsMosaic,
                          rightAscension: plan.target.rightAscension, declination: plan.target.declination,
                          majorAxisArcminutes: plan.target.majorAxisArcminutes,
                          minorAxisArcminutes: plan.target.minorAxisArcminutes,
                          framingNote: plan.fit.framingNote,
                          altitudeTrace: plan.usableMinutes > 0 || planned.contains(plan.id) ? plan.altitudeTrace.map { ($0 * 10).rounded() / 10 } : nil)
        }
        let blocks = segments.map { segment in
            Block(id: segment.id.uuidString, targetID: segment.targetID, targetName: segment.targetName, window: segment.window,
                  unusableMinutes: segment.unusableMinutes(against: night.targets.first { $0.id == segment.targetID }))
        }
        let dew = DewRisk.Assessment.forPlan(segments, in: night).map {
            Dew(level: $0.level.name, advice: $0.adviceLine(in: night.timeZone),
                when: $0.when(in: night.timeZone), spreadAtPeak: $0.spreadAtPeak)
        }
        let samples = night.samples.map {
            Sample(date: $0.date, sunAltitude: $0.sunAltitude, moonAltitude: $0.moonAltitude,
                   moonBrightness: $0.moonBrightness, darkness: $0.darkness, cloudCover: finite($0.cloudCover),
                   cloudLow: finite($0.cloudLow), cloudMid: finite($0.cloudMid), cloudHigh: finite($0.cloudHigh),
                   cloudCredit: $0.cloudCover.isFinite ? preferences.cloudCredit(cloudCover: $0.cloudCover) : nil,
                   temperature: finite($0.temperature),
                   dewSpread: $0.hasWeather ? finite($0.dewSpread) : nil,
                   windSpeed: $0.hasWeather ? finite($0.windSpeed) : nil,
                   hasWeather: $0.hasWeather)
        }
        return NightSummary(planKey: night.planKey,
                            date: night.date,
                            score: night.score,
                            verdict: night.verdict.rawValue,
                            headline: night.headline,
                            hasWeather: night.hasWeather,
                            isCloudedOut: night.isCloudedOut,
                            darkHours: night.darkHours,
                            clearDarkHours: night.clearDarkHours,
                            moonIlluminatedFraction: night.moon.illuminatedFraction,
                            moonPhase: night.moon.phaseName,
                            moonIsWaxing: night.moon.isWaxing,
                            sunset: night.sunset,
                            sunrise: night.sunrise,
                            astronomicalDusk: night.astronomicalDusk,
                            astronomicalDawn: night.astronomicalDawn,
                            chartWindow: night.chartWindow,
                            bestImagingWindow: night.bestImagingWindow,
                            moonlessDarkHours: night.moonlessDarkHours,
                            meanCloudDuringDark: finite(night.meanCloudDuringDark),
                            minimumTemperature: finite(night.minimumTemperature),
                            maximumGust: finite(night.maximumGust),
                            limitation: nightLimitationPhrase(for: night),
                            dew: dew,
                            skyScore: skyScore,
                            cappedBy: cappedBy,
                            factors: factors,
                            samples: samples,
                            plan: blocks,
                            isManualPlan: stored != nil,
                            targets: targets)
    }

    static func finite(_ value: Double) -> Double? { value.isFinite ? value : nil }

    /// What Sky View needs beyond the page's own geometry (sidereal time,
    /// horizontal coordinates and the dome projection are simple enough to do
    /// in JavaScript with the same formulas): the Sun and Moon through the
    /// night, the wind that carries the dome's clouds, the horizon and the
    /// signpost stars. Every `stepMinutes` from `start`.
    struct SkyTrack: Encodable {
        var latitude: Double
        var longitude: Double
        /// Blocked altitude by compass sector, N, NE … NW (Site.horizonByDirection).
        var horizon: [Double]
        var start: Date
        var stepMinutes: Double
        /// [right ascension, declination] per step.
        var sun: [[Double]]
        /// [right ascension, declination, illuminated fraction, apparent diameter °, waxing 1/0] per step.
        var moon: [[Double]]
        /// [km/h toward east, km/h toward north] per step; wind direction is
        /// where it blows from, so this is reversed (SkyView.windVector).
        var wind: [[Double]]
        /// [low, mid, high] cloud cover 0–1 per step, from the hourly forecast
        /// (the night's samples stop at its edges; Sky View's Now can be by day).
        /// Empty beyond the forecast.
        var cloud: [[Double]]
        var stars: [Star]
        /// Showpieces worth marking on the dome, in AppState.famousTargets'
        /// order (named first, then brightest); the page puts the night's
        /// planned targets ahead of them, as AppState.domeHighlights does.
        var highlights: [String]
    }

    /// AppState.famousTargets
    static let famousTargets: [Target] = (BuiltInCatalog.messier + BuiltInCatalog.showpieces).sorted {
        let a = $0.commonName != nil, b = $1.commonName != nil
        return a != b ? a : $0.magnitude < $1.magnitude
    }

    struct Star: Encodable {
        var name: String
        var rightAscension: Double
        var declination: Double
    }

    struct TrackRequest: Decodable { var planKey: String }

    /// Sky View's data for a night of the last week planned, from twelve
    /// hours before the chart window to twelve after.
    public static func skyTrack(_ requestJSON: Data) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let request = try? JSONDecoder().decode(TrackRequest.self, from: requestJSON),
              let night = lastNights.first(where: { $0.planKey == request.planKey })
        else {
            return (try? encoder.encode(Failure(error: "No such night."))) ?? Data()
        }
        let step = 10.0
        // Twelve hours either side, so Now can show today's sky by day too.
        let start = night.chartWindow.start.addingTimeInterval(-12 * 3600)
        let count = Int((night.chartWindow.duration + 24 * 3600) / (step * 60)) + 1
        var sun: [[Double]] = [], moon: [[Double]] = [], wind: [[Double]] = [], cloud: [[Double]] = []
        for index in 0..<count {
            let date = start.addingTimeInterval(Double(index) * step * 60)
            let d = date.daysSinceJ2000
            let sunPosition = Sun.position(daysSinceJ2000: d)
            sun.append([sunPosition.rightAscension, sunPosition.declination])
            let moonPosition = Moon.position(daysSinceJ2000: d)
            moon.append([moonPosition.coordinate.rightAscension, moonPosition.coordinate.declination,
                         Moon.illuminatedFraction(daysSinceJ2000: d),
                         (3474.8 / moonPosition.distanceKilometers) * (180 / Double.pi),
                         Moon.isWaxing(daysSinceJ2000: d) ? 1 : 0])
            if let hour = lastForecast.interpolated(at: date) {
                let toward = ((hour.windDirectionDegrees ?? 270) + 180) * .pi / 180
                wind.append([sin(toward) * hour.windSpeedKilometersPerHour, cos(toward) * hour.windSpeedKilometersPerHour])
                cloud.append([hour.cloudCoverLow / 100, hour.cloudCoverMid / 100, hour.cloudCoverHigh / 100])
            } else {
                wind.append([0, 0])
                cloud.append([])
            }
        }
        let track = SkyTrack(latitude: night.site.latitude, longitude: night.site.longitude,
                             horizon: night.site.horizonByDirection, start: start, stepMinutes: step,
                             sun: sun, moon: moon, wind: wind,
                             cloud: lastForecast.hours.isEmpty ? [] : cloud,
                             stars: BuiltInCatalog.signpostStars.map {
                                 Star(name: $0.displayName, rightAscension: $0.rightAscension, declination: $0.declination)
                             },
                             highlights: famousTargets.map(\.id))
        return (try? encoder.encode(track)) ?? Data()
    }

    /// One edit to a night's plan, done by SessionPlanRules exactly as the
    /// Mac's planner does it (PlanStripView, PlannerWorkspaceView.add).
    struct PlanEditRequest: Decodable {
        var planKey: String
        /// "move", "resize", "add", "seed" (the displayed plan to start from),
        /// "suggest" (the app's suggestion)
        /// or "check" (just the unusable minutes of `segments`).
        var op: String
        var segments: [PlanSegment]
        var id: String?
        var seconds: Double?
        var movingStart: Bool?
        var targetID: String?
        /// "move" only: whether a neighbour may hop across (always, on the Mac).
        var allowSwap: Bool?
    }

    struct PlanEditResult: Encodable {
        /// Nil when the edit can't be made (the caller keeps the last layout).
        var segments: [PlanSegment]?
        var blocks: [Block]?
        /// "add": the new block's id.
        var added: String?
        var error: String?
    }

    public static func planEdit(_ requestJSON: Data) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func reply(_ result: PlanEditResult) -> Data { (try? encoder.encode(result)) ?? Data() }
        guard let request = try? decoder.decode(PlanEditRequest.self, from: requestJSON),
              let night = lastNights.first(where: { $0.planKey == request.planKey })
        else { return reply(PlanEditResult(error: "No such night.")) }
        let window = night.chartWindow
        var segments = request.segments
        var added: String?

        switch request.op {
        case "seed", "suggest":
            // "seed": what the night shows now, yours or the suggestion;
            // "suggest": the suggestion, for Reset. On the 5-minute grid.
            let stored = request.op == "seed" ? lastStoredPlans[night.planKey] : nil
            segments = (stored ?? suggestedPlan(for: night, preferences: lastPreferences ?? .default))
                .map { var s = $0; s.window = SessionPlanRules.snapped(s.window); return s }
        case "move", "resize":
            guard let id = request.id, let seconds = request.seconds,
                  let segment = segments.first(where: { $0.id.uuidString == id })
            else { return reply(PlanEditResult(error: "No such block.")) }
            let dragged = request.op == "move"
                ? SessionPlanRules.moved(segment, by: seconds, within: window)
                : SessionPlanRules.resized(segment, movingStart: request.movingStart ?? false, by: seconds, within: window)
            guard let resolved = SessionPlanRules.resolve(dragged: dragged, against: segments, within: window,
                                                          allowSwap: request.op == "move" && (request.allowSwap ?? true))
            else { return reply(PlanEditResult()) }
            segments = resolved
        case "add":
            guard let targetID = request.targetID,
                  let targetPlan = night.targets.first(where: { $0.id == targetID })
            else { return reply(PlanEditResult(error: "No such target.")) }
            guard let slot = SessionPlanRules.placement(for: targetPlan, among: segments, within: window,
                                                         preferredMinutes: (lastPreferences ?? .default).sessionCapMinutes)
            else { return reply(PlanEditResult(error: "Every stretch of the night is already taken.")) }
            let segment = PlanSegment(targetID: targetID, targetName: targetPlan.target.displayName, window: slot)
            added = segment.id.uuidString
            segments = (segments + [segment]).chronological
        default:
            break
        }
        let blocks = segments.map { segment in
            Block(id: segment.id.uuidString, targetID: segment.targetID, targetName: segment.targetName, window: segment.window,
                  unusableMinutes: segment.unusableMinutes(against: night.targets.first { $0.id == segment.targetID }))
        }
        return reply(PlanEditResult(segments: segments, blocks: blocks, added: added))
    }

    struct TargetRequest: Decodable {
        var planKey: String
        var targetID: String
    }

    /// One target on one night of the last week planned, or `{"error": …}`.
    public static func targetDetail(_ requestJSON: Data) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let request = try? JSONDecoder().decode(TargetRequest.self, from: requestJSON),
              let night = lastNights.first(where: { $0.planKey == request.planKey }),
              let rig = lastRig
        else {
            return (try? encoder.encode(Failure(error: "No such night."))) ?? Data()
        }
        if let plan = night.targets.first(where: { $0.id == request.targetID }) {
            return (try? encoder.encode(detail(plan, night: night, rig: rig))) ?? Data()
        }
        guard let target = lastCatalog.first(where: { $0.id == request.targetID }) else {
            return (try? encoder.encode(Failure(error: "No such target."))) ?? Data()
        }
        return (try? encoder.encode(unscoredDetail(target, rig: rig))) ?? Data()
    }

    /// The catalogue's card for a target with nothing usable on the night.
    static func unscoredDetail(_ target: Target, rig: Rig) -> TargetDetail {
        let minimum = lastPreferences?.minimumUsefulAltitude ?? 30
        let reason: String
        if let site = lastSite, !target.isEverVisible(latitude: site.latitude, aboveAltitude: minimum) {
            reason = "Never gets above your minimum altitude of \(Format.degrees(minimum)) from here."
        } else {
            reason = "Not above your minimum altitude while it's dark on this night."
        }
        var numbers = [
            Number(label: "Coordinates", value: Format.coordinates(target.coordinate)),
            Number(label: "Magnitude", value: String(format: "%.1f", target.magnitude)),
            Number(label: "Apparent size", value: target.sizeSummary),
        ]
        if !target.type.isStarField {
            numbers.append(Number(label: "Surface brightness", value: String(format: "%.1f mag/arcsec²", target.surfaceBrightness)))
        }
        return TargetDetail(
            scored: false,
            rightAscension: target.rightAscension, declination: target.declination,
            majorAxisArcminutes: target.majorAxisArcminutes, minorAxisArcminutes: target.minorAxisArcminutes,
            id: target.id, displayName: target.displayName, designation: target.designation,
            subtitle: "\(target.designation) · \(target.type.displayName)\(target.inConstellation)",
            score: 0, verdict: "", recommendation: "Not usable on this night", verdictSentence: reason,
            transitTime: nil, maximumAltitude: 0, bestWindow: nil, zenithRisk: nil,
            framingNote: "", samplingNote: nil,
            rigSummary: "\(rig.name) · \(rig.fieldOfViewSummary) · \(rig.opticalSummary)",
            whyNot: [], warnings: [], facts: CuratedFacts.facts(for: target.designation), factors: [],
            filterNote: nil, numbers: numbers)
    }

    static func detail(_ plan: TargetPlan, night: NightPlan, rig: Rig) -> TargetDetail {
        let target = plan.target
        let zone = night.timeZone
        var recommendation = ["\(plan.usableHoursText) usable"]
        if let best = plan.bestTime {
            let compass = HorizontalCoordinate(altitude: plan.altitudeAtBest, azimuth: plan.azimuthAtBest).compassPoint
            recommendation.append("best around \(Format.time(best, in: zone)) at \(Format.degrees(plan.altitudeAtBest)) in the \(compass)")
        }
        var numbers = [
            Number(label: "Coordinates", value: Format.coordinates(target.coordinate)),
            Number(label: "Magnitude", value: String(format: "%.1f", target.magnitude)),
            Number(label: "Apparent size", value: target.sizeSummary),
        ]
        if !target.type.isStarField {
            numbers.append(Number(label: "Surface brightness", value: String(format: "%.1f mag/arcsec²", target.surfaceBrightness)))
        }
        numbers.append(Number(label: "Peak altitude", value: Format.degrees(plan.maximumAltitude)))
        numbers.append(Number(label: "Air mass at peak", value: String(format: "%.2f", SkyCoordinates.airMass(altitude: plan.maximumAltitude))))
        numbers.append(Number(label: "Moon separation", value: Format.degrees(plan.minimumMoonSeparation)))
        if rig.mountType.rotatesField && plan.maximumFieldRotation > 0 {
            numbers.append(Number(label: "Peak field rotation", value: String(format: "%.1f°/h", plan.maximumFieldRotation)))
        }
        return TargetDetail(
            scored: true,
            rightAscension: target.rightAscension, declination: target.declination,
            majorAxisArcminutes: target.majorAxisArcminutes, minorAxisArcminutes: target.minorAxisArcminutes,
            id: plan.id,
            displayName: target.displayName,
            designation: target.designation,
            subtitle: "\(target.designation) · \(target.type.displayName)\(target.inConstellation)",
            score: plan.score,
            verdict: plan.verdict.rawValue,
            recommendation: recommendation.joined(separator: ", "),
            verdictSentence: targetVerdictSentence(plan),
            transitTime: plan.transitTime,
            maximumAltitude: plan.maximumAltitude,
            bestWindow: plan.bestWindow,
            zenithRisk: plan.bestWindowZenithRisk,
            framingNote: plan.fit.framingNote,
            samplingNote: plan.fit.samplingNote,
            rigSummary: "\(rig.name) · \(rig.fieldOfViewSummary) · \(rig.opticalSummary)",
            whyNot: plan.verdict == .marginal || plan.verdict == .poor ? whyNotBullets(factors: plan.factors) : [],
            warnings: plan.warnings,
            facts: CuratedFacts.facts(for: target.designation),
            factors: plan.factors.map {
                DetailFactor(name: $0.name, value: $0.value, detail: $0.detail,
                             impact: scoreImpact(of: $0, in: plan.factors, actualScore: plan.score))
            },
            filterNote: target.type.respondsToNarrowband && rig.hasNarrowbandFilter
                ? "Scored with your dual-band (light-pollution) filter in use. It cuts moonlight and light pollution on this target; without it, this would score lower."
                : nil,
            numbers: numbers)
    }

    /// AppState.suggestedSlots/suggestedPlan, which live in the Mac UI layer.
    static func suggestedPlan(for night: NightPlan, preferences: Preferences) -> [PlanSegment] {
        guard !night.isCloudedOut else { return [] }
        return AutoPlanner.plan(for: night, minimumScore: preferences.minimumScore,
                                sessionCapMinutes: preferences.sessionCapMinutes,
                                minimumSlotMinutes: preferences.minimumSessionMinutes)
            .map { PlanSegment.suggested(targetID: $0.targetPlan.id,
                                         targetName: $0.targetPlan.target.displayName,
                                         window: $0.window) }
            .chronological
    }
}
