import Foundation

enum LandCoverError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Satellite land-cover data couldn't be loaded for this area."
        }
    }
}

/// ESA WorldCover land-cover classes. Values are the dataset's own codes.
enum LandCoverClass: UInt8 {
    case noData = 0
    case trees = 10
    case shrubland = 20
    case grassland = 30
    case cropland = 40
    case builtUp = 50
    case bare = 60
    case snowAndIce = 70
    case water = 80
    case wetland = 90
    case mangroves = 95
    case mossAndLichen = 100
}

/// A block of land-cover classes on WorldCover's own global pixel lattice. Row 0
/// is the northern edge.
struct LandCoverGrid: Sendable {
    /// Global pixel indices of the grid's north-west corner.
    var originColumn: Int
    var originRow: Int
    var width: Int
    var height: Int
    var classes: [UInt8]
    var pixelsPerDegree: Double

    var pixelHeightMeters: Double { 111_200 / pixelsPerDegree }
    func pixelWidthMeters(atLatitude latitude: Double) -> Double {
        111_200 * max(cosDeg(latitude), 0.2) / pixelsPerDegree
    }

    /// Grid position of a coordinate, or nil if it falls outside.
    func position(latitude: Double, longitude: Double) -> (column: Int, row: Int)? {
        let column = Int(((longitude + 180) * pixelsPerDegree).rounded(.down)) - originColumn
        let row = Int(((90 - latitude) * pixelsPerDegree).rounded(.down)) - originRow
        guard (0..<width).contains(column), (0..<height).contains(row) else { return nil }
        return (column, row)
    }

    func coordinate(column: Int, row: Int) -> (latitude: Double, longitude: Double) {
        (90 - (Double(originRow + row) + 0.5) / pixelsPerDegree,
         (Double(originColumn + column) + 0.5) / pixelsPerDegree - 180)
    }

    subscript(column: Int, row: Int) -> UInt8 { classes[row * width + column] }
}

/// ESA WorldCover 2021 (v200), a 10 m global land-cover map from Sentinel-1 and
/// Sentinel-2 imagery, read straight from the dataset's public copy on AWS —
/// no API key, no account, CC BY 4.0.
///
/// The files are cloud-optimised GeoTIFFs, one per 3°×3° cell, each 36,000
/// pixels square and split internally into 1,024-pixel tiles, with half-, quarter-
/// and smaller-resolution overviews. An HTTP range request can pull out just the
/// few internal tiles around a site instead of a 60–100 MB file. This reads the
/// first overview (about 20 m per pixel): a tree line a hundred metres away
/// needs nothing finer, and it's a quarter of the download.
///
/// Only as much TIFF as WorldCover actually uses is parsed — little-endian
/// classic TIFF, 8-bit samples, Deflate compression, no predictor — and anything
/// else fails cleanly rather than decoding garbage.
actor LandCoverClient {

    private static let userAgent = "SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; land cover)"
    private static let baseURL = "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/"
    private static let fileSpanDegrees = 3
    /// Level 1 is the first overview, 18,000 pixels per 3° file.
    private static let overviewLevel = 1
    private static let headerBytes = 65_536

    private struct FileLayout {
        var width: Int
        var tileSize: Int
        var tileOffsets: [UInt32]
        var tileByteCounts: [UInt32]
    }

    /// nil marks a file that doesn't exist — WorldCover skips cells that are
    /// entirely open ocean.
    private var layouts: [String: FileLayout?] = [:]
    private var tiles: [String: [UInt8]] = [:]

    /// Land cover for a box around a point, `halfSizeMeters` in each direction.
    func grid(latitude: Double, longitude: Double, halfSizeMeters: Double) async throws -> LandCoverGrid {
        let pixelsPerDegree = Double(36_000 >> Self.overviewLevel) / Double(Self.fileSpanDegrees)
        let halfLatitude = halfSizeMeters / 111_200
        let halfLongitude = halfSizeMeters / (111_200 * max(cosDeg(latitude), 0.2))

        let originColumn = Int(((longitude - halfLongitude + 180) * pixelsPerDegree).rounded(.down))
        let originRow = Int(((90 - (latitude + halfLatitude)) * pixelsPerDegree).rounded(.down))
        let endColumn = Int(((longitude + halfLongitude + 180) * pixelsPerDegree).rounded(.up))
        let endRow = Int(((90 - (latitude - halfLatitude)) * pixelsPerDegree).rounded(.up))
        let width = endColumn - originColumn
        let height = endRow - originRow
        var classes = [UInt8](repeating: LandCoverClass.noData.rawValue, count: width * height)

        let filePixels = 36_000 >> Self.overviewLevel
        var anyData = false

        // Every file cell the box touches — usually one, up to four at a corner.
        let firstFileColumn = originColumn / filePixels
        let lastFileColumn = (endColumn - 1) / filePixels
        let firstFileRow = originRow / filePixels
        let lastFileRow = (endRow - 1) / filePixels

        for fileRow in firstFileRow...lastFileRow {
            for fileColumn in firstFileColumn...lastFileColumn {
                let name = Self.fileName(fileColumn: fileColumn, fileRow: fileRow)
                guard let layout = try await layout(for: name) else {
                    // No file: open ocean. Water is the right answer, not a gap.
                    Self.fill(&classes, width: width, height: height,
                              originColumn: originColumn, originRow: originRow,
                              fileColumn: fileColumn, fileRow: fileRow, filePixels: filePixels,
                              with: LandCoverClass.water.rawValue)
                    anyData = true
                    continue
                }
                guard layout.width == filePixels else { throw LandCoverError.unavailable }

                let fileOriginColumn = fileColumn * filePixels
                let fileOriginRow = fileRow * filePixels
                let localStartColumn = max(originColumn - fileOriginColumn, 0)
                let localEndColumn = min(endColumn - fileOriginColumn, filePixels)
                let localStartRow = max(originRow - fileOriginRow, 0)
                let localEndRow = min(endRow - fileOriginRow, filePixels)
                let tilesAcross = (filePixels + layout.tileSize - 1) / layout.tileSize

                for tileRow in (localStartRow / layout.tileSize)...((localEndRow - 1) / layout.tileSize) {
                    for tileColumn in (localStartColumn / layout.tileSize)...((localEndColumn - 1) / layout.tileSize) {
                        let tileIndex = tileRow * tilesAcross + tileColumn
                        let pixels = try await tile(name: name, index: tileIndex, layout: layout)
                        anyData = true

                        let tileOriginColumn = tileColumn * layout.tileSize
                        let tileOriginRow = tileRow * layout.tileSize
                        let rowRange = max(localStartRow, tileOriginRow)..<min(localEndRow, tileOriginRow + layout.tileSize)
                        let columnRange = max(localStartColumn, tileOriginColumn)..<min(localEndColumn, tileOriginColumn + layout.tileSize)
                        for localRow in rowRange {
                            let gridRow = fileOriginRow + localRow - originRow
                            let sourceRowStart = (localRow - tileOriginRow) * layout.tileSize
                            for localColumn in columnRange {
                                let gridColumn = fileOriginColumn + localColumn - originColumn
                                classes[gridRow * width + gridColumn] = pixels[sourceRowStart + localColumn - tileOriginColumn]
                            }
                        }
                    }
                }
            }
        }

        guard anyData else { throw LandCoverError.unavailable }
        return LandCoverGrid(originColumn: originColumn, originRow: originRow, width: width, height: height,
                             classes: classes, pixelsPerDegree: pixelsPerDegree)
    }

    // MARK: - Files

    /// Files are named for their south-west corner, e.g. N27W084 covers
    /// 27–30°N, 84–81°W.
    private static func fileName(fileColumn: Int, fileRow: Int) -> String {
        let west = fileColumn * fileSpanDegrees - 180
        let south = 90 - (fileRow + 1) * fileSpanDegrees
        let latitudePart = String(format: "%@%02d", south >= 0 ? "N" : "S", abs(south))
        let longitudePart = String(format: "%@%03d", west >= 0 ? "E" : "W", abs(west))
        return "ESA_WorldCover_10m_2021_v200_\(latitudePart)\(longitudePart)_Map.tif"
    }

    private static func fill(_ classes: inout [UInt8], width: Int, height: Int,
                             originColumn: Int, originRow: Int,
                             fileColumn: Int, fileRow: Int, filePixels: Int, with value: UInt8) {
        let columns = max(fileColumn * filePixels - originColumn, 0)..<min((fileColumn + 1) * filePixels - originColumn, width)
        let rows = max(fileRow * filePixels - originRow, 0)..<min((fileRow + 1) * filePixels - originRow, height)
        for row in rows {
            for column in columns { classes[row * width + column] = value }
        }
    }

    private func layout(for name: String) async throws -> FileLayout? {
        if let cached = layouts[name] { return cached }
        let header: Data
        do {
            header = try await Self.fetch(name: name, offset: 0, length: Self.headerBytes)
        } catch LandCoverFetchError.notFound {
            layouts[name] = .some(nil)
            return nil
        }
        var parsed = try Self.parseLayout(header, level: Self.overviewLevel)
        // The directory and tile tables normally sit inside the first few dozen
        // kilobytes; if a file ever puts them further out, fetch far enough once.
        if case .needsBytes(let count) = parsed {
            let longer = try await Self.fetch(name: name, offset: 0, length: count)
            parsed = try Self.parseLayout(longer, level: Self.overviewLevel)
        }
        guard case .layout(let layout) = parsed else { throw LandCoverError.unavailable }
        layouts[name] = layout
        return layout
    }

    private func tile(name: String, index: Int, layout: FileLayout) async throws -> [UInt8] {
        let key = "\(name)#\(index)"
        if let cached = tiles[key] { return cached }
        guard index < layout.tileOffsets.count else { throw LandCoverError.unavailable }
        let compressed = try await Self.fetch(name: name,
                                              offset: Int(layout.tileOffsets[index]),
                                              length: Int(layout.tileByteCounts[index]))
        let pixels = try Self.inflate(compressed, expectedCount: layout.tileSize * layout.tileSize)
        // A search touches a handful of tiles; keep a session's worth, but not
        // an unbounded pile if someone pans across a state.
        if tiles.count > 48 { tiles.removeAll() }
        tiles[key] = pixels
        return pixels
    }

    // MARK: - TIFF

    private enum ParsedLayout {
        case layout(FileLayout)
        /// The header runs past what was fetched; this many bytes will cover it.
        case needsBytes(Int)
    }

    private static func parseLayout(_ data: Data, level: Int) throws -> ParsedLayout {
        guard data.count >= 8, data[data.startIndex] == 0x49, data[data.startIndex + 1] == 0x49,
              readUInt16(data, 2) == 42 else {
            throw LandCoverError.unavailable
        }
        var ifdOffset = Int(readUInt32(data, 4))
        var currentLevel = 0
        while ifdOffset > 0 {
            guard ifdOffset + 2 <= data.count else { return .needsBytes(ifdOffset + 65_536) }
            let count = Int(readUInt16(data, ifdOffset))
            let directoryEnd = ifdOffset + 2 + count * 12 + 4
            guard directoryEnd <= data.count else { return .needsBytes(directoryEnd + 65_536) }

            if currentLevel == level {
                var width = 0, tileSize = 0, compression = 0, bits = 0, predictor = 1
                var offsetsEntry: (count: Int, at: Int)?
                var countsEntry: (count: Int, at: Int)?
                for index in 0..<count {
                    let entry = ifdOffset + 2 + index * 12
                    let tag = readUInt16(data, entry)
                    let type = readUInt16(data, entry + 2)
                    let valueCount = Int(readUInt32(data, entry + 4))
                    let inlineValue = type == 3 ? Int(readUInt16(data, entry + 8)) : Int(readUInt32(data, entry + 8))
                    switch tag {
                    case 256: width = inlineValue
                    case 258: bits = inlineValue
                    case 259: compression = inlineValue
                    case 317: predictor = inlineValue
                    case 322: tileSize = inlineValue
                    case 324: offsetsEntry = (valueCount, Int(readUInt32(data, entry + 8)))
                    case 325: countsEntry = (valueCount, Int(readUInt32(data, entry + 8)))
                    default: break
                    }
                }
                guard bits == 8, compression == 8, predictor == 1, tileSize > 0,
                      let offsetsEntry, let countsEntry else { throw LandCoverError.unavailable }
                // Both tables are LONG arrays stored out of line.
                let tableEnd = max(offsetsEntry.at + offsetsEntry.count * 4, countsEntry.at + countsEntry.count * 4)
                guard tableEnd <= data.count else { return .needsBytes(tableEnd) }
                return .layout(FileLayout(width: width, tileSize: tileSize,
                                          tileOffsets: (0..<offsetsEntry.count).map { readUInt32(data, offsetsEntry.at + $0 * 4) },
                                          tileByteCounts: (0..<countsEntry.count).map { readUInt32(data, countsEntry.at + $0 * 4) }))
            }

            ifdOffset = Int(readUInt32(data, ifdOffset + 2 + count * 12))
            currentLevel += 1
        }
        throw LandCoverError.unavailable
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[data.startIndex + offset]) | UInt16(data[data.startIndex + offset + 1]) << 8
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[data.startIndex + offset + $1]) << (8 * $1) }
    }

    /// TIFF's Deflate is a zlib stream; Apple's `.zlib` decompressor wants the
    /// raw Deflate data inside it, so the two-byte zlib header is dropped.
    private static func inflate(_ data: Data, expectedCount: Int) throws -> [UInt8] {
        guard data.count > 2,
              let raw = try? (data.subdata(in: (data.startIndex + 2)..<data.endIndex) as NSData).decompressed(using: .zlib),
              raw.length >= expectedCount
        else { throw LandCoverError.unavailable }
        return [UInt8](Data(referencing: raw).prefix(expectedCount))
    }

    // MARK: - Network

    private static func fetch(name: String, offset: Int, length: Int) async throws -> Data {
        guard let url = URL(string: baseURL + name) else { throw LandCoverError.unavailable }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=\(offset)-\(offset + length - 1)", forHTTPHeaderField: "Range")
        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LandCoverError.unavailable }
        if http.statusCode == 404 || http.statusCode == 403 { throw LandCoverFetchError.notFound }
        // Insist on a partial response: a server that ignored the range would
        // otherwise hand back the whole 60–100 MB file.
        guard http.statusCode == 206 else { throw LandCoverError.unavailable }
        return data
    }
}

private enum LandCoverFetchError: Error {
    case notFound
}
