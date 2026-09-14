import Foundation

/// Picks which spots to suggest out of everything a search found, on one rule:
/// never send someone further than they need to go.
///
/// Take the best spot in range. If anywhere closer is nearly as good — within
/// `margin` — suggest the closest such place instead, because the extra
/// distance isn't buying anything worth the drive. Then do the same again
/// among the places closer still, to offer a nearer, lesser alternative.
///
/// The margin is set above each estimate's own uncertainty: about twice the
/// sky-brightness model's scatter, and a few degrees of horizon, which is
/// within what an assumed tree height can move. A spot that's "better" by less
/// than that may not actually be better at all.
enum NearbySpotSelection {

    static let maximumSpots = 3

    static func margin(for goal: SpotGoal) -> Double {
        switch goal {
        case .darkerSky: return 0.3   // magnitudes per square arcsecond
        case .openHorizon: return 3   // degrees of horizon
        }
    }

    /// Higher is better, in the units `margin` uses.
    static func quality(of spot: NearbySpot, for goal: SpotGoal) -> Double {
        switch goal {
        case .darkerSky: return spot.zenithBrightness
        case .openHorizon: return -(spot.horizonAltitude ?? 90)
        }
    }

    /// Best suggestion first, then closer alternatives, nearest last.
    static func recommend(_ candidates: [NearbySpot], goal: SpotGoal) -> [NearbySpot] {
        let margin = margin(for: goal)
        var remaining = distinctPlaces(candidates, goal: goal)
        var chosen: [NearbySpot] = []

        while !remaining.isEmpty, chosen.count < maximumSpots {
            guard let best = remaining.max(by: { quality(of: $0, for: goal) < quality(of: $1, for: goal) }) else { break }
            let threshold = quality(of: best, for: goal) - margin
            // The closest place that's nearly as good as the best one.
            guard let pick = remaining
                .filter({ quality(of: $0, for: goal) >= threshold })
                .min(by: { $0.distanceKilometers < $1.distanceKilometers })
            else { break }
            chosen.append(pick)
            // Alternates only make sense if they're closer than what's already
            // suggested — anything further and no better has been ruled out.
            remaining = remaining.filter { $0.distanceKilometers < pick.distanceKilometers }
        }
        return chosen
    }

    /// The same park often turns up more than once — once per entrance, or from
    /// several overlapping searches. Keep the best entry for each name, and
    /// merge entries at the same spot under different names.
    static func distinctPlaces(_ candidates: [NearbySpot], goal: SpotGoal) -> [NearbySpot] {
        var kept: [NearbySpot] = []
        for candidate in candidates {
            if let index = kept.firstIndex(where: {
                $0.name == candidate.name
                    || (abs($0.latitude - candidate.latitude) < 0.0005 && abs($0.longitude - candidate.longitude) < 0.0005)
            }) {
                let existing = kept[index]
                let candidateQuality = quality(of: candidate, for: goal)
                let existingQuality = quality(of: existing, for: goal)
                if candidateQuality > existingQuality
                    || (candidateQuality == existingQuality && candidate.distanceKilometers < existing.distanceKilometers) {
                    kept[index] = candidate
                }
            } else {
                kept.append(candidate)
            }
        }
        return kept
    }
}
