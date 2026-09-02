import Foundation

/// Converts galactic coordinates to equatorial. The same shape of problem as
/// `SkyCoordinates.equatorial(eclipticLongitude:eclipticLatitude:obliquity:)`
/// — a spherical rotation defined by a pole and a reference longitude — just
/// with the IAU 1958 galactic pole instead of the ecliptic's obliquity.
enum GalacticCoordinates {
    // IAU 1958 definition, J2000.
    private static let poleRA = 192.859508
    private static let poleDec = 27.128336
    private static let ncpLongitude = 122.932

    /// Equatorial coordinate for a point given in galactic longitude/latitude.
    static func equatorial(galacticLongitude l: Double, galacticLatitude b: Double) -> EquatorialCoordinate {
        let dec = asinDeg(sinDeg(b) * sinDeg(poleDec) + cosDeg(b) * cosDeg(poleDec) * cosDeg(ncpLongitude - l))
        let ra = poleRA + atan2Deg(cosDeg(b) * sinDeg(ncpLongitude - l),
                                   cosDeg(poleDec) * sinDeg(b) - sinDeg(poleDec) * cosDeg(b) * cosDeg(ncpLongitude - l))
        return EquatorialCoordinate(rightAscension: normalize360(ra), declination: dec)
    }

    /// Sgr A* — the galactic centre is l=0, b=0 by definition, derived
    /// through the same rotation rather than hand-typed as a separate magic
    /// constant, so it can't drift out of sync with the rotation above.
    static let galacticCenter = equatorial(galacticLongitude: 0, galacticLatitude: 0)
}
