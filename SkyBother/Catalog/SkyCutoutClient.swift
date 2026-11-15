import AppKit
import Foundation
import ImageIO

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
        // same picture, and redrawing it on every frame of a drag would be
        // slow and fetch tiles for nothing.
        //
        // Capped as well. The survey is shallow, so beyond this there's no
        // more detail to fetch, only more pixels and more tiles. The image is
        // drawn to fit its rectangle, so a smaller one scales up.
        let longest = max(pixelWidth, pixelHeight, 1)
        let shrink = min(1, Double(Self.maximumPixels) / Double(longest))
        self.pixelWidth = max(64, Int((Double(pixelWidth) * shrink / 64).rounded()) * 64)
        self.pixelHeight = max(64, Int((Double(pixelHeight) * shrink / 64).rounded()) * 64)
    }

    /// Longest side ever requested.
    static let maximumPixels = 1600

    /// Stable, readable, and safe as a filename.
    var cacheKey: String {
        String(format: "dss2_%.3f_%.3f_%.3f_%dx%d",
               rightAscensionDegrees, declinationDegrees, widthDegrees, pixelWidth, pixelHeight)
    }
}

/// Real sky imagery for a patch of sky, from the Digitized Sky Survey.
///
/// A real picture shows what a catalogued size can't: nebulosity past the
/// listed extent, neighbours just outside it, and how crowded the field is —
/// all of which decide whether a target is worth pointing at.
///
/// Images are drawn here from the survey's HiPS tiles — plain JPEGs any
/// mirror can serve — rather than asked of a server that renders cutouts.
/// That server, CDS's `hips2fits`, went down with the rest of CDS in November
/// 2026 and left every preview blank; tiles come from IRSA's copy of the
/// survey, with CDS's own kept as the fallback. See `HiPSCutoutRenderer`.
struct SkyCutoutClient: Sendable {
    static let shared = SkyCutoutClient()

    /// DSS2 colour is the only all-sky option, so every target gets a picture
    /// and none ever falls back to a blank. Deeper surveys — PanSTARRS, SDSS —
    /// are prettier where they reach but leave holes, and a preview that
    /// sometimes has no image is worse than one that is always a little flat.
    ///
    /// The mirrors, in order. IRSA (NASA/Caltech) mirrors CDS's survey tile
    /// for tile.
    static let surveys = [
        "https://irsa.ipac.caltech.edu/data/hips/CDS/DSS2/color",
        "https://alasky.cds.unistra.fr/DSS/DSSColor",
    ]

    private static let userAgent =
        "SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; sky cutouts)"

    /// Credit required by the survey's own terms, shown wherever its imagery
    /// is. DSS is free for non-commercial and educational use on condition the
    /// source is acknowledged.
    static let attribution = "Digitized Sky Survey (STScI/NASA), colour by CDS, via IRSA"
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

    /// No more than this many pictures drawn at once: each wants a dozen or
    /// two tiles, and letting an unbounded number queue means they time out
    /// and get retried, which makes the queue longer still.
    private static let gate = AsyncGate(limit: 4)
    private static let health = EndpointHealth(cooldown: 180)
    private static let tiles = TileStore(limit: 40)

    /// Draws the patch, or returns nil rather than throwing: a missing sky
    /// image is a cosmetic disappointment, not an error worth a banner. The
    /// caller keeps drawing what it drew before.
    func image(for cutout: SkyCutout) async -> NSImage? {
        if let cached = cachedImage(for: cutout) { return cached }
        await Self.gate.enter()
        defer { Task { await Self.gate.leave() } }

        let renderer = HiPSCutoutRenderer(
            rightAscension: cutout.rightAscensionDegrees, declination: cutout.declinationDegrees,
            fieldOfView: cutout.widthDegrees, width: cutout.pixelWidth, height: cutout.pixelHeight)

        var tiles: [Int: TilePixels] = [:]
        var missing = false
        await withTaskGroup(of: (Int, TilePixels?).self) { group in
            for npix in renderer.neededTiles {
                group.addTask { (npix, await Self.tile(order: renderer.order, npix: npix)) }
            }
            for await (npix, pixels) in group {
                if let pixels { tiles[npix] = pixels } else { missing = true }
            }
        }
        // Not one tile arrived: no mirror is answering. Say so rather than
        // show a black square.
        guard !tiles.isEmpty, !Task.isCancelled,
              let picture = renderer.render(tiles: tiles),
              let data = NSBitmapImageRep(cgImage: picture)
                .representation(using: .jpeg, properties: [.compressionFactor: 0.88]),
              let image = NSImage(data: data)
        else { return nil }

        Self.memoryCache.setObject(image, forKey: cutout.cacheKey as NSString)
        // Kept on disk only if whole: a gap left by a mirror that didn't
        // answer would otherwise stay there for good.
        if !missing { Self.write(data, for: cutout) }
        return image
    }

    /// One tile's pixels, from memory or the first mirror that answers. A
    /// mirror that fails to is skipped for a while, so that when it's down
    /// every tile doesn't wait out its own timeout before the next is tried.
    private static func tile(order: Int, npix: Int) async -> TilePixels? {
        let key = "\(order)/\(npix)"
        if let hit = await tiles.pixels(for: key) { return hit }
        let path = "Norder\(order)/Dir\(npix / 10000 * 10000)/Npix\(npix).jpg"
        for survey in surveys {
            guard await health.isUp(survey), let url = URL(string: "\(survey)/\(path)") else { continue }
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            let fetched: (Data, URLResponse)
            do {
                fetched = try await URLSession.shared.data(for: request)
            } catch {
                // Our own cancellation says nothing about the server.
                if !Task.isCancelled { await health.markDown(survey) }
                continue
            }
            guard let http = fetched.1 as? HTTPURLResponse else { continue }
            // A tile the survey doesn't have is missing from every mirror.
            if http.statusCode == 404 { return nil }
            guard http.statusCode == 200, let pixels = TilePixels(jpeg: fetched.0) else { continue }
            await tiles.store(pixels, for: key)
            return pixels
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


/// Which servers recently failed to answer, so callers can skip them until a
/// cooldown has passed instead of each waiting out its own timeout.
actor EndpointHealth {
    private let cooldown: TimeInterval
    private var downUntil: [String: Date] = [:]

    init(cooldown: TimeInterval) { self.cooldown = cooldown }

    func isUp(_ endpoint: String) -> Bool {
        guard let until = downUntil[endpoint] else { return true }
        if Date() >= until { downUntil[endpoint] = nil; return true }
        return false
    }

    func markDown(_ endpoint: String) {
        downUntil[endpoint] = Date().addingTimeInterval(cooldown)
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


// MARK: - Drawing a cutout from HiPS tiles

/// A gnomonic (TAN) picture of the sky drawn from a HiPS survey's tiles —
/// the job `hips2fits` did server-side. A HiPS survey is the sky cut into
/// HEALPix cells: at order k there are 12·4^k tiles, each 512×512 pixels of
/// order k+9. For each pixel of the picture we find the sky position it looks
/// at, which tile and which pixel of that tile holds it, and sample there.
///
/// The same as the web's `hips.js`; the tile layout was checked against NASA
/// SkyView pictures of the same fields, both polar caps included.
struct HiPSCutoutRenderer: Sendable {
    static let tileSize = 512
    private static let tileBits = 9
    private static let maximumOrder = 9
    /// Degrees per pixel at the deepest tiles.
    private static let deepestPixel = 2.236e-4

    let rightAscension: Double
    let declination: Double
    /// Degrees along the longer side.
    let fieldOfView: Double
    let width: Int
    let height: Int
    /// The tile order whose pixels are about the size of the picture's:
    /// finer would fetch detail that's thrown away, coarser would blur it.
    let order: Int
    /// Where every pixel lands, row by row.
    private let spots: [Spot]

    struct Spot: Sendable {
        var npix: Int
        var column: Double
        var row: Double
    }

    init(rightAscension: Double, declination: Double, fieldOfView: Double, width: Int, height: Int) {
        self.rightAscension = rightAscension
        self.declination = declination
        self.fieldOfView = fieldOfView
        self.width = width
        self.height = height
        let perPixel = fieldOfView / Double(max(width, height))
        let k = Self.maximumOrder - Int((log2(perPixel / Self.deepestPixel)).rounded())
        order = min(Self.maximumOrder, max(0, k))

        // North up, east left.
        let d2r = Double.pi / 180
        let a0 = rightAscension * d2r, d0 = declination * d2r
        let sinD0 = sin(d0), cosD0 = cos(d0)
        let scale = 2 * tan(fieldOfView * d2r / 2) / Double(max(width, height))
        var spots: [Spot] = []
        spots.reserveCapacity(width * height)
        for j in 0..<height {
            let eta = (Double(height - 1) / 2 - Double(j)) * scale
            for i in 0..<width {
                let xi = (Double(width - 1) / 2 - Double(i)) * scale
                let den = cosD0 - eta * sinD0
                let ra = (a0 + atan2(xi, den)) / d2r
                let dec = atan2(sinD0 + eta * cosD0, hypot(xi, den)) / d2r
                spots.append(Self.locate(ra: ra, dec: dec, order: order))
            }
        }
        self.spots = spots
    }

    var neededTiles: Set<Int> { Set(spots.map(\.npix)) }

    /// The picture, black wherever a tile is missing.
    func render(tiles: [Int: TilePixels]) -> CGImage? {
        let size = Self.tileSize
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for (index, spot) in spots.enumerated() {
            let o = index * 4
            out[o + 3] = 255
            guard let tile = tiles[spot.npix] else { continue }
            // Bilinear within the tile; at its edge, the edge pixel.
            let cx = min(Double(size - 1), max(0, spot.column - 0.5))
            let cy = min(Double(size - 1), max(0, spot.row - 0.5))
            let x0 = Int(cx), y0 = Int(cy)
            let x1 = min(size - 1, x0 + 1), y1 = min(size - 1, y0 + 1)
            let fx = cx - Double(x0), fy = cy - Double(y0)
            let i00 = (y0 * size + x0) * 4, i10 = (y0 * size + x1) * 4
            let i01 = (y1 * size + x0) * 4, i11 = (y1 * size + x1) * 4
            tile.bytes.withUnsafeBufferPointer { p in
                for c in 0..<3 {
                    let top = Double(p[i00 + c]) * (1 - fx) + Double(p[i10 + c]) * fx
                    let bottom = Double(p[i01 + c]) * (1 - fx) + Double(p[i11 + c]) * fx
                    out[o + c] = UInt8(max(0, min(255, (top * (1 - fy) + bottom * fy).rounded())))
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Which tile holds a position, and where in that tile's image (column,
    /// row from the top), fractional.
    static func locate(ra: Double, dec: Double, order: Int) -> Spot {
        let nside = Double(1 << (order + tileBits))
        var (face, x, y) = toFace(ra: ra, dec: dec, nside: nside)
        x = min(nside - 1e-6, max(0, x))
        y = min(nside - 1e-6, max(0, y))
        let size = Double(tileSize)
        let tx = Int(x / size), ty = Int(y / size)
        let npix = face * (1 << (2 * order)) + interleave(tx, ty)
        // In a HiPS tile image, x runs down the rows and y along the columns.
        return Spot(npix: npix, column: y - Double(ty) * size, row: x - Double(tx) * size)
    }

    /// HEALPix: a sky position to (face, x, y) at nside, x and y continuous
    /// in [0, nside) within the face. The standard ang2pix, kept fractional
    /// so that pixels can be interpolated.
    static func toFace(ra: Double, dec: Double, nside: Double) -> (Int, Double, Double) {
        let z = sin(dec * .pi / 180)
        let za = abs(z)
        var tt = (ra.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 90
        if tt >= 4 { tt = 0 }
        if za <= 2.0 / 3 {
            let t1 = nside * (0.5 + tt), t2 = nside * z * 0.75
            let jp = t1 - t2, jm = t1 + t2
            let ifp = Int(floor(jp / nside)), ifm = Int(floor(jm / nside))
            let face = ifp == ifm ? (ifp % 4) + 4 : ifp < ifm ? ifp % 4 : (ifm % 4) + 8
            return (face, jm - floor(jm / nside) * nside, nside - (jp - floor(jp / nside) * nside))
        }
        let ntt = min(3, Int(tt))
        let tp = tt - Double(ntt)
        let tmp = nside * sqrt(3 * (1 - za))
        let jp = min(nside, tp * tmp), jm = min(nside, (1 - tp) * tmp)
        return z > 0 ? (ntt, nside - jm, nside - jp) : (ntt + 8, jp, jm)
    }

    /// HEALPix's nested numbering within a face: x's bits in the even
    /// places, y's in the odd.
    private static func interleave(_ x: Int, _ y: Int) -> Int {
        var n = 0
        for b in 0..<30 { n |= ((x >> b) & 1) << (2 * b) | ((y >> b) & 1) << (2 * b + 1) }
        return n
    }
}

/// A decoded tile: 512×512 RGBA bytes.
struct TilePixels: Sendable {
    let bytes: [UInt8]

    init?(jpeg: Data) {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let size = HiPSCutoutRenderer.tileSize
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }
        self.bytes = bytes
    }
}

/// Recently used tiles, so neighbouring views don't fetch them again. A tile
/// is a megabyte decoded; forty is a few views' worth.
actor TileStore {
    private let limit: Int
    private var order: [String] = []
    private var pixels: [String: TilePixels] = [:]

    init(limit: Int) { self.limit = limit }

    func pixels(for key: String) -> TilePixels? {
        guard let hit = pixels[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return hit
    }

    func store(_ tile: TilePixels, for key: String) {
        if pixels[key] == nil { order.append(key) }
        pixels[key] = tile
        while order.count > limit { pixels[order.removeFirst()] = nil }
    }
}
