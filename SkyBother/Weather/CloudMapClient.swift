import AppKit
import Foundation

enum CloudMapError: LocalizedError {
    case outOfCoverage
    case noRecentImagery

    var errorDescription: String? {
        switch self {
        case .outOfCoverage: return "No satellite cloud imagery is available for this location."
        case .noRecentImagery: return "No recent satellite imagery could be found."
        }
    }
}

/// A regional satellite snapshot centred on the site, pulled from NASA's
/// GIBS Worldview Snapshot service — free, no API key, no account, same
/// design bar as the weather clients. The layer is GOES-East's GeoColor
/// product: a blend of true-colour daytime imagery with infrared-derived
/// cloud texture and city lights at night, so unlike a plain visible-light
/// photo it's still useful after dark, which is when this app matters most.
///
/// GOES-East only sees the Americas and the surrounding oceans — outside
/// that footprint the frame is reliably solid black, so `isAvailable`
/// short-circuits rather than spending a request finding that out.
struct CloudMapClient {

    private static let userAgent = "SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; cloud map)"
    // GIBS composites layers server-side in the order given. Reference_Features
    // adds coastlines and state/county boundary lines on top of the imagery —
    // a real orientation aid on a night thick enough to hide the land itself.
    private static let layers = "GOES-East_ABI_GeoColor,Reference_Features"
    private static let coverageLongitudeRange = -155.0...(-5.0)
    /// GIBS returns a real (but near-empty) JPEG rather than an error for a
    /// timestamp that hasn't been ingested yet — Reference_Features' roads
    /// and boundaries still composite onto solid black, so even a blank
    /// frame carries real, non-trivial bytes. A byte-count floor to catch
    /// that used to work — verified at the time against Wesley Chapel,
    /// where a blank frame ran ~17 KB versus ~35 KB real — right up until a
    /// dense-highway metro proved the premise wrong: a genuinely blank
    /// frame centred on New York, with nothing to draw but its own much
    /// busier road network, ran ~31 KB on its own — comfortably past that
    /// floor with zero actual satellite content, so New York was reliably
    /// showing this exact black-with-roads placeholder as if it were live
    /// imagery. Blank-detection now decodes the frame and samples actual
    /// pixels instead — see `isBlankPlaceholder` — since how much vector
    /// linework a region happens to have was never a reliable proxy for
    /// whether the photo underneath it is real.
    private static let darkSampleGridSize = 16
    private static let darkPixelThreshold: UInt8 = 20
    private static let blankDarkFraction = 0.7

    func isAvailable(longitude: Double) -> Bool {
        Self.coverageLongitudeRange.contains(longitude)
    }

    func snapshotURL(latitude: Double, longitude: Double, time: Date, pixelSize: Int) -> URL? {
        let latSpan = 1.75
        // Longitude degrees shrink toward the poles; widening the box by
        // 1/cos(latitude) keeps the frame roughly square on the ground
        // instead of visibly squashed for anyone well north or south.
        let lonSpan = latSpan / max(cos(latitude * .pi / 180), 0.2)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: "https://wvs.earthdata.nasa.gov/api/v1/snapshot")
        components?.queryItems = [
            URLQueryItem(name: "REQUEST", value: "GetSnapshot"),
            URLQueryItem(name: "LAYERS", value: Self.layers),
            URLQueryItem(name: "CRS", value: "EPSG:4326"),
            URLQueryItem(name: "TIME", value: formatter.string(from: time)),
            URLQueryItem(name: "BBOX", value: "\(latitude - latSpan),\(longitude - lonSpan),\(latitude + latSpan),\(longitude + lonSpan)"),
            URLQueryItem(name: "FORMAT", value: "image/jpeg"),
            URLQueryItem(name: "WIDTH", value: String(pixelSize)),
            URLQueryItem(name: "HEIGHT", value: String(pixelSize))
        ]
        return components?.url
    }

    /// GOES-East's GeoColor product reaches GIBS roughly 40 minutes behind
    /// real time even when everything's working normally (per NASA's own
    /// Earthdata documentation) — not "a little behind," and not something
    /// that shows up as an error: GIBS's snapshot API always snaps a TIME
    /// request to its nearest *available* frame rather than failing, so
    /// asking for `now` doesn't get something fresh, it just gets that same
    /// ~40-minute-old frame back, unlabelled as such. Starting the search
    /// there instead of at `now` means the very first successful attempt
    /// already carries an honest `capturedAt`, rather than routinely
    /// "succeeding" on the first try against content that's actually 40
    /// minutes older than the timestamp it got credited with. Stepping
    /// further back in the same 10-minute increments still covers a
    /// genuine gap beyond the normal case — a satellite recalibration, a
    /// GIBS ingest hiccup — up to `maximumLookbackMinutes`.
    private static let typicalLatencyMinutes = 40
    private static let maximumLookbackMinutes = 240
    private static let stepMinutes = 10

    // The boundary lines Reference_Features adds are thin enough that they
    // can wash out once downscaled to the sidebar panel's display size — a
    // bigger source image survives that downscale with more of the line
    // detail intact.
    func fetchLatestSnapshot(latitude: Double, longitude: Double, pixelSize: Int = 480) async throws -> (data: Data, capturedAt: Date) {
        guard isAvailable(longitude: longitude) else { throw CloudMapError.outOfCoverage }

        let now = Date()
        var minutesBack = Self.typicalLatencyMinutes
        while minutesBack <= Self.maximumLookbackMinutes {
            defer { minutesBack += Self.stepMinutes }
            let candidateTime = now.addingTimeInterval(TimeInterval(-minutesBack * 60))
            guard let url = snapshotURL(latitude: latitude, longitude: longitude, time: candidateTime, pixelSize: pixelSize) else { continue }

            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            // Same reasoning as the weather clients: never let a cache stand
            // between a refresh and a genuine live answer.
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

            // Fresh session per attempt — see OpenMeteoClient.fetch for why
            // `.shared`'s indefinite connection reuse is a real problem here;
            // it would apply equally within this retry loop.
            let session = URLSession(configuration: .ephemeral)
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
            else { continue }

            if !isBlankPlaceholder(data) {
                return (data, candidateTime)
            }
        }
        throw CloudMapError.noRecentImagery
    }

    /// True content check rather than a byte-count proxy: decodes the frame
    /// and samples a grid of pixels across it, since a genuinely blank
    /// placeholder — nothing composited but Reference_Features' lines on
    /// solid black — is overwhelmingly near-black regardless of how much
    /// linework inflates its file size, while any real GeoColor frame
    /// (ocean, land, night lights, cloud) isn't. Verified empirically: real
    /// frames sampled at 0% near-black, blank ones at 93–97%, so
    /// `blankDarkFraction` has wide margin either way.
    private func isBlankPlaceholder(_ data: Data) -> Bool {
        guard let bitmap = NSBitmapImageRep(data: data) else { return true }
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return true }

        var sampled = 0
        var dark = 0
        for column in 0..<Self.darkSampleGridSize {
            for row in 0..<Self.darkSampleGridSize {
                let x = Int((Double(column) + 0.5) * Double(width) / Double(Self.darkSampleGridSize))
                let y = Int((Double(row) + 0.5) * Double(height) / Double(Self.darkSampleGridSize))
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                sampled += 1
                let r = UInt8(clamp(Double(color.redComponent) * 255, 0, 255))
                let g = UInt8(clamp(Double(color.greenComponent) * 255, 0, 255))
                let b = UInt8(clamp(Double(color.blueComponent) * 255, 0, 255))
                if r < Self.darkPixelThreshold, g < Self.darkPixelThreshold, b < Self.darkPixelThreshold {
                    dark += 1
                }
            }
        }
        guard sampled > 0 else { return true }
        return Double(dark) / Double(sampled) >= Self.blankDarkFraction
    }
}
