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

    /// IRSA first: it is in the US, serves these as plain static files, and
    /// answers in about a quarter of a second — several times quicker than
    /// either European mirror from here. The others are fallbacks, and the
    /// CDS primary is left out entirely because it refuses connections from
    /// some networks (see `SkyCutoutClient`).
    private static let mirrors = [
        "https://irsa.ipac.caltech.edu/data/hips/CDS/DSS2/color",
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

    /// Fetches a tile, or nil — a missing tile is a gap in the picture, not an
    /// error worth reporting. The survey genuinely has holes at high orders.
    func image(order: Int, pixel: Int) async -> NSImage? {
        if let cached = cachedImage(order: order, pixel: pixel) { return cached }
        guard let (data, image) = await Self.fetch(order: order, pixel: pixel) else { return nil }
        memory.setObject(image, forKey: Self.key(order: order, pixel: pixel) as NSString)
        Self.write(data, order: order, pixel: pixel)
        return image
    }

    private static func fetch(order: Int, pixel: Int) async -> (Data, NSImage)? {
        for mirror in mirrors {
            let directory = (pixel / 10_000) * 10_000
            guard let url = URL(string: "\(mirror)/Norder\(order)/Dir\(directory)/Npix\(pixel).jpg")
            else { continue }
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let image = NSImage(data: data)
            else { continue }
            return (data, image)
        }
        return nil
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
                // Six is brisk without being a nuisance to a free archive.
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<6 {
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
}
