import Foundation

/// A comet's orbit, as the Minor Planet Center publishes it, and where that
/// puts the comet on a given night.
///
/// Positions come from the two-body orbit plus a low-precision Sun, which
/// agreed with JPL Horizons to a few thousandths of a degree when this was
/// written — far finer than anything here decides with. Brightness is the
/// MPC's standard formula, and that is the weak part: comets regularly come
/// in a magnitude or more off their predictions, which the app says.
struct CometOrbit: Codable, Hashable, Sendable {
    /// "C/2026 A2" or "10P" — stable, so a planned block keeps its comet.
    var designation: String
    /// "Bok", "Tempel", or empty when the comet has no name.
    var name: String
    /// Julian date of perihelion (TT, treated as UT: a minute's difference).
    var perihelionJulianDate: Double
    var perihelionDistance: Double        // q, AU
    var eccentricity: Double
    var argumentOfPerihelion: Double      // ω, degrees, J2000 ecliptic
    var ascendingNode: Double             // Ω, degrees
    var inclination: Double               // i, degrees
    var absoluteMagnitude: Double         // H
    var slope: Double                     // the MPC's G: m = H + 5 log Δ + 2.5 G log r

    /// Brighter than this on a night and a comet is listed as a target.
    /// Fainter ones would be hundreds of entries no small scope records.
    static let magnitudeLimit = 14.0

    struct Position {
        var coordinate: EquatorialCoordinate
        var earthDistance: Double   // Δ, AU
        var sunDistance: Double     // r, AU
        var magnitude: Double
    }

    /// The comet as a target for the night around `date`, or nil when it's
    /// predicted fainter than `magnitudeLimit`.
    func target(at date: Date) -> Target? {
        let position = position(at: date)
        guard position.magnitude <= Self.magnitudeLimit else { return nil }
        let coma = Self.estimatedComaArcminutes(magnitude: position.magnitude)
        return Target(designation: designation,
                      commonName: name.isEmpty ? nil : "Comet \(name)",
                      type: .comet,
                      rightAscension: position.coordinate.rightAscension,
                      declination: position.coordinate.declination,
                      magnitude: (position.magnitude * 10).rounded() / 10,
                      majorAxisArcminutes: coma,
                      minorAxisArcminutes: coma,
                      constellation: "")
    }

    /// The orbit data says nothing about how big the coma looks, so this is
    /// a rough guess from brightness alone: about a minute of arc for a
    /// faint comet, several for a binocular one, half a degree for a great
    /// one. The tail isn't counted.
    static func estimatedComaArcminutes(magnitude: Double) -> Double {
        let size = 3 * pow(10, (10 - magnitude) / 7.5)
        return (clamp(size, 1, 30) * 10).rounded() / 10
    }

    func position(at date: Date) -> Position {
        let julianDate = date.timeIntervalSince1970 / 86400 + 2440587.5
        let sun = Self.geocentricSun(julianDate: julianDate)

        // Where the comet was when the light now arriving left it.
        var delta = 1.0
        var geocentric = (x: 0.0, y: 0.0, z: 0.0)
        var sunDistance = 1.0
        for _ in 0..<3 {
            let helio = heliocentric(julianDate: julianDate - 0.0057755183 * delta)
            geocentric = (helio.x + sun.x, helio.y + sun.y, helio.z + sun.z)
            delta = sqrt(geocentric.x * geocentric.x + geocentric.y * geocentric.y + geocentric.z * geocentric.z)
            sunDistance = helio.r
        }

        let obliquity = 23.4392911 * .pi / 180
        let x = geocentric.x
        let y = geocentric.y * cos(obliquity) - geocentric.z * sin(obliquity)
        let z = geocentric.y * sin(obliquity) + geocentric.z * cos(obliquity)
        var rightAscension = atan2(y, x) * 180 / .pi
        if rightAscension < 0 { rightAscension += 360 }
        let declination = asin(clamp(z / delta, -1, 1)) * 180 / .pi

        let magnitude = absoluteMagnitude + 5 * log10(delta) + 2.5 * slope * log10(max(sunDistance, 0.01))
        return Position(coordinate: EquatorialCoordinate(rightAscension: rightAscension, declination: declination),
                        earthDistance: delta, sunDistance: sunDistance, magnitude: magnitude)
    }

    /// Heliocentric ecliptic position (J2000), in AU, by Kepler's equation:
    /// elliptic, near-parabolic or hyperbolic as the orbit needs.
    private func heliocentric(julianDate: Double) -> (x: Double, y: Double, z: Double, r: Double) {
        let gauss = 0.01720209895
        let q = perihelionDistance, e = eccentricity
        let days = julianDate - perihelionJulianDate
        let trueAnomaly: Double
        let radius: Double

        if abs(e - 1) < 1e-3 {
            // Parabolic, by Barker's equation. Near enough for the handful
            // of orbits this close to 1 either side.
            let w = 3 * gauss / sqrt(2 * q * q * q) * days
            let y = cbrt(w / 2 + sqrt(w * w / 4 + 1))
            let s = y - 1 / y
            trueAnomaly = 2 * atan(s)
            radius = q * (1 + s * s)
        } else if e < 1 {
            let a = q / (1 - e)
            let meanAnomaly = fmod(gauss * days / pow(a, 1.5), 2 * .pi)
            var eccentric = e < 0.8 ? meanAnomaly : (meanAnomaly >= 0 ? .pi : -.pi)
            for _ in 0..<100 {
                let step = (eccentric - e * sin(eccentric) - meanAnomaly) / (1 - e * cos(eccentric))
                eccentric -= step
                if abs(step) < 1e-12 { break }
            }
            radius = a * (1 - e * cos(eccentric))
            trueAnomaly = 2 * atan(sqrt((1 + e) / (1 - e)) * tan(eccentric / 2))
        } else {
            let a = q / (e - 1)
            let meanAnomaly = gauss * days / pow(a, 1.5)
            var hyperbolic = asinh(meanAnomaly / e)
            for _ in 0..<100 {
                let step = (e * sinh(hyperbolic) - hyperbolic - meanAnomaly) / (e * cosh(hyperbolic) - 1)
                hyperbolic -= step
                if abs(step) < 1e-12 { break }
            }
            radius = a * (e * cosh(hyperbolic) - 1)
            trueAnomaly = 2 * atan(sqrt((e + 1) / (e - 1)) * tanh(hyperbolic / 2))
        }

        let node = ascendingNode * .pi / 180
        let tilt = inclination * .pi / 180
        let u = argumentOfPerihelion * .pi / 180 + trueAnomaly
        let x = radius * (cos(node) * cos(u) - sin(node) * sin(u) * cos(tilt))
        let y = radius * (sin(node) * cos(u) + cos(node) * sin(u) * cos(tilt))
        let z = radius * sin(u) * sin(tilt)
        return (x, y, z, radius)
    }

    /// The Sun seen from the Earth, ecliptic J2000, in AU — Meeus's low
    /// precision formula, brought from the equinox of date back to J2000.
    private static func geocentricSun(julianDate: Double) -> (x: Double, y: Double, z: Double) {
        let t = (julianDate - 2451545.0) / 36525
        let meanLongitude = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
        let meanAnomaly = (357.52911 + 35999.05029 * t - 0.0001537 * t * t) * .pi / 180
        let orbitEccentricity = 0.016708634 - 0.000042037 * t
        let centre = (1.914602 - 0.004817 * t) * sin(meanAnomaly)
            + (0.019993 - 0.000101 * t) * sin(2 * meanAnomaly)
            + 0.000289 * sin(3 * meanAnomaly)
        let trueAnomaly = meanAnomaly + centre * .pi / 180
        let distance = 1.000001018 * (1 - orbitEccentricity * orbitEccentricity) / (1 + orbitEccentricity * cos(trueAnomaly))
        let longitude = (meanLongitude + centre - 1.397 * t) * .pi / 180
        return (distance * cos(longitude), distance * sin(longitude), 0)
    }
}

extension CometOrbit {
    /// One line of the MPC's CometEls.txt, whose columns are fixed; nil for
    /// anything that doesn't read as an orbit.
    init?(mpcLine line: String) {
        let characters = Array(line)
        func field(_ from: Int, _ to: Int) -> String {
            guard characters.count >= from else { return "" }
            return String(characters[(from - 1)..<min(to, characters.count)]).trimmingCharacters(in: .whitespaces)
        }
        guard let year = Int(field(15, 18)), let month = Int(field(20, 21)), let day = Double(field(23, 29)),
              let q = Double(field(31, 39)), let e = Double(field(42, 49)),
              let peri = Double(field(52, 59)), let node = Double(field(62, 69)), let incl = Double(field(72, 79)),
              let h = Double(field(92, 95))
        else { return nil }
        let fullName = field(103, 158)
        guard !fullName.isEmpty else { return nil }

        // "C/2026 A2 (Bok)" or "10P/Tempel" or "P/2021 N1 (ZTF)".
        var designation = fullName
        var name = ""
        if let open = fullName.firstIndex(of: "("), fullName.hasSuffix(")") {
            designation = fullName[..<open].trimmingCharacters(in: .whitespaces)
            name = String(fullName[fullName.index(after: open)..<fullName.index(before: fullName.endIndex)])
        } else if let slash = fullName.firstIndex(of: "/"), fullName[..<slash].last?.isLetter == true,
                  fullName[..<slash].dropLast().allSatisfy(\.isNumber), fullName[..<slash].count > 1 {
            designation = String(fullName[..<slash])
            name = String(fullName[fullName.index(after: slash)...])
        }

        self.init(designation: designation,
                  name: name,
                  perihelionJulianDate: Self.julianDate(year: year, month: month, day: day),
                  perihelionDistance: q,
                  eccentricity: e,
                  argumentOfPerihelion: peri,
                  ascendingNode: node,
                  inclination: incl,
                  absoluteMagnitude: h,
                  slope: Double(field(97, 100)) ?? 4)
    }

    static func parse(_ text: String) -> [CometOrbit] {
        text.split(whereSeparator: \.isNewline).compactMap { CometOrbit(mpcLine: String($0)) }
    }

    private static func julianDate(year: Int, month: Int, day: Double) -> Double {
        var y = year, m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = y / 100
        let b = 2 - a + a / 4
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + day + Double(b) - 1524.5
    }
}
