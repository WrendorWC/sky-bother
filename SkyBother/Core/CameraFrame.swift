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

        static func dot(_ a: Vector3, _ b: Vector3) -> Double {
            a.x * b.x + a.y * b.y + a.z * b.z
        }

        static func cross(_ a: Vector3, _ b: Vector3) -> Vector3 {
            Vector3(x: a.y * b.z - a.z * b.y,
                   y: a.z * b.x - a.x * b.z,
                   z: a.x * b.y - a.y * b.x)
        }
    }

    /// What "roll = 0" is measured from. An alt-az mount holds the camera's
    /// up fixed relative to the zenith — the observer's own local vertical —
    /// which is exactly why its frame visibly rotates relative to the stars
    /// over a session (the same field rotation "Zenith Risk" warns about).
    /// A properly polar-aligned equatorial mount holds up fixed relative to
    /// the celestial pole instead, which — being defined on the celestial
    /// sphere rather than the ground — doesn't sweep around like that: an
    /// EQ frame keeps one orientation relative to the star field all night.
    enum UpReference {
        case zenith
        case celestialPole(latitude: Double)
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
    /// `rollDegrees` from whatever `upReference` calls "up", with the given
    /// field of view. Returns the frame's outline, traced clockwise and
    /// subdivided per edge so it curves correctly once projected onto the
    /// sky view's flattened, non-linear map instead of drawing as straight
    /// segments.
    static func footprint(centerAltitude: Double, centerAzimuth: Double,
                          fieldOfViewWidthDegrees width: Double,
                          fieldOfViewHeightDegrees height: Double,
                          rollDegrees: Double,
                          upReference: UpReference = .zenith,
                          subdivisionsPerEdge: Int = 6) -> [HorizontalCoordinate] {
        let halfWidth = width / 2
        let halfHeight = height / 2

        let forward = direction(altitude: centerAltitude, azimuth: centerAzimuth)

        // "Up" before roll: the local tangent direction, at the centre,
        // toward whichever reference this mount actually holds fixed.
        let up0: Vector3
        switch upReference {
        case .zenith:
            // The tangent direction of increasing altitude at the centre —
            // correct for alt-az, where the mount's own axes are altitude
            // and azimuth to begin with.
            up0 = Vector3(x: -sinDeg(centerAltitude) * sinDeg(centerAzimuth),
                         y: -sinDeg(centerAltitude) * cosDeg(centerAzimuth),
                         z: cosDeg(centerAltitude))
        case .celestialPole(let latitude):
            // The pole itself sits at a fixed alt/az for any observer at a
            // given latitude — altitude equal to the latitude's magnitude,
            // due north for a northern site and due south for a southern
            // one — regardless of what's being pointed at or when. "Toward
            // the pole, as seen from the target" is that fixed direction
            // with its component along `forward` projected out, the same
            // Gram-Schmidt step that turns any reference direction into a
            // valid local tangent vector.
            let pole = latitude >= 0
                ? direction(altitude: latitude, azimuth: 0)
                : direction(altitude: -latitude, azimuth: 180)
            up0 = (pole - forward * Vector3.dot(pole, forward)).normalized
        }
        // "Right" is whatever's perpendicular to both — this falls out of
        // the cross product regardless of which reference `up0` came from,
        // rather than needing its own separate per-case formula.
        let right0 = Vector3.cross(forward, up0)

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
