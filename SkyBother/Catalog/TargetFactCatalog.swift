import Foundation

/// One entry from `TargetFacts.json` — a short, real piece of context for a
/// catalog target (who found it, when, what makes it notable), pulled from
/// its Wikipedia summary the same way `TargetImageCatalog` pulls a photo
/// (see Scripts/fetch_target_facts.py), not written from memory. `sourceURL`
/// points back to the article, the same attribution `TargetImageInfo`
/// already carries for photos — this text is reused from Wikipedia
/// (CC-BY-SA-4.0) just as much as the images are.
struct TargetFactInfo: Decodable, Sendable {
    var fact: String
    var sourceTitle: String
    var sourceURL: String
}

/// Most of the ~1,000 extended-catalog objects don't have a dedicated
/// Wikipedia article to draw a fact from, same as with photos, so this is
/// frequently nil — callers should treat it as a bonus, not something to
/// design a layout around.
enum TargetFactCatalog {
    static let manifest: [String: TargetFactInfo] = {
        guard let url = Bundle.main.url(forResource: "TargetFacts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: TargetFactInfo].self, from: data)
        else { return [:] }
        return decoded
    }()

    static func info(for designation: String) -> TargetFactInfo? {
        manifest[designation]
    }

    static func fact(for designation: String) -> String? {
        manifest[designation]?.fact
    }
}
