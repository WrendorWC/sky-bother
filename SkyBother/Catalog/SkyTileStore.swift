import AppKit
import Foundation

/// The sky as static tiles, cached on disk.
///
/// This replaces asking `hips2fits` to render a bespoke cutout for every view.
/// A cutout takes the server about a second and a half and is never reusable —
/// move the view a pixel and it is worthless — which is why panning and
/// zooming stalled. A tile is a file: it comes back in under half a second,
/// overlapping views share them, and once on disk it is free forever.
///
/// That is also what makes downloading the sky in advance possible at all.
@MainActor
final class SkyTileStore: ObservableObject {
    static let shared = SkyTileStore()

    /// Progress of a bulk download, if one is running.
    @Published private(set) var downloadingOrder: Int?
    @Published private(set) var downloadedTiles = 0
    @Published private(set) var totalTiles = 0
    /// Bytes currently on disk. Refreshed rather than tracked, since tiles
    /// also arrive one at a time from ordinary browsing.
    @Published private(set) var bytesOnDisk: Int64 = 0

    private var downloadTask: Task<Void, Never>?
    private let memory: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 900
        return cache
    }()

    /// Pan-STARRS first, DSS2 behind it.
    ///
    /// This is not about depth, it is about seams. Laying DSS2's tiles down
    /// untouched shows its plates disagreeing about how bright the sky is:
    /// five neighbouring tiles measured here came out at mean brightnesses of
    /// 7.5, 8.6, 19.4, 20.2 and 34.9 — a factor of four and a half, which
    /// reads as a patchwork of diamonds. The same five from Pan-STARRS ran
    /// 35.0 to 39.1, a spread of a tenth, because it is a calibrated CCD
    /// survey rather than a century of scanned photographic plates.
    ///
    /// Pan-STARRS stops at about 30 degrees south, so DSS2 fills in below
    /// that. A southern view is therefore the patchy one, which is the right
    /// way round: it is the only sky there is down there.
    /// DSS2, despite its seams, because Pan-STARRS cannot show a nebula.
    ///
    /// Pan-STARRS is the better-behaved survey by a distance: five
    /// neighbouring tiles measured 35.0 to 39.1 in mean brightness where
    /// DSS2's ran 7.5 to 34.9, so its tiles join invisibly where DSS2's show
    /// every plate boundary. It was wired in, and the joins did disappear.
    ///
    /// What also disappeared was the Flaming Star Nebula. Pan-STARRS images in
    /// g/r/i/z, stretched for point sources, and emission nebulosity barely
    /// registers — the frame came back a rich star field with nothing in it.
    /// The i-r-g composite is no better. For someone photographing nebulae
    /// that is the wrong trade: DSS2's red plates are why its pictures look
    /// like the thing you are going to shoot.
    ///
    /// So the seams stay, and they are the reason the default view is still a
    /// blended cutout rather than tiles.
    private static let primaryMirrors = [
        "https://irsa.ipac.caltech.edu/data/hips/CDS/DSS2/color",
    ]
    private static let fallbackMirrors = [
        "https://skies.esac.esa.int/DSSColor",
        "https://alaskybis.cds.unistra.fr/DSS/DSSColor",
    ]

    private static let userAgent =
        "SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; sky tiles)"

    /// The survey's own maximum. Below this a tile is an upscale of coarser
    /// data, above it there is nothing more to have.
    static let nativeOrder = 9

    // MARK: - Reading

    func cachedImage(order: Int, pixel: Int) -> NSImage? {
        let key = Self.key(order: order, pixel: pixel) as NSString
        if let image = memory.object(forKey: key) { return image }
        guard let url = Self.fileURL(order: order, pixel: pixel),
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data)
        else { return nil }
        memory.setObject(image, forKey: key)
        return image
    }

    /// At most this many tiles are fetched at once.
    ///
    /// Without a cap the browser asked for every tile in view simultaneously,
    /// and each failure was retried on the next redraw, so a view needing
    /// thirty tiles turned into thousands of requests in flight against one
    /// host. Every one then timed out, which triggered more redraws and more
    /// requests: a collapse that fed itself. It logged 4,813 timeouts in under
    /// a minute, and looked for all the world like the server refusing us —
    /// the same URL fetched fine from anywhere else at the time.
    private static let maximumConcurrentFetches = 5
    private var activeFetches = 0
    /// Tiles that just failed, and when it is reasonable to ask again. Retrying
    /// a timeout immediately is what turned a slow server into an unusable one.
    private var retryAfter: [String: Date] = [:]

    /// Fetches a tile, or nil — a missing tile is a gap in the picture, not an
    /// error worth reporting. Nil also means "not now": at capacity, or too
    /// soon after a failure. The caller redraws often enough to ask again.
    func image(order: Int, pixel: Int) async -> NSImage? {
        if let cached = cachedImage(order: order, pixel: pixel) { return cached }
        let key = Self.key(order: order, pixel: pixel)
        if let wait = retryAfter[key], wait > Date() { return nil }
        guard activeFetches < Self.maximumConcurrentFetches else { return nil }

        activeFetches += 1
        defer { activeFetches -= 1 }

        guard let (data, image) = await Self.fetch(order: order, pixel: pixel) else {
            retryAfter[key] = Date().addingTimeInterval(15)
            return nil
        }
        retryAfter[key] = nil
        memory.setObject(image, forKey: key as NSString)
        Self.write(data, order: order, pixel: pixel)
        return image
    }

    private static func fetch(order: Int, pixel: Int) async -> (Data, NSImage)? {
        // Pan-STARRS is tried on its own terms first. Only a definite "not
        // here" moves on to the photographic survey — a timeout or a dropped
        // connection does not.
        //
        // Falling through on *any* failure is what produced a view built from
        // both surveys at once: a handful of Pan-STARRS tiles among a majority
        // of DSS2 ones, which is precisely the patchwork the switch was meant
        // to remove. A slow tile should arrive late, not arrive from somewhere
        // else. It costs a redraw, since a nil is retried on the next pass.
        var sawFailure = false
        for mirror in primaryMirrors {
            if let result = await load(mirror: mirror, order: order, pixel: pixel, timeout: 40) {
                return result.image
            }
            if await !isMissing(mirror: mirror, order: order, pixel: pixel) { sawFailure = true }
        }
        // Every Pan-STARRS mirror said "not here", so this is sky it does not
        // cover — south of about 30 degrees — and the photographic survey is
        // the only thing that has it.
        if sawFailure { return nil }
        for mirror in fallbackMirrors {
            if let result = await load(mirror: mirror, order: order, pixel: pixel, timeout: 20) {
                return result.image
            }
        }
        return nil
    }

    private static func url(mirror: String, order: Int, pixel: Int) -> URL? {
        URL(string: "\(mirror)/Norder\(order)/Dir\((pixel / 10_000) * 10_000)/Npix\(pixel).jpg")
    }

    private static func load(mirror: String, order: Int, pixel: Int,
                             timeout: TimeInterval) async -> (image: (Data, NSImage), Void)? {
        guard let url = url(mirror: mirror, order: order, pixel: pixel) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let image = NSImage(data: data)
        else { return nil }
        return ((data, image), ())
    }

    /// Whether the survey genuinely lacks this tile, as opposed to the request
    /// having failed. Asked with a cheap HEAD so that deciding to fall back
    /// doesn't cost a second download.
    private static func isMissing(mirror: String, order: Int, pixel: Int) async -> Bool {
        guard let url = url(mirror: mirror, order: order, pixel: pixel) else { return true }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return http.statusCode == 404
    }

    // MARK: - Bulk download

    /// Whether a whole order is already on disk, which is what the settings
    /// panel reports rather than a byte count that means nothing on its own.
    func isFullyDownloaded(order: Int) -> Bool {
        tileCount(order: order) >= Healpix.pixelCount(forOrder: order)
    }

    func tileCount(order: Int) -> Int {
        guard let directory = Self.directoryURL(order: order),
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return 0 }
        return files.count
    }

    /// Downloads every tile of an order, and every coarser order beneath it.
    ///
    /// The coarser ones come too because they cost almost nothing — orders 0
    /// to 4 together are under 80 MB — and they are what a zoomed-out view
    /// draws from. Having the fine detail but not the overview would make the
    /// wide shots the slow ones.
    func download(order: Int) {
        guard downloadTask == nil else { return }
        let orders = Array(0...order)
        totalTiles = orders.reduce(0) { $0 + Healpix.pixelCount(forOrder: $1) }
        downloadedTiles = 0
        downloadingOrder = order

        downloadTask = Task { [weak self] in
            for tileOrder in orders {
                let count = Healpix.pixelCount(forOrder: tileOrder)
                var next = 0
                // Several at a time: the cost is almost all latency, and one
                // at a time would make an order-6 download take most of a day.
                // Four is brisk without tipping a free archive into timing out
                // every request, which is what too many at once does.
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<4 {
                        guard next < count else { break }
                        let pixel = next
                        next += 1
                        group.addTask { await self?.downloadOne(order: tileOrder, pixel: pixel) }
                    }
                    while await group.next() != nil {
                        if Task.isCancelled { break }
                        await self?.advance()
                        guard next < count else { continue }
                        let pixel = next
                        next += 1
                        group.addTask { await self?.downloadOne(order: tileOrder, pixel: pixel) }
                    }
                }
                if Task.isCancelled { break }
            }
            await self?.finishDownload()
        }
    }

    private func downloadOne(order: Int, pixel: Int) async {
        guard let url = Self.fileURL(order: order, pixel: pixel),
              !FileManager.default.fileExists(atPath: url.path)
        else { return }
        if let (data, _) = await Self.fetch(order: order, pixel: pixel) {
            Self.write(data, order: order, pixel: pixel)
        }
    }

    private func advance() { downloadedTiles += 1 }

    private func finishDownload() {
        downloadTask = nil
        downloadingOrder = nil
        refreshUsage()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadingOrder = nil
    }

    // MARK: - Disk

    func refreshUsage() {
        let root = Self.rootURL
        Task.detached(priority: .utility) {
            var total: Int64 = 0
            if let root, let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let file as URL in walker {
                    total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
            }
            await MainActor.run { SkyTileStore.shared.bytesOnDisk = total }
        }
    }

    func clear() {
        cancelDownload()
        memory.removeAllObjects()
        if let root = Self.rootURL { try? FileManager.default.removeItem(at: root) }
        bytesOnDisk = 0
    }

    private static func key(order: Int, pixel: Int) -> String { "\(order)/\(pixel)" }

    /// Caches, not Application Support: all of it can be fetched again and
    /// none of it is the user's own data.
    private static var rootURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SkyBother/SkyTiles", isDirectory: true)
    }

    private static func directoryURL(order: Int) -> URL? {
        rootURL?.appendingPathComponent("Norder\(order)", isDirectory: true)
    }

    private static func fileURL(order: Int, pixel: Int) -> URL? {
        directoryURL(order: order)?.appendingPathComponent("\(pixel).jpg")
    }

    private static func write(_ data: Data, order: Int, pixel: Int) {
        guard let directory = directoryURL(order: order),
              let file = fileURL(order: order, pixel: pixel) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

extension SkyTileStore {
    /// What a given order costs, from tile sizes measured against the real
    /// survey rather than guessed: about 8 KB a tile at order 3 rising to
    /// roughly 50 KB by order 6 and above, times `12 · 4^order` tiles.
    static func estimatedBytes(forOrder order: Int) -> Int64 {
        // Measured against the survey rather than guessed. Tile size varies a
        // lot with how crowded the field is — a Milky Way tile compresses to
        // three times a polar one — so these are averages over sampled tiles.
        let perTile: [Int] = [4_000, 5_000, 6_000, 8_000, 21_000, 37_000, 46_000, 50_000, 50_000, 50_000]
        var total: Int64 = 0
        for tileOrder in 0...min(order, 9) {
            total += Int64(Healpix.pixelCount(forOrder: tileOrder)) * Int64(perTile[tileOrder])
        }
        return total
    }

    /// How sharp an order is, in arcseconds per pixel — the survey's native
    /// 0.8″ doubling with every order below 9.
    static func resolutionArcseconds(forOrder order: Int) -> Double {
        0.8052 * pow(2, Double(nativeOrder - order))
    }

    static let attribution = "Digitized Sky Survey (STScI/NASA), colour by CDS"
}
