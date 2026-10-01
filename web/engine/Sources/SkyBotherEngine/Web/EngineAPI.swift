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
        /// Raw Open-Meteo response body, fetched by the page — parsed here by
        /// the Mac app's own parser. Either this or `forecast`.
        var openMeteoResponse: String?
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
        var factors: [Factor]
        /// Every five minutes from sunset to sunrise, for the timeline.
        var samples: [Sample]
        /// The app's suggested running order (AppState.suggestedPlan).
        var plan: [Block]
        var targets: [TargetSummary]
    }

    struct Sample: Encodable {
        var date: Date
        var sunAltitude: Double
        var moonAltitude: Double
        var moonBrightness: Double
        var darkness: Double
        var cloudCover: Double?
        var temperature: Double?
        var hasWeather: Bool
    }

    struct Block: Encodable {
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
        var framingNote: String
        /// Only for targets that are usable at all: the rest never show a bar.
        /// To 0.1°, finer than a pixel on either chart: at full precision a
        /// week of them was 6 MB of JSON.
        var altitudeTrace: [Double]?
    }

    struct Failure: Encodable { var error: String }

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
            } else {
                forecast = request.forecast ?? .empty
            }
            let planner = Planner(site: request.site,
                                  rig: request.rig,
                                  preferences: request.preferences,
                                  catalog: catalog + (request.customTargets ?? []),
                                  forecast: forecast,
                                  comets: request.cometElements.map(CometOrbit.parse) ?? [])
            let nights = planner.plan(from: request.now).map { summary($0, preferences: request.preferences) }
            return try encoder.encode(nights)
        } catch {
            return (try? encoder.encode(Failure(error: String(describing: error)))) ?? Data()
        }
    }

    static func summary(_ night: NightPlan, preferences: Preferences) -> NightSummary {
        let factors = night.factors.map { Factor(name: $0.name, value: $0.value, weight: $0.weight, detail: $0.detail) }
        let segments = suggestedPlan(for: night, preferences: preferences)
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
                          framingNote: plan.fit.framingNote,
                          altitudeTrace: plan.usableMinutes > 0 || planned.contains(plan.id) ? plan.altitudeTrace.map { ($0 * 10).rounded() / 10 } : nil)
        }
        let blocks = segments.map { segment in
            Block(targetID: segment.targetID, targetName: segment.targetName, window: segment.window,
                  unusableMinutes: segment.unusableMinutes(against: night.targets.first { $0.id == segment.targetID }))
        }
        let dew = DewRisk.Assessment.forPlan(segments, in: night).map {
            Dew(level: $0.level.name, advice: $0.adviceLine(in: night.timeZone),
                when: $0.when(in: night.timeZone), spreadAtPeak: $0.spreadAtPeak)
        }
        let samples = night.samples.map {
            Sample(date: $0.date, sunAltitude: $0.sunAltitude, moonAltitude: $0.moonAltitude,
                   moonBrightness: $0.moonBrightness, darkness: $0.darkness, cloudCover: finite($0.cloudCover),
                   temperature: finite($0.temperature), hasWeather: $0.hasWeather)
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
                            factors: factors,
                            samples: samples,
                            plan: blocks,
                            targets: targets)
    }

    static func finite(_ value: Double) -> Double? { value.isFinite ? value : nil }

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
