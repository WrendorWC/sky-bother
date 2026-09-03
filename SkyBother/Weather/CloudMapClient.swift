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
    private static let layer = "GOES-East_ABI_GeoColor"
    private static let coverageLongitudeRange = -155.0...(-5.0)
    /// GIBS returns a real (but tiny, near-empty) JPEG rather than an error
    /// for a timestamp that hasn't been ingested yet — verified empirically
    /// against a live blank frame (~2 KB) versus a real one (30–50 KB+).
    private static let minimumValidByteCount = 4000

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
            URLQueryItem(name: "LAYERS", value: Self.layer),
            URLQueryItem(name: "CRS", value: "EPSG:4326"),
            URLQueryItem(name: "TIME", value: formatter.string(from: time)),
            URLQueryItem(name: "BBOX", value: "\(latitude - latSpan),\(longitude - lonSpan),\(latitude + latSpan),\(longitude + lonSpan)"),
            URLQueryItem(name: "FORMAT", value: "image/jpeg"),
            URLQueryItem(name: "WIDTH", value: String(pixelSize)),
            URLQueryItem(name: "HEIGHT", value: String(pixelSize))
        ]
        return components?.url
    }

    /// GOES imagery lands in GIBS a little behind real time and not on a
    /// perfectly predictable cadence, so this steps back from now in 10-minute
    /// increments until it finds a frame that isn't the blank placeholder.
    func fetchLatestSnapshot(latitude: Double, longitude: Double, pixelSize: Int = 360) async throws -> (data: Data, capturedAt: Date) {
        guard isAvailable(longitude: longitude) else { throw CloudMapError.outOfCoverage }

        let now = Date()
        for stepsBack in 0..<6 {
            let candidateTime = now.addingTimeInterval(TimeInterval(-stepsBack * 600))
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

            if data.count >= Self.minimumValidByteCount {
                return (data, candidateTime)
            }
        }
        throw CloudMapError.noRecentImagery
    }
}
