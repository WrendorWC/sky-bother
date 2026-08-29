import Foundation

/// Projects points on the sky (altitude/azimuth) onto a flat, 2D "planisphere"
/// view centred on the zenith — the standard way to draw an entire sky at
/// once: azimuth becomes the angle around the circle (north at the top,
/// clockwise through east), and altitude becomes distance from the centre,
/// so the zenith sits in the middle and the horizon forms the outer rim.
enum SkyProjection {
    /// A point in the unit disc: (0,0) is the zenith, magnitude 1 is the
    /// horizon, and y increases downward — matching screen/Canvas coordinate
    /// space directly, so callers just scale by their own canvas radius and
    /// offset by their own center with no further flipping.
    struct UnitPoint: Hashable {
        var x: Double
        var y: Double
    }

    /// Azimuthal-equidistant projection: altitude maps linearly to radius, so
    /// the 30°/60° rings end up evenly spaced — easier to read at a glance
    /// than a true stereographic projection, and the small distortion that
    /// introduces near the horizon doesn't matter for planning purposes.
    static func project(_ coordinate: HorizontalCoordinate) -> UnitPoint {
        let radius = clamp((90 - coordinate.altitude) / 90, 0, 1)
        return UnitPoint(x: radius * sinDeg(coordinate.azimuth),
                         y: -radius * cosDeg(coordinate.azimuth))
    }

    /// Inverse of `project`, for hit-testing a tap/click against the sky.
    /// Returns nil for points outside the horizon circle — nothing to select
    /// out there.
    static func unproject(_ point: UnitPoint) -> HorizontalCoordinate? {
        let radius = (point.x * point.x + point.y * point.y).squareRoot()
        guard radius <= 1 else { return nil }
        let altitude = 90 - radius * 90
        let azimuth = normalize360(atan2Deg(point.x, -point.y))
        return HorizontalCoordinate(altitude: altitude, azimuth: azimuth)
    }
}
