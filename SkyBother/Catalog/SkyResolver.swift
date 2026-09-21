import Foundation

/// Names whatever is at a given spot on the sky.
///
/// The built-in catalogue answers first, because it is instant, works offline
/// and covers the things worth pointing a telescope at. But it holds about
/// eleven hundred objects, and the sky has rather more than that — pan across
/// a random galaxy and the catalogue has nothing to say. Simbad does.
enum SkyResolver {
    /// Harvard rather than Strasbourg. The CDS hosts are unreachable from some
    /// networks — the same problem the cutout client works around — and this
    /// mirror answers in about a second.
    private static let endpoint = "https://simbad.harvard.edu/simbad/sim-coo"

    private static let userAgent =
        "SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; object lookup)"

    /// Catalogue prefixes worth reporting. A cone search returns everything —
    /// X-ray sources, radio detections, survey serial numbers, thousands of
    /// them around anything interesting — and almost none of it answers "what
    /// am I looking at". These are the designations a person recognises.
    private static let prefixes = ["M ", "NGC ", "IC ", "UGC ", "PGC ", "Sh2-", "LBN ", "LDN ", "NAME "]

    /// What's at this position, or nil if nothing recognisable is.
    static func name(rightAscensionDegrees ra: Double, declinationDegrees dec: Double,
                     radiusArcminutes: Double) async -> String? {
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "Coord", value: String(format: "%.5f %+.5f", ra, dec)),
            URLQueryItem(name: "Radius", value: String(format: "%.1f", max(0.5, min(30, radiusArcminutes)))),
            URLQueryItem(name: "Radius.unit", value: "arcmin"),
            URLQueryItem(name: "output.format", value: "ASCII"),
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        return firstRecognisable(in: text)
    }

    /// Simbad's ASCII table is pipe-separated, sorted nearest first, with the
    /// identifier in the third column and the object type in the fourth.
    /// Taking the first row whose identifier is one a person would recognise
    /// gives the right answer where the nearest row on its own does not — the
    /// closest thing to the centre of M31 is a radio source inside it.
    private static func firstRecognisable(in text: String) -> String? {
        var best: String?
        var anything: String?

        for line in text.split(separator: "\n") {
            let columns = line.split(separator: "|", omittingEmptySubsequences: false)
            guard columns.count > 4 else { continue }
            let identifier = columns[2].trimmingCharacters(in: .whitespaces)
            let type = columns[3].trimmingCharacters(in: .whitespaces)
            guard prefixes.contains(where: { identifier.hasPrefix($0) }) else { continue }
            // A trailing star marks a component of something — "M31*" is the
            // radio source at the galaxy's nucleus, not the galaxy.
            guard !identifier.hasSuffix("*") else { continue }

            let name = identifier.hasPrefix("NAME ")
                ? String(identifier.dropFirst(5))
                : identifier
            let described = type.isEmpty ? name : "\(name) · \(describe(type))"
            if anything == nil { anything = described }
            if extendedTypes.contains(type), best == nil { best = described }
        }
        return best ?? anything
    }

    /// Types worth answering with. Taken on its own, the nearest recognisable
    /// row is often a detection *inside* the thing you are looking at rather
    /// than the thing itself — at the centre of M31 the closest entry is a
    /// radio source, and the answer came back "M31*" instead of "M 31".
    /// Preferring an object with real extent fixes that.
    private static let extendedTypes: Set<String> = [
        "G", "GiG", "GiC", "H2G", "Sy1", "Sy2", "AGN", "LIN", "SBG", "rG", "IG",
        "GlC", "OpC", "Cl*", "PN", "SNR", "HII", "RNe", "DNe", "GNe", "ISM", "MoC", "Cld",
    ]

    /// Simbad's type codes are terse to the point of being a private language.
    /// Only the ones likely to turn up under a telescope are spelled out; the
    /// rest are passed through rather than guessed at.
    private static func describe(_ code: String) -> String {
        switch code {
        case "G", "GiG", "GiC", "H2G", "Sy2", "Sy1", "AGN", "LIN", "SBG", "rG", "IG": return "Galaxy"
        case "GlC": return "Globular Cluster"
        case "OpC", "Cl*": return "Open Cluster"
        case "PN", "pA*": return "Planetary Nebula"
        case "SNR": return "Supernova Remnant"
        case "HII", "ISM", "RNe", "DNe", "GNe", "Cld", "MoC": return "Nebula"
        case "*", "PM*", "V*", "**": return "Star"
        default: return code
        }
    }
}
