import Foundation

/// Comet orbits from the Minor Planet Center, kept on disk so comets are
/// still there offline and the file is only fetched about once a week.
/// Orbits barely change in a week; new comets are what a refresh brings.
struct CometClient: Sendable {
    static let shared = CometClient()

    private static let endpoint = URL(string: "https://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt")!
    private static let refreshInterval: TimeInterval = 7 * 86400

    private var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("SkyBother", isDirectory: true).appendingPathComponent("CometEls.txt")
    }

    /// Whatever was last downloaded, however old.
    func cached() -> [CometOrbit] {
        guard let fileURL, let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return CometOrbit.parse(text)
    }

    var isStale: Bool {
        guard let fileURL,
              let modified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return true }
        return Date().timeIntervalSince(modified) > Self.refreshInterval
    }

    /// A fresh copy, saved for next time. Throws rather than returning
    /// nothing, so a failed download never replaces a good cache.
    func fetch() async throws -> [CometOrbit] {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 60)
        request.setValue("SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; comet orbits)",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        let orbits = CometOrbit.parse(text)
        // A page of HTML or an empty file parses to nothing; keep the old one.
        guard orbits.count > 100 else { throw URLError(.cannotParseResponse) }
        if let fileURL {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
        return orbits
    }
}
