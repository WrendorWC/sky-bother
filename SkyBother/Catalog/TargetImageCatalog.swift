import AppKit
import Foundation

/// One entry from `TargetImages.json` — a thumbnail pulled from Wikipedia for a
/// catalog target, keyed by designation.
struct TargetImageInfo: Decodable, Sendable {
    var file: String
    /// Absent for sky-survey thumbnails, whose credit is the survey's own and
    /// is stated once rather than per target.
    var sourceTitle: String?
    var sourceURL: String?
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

    /// Sky-survey thumbnails for the targets Wikipedia has no photo of —
    /// roughly 600 of the ~1150 in the catalogue. Built by
    /// `Scripts/build_sky_thumbnails.py`; see `skyThumbnail(for:)`.
    static let skyManifest: [String: TargetImageInfo] = {
        guard let url = Bundle.main.url(forResource: "SkyThumbnails", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: TargetImageInfo].self, from: data)
        else { return [:] }
        return decoded
    }()

    private static let skyCache = NSCache<NSString, NSImage>()

    static func hasPhoto(for designation: String) -> Bool { manifest[designation] != nil }

    /// A real photograph of this target's patch of sky, from the Digitized
    /// Sky Survey. Second choice behind a Wikipedia photo, which is a colour
    /// image from a real telescope and simply looks better than a
    /// photographic-plate scan — but far better than the "No Photo Available"
    /// placeholder these replace, which told you nothing at all.
    static func skyThumbnail(for designation: String) -> NSImage? {
        if let cached = skyCache.object(forKey: designation as NSString) { return cached }
        guard let info = skyManifest[designation] else { return nil }
        let name = (info.file as NSString).deletingPathExtension
        let ext = (info.file as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "SkyThumbnails"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        skyCache.setObject(image, forKey: designation as NSString)
        return image
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
