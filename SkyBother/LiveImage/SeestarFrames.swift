import Foundation
import CoreGraphics
import ImageIO
import Compression

/// The Seestar's image socket (port 4800, telephoto): binary frames with an
/// 80-byte header, interleaved with `\r\n`-terminated JSON replies to our
/// heartbeats. Worked out from SeeStar-Py's protocol notes
/// (seestarpy.readthedocs.io), which is the only public description; ZWO
/// don't document it.
enum SeestarFrames {
    static let magic: UInt16 = 0x03C3
    /// The named fields; the header itself says how long it really is.
    static let namedHeaderSize = 34
    static let defaultHeaderSize = 80

    enum ImageType: UInt8 {
        case ack = 0
        /// One unstacked exposure, raw Bayer.
        case preview = 1
        /// The stack as a finished JPEG, already stretched (firmware 8.46+).
        case jpegStack = 4
        /// The stack as linear 16-bit RGB, raw or zipped.
        case rawStack = 5
    }

    struct Header: Equatable {
        var headerSize: Int
        var length: Int
        var imageType: UInt8
        var width: Int
        var height: Int
        var imageID: Int

        var type: ImageType? { ImageType(rawValue: imageType) }
        var isStack: Bool { type == .jpegStack || type == .rawStack }

        init(headerSize: Int, length: Int, imageType: UInt8, width: Int, height: Int, imageID: Int) {
            self.headerSize = headerSize
            self.length = length
            self.imageType = imageType
            self.width = width
            self.height = height
            self.imageID = imageID
        }

        /// Big-endian fields from the first 34 bytes.
        init?(_ bytes: Data) {
            guard bytes.count >= SeestarFrames.namedHeaderSize else { return nil }
            let b = [UInt8](bytes.prefix(SeestarFrames.namedHeaderSize))
            func u16(_ at: Int) -> Int { Int(b[at]) << 8 | Int(b[at + 1]) }
            guard UInt16(u16(0)) == SeestarFrames.magic else { return nil }
            let declared = u16(4)
            headerSize = (SeestarFrames.namedHeaderSize...4096).contains(declared) ? declared : SeestarFrames.defaultHeaderSize
            length = Int(b[6]) << 24 | Int(b[7]) << 16 | Int(b[8]) << 8 | Int(b[9])
            imageType = b[13]
            width = u16(16)
            height = u16(18)
            imageID = u16(28)
        }
    }

    struct Frame {
        var header: Header
        var payload: Data
    }

    /// Pulls whole frames out of the byte stream as it arrives, skipping the
    /// JSON lines between them.
    struct Reader {
        private var buffer = Data()

        mutating func append(_ data: Data) {
            buffer.append(data)
        }

        /// The next complete frame, or nil until more bytes arrive.
        mutating func nextFrame() -> Frame? {
            while true {
                guard let first = buffer.first else { return nil }
                if first == UInt8(ascii: "{") {
                    // A JSON reply: drop through its line ending.
                    guard let end = buffer.firstRange(of: Data("\r\n".utf8)) else {
                        if buffer.count > 4096 { buffer.removeFirst() }
                        return nil
                    }
                    buffer.removeSubrange(buffer.startIndex..<end.upperBound)
                    continue
                }
                guard buffer.count >= 2 else { return nil }
                let start = buffer.startIndex
                if buffer[start] != 0x03 || buffer[start + 1] != 0xC3 {
                    buffer.removeFirst()
                    continue
                }
                guard buffer.count >= SeestarFrames.namedHeaderSize else { return nil }
                guard let header = Header(buffer) else {
                    buffer.removeFirst()
                    continue
                }
                let total = header.headerSize + header.length
                guard buffer.count >= total else { return nil }
                let payload = buffer.subdata(in: (start + header.headerSize)..<(start + total))
                buffer.removeSubrange(start..<(start + total))
                buffer = Data(buffer)   // re-base indices to zero
                return Frame(header: header, payload: payload)
            }
        }
    }

    enum DecodeError: Error {
        case notAnImage
        case unknownFormat(bytes: Int, width: Int, height: Int)
    }

    /// A displayable picture of a stack frame. A JPEG stack is used as it
    /// comes, because the firmware has already stretched it; a raw stack is
    /// linear and gets the same kind of automatic stretch astro software
    /// uses, or it looks black.
    static func image(from frame: Frame) throws -> CGImage {
        let payload = frame.payload
        if payload.starts(with: [0xFF, 0xD8, 0xFF]) {
            guard let source = CGImageSourceCreateWithData(payload as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw DecodeError.notAnImage }
            return image
        }
        let width = frame.header.width, height = frame.header.height
        guard width > 0, height > 0 else { throw DecodeError.notAnImage }
        let expected = width * height * 3 * 2
        let pixels: Data
        if payload.count == expected {
            pixels = payload
        } else if let unzipped = unzip(payload, expectedSize: expected) {
            pixels = unzipped
        } else {
            throw DecodeError.unknownFormat(bytes: payload.count, width: width, height: height)
        }
        return try stretchedImage(rgb16: pixels, width: width, height: height)
    }

    /// Older firmware zips the raw stack: a single entry after some zero
    /// bytes, compressed with raw deflate.
    static func unzip(_ payload: Data, expectedSize: Int) -> Data? {
        guard let signature = payload.firstRange(of: Data([0x50, 0x4B, 0x03, 0x04])) else { return nil }
        let pk = signature.lowerBound
        guard payload.count > pk + 30 else { return nil }
        func u16le(_ at: Int) -> Int { Int(payload[at]) | Int(payload[at + 1]) << 8 }
        let dataStart = pk + 30 + u16le(pk + 26) + u16le(pk + 28)
        guard dataStart < payload.endIndex else { return nil }
        let compressed = payload[dataStart...]
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { out in
            compressed.withUnsafeBytes { input in
                // COMPRESSION_ZLIB is raw deflate, which is what a zip entry holds.
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                                          input.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        return written == expectedSize ? output : nil
    }

    /// Linked screen-transfer stretch, as SeeStar-Py and PixInsight do it:
    /// black point from the noise below the median, white point near the
    /// top, and a midtone solved to put the sky background at 15% grey.
    static func stretchedImage(rgb16: Data, width: Int, height: Int) throws -> CGImage {
        let count = width * height
        var rgb = [UInt8](repeating: 255, count: count * 4)
        rgb16.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: UInt16.self)
            func luminance(_ pixel: Int) -> Float {
                (Float(UInt16(littleEndian: samples[pixel * 3]))
                 + Float(UInt16(littleEndian: samples[pixel * 3 + 1]))
                 + Float(UInt16(littleEndian: samples[pixel * 3 + 2]))) / 3
            }
            // Statistics from a sample of the frame are close enough, and
            // far quicker than sorting eight million pixels.
            let step = max(1, count / 200_000)
            var sample = stride(from: 0, to: count, by: step).map(luminance)
            sample.sort()
            let median = sample[sample.count / 2]
            var deviations = sample.map { abs($0 - median) }
            deviations.sort()
            let madn = 1.4826 * deviations[deviations.count / 2]
            let black = median - 2.8 * madn
            var white = sample[min(sample.count - 1, Int(Float(sample.count) * 0.9995))]
            if white <= black { white = black + 1 }
            let span = white - black
            let target: Float = 0.15
            let x0 = min(max((median - black) / span, 1e-6), 0.999)
            var m = (x0 * (target - 1)) / (2 * target * x0 - target - x0)
            m = min(max(m, 1e-4), 0.9999)
            // One curve for all three channels, as a 16-bit lookup table.
            var table = [UInt8](repeating: 0, count: 65536)
            for value in 0..<65536 {
                let x = min(max((Float(value) - black) / span, 0), 1)
                let y = (m - 1) * x / ((2 * m - 1) * x - m)
                table[value] = UInt8(min(max(y, 0), 1) * 255 + 0.5)
            }
            for pixel in 0..<count {
                rgb[pixel * 4] = table[Int(UInt16(littleEndian: samples[pixel * 3]))]
                rgb[pixel * 4 + 1] = table[Int(UInt16(littleEndian: samples[pixel * 3 + 1]))]
                rgb[pixel * 4 + 2] = table[Int(UInt16(littleEndian: samples[pixel * 3 + 2]))]
            }
        }
        guard let provider = CGDataProvider(data: Data(rgb) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent) else { throw DecodeError.notAnImage }
        return image
    }
}
