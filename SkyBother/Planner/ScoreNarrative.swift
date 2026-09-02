import Foundation

/// How many points the overall score would gain if this one factor were
/// perfect (1.0) instead of its actual value. This is computed by literally
/// re-running `weightedGeometricScore` with that one substitution — a real
/// counterfactual from the actual model, not an invented additive number.
/// Because the mean is geometric, this isn't a fixed "weight × something";
/// how much a factor is costing you depends on what every other factor is
/// doing too, which is exactly why this has to be computed rather than read
/// off the weight.
func scoreImpact(of factor: ScoreFactor, in factors: [ScoreFactor], actualScore: Double) -> Double {
    guard let index = factors.firstIndex(where: { $0.id == factor.id }) else { return 0 }
    var idealized = factors
    idealized[index].value = 1.0
    return weightedGeometricScore(idealized) - actualScore
}

/// The single factor most worth blaming for a score — the one that would
/// move it the most if it were perfect. Returns nil only when there are no
/// factors at all.
func primaryFactor(in factors: [ScoreFactor], actualScore: Double) -> (factor: ScoreFactor, impact: Double)? {
    factors
        .map { ($0, scoreImpact(of: $0, in: factors, actualScore: actualScore)) }
        .max { $0.1 < $1.1 }
}

/// A short, plain-language read on what a factor is costing you — every
/// caller uses this only for the factor already identified as the primary
/// limitation, so this always describes the downside, even when that
/// factor's own tier is merely "Good" rather than outright "Poor": in a
/// night or target where everything else is Exceptional, a "Good" factor
/// can still be the single biggest reason the score isn't higher, and the
/// phrasing should say so rather than compliment it.
func limitationPhrase(for factor: ScoreFactor) -> String {
    switch factor.name {
    case "Moon": return "bright moon"
    case "Clear dark time": return "short dark window"
    case "Sky clarity": return "cloud during the dark hours"
    case "Conditions": return "dew or wind risk"
    case "Time on target": return "not up for long enough"
    case "Sky darkness": return "twilight or moonlit sky"
    case "Cloud cover": return "intermittent clouds during the window"
    case "Altitude": return "stays low, heavy air mass"
    case "Framing": return "poor fit for your frame"
    case "Detectability": return "faint against your sky"
    default: return factor.name.lowercased()
    }
}

/// The night's headline "main limitation" — grounded in real data (the
/// moon's actual phase, not a made-up description) rather than the generic
/// phrase used for target-level factors.
func nightLimitationPhrase(for night: NightPlan) -> String? {
    guard let primary = primaryFactor(in: night.factors, actualScore: night.score), primary.impact > 1.5 else {
        return nil
    }
    switch primary.factor.name {
    case "Moon": return night.moon.phaseName.lowercased()
    case "Sky clarity": return "cloud during the dark hours"
    case "Clear dark time": return "short dark window"
    case "Conditions": return night.hasDewRisk ? "dew risk" : "wind"
    default: return limitationPhrase(for: primary.factor)
    }
}

/// Short bullet points explaining why a target isn't a good pick tonight —
/// picked out from the same factors already computed for it, not invented.
/// Each bullet keeps the real number from the factor's own detail string.
func whyNotBullets(factors: [ScoreFactor], limit: Int = 3) -> [String] {
    factors
        .filter { $0.value < 0.55 }
        .sorted { $0.weight * (1 - $0.value) > $1.weight * (1 - $1.value) }
        .prefix(limit)
        .map { "\($0.name) — \($0.detail)" }
}
