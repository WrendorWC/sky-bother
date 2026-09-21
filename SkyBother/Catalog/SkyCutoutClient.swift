import AppKit
import Foundation

/// One square-on patch of real sky: where to centre it, how wide a piece of
/// sky it covers, and how many pixels to render that into.
///
/// Rounded on construction so that a view resizing by a point, or a
/// floating-point coordinate arriving a hair different, doesn't miss the cache
/// and fetch the same picture again.
struct SkyCutout: Hashable, Sendable {
    var rightAscensionDegrees: Double
    var declinationDegrees: Double
    var widthDegrees: Double
    var pixelWidth: Int
    var pixelHeight: Int

    init(rightAscensionDegrees: Double, declinationDegrees: Double,
         widthDegrees: Double, pixelWidth: Int, pixelHeight: Int) {
        self.rightAscensionDegrees = (rightAscensionDegrees * 1000).rounded() / 1000
        self.declinationDegrees = (declinationDegrees * 1000).rounded() / 1000
        self.widthDegrees = (widthDegrees * 1000).rounded() / 1000
        // To the nearest 64 pixels: a window dragged a few points wider is the
        // same picture, and re-fetching it on every frame of a drag would be
        // both slow and rude to a service that costs nothing to use.
        self.pixelWidth = max(64, (pixelWidth / 64) * 64)
        self.pixelHeight = max(64, (pixelHeight / 64) * 64)
    }

    /// Stable, readable, and safe as a filename.
    var cacheKey: String {
        String(format: "dss2_%.3f_%.3f_%.3f_%dx%d",
               rightAscensionDegrees, declinationDegrees, widthDegrees, pixelWidth, pixelHeight)
    }
}

/// Real sky imagery for a patch of sky, from the Digitized Sky Survey.
///
/// The catalogue gives a target's angular size as a single ellipse, which is
/// what the framing preview used to draw over an invented star field. That is
/// honest about scale and misleading about everything else: it says nothing
/// about the nebulosity that spills past the catalogued extent, the companion
/// galaxy just outside it, or how crowded the field is — all of which decide
/// whether a target is worth pointing at.
///
/// Images come from `hips2fits`, which renders a cutout from a HiPS survey
/// (the IVOA's all-sky tiled image standard) to an exact centre, field of view
/// and pixel size in a single request. Doing the projection server-side is the
/// whole reason this is a small piece of code rather than a HEALPix
/// implementation.
struct SkyCutoutClient: Sendable {
    static let shared = SkyCutoutClient()

    /// DSS2 colour is the only all-sky option, so every target gets a picture
    /// and none ever falls back to a blank. Deeper surveys — PanSTARRS, SDSS —
    /// are prettier where they reach but leave holes, and a preview that
    /// sometimes has no image is worse than one that is always a little flat.
    private static let survey = "CDS/P/DSS2/color"

    /// `alasky` is the service's documented primary and `alaskybis` its
    /// mirror, but the primary refuses connections from some networks — it
    /// times out here — so the mirror is tried first and the primary kept as
    /// the fallback rather than the other way round.
    private static let endpoints = [
        "https://alaskybis.cds.unistra.fr/hips-image-services/hips2fits",
        "https://alasky.cds.unistra.fr/hips-image-services/hips2fits",
    ]

    private static let userAgent =
        "SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; sky cutouts)"

    /// Credit required by the survey's own terms, shown wherever its imagery
    /// is. DSS is free for non-commercial and educational use on condition the
    /// source is acknowledged.
    static let attribution = "Digitized Sky Survey (STScI/NASA), colour by CDS"
    static let attributionURL = "https://archive.stsci.edu/dss/copyright.html"

    private static let memoryCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 60
        return cache
    }()

    /// Already in hand, if it is — so a view can draw the real sky on its
    /// first pass instead of flashing the placeholder and replacing it.
    func cachedImage(for cutout: SkyCutout) -> NSImage? {
        if let image = Self.memoryCache.object(forKey: cutout.cacheKey as NSString) { return image }
        guard let url = Self.fileURL(for: cutout),
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data)
        else { return nil }
        Self.memoryCache.setObject(image, forKey: cutout.cacheKey as NSString)
        return image
    }

    /// Fetches the patch, or returns nil rather than throwing: a missing sky
    /// image is a cosmetic disappointment, not an error worth a banner. The
    /// caller keeps drawing what it drew before.
    /// No more than this many renders in flight at once. The service is
    /// quick in parallel but each request is expensive, and letting an
    /// unbounded number queue means they time out and get retried, which
    /// makes the queue longer still.
    private static let gate = AsyncGate(limit: 4)

    func image(for cutout: SkyCutout) async -> NSImage? {
        if let cached = cachedImage(for: cutout) { return cached }
        await Self.gate.enter()
        defer { Task { await Self.gate.leave() } }

        for endpoint in Self.endpoints {
            guard var components = URLComponents(string: endpoint) else { continue }
            components.queryItems = [
                URLQueryItem(name: "hips", value: Self.survey),
                URLQueryItem(name: "ra", value: String(cutout.rightAscensionDegrees)),
                URLQueryItem(name: "dec", value: String(cutout.declinationDegrees)),
                URLQueryItem(name: "fov", value: String(cutout.widthDegrees)),
                URLQueryItem(name: "width", value: String(cutout.pixelWidth)),
                URLQueryItem(name: "height", value: String(cutout.pixelHeight)),
                URLQueryItem(name: "format", value: "jpg"),
            ]
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let image = NSImage(data: data)
            else { continue }

            Self.memoryCache.setObject(image, forKey: cutout.cacheKey as NSString)
            Self.write(data, for: cutout)
            return image
        }
        return nil
    }

    // MARK: - Disk cache

    /// Caches, not Application Support: every one of these can be fetched
    /// again, and none of it is the user's own data.
    private static var directoryURL: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("SkyBother/SkyCutouts", isDirectory: true)
    }

    private static func fileURL(for cutout: SkyCutout) -> URL? {
        directoryURL?.appendingPathComponent(cutout.cacheKey).appendingPathExtension("jpg")
    }

    private static func write(_ data: Data, for cutout: SkyCutout) {
        guard let directoryURL, let fileURL = fileURL(for: cutout) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        prune(in: directoryURL)
    }

    /// Keeps the cache from growing without limit — browsing the whole
    /// catalogue at several rigs would otherwise leave a few hundred megabytes
    /// behind for nobody's benefit. Oldest first, since the target you last
    /// looked at is the one you are most likely to look at again.
    private static func prune(in directoryURL: URL, keeping limit: Int = 400) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: keys), files.count > limit
        else { return }

        let sorted = files.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return leftDate < rightDate
        }
        for file in sorted.prefix(files.count - limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}


/// A plain counting semaphore for async callers.
actor AsyncGate {
    private let limit: Int
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func enter() async {
        if active < limit { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if let next = waiting.first {
            waiting.removeFirst()
            next.resume()
        } else {
            active = max(0, active - 1)
        }
    }
}
