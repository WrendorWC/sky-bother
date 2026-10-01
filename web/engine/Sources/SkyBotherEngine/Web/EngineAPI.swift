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
        var sunset: Date?
        var sunrise: Date?
        var factors: [Factor]
        var targets: [TargetSummary]
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
        var score: Double
        var usableMinutes: Double
        var maximumAltitude: Double
        var bestTime: Date?
        var windows: [TimeWindow]
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
            let nights = planner.plan(from: request.now).map(summary)
            return try encoder.encode(nights)
        } catch {
            return (try? encoder.encode(Failure(error: String(describing: error)))) ?? Data()
        }
    }

    static func summary(_ night: NightPlan) -> NightSummary {
        let factors = night.factors.map { Factor(name: $0.name, value: $0.value, weight: $0.weight, detail: $0.detail) }
        let ranked = night.targets.sorted { a, b in a.score != b.score ? a.score > b.score : a.id < b.id }
        let targets = ranked.map { (plan: TargetPlan) -> TargetSummary in
            TargetSummary(id: plan.id, name: plan.target.fullName, score: plan.score,
                          usableMinutes: plan.usableMinutes, maximumAltitude: plan.maximumAltitude,
                          bestTime: plan.bestTime, windows: plan.windows)
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
                            sunset: night.sunset,
                            sunrise: night.sunrise,
                            factors: factors,
                            targets: targets)
    }
}
