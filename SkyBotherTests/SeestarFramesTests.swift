import XCTest
import Compression

/// The Seestar image socket's framing and decoding, against hand-built
/// frames laid out the way SeeStar-Py documents them.
final class SeestarFramesTests: XCTestCase {
    private func frameBytes(type: UInt8, width: Int = 0, height: Int = 0, imageID: Int = 7,
                            payload: Data, headerSize: Int = 80) -> Data {
        var header = [UInt8](repeating: 0, count: headerSize)
        header[0] = 0x03; header[1] = 0xC3
        header[3] = 2
        header[4] = UInt8(headerSize >> 8); header[5] = UInt8(headerSize & 0xFF)
        let length = payload.count
        header[6] = UInt8(length >> 24 & 0xFF); header[7] = UInt8(length >> 16 & 0xFF)
        header[8] = UInt8(length >> 8 & 0xFF); header[9] = UInt8(length & 0xFF)
        header[13] = type
        header[16] = UInt8(width >> 8); header[17] = UInt8(width & 0xFF)
        header[18] = UInt8(height >> 8); header[19] = UInt8(height & 0xFF)
        header[28] = UInt8(imageID >> 8); header[29] = UInt8(imageID & 0xFF)
        return Data(header) + payload
    }

    func testSkipsJSONLinesAndReadsFrames() {
        var reader = SeestarFrames.Reader()
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        reader.append(Data("{\"jsonrpc\":\"2.0\",\"method\":\"test_connection\",\"result\":\"server connected!\"}\r\n".utf8))
        reader.append(frameBytes(type: 0, payload: Data([0, 0, 0, 0])))
        reader.append(frameBytes(type: 4, imageID: 42, payload: jpeg))

        let ack = reader.nextFrame()
        XCTAssertEqual(ack?.header.type, .ack)
        let stack = reader.nextFrame()
        XCTAssertEqual(stack?.header.type, .jpegStack)
        XCTAssertEqual(stack?.header.imageID, 42)
        XCTAssertEqual(stack?.payload, jpeg)
        XCTAssertNil(reader.nextFrame())
    }

    func testWaitsForAFrameSplitAcrossReads() {
        var reader = SeestarFrames.Reader()
        let bytes = frameBytes(type: 5, width: 2, height: 1, payload: Data(repeating: 9, count: 12))
        reader.append(bytes.prefix(50))
        XCTAssertNil(reader.nextFrame())
        reader.append(bytes.dropFirst(50))
        let frame = reader.nextFrame()
        XCTAssertEqual(frame?.header.width, 2)
        XCTAssertEqual(frame?.payload.count, 12)
    }

    func testUsesTheHeaderSizeTheFrameDeclares() {
        var reader = SeestarFrames.Reader()
        reader.append(frameBytes(type: 4, payload: Data([0xFF, 0xD8, 0xFF]), headerSize: 96))
        XCTAssertEqual(reader.nextFrame()?.payload, Data([0xFF, 0xD8, 0xFF]))
    }

    func testStretchesARawStack() throws {
        // A dim noisy sky with one bright star: the stretch should lift the
        // sky well off black and leave the star white.
        let width = 64, height = 64
        var samples = [UInt16]()
        for pixel in 0..<(width * height) {
            let sky = UInt16(1000 + (pixel * 7919) % 40)
            let value: UInt16 = pixel == 2080 ? 60000 : sky
            samples += [value, value, value]
        }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let frame = SeestarFrames.Frame(header: .init(headerSize: 80, length: data.count, imageType: 5,
                                                      width: width, height: height, imageID: 1),
                                        payload: data)
        let image = try SeestarFrames.image(from: frame)
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, height)

        let bytes = try XCTUnwrap(image.dataProvider?.data as Data?)
        let median = bytes[(1000 * 4)]
        XCTAssertGreaterThan(median, 10, "sky shouldn't be black")
        XCTAssertLessThan(median, 120, "sky shouldn't be grey mush")
        XCTAssertEqual(bytes[2080 * 4], 255)
    }

    func testUnzipsAnOlderFirmwareStack() throws {
        let width = 4, height = 2
        let raw = Data((0..<(width * height * 3 * 2)).map { UInt8($0 % 251) })
        // A zip local-file header ("raw_data") ahead of a stored-as-deflate
        // body, with a few zero bytes in front the way the scope sends it.
        let deflated = try XCTUnwrap(Self.rawDeflate(raw))
        var zip = Data([0, 0, 0])
        zip += Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0, count: 22)
        zip += Data([8, 0, 0, 0]) + Data("raw_data".utf8) + deflated
        XCTAssertEqual(SeestarFrames.unzip(zip, expectedSize: raw.count), raw)
    }

    private static func rawDeflate(_ data: Data) -> Data? {
        var output = Data(count: data.count + 1024)
        let count = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                compression_encode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, out.count,
                                          input.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        return count > 0 ? output.prefix(count) : nil
    }

    func testOnlyTheS50ProIsOffered() {
        XCTAssertEqual(LiveImageAvailability.of(.seestarS50Pro), .supported(port: 4800))
        if case .supported = LiveImageAvailability.of(.seestarS50) { XCTFail("S50 isn't verified yet") }
        if case .supported = LiveImageAvailability.of(.seestarS50ProWide) { XCTFail("wide camera isn't verified") }
    }
}
