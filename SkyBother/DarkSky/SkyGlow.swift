import Foundation

enum DarkSkyGeometry {
    static let kilometersPerDegree = 111.2

    /// Great-circle distance, adequate at the tens-of-kilometres scale used here.
    static func distanceKilometers(fromLatitude lat1: Double, longitude lon1: Double,
                                   toLatitude lat2: Double, longitude lon2: Double) -> Double {
        let dLat = (lat2 - lat1) * degreesToRadians
        let dLon = (lon2 - lon1) * degreesToRadians
        let a = pow(sin(dLat / 2), 2) + cosDeg(lat1) * cosDeg(lat2) * pow(sin(dLon / 2), 2)
        return 2 * 6371 * asin(min(1, sqrt(a)))
    }

    /// Eight-point compass direction from one point to another, e.g. "NE".
    static func compassDirection(fromLatitude lat1: Double, longitude lon1: Double,
                                 toLatitude lat2: Double, longitude lon2: Double) -> String {
        let deltaLongitude = lon2 - lon1
        let y = sinDeg(deltaLongitude) * cosDeg(lat2)
        let towardNorth: Double = cosDeg(lat1) * sinDeg(lat2)
        let correction: Double = sinDeg(lat1) * cosDeg(lat2) * cosDeg(deltaLongitude)
        let x = towardNorth - correction
        let bearing = normalize360(atan2Deg(y, x))
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return names[Int((bearing + 22.5) / 45) % 8]
    }
}

/// Artificial sky glow estimated from the radiance grid.
///
/// Every lit pixel contributes glow that falls off with distance following
/// Walker's law — brightness ∝ d^-2.5 — the long-standing empirical rule for
/// how a city's light dome fades across the tens of kilometres that matter
/// here. It's far simpler than the radiative-transfer model behind the World
/// Atlas, and it ignores terrain, aerosols and how well each light is
/// shielded. `DarkSkyEstimate` turns the result into a sky brightness.
struct SkyGlowField: Sendable {
    private let grid: RadianceGrid
    private let blockSize = 4
    private let blocksWide: Int
    private let blocksHigh: Int
    /// Summed radiance of each 4×4 block, for distant light where the exact
    /// pixel doesn't matter.
    private let blockSums: [Double]

    /// Light within this distance is summed pixel by pixel instead of by block,
    /// so a single lit car park next to a candidate spot counts for what it is.
    private let nearFieldKilometers = 5.0
    /// Softens the d^-2.5 falloff at short range. Glow overhead comes from light
    /// scattered kilometres up, so it stops climbing steeply once you're closer
    /// to a light than that — a point-source law taken all the way to zero
    /// makes every suburb look far brighter than the countryside beside it.
    /// 2 km is the value that best matched the reference atlas (see
    /// `DarkSkyEstimate`); 0.5, 1, 3 and 5 km all fit worse.
    private let softeningKilometers = 2.0

    init(grid: RadianceGrid) {
        self.grid = grid
        blocksWide = grid.width / blockSize
        blocksHigh = grid.height / blockSize
        var sums = [Double](repeating: 0, count: blocksWide * blocksHigh)
        for blockRow in 0..<blocksHigh {
            for blockColumn in 0..<blocksWide {
                var sum = 0.0
                for row in (blockRow * blockSize)..<((blockRow + 1) * blockSize) {
                    let rowStart = row * grid.width
                    for column in (blockColumn * blockSize)..<((blockColumn + 1) * blockSize) {
                        sum += Double(grid.values[rowStart + column])
                    }
                }
                sums[blockRow * blocksWide + blockColumn] = sum
            }
        }
        blockSums = sums
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        (grid.south...grid.north).contains(latitude) && (grid.west...grid.east).contains(longitude)
    }

    /// Relative artificial glow overhead at a point, in arbitrary units.
    func glow(latitude: Double, longitude: Double) -> Double {
        let pixelHeight = grid.pixelHeightKilometers
        let pixelWidth = grid.pixelWidthKilometers
        // The point's position in kilometres from the grid's north-west corner.
        let pointY = (grid.north - latitude) / (grid.north - grid.south) * Double(grid.height) * pixelHeight
        let pointX = (longitude - grid.west) / (grid.east - grid.west) * Double(grid.width) * pixelWidth
        let softening2 = softeningKilometers * softeningKilometers
        let nearField2 = nearFieldKilometers * nearFieldKilometers

        var total = 0.0
        for blockRow in 0..<blocksHigh {
            let blockY = (Double(blockRow) + 0.5) * Double(blockSize) * pixelHeight - pointY
            for blockColumn in 0..<blocksWide {
                let blockSum = blockSums[blockRow * blocksWide + blockColumn]
                guard blockSum > 0 else { continue }
                let blockX = (Double(blockColumn) + 0.5) * Double(blockSize) * pixelWidth - pointX
                let distance2 = blockX * blockX + blockY * blockY

                if distance2 > nearField2 {
                    total += blockSum / Self.falloff(distance2 + softening2)
                    continue
                }
                for row in (blockRow * blockSize)..<((blockRow + 1) * blockSize) {
                    let dy = (Double(row) + 0.5) * pixelHeight - pointY
                    let rowStart = row * grid.width
                    for column in (blockColumn * blockSize)..<((blockColumn + 1) * blockSize) {
                        let value = Double(grid.values[rowStart + column])
                        guard value > 0 else { continue }
                        let dx = (Double(column) + 0.5) * pixelWidth - pointX
                        total += value / Self.falloff(dx * dx + dy * dy + softening2)
                    }
                }
            }
        }
        return total
    }

    /// (d²)^1.25 = d^2.5, without calling `pow` a few million times a search.
    @inline(__always) private static func falloff(_ distanceSquared: Double) -> Double {
        distanceSquared * sqrt(sqrt(distanceSquared))
    }
}

/// Turns modelled glow into zenith sky brightness and a Bortle class.
///
/// Sky brightness adds in linear units: the natural sky (airglow, zodiacal
/// light, starlight — about 22.0 mag/arcsec²) plus the artificial glow on top.
/// `glowToArtificialRatio` converts `SkyGlowField` units into artificial
/// brightness as a multiple of the natural sky. It was fitted against David
/// Lorenz's 2024 Light Pollution Atlas — itself a VIIRS-based recalculation of
/// the World Atlas of Artificial Night Sky Brightness — at 18 reference points
/// spanning Tampa Bay, Denver and the Front Range, and Anchorage: suburbs,
/// downtowns, state parks and forest. On a log scale the model tracks the atlas
/// with a slope of 1.04 and a correlation of 0.99, and 0.17 magnitudes RMS
/// scatter in artificial brightness. The atlas was only used to set this one
/// number; nothing from it is fetched or shipped.
enum DarkSkyEstimate {
    static let naturalSkyBrightness = 22.0
    static let glowToArtificialRatio = 0.0366

    /// Boundaries between the Bortle-class midpoints in `Site.zenithSkyBrightness`.
    private static let bortleBoundaries: [Double] = [21.8, 21.55, 21.15, 20.6, 19.8, 18.95, 18.3, 17.75]

    /// Estimated zenith sky brightness in mag/arcsec² on a moonless night.
    static func zenithBrightness(glow: Double) -> Double {
        naturalSkyBrightness - 2.5 * log10(1 + max(glow, 0) * glowToArtificialRatio)
    }

    static func bortleClass(forZenithBrightness brightness: Double) -> Int {
        1 + bortleBoundaries.filter { brightness < $0 }.count
    }
}
