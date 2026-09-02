import Foundation

/// The outline a rectilinear camera lens actually traces on the sky when
/// pointed somewhere and rolled by some angle. A rectilinear lens is,
/// physically, a gnomonic (tangent-plane) projection, so this is exact
/// geometry — not an approximation of one.
enum CameraFrame {
    private struct Vector3 {
        var x: Double
        var y: Double
        var z: Double

        static func + (a: Vector3, b: Vector3) -> Vector3 {
            Vector3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)
        }

        static func - (a: Vector3, b: Vector3) -> Vector3 {
            Vector3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
        }

        static func * (v: Vector3, scalar: Double) -> Vector3 {
            Vector3(x: v.x * scalar, y: v.y * scalar, z: v.z * scalar)
        }

        var normalized: Vector3 {
            let length = (x * x + y * y + z * z).squareRoot()
            guard length > 0 else { return self }
            return Vector3(x: x / length, y: y / length, z: z / length)
        }
    }

    private static func direction(altitude: Double, azimuth: Double) -> Vector3 {
        Vector3(x: cosDeg(altitude) * sinDeg(azimuth),
               y: cosDeg(altitude) * cosDeg(azimuth),
               z: sinDeg(altitude))
    }

    private static func horizontal(of vector: Vector3) -> HorizontalCoordinate {
        let unit = vector.normalized
        return HorizontalCoordinate(altitude: asinDeg(unit.z),
                                    azimuth: normalize360(atan2Deg(unit.x, unit.y)))
    }

    /// The camera pointed at (centerAltitude, centerAzimuth), rolled by
    /// `rollDegrees` from "up = toward the zenith", with the given field of
    /// view. Returns the frame's outline, traced clockwise and subdivided
    /// per edge so it curves correctly once projected onto the sky view's
    /// flattened, non-linear map instead of drawing as straight segments.
    static func footprint(centerAltitude: Double, centerAzimuth: Double,
                          fieldOfViewWidthDegrees width: Double,
                          fieldOfViewHeightDegrees height: Double,
                          rollDegrees: Double,
                          subdivisionsPerEdge: Int = 6) -> [HorizontalCoordinate] {
        let halfWidth = width / 2
        let halfHeight = height / 2

        let forward = direction(altitude: centerAltitude, azimuth: centerAzimuth)
        // "Up" and "right" before roll: the local tangent directions of
        // increasing altitude and increasing azimuth at the centre.
        let up0 = Vector3(x: -sinDeg(centerAltitude) * sinDeg(centerAzimuth),
                          y: -sinDeg(centerAltitude) * cosDeg(centerAzimuth),
                          z: cosDeg(centerAltitude))
        let right0 = Vector3(x: cosDeg(centerAzimuth), y: -sinDeg(centerAzimuth), z: 0)

        let up = up0 * cosDeg(rollDegrees) + right0 * sinDeg(rollDegrees)
        let right = right0 * cosDeg(rollDegrees) - up0 * sinDeg(rollDegrees)

        let corners: [(Double, Double)] = [(-halfWidth, halfHeight), (halfWidth, halfHeight),
                                           (halfWidth, -halfHeight), (-halfWidth, -halfHeight)]

        var points: [HorizontalCoordinate] = []
        for index in corners.indices {
            let start = corners[index]
            let end = corners[(index + 1) % corners.count]
            for step in 0..<subdivisionsPerEdge {
                let t = Double(step) / Double(subdivisionsPerEdge)
                let angleX = start.0 + (end.0 - start.0) * t
                let angleY = start.1 + (end.1 - start.1) * t
                let direction3D = forward + right * tanDeg(angleX) + up * tanDeg(angleY)
                points.append(horizontal(of: direction3D))
            }
        }
        return points
    }
}
