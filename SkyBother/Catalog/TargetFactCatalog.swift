import Foundation

/// A short, real piece of context for a catalog target — who found it, when,
/// what makes it notable — pulled from its Wikipedia summary the same way
/// `TargetImageCatalog` pulls a photo (see Scripts/fetch_target_facts.py),
/// not written from memory. Most of the ~1,000 extended-catalog objects
/// don't have a dedicated Wikipedia article to draw one from, same as with
/// photos, so this is frequently nil — callers should treat it as a bonus,
/// not something to design a layout around.
enum TargetFactCatalog {
    static let manifest: [String: String] = {
        guard let url = Bundle.main.url(forResource: "TargetFacts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }()

    static func fact(for designation: String) -> String? {
        manifest[designation]
    }
}
