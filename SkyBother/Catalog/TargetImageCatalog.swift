import AppKit
import Foundation

/// One entry from `TargetImages.json` — a thumbnail pulled from Wikipedia for a
/// catalog target, keyed by designation.
struct TargetImageInfo: Decodable, Sendable {
    var file: String
    var sourceTitle: String
    var sourceURL: String
}

/// Reference photos for the built-in catalog, bundled locally so browsing the
/// catalog (and the "in your frame" preview) works offline. Every image comes
/// from Wikipedia, which only hosts appropriately licensed media; `sourceURL`
/// points back to the article for full credit and license detail.
enum TargetImageCatalog {
    static let manifest: [String: TargetImageInfo] = {
        guard let url = Bundle.main.url(forResource: "TargetImages", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: TargetImageInfo].self, from: data)
        else { return [:] }
        return decoded
    }()

    private static let imageCache = NSCache<NSString, NSImage>()

    static func info(for designation: String) -> TargetImageInfo? {
        manifest[designation]
    }

    static func nsImage(for designation: String) -> NSImage? {
        if let cached = imageCache.object(forKey: designation as NSString) { return cached }
        guard let info = manifest[designation] else { return nil }
        let name = (info.file as NSString).deletingPathExtension
        let ext = (info.file as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Images"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        imageCache.setObject(image, forKey: designation as NSString)
        return image
    }
}
