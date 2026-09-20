import Foundation

/// HEALPix, in the nested numbering that HiPS surveys are tiled by.
///
/// A HiPS survey is not a grid of latitude/longitude rectangles. The sky is cut
/// into twelve equal diamonds and each is subdivided in fours, which is what
/// gives every pixel the same area at every declination — and also why a tile
/// cannot simply be pasted into a rectangle on screen. Placing one means
/// knowing where its corners actually fall, which is what this exists for.
///
/// `order` is the HiPS "Norder": side length of a face is `nside = 2^order`,
/// and the whole sky is `12 * nside²` pixels.
enum Healpix {
    static func nside(forOrder order: Int) -> Int { 1 << order }
    static func pixelCount(forOrder order: Int) -> Int { 12 * nside(forOrder: order) * nside(forOrder: order) }

    /// Which pixel a sky position falls in.
    static func pixel(rightAscensionDegrees ra: Double, declinationDegrees dec: Double, order: Int) -> Int {
        let nside = nside(forOrder: order)
        let phi = normalize360(ra) * .pi / 180
        let theta = (90 - dec) * .pi / 180
        let z = cos(theta)
        let za = abs(z)
        // Longitude measured in units of a face's width, so the integer part
        // names the face and the fraction places you within it.
        let tt = (phi * 2 / .pi).truncatingRemainder(dividingBy: 4)

        var face = 0, ix = 0, iy = 0
        if za <= 2.0 / 3.0 {
            // The equatorial belt: faces 4-7, plus the lower halves of 0-3 and
            // the upper halves of 8-11, addressed by the two diagonal edges a
            // point sits between.
            let temp1 = Double(nside) * (0.5 + tt)
            let temp2 = Double(nside) * z * 0.75
            let jp = Int(floor(temp1 - temp2))
            let jm = Int(floor(temp1 + temp2))
            let ifp = jp >> order
            let ifm = jm >> order
            if ifp == ifm { face = (ifp & 3) + 4 }
            else if ifp < ifm { face = ifp & 3 }
            else { face = (ifm & 3) + 8 }
            ix = jm & (nside - 1)
            iy = nside - (jp & (nside - 1)) - 1
        } else {
            // The polar caps, where the faces converge and the spacing of the
            // diamonds is set by how far you are from the pole.
            let ntt = min(3, Int(tt))
            let tp = tt - Double(ntt)
            let tmp = Double(nside) * (3 * (1 - za)).squareRoot()
            var jp = Int(tp * tmp)
            var jm = Int((1 - tp) * tmp)
            jp = min(nside - 1, jp)
            jm = min(nside - 1, jm)
            if z >= 0 {
                face = ntt
                ix = nside - jm - 1
                iy = nside - jp - 1
            } else {
                face = ntt + 8
                ix = jp
                iy = jm
            }
        }
        return face * nside * nside + interleave(ix, iy)
    }

    /// Where the centre of a pixel is on the sky.
    static func centre(ofPixel pixel: Int, order: Int) -> EquatorialCoordinate {
        position(ofPixel: pixel, order: order, offsetX: 0.5, offsetY: 0.5)
    }

    /// A point inside a pixel, given where in it you want — (0,0) and (1,1)
    /// being opposite corners. This is what places a tile on screen: the four
    /// corners of the image are the four corners of the pixel.
    static func position(ofPixel pixel: Int, order: Int,
                         offsetX: Double, offsetY: Double) -> EquatorialCoordinate {
        let nside = nside(forOrder: order)
        let pixelsPerFace = nside * nside
        let face = pixel / pixelsPerFace
        let (ix, iy) = deinterleave(pixel % pixelsPerFace)

        // Position within the face, in the face's own diagonal coordinates.
        let jr = Double(jrll[face]) * Double(nside) - (Double(ix) + offsetX) - (Double(iy) + offsetY)
        let nr: Double
        var z: Double
        var kshift: Double
        let ring = jr
        if ring < Double(nside) {
            // North cap.
            nr = ring
            z = 1 - nr * nr / (3 * Double(nside) * Double(nside))
            kshift = 0
        } else if ring <= 3 * Double(nside) {
            nr = Double(nside)
            z = (2 * Double(nside) - ring) * 2 / (3 * Double(nside))
            kshift = (ring - Double(nside)).truncatingRemainder(dividingBy: 2)
        } else {
            nr = 4 * Double(nside) - ring
            z = -1 + nr * nr / (3 * Double(nside) * Double(nside))
            kshift = 0
        }
        z = max(-1, min(1, z))

        let tmp = Double(jpll[face]) * nr + (Double(ix) + offsetX) - (Double(iy) + offsetY)
        var jp = (tmp - kshift) / 2
        // Wrap into [0, 4nr).
        let fourNr = 4 * nr
        if fourNr > 0 {
            jp = jp.truncatingRemainder(dividingBy: fourNr)
            if jp < 0 { jp += fourNr }
        }
        let phi = nr > 0 ? (jp + 0.5 * kshift) * (.pi / 2) / nr : 0

        let declination = 90 - acos(z) * 180 / .pi
        let rightAscension = normalize360(phi * 180 / .pi)
        return EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
    }

    /// The four corners of a pixel, in the order the tile image's corners run:
    /// top-left, top-right, bottom-right, bottom-left of the stored image.
    static func corners(ofPixel pixel: Int, order: Int) -> [EquatorialCoordinate] {
        // A hair inside the edges: exactly on a boundary the face arithmetic
        // can land in the neighbouring pixel, which throws a corner right
        // across the sky.
        let e = 1e-6
        return [
            position(ofPixel: pixel, order: order, offsetX: e, offsetY: 1 - e),
            position(ofPixel: pixel, order: order, offsetX: 1 - e, offsetY: 1 - e),
            position(ofPixel: pixel, order: order, offsetX: 1 - e, offsetY: e),
            position(ofPixel: pixel, order: order, offsetX: e, offsetY: e),
        ]
    }

    /// Roughly how wide a pixel is, in degrees — the whole sky's area shared
    /// out equally, square-rooted. Good enough for deciding which order to
    /// draw at.
    static func pixelWidthDegrees(order: Int) -> Double {
        (41_252.96 / Double(pixelCount(forOrder: order))).squareRoot()
    }

    /// The order whose pixels are about the size of the field being drawn, so
    /// a view is covered by a handful of tiles rather than one stretched one
    /// or thousands of tiny ones.
    static func order(forFieldOfViewDegrees fov: Double, tilesAcross: Double = 3) -> Int {
        var order = 0
        while order < 11 && pixelWidthDegrees(order: order) > fov / tilesAcross { order += 1 }
        return order
    }

    // MARK: - Face tables and bit interleaving

    /// Which ring each face starts on, and where it sits around the sky.
    private static let jrll = [2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4]
    private static let jpll = [1, 3, 5, 7, 0, 2, 4, 6, 1, 3, 5, 7]

    /// Nested numbering interleaves the bits of the two in-face coordinates,
    /// which is what makes a pixel's children contiguous and lets a tile be
    /// addressed by a single number.
    private static func interleave(_ x: Int, _ y: Int) -> Int {
        var result = 0
        for bit in 0..<32 {
            result |= ((x >> bit) & 1) << (2 * bit)
            result |= ((y >> bit) & 1) << (2 * bit + 1)
        }
        return result
    }

    private static func deinterleave(_ value: Int) -> (x: Int, y: Int) {
        var x = 0, y = 0
        for bit in 0..<32 {
            x |= ((value >> (2 * bit)) & 1) << bit
            y |= ((value >> (2 * bit + 1)) & 1) << bit
        }
        return (x, y)
    }
}
