import Foundation

/// Trig helpers that take and return degrees. Every angle in this app is stored
/// in degrees; radians only ever appear inside these functions.

let degreesToRadians = Double.pi / 180.0
let radiansToDegrees = 180.0 / Double.pi

@inline(__always) func sinDeg(_ x: Double) -> Double { sin(x * degreesToRadians) }
@inline(__always) func cosDeg(_ x: Double) -> Double { cos(x * degreesToRadians) }
@inline(__always) func tanDeg(_ x: Double) -> Double { tan(x * degreesToRadians) }
@inline(__always) func asinDeg(_ x: Double) -> Double { asin(min(1, max(-1, x))) * radiansToDegrees }
@inline(__always) func acosDeg(_ x: Double) -> Double { acos(min(1, max(-1, x))) * radiansToDegrees }
@inline(__always) func atan2Deg(_ y: Double, _ x: Double) -> Double { atan2(y, x) * radiansToDegrees }

/// Wraps an angle into [0, 360).
func normalize360(_ x: Double) -> Double {
    let r = x.truncatingRemainder(dividingBy: 360)
    return r < 0 ? r + 360 : r
}

/// Wraps an angle into [-180, 180).
func normalize180(_ x: Double) -> Double {
    var r = normalize360(x)
    if r >= 180 { r -= 360 }
    return r
}

func clamp(_ x: Double, _ low: Double, _ high: Double) -> Double {
    min(high, max(low, x))
}

/// Smooth 0->1 ramp across [edge0, edge1]; flat outside.
func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    guard edge1 != edge0 else { return x < edge0 ? 0 : 1 }
    let t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
}
