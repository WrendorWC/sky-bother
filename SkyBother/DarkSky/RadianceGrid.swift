import Foundation

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
