import CoreGraphics
import Foundation
import ImageIO

enum NightLightsError: LocalizedError {
    case noUsableImagery

    var errorDescription: String? {
        switch self {
        case .noUsableImagery: return "NASA's night-lights imagery couldn't be loaded for this area."
        }
    }
}

/// Upward night-time radiance around a site, in nW/(cm² sr), on a regular
/// latitude/longitude grid. Row 0 is the northern edge.
struct RadianceGrid: Codable, Sendable {
    var south: Double
    var west: Double
    var north: Double
    var east: Double
    var width: Int
    var height: Int
    var values: [Float]
    var retrievedAt: Date

    var centerLatitude: Double { (south + north) / 2 }
    var centerLongitude: Double { (west + east) / 2 }

    /// Ground size of one pixel. Longitude degrees are converted at the grid's
    /// centre latitude, which is accurate to a few percent across a grid this
    /// size — well inside the uncertainty of everything downstream of it.
    var pixelHeightKilometers: Double { (north - south) / Double(height) * DarkSkyGeometry.kilometersPerDegree }
    var pixelWidthKilometers: Double {
        (east - west) / Double(width) * DarkSkyGeometry.kilometersPerDegree * max(cosDeg(centerLatitude), 0.2)
    }
}

/// NASA's Black Marble daily radiance (VNP46A2: VIIRS Day/Night Band,
/// gap-filled and BRDF-corrected, so moonlight is already taken out), pulled
/// through the same GIBS Worldview Snapshot service as the cloud map — free,
/// no API key, no account, public domain.
///
/// GIBS only serves this layer as a rendered image, but the rendering is a
/// published greyscale colour map, so each grey level decodes straight back
/// to a radiance band (`grayLevels` / `radianceMidpoints`, generated from
/// https://gibs.earthdata.nasa.gov/colormaps/v1.3/VIIRS_DayNightBand_At_Sensor_Radiance.xml).
///
/// A single day is noisy — cloud-gap filling leaves visible blotches — so the
/// grid is the per-pixel median of several dates spread across the past year.
/// Spreading them out also rides over this product's summer gap at high
/// latitudes, where it never gets dark enough for a usable night pass.
struct NightLightsClient: Sendable {

    private static let userAgent = "SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; night lights)"
    private static let layer = "VIIRS_SNPP_GapFilled_BRDF_Corrected_DayNightBand_Radiance"

    /// Half the grid's height in degrees, about 140 km. The widest search is
    /// 50 km, and sky glow still arrives from cities tens of kilometres beyond
    /// that, so the grid has to reach well past the search itself.
    static let halfSpanDegrees = 1.25
    /// About 430 m per pixel at this span — close to the product's native
    /// 500 m, so asking for more gains nothing.
    private static let pixelSize = 640
    private static let sampleDates = 6
    private static let daysBetweenSamples = 61
    /// GIBS takes a few days to publish each daily composite.
    private static let newestSampleAgeDays = 10
    /// Fewer than this many usable dates and the median is too noisy to trust.
    private static let minimumUsableDates = 2
    /// City lights change over years, not weeks.
    private static let cacheLifetime: TimeInterval = 60 * 86400

    /// Fetches (or loads from cache) the grid centred near a site. The centre
    /// is snapped to a 0.1° lattice so small edits to a site's coordinates
    /// reuse the same cached grid; the offset that introduces is a few
    /// kilometres against a grid ~280 km across.
    func grid(latitude: Double, longitude: Double) async throws -> RadianceGrid {
        let centerLatitude = (latitude * 10).rounded() / 10
        let centerLongitude = (longitude * 10).rounded() / 10
        let cacheURL = Self.cacheURL(latitude: centerLatitude, longitude: centerLongitude)

        if let cacheURL, let cached = Self.loadCache(from: cacheURL),
           Date().timeIntervalSince(cached.retrievedAt) < Self.cacheLifetime {
            return cached
        }

        let latSpan = Self.halfSpanDegrees
        // Widened by 1/cos(latitude) so pixels stay roughly square on the ground.
        let lonSpan = latSpan / max(cosDeg(centerLatitude), 0.3)
        let south = max(centerLatitude - latSpan, -90)
        let north = min(centerLatitude + latSpan, 90)
        let west = centerLongitude - lonSpan
        let east = centerLongitude + lonSpan

        let now = Date()
        let dates = (0..<Self.sampleDates).map { index in
            now.addingTimeInterval(-Double(Self.newestSampleAgeDays + index * Self.daysBetweenSamples) * 86400)
        }

        let frames: [[Float]] = await withTaskGroup(of: [Float]?.self) { group in
            for date in dates {
                group.addTask {
                    await Self.fetchFrame(date: date, south: south, west: west, north: north, east: east)
                }
            }
            var collected: [[Float]] = []
            for await frame in group {
                if let frame { collected.append(frame) }
            }
            return collected
        }

        guard frames.count >= Self.minimumUsableDates else { throw NightLightsError.noUsableImagery }

        let pixelCount = Self.pixelSize * Self.pixelSize
        var values = [Float](repeating: 0, count: pixelCount)
        var samples: [Float] = []
        samples.reserveCapacity(frames.count)
        for index in 0..<pixelCount {
            samples.removeAll(keepingCapacity: true)
            for frame in frames where !frame[index].isNaN {
                samples.append(frame[index])
            }
            values[index] = Self.median(&samples)
        }

        let grid = RadianceGrid(south: south, west: west, north: north, east: east,
                                width: Self.pixelSize, height: Self.pixelSize,
                                values: values, retrievedAt: now)
        if let cacheURL { Self.saveCache(grid, to: cacheURL) }
        return grid
    }

    // MARK: - Fetching and decoding

    /// One date's frame as radiance, NaN where GIBS has no data. Nil if the
    /// request failed or the frame is empty — GIBS answers a date inside a
    /// data gap with a tiny, fully transparent PNG rather than an error.
    private static func fetchFrame(date: Date, south: Double, west: Double, north: Double, east: Double) async -> [Float]? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var components = URLComponents(string: "https://wvs.earthdata.nasa.gov/api/v1/snapshot")
        components?.queryItems = [
            URLQueryItem(name: "REQUEST", value: "GetSnapshot"),
            URLQueryItem(name: "LAYERS", value: layer),
            URLQueryItem(name: "CRS", value: "EPSG:4326"),
            URLQueryItem(name: "TIME", value: formatter.string(from: date)),
            URLQueryItem(name: "BBOX", value: "\(south),\(west),\(north),\(east)"),
            URLQueryItem(name: "FORMAT", value: "image/png"),
            URLQueryItem(name: "WIDTH", value: String(pixelSize)),
            URLQueryItem(name: "HEIGHT", value: String(pixelSize))
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        // Fresh session, as in CloudMapClient — see OpenMeteoClient.fetch.
        let session = URLSession(configuration: .ephemeral)
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { return nil }

        return decodeRadiance(data)
    }

    private static func decodeRadiance(_ data: Data) -> [Float]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let width = pixelSize
        let height = pixelSize
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var values = [Float](repeating: .nan, count: width * height)
        var opaque = 0
        for index in 0..<(width * height) {
            let alpha = rgba[index * 4 + 3]
            guard alpha > 127 else { continue }
            opaque += 1
            values[index] = radiance(forGray: rgba[index * 4])
        }
        // A frame that's mostly no-data is a gap day, not a real observation.
        guard opaque > width * height / 4 else { return nil }
        return values
    }

    /// Linear interpolation between colour-map bands, since a resampled
    /// snapshot can land a pixel between two of the published grey levels.
    private static func radiance(forGray gray: UInt8) -> Float {
        guard gray > grayLevels[0] else {
            return Float(radianceMidpoints[0] * Double(gray) / Double(grayLevels[0]))
        }
        var low = 0
        var high = grayLevels.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if grayLevels[middle] <= gray { low = middle } else { high = middle }
        }
        if grayLevels[high] <= gray { return Float(radianceMidpoints[high]) }
        let span = Double(grayLevels[high]) - Double(grayLevels[low])
        let t = (Double(gray) - Double(grayLevels[low])) / span
        return Float(radianceMidpoints[low] + t * (radianceMidpoints[high] - radianceMidpoints[low]))
    }

    private static func median(_ samples: inout [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        samples.sort()
        let middle = samples.count / 2
        return samples.count % 2 == 1 ? samples[middle] : (samples[middle - 1] + samples[middle]) / 2
    }

    // MARK: - Cache

    private static func cacheURL(latitude: Double, longitude: Double) -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let name = String(format: "nightlights_%+.1f_%+.1f.json", latitude, longitude)
        return base.appendingPathComponent("SkyBother", isDirectory: true).appendingPathComponent(name)
    }

    private static func loadCache(from url: URL) -> RadianceGrid? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RadianceGrid.self, from: data)
    }

    private static func saveCache(_ grid: RadianceGrid, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(grid).write(to: url, options: .atomic)
        } catch {
            NSLog("Sky Bother: could not cache night lights — \(error.localizedDescription)")
        }
    }

    // MARK: - Colour map

    // The colour map's saturation point is 38.2 nW/(cm² sr); anything brighter
    // renders pure white. The top band is given 60 — a deliberately modest
    // stand-in for a city core, which undercounts the brightest downtowns but
    // keeps them from reading as mere suburbs.
    private static let grayLevels: [UInt8] = [
        7, 13, 19, 24, 29, 33, 37, 41, 45, 48, 52, 55, 58, 61, 64, 67,
        69, 72, 74, 77, 79, 81, 83, 85, 87, 89, 91, 93, 95, 96, 98, 100,
        101, 103, 105, 106, 108, 109, 111, 112, 113, 115, 116, 117, 118, 120, 121, 122,
        123, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139,
        140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155,
        156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171,
        172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187,
        188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203,
        204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219,
        220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235,
        236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251,
        252, 253, 254, 255,
    ]

    private static let radianceMidpoints: [Double] = [
        0.05, 0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95,
        1.05, 1.15, 1.25, 1.35, 1.45, 1.55, 1.65, 1.75, 1.85, 1.95,
        2.05, 2.15, 2.25, 2.35, 2.45, 2.55, 2.65, 2.75, 2.85, 2.95,
        3.05, 3.15, 3.25, 3.35, 3.45, 3.55, 3.65, 3.75, 3.85, 3.95,
        4.05, 4.15, 4.25, 4.35, 4.45, 4.55, 4.65, 4.75, 4.85, 4.95,
        5.05, 5.15, 5.25, 5.35, 5.45, 5.55, 5.65, 5.75, 5.85, 5.95,
        6.05, 6.15, 6.25, 6.35, 6.45, 6.55, 6.65, 6.75, 6.9, 7.05,
        7.15, 7.25, 7.35, 7.5, 7.65, 7.75, 7.85, 8.0, 8.15, 8.25,
        8.4, 8.55, 8.7, 8.85, 8.95, 9.1, 9.25, 9.4, 9.55, 9.7,
        54.9, 10.05, 10.2, 10.35, 10.5, 10.7, 10.9, 11.05, 11.2, 11.4,
        11.6, 11.75, 11.9, 12.1, 12.3, 12.5, 12.7, 12.9, 13.1, 13.3,
        13.5, 13.75, 14.0, 14.2, 14.4, 14.6, 14.85, 15.1, 15.3, 15.55,
        15.8, 16.05, 16.3, 16.55, 16.8, 17.05, 17.35, 17.6, 17.85, 18.15,
        18.45, 18.7, 18.95, 19.25, 19.55, 19.85, 20.15, 20.5, 20.85, 21.15,
        21.45, 21.75, 22.1, 22.45, 22.8, 23.15, 23.5, 23.85, 24.2, 24.6,
        24.95, 25.3, 25.7, 26.1, 26.5, 26.9, 27.3, 27.7, 28.1, 28.55,
        29.0, 29.4, 29.85, 30.3, 30.75, 31.25, 31.7, 32.15, 32.65, 33.15,
        33.65, 34.15, 34.65, 35.2, 35.75, 36.25, 36.8, 37.35, 37.9, 60.0,
    ]
}
