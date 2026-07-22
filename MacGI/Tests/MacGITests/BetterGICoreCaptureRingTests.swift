import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI Core shared capture ring")
struct BetterGICoreCaptureRingTests {
    @Test("Writes committed BGRA frames with monotonic IDs and alternating slots")
    func writesCommittedFrames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-capture-ring-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ring = BetterGICoreCaptureRing(runURL: root)
        let first = try ring.write(makeFrame())
        let second = try BetterGICoreCaptureRing(runURL: root).write(makeFrame())

        #expect(first["frameId"] as? UInt64 == 1)
        #expect(second["frameId"] as? UInt64 == 2)
        #expect(first["slot"] as? Int == 1)
        #expect(second["slot"] as? Int == 0)
        #expect(second["width"] as? Int == 2)
        #expect(second["height"] as? Int == 2)
        #expect(second["stride"] as? Int == 8)
        #expect(second["pixelFormat"] as? String == "BGRA8")

        let fileURL = root.appendingPathComponent("capture-ring.bin")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let header = try #require(try handle.read(upToCount: BetterGICoreCaptureRing.headerSize))
        #expect(Array(header.prefix(8)) == Array("BGIRING1".utf8))
        #expect(readUInt64(header, at: 56) == 2)
        #expect(readUInt64(header, at: 80) % 2 == 0)

        try handle.seek(toOffset: UInt64(BetterGICoreCaptureRing.headerSize))
        let pixels = try #require(try handle.read(upToCount: 16))
        #expect(Array(pixels) == [
            0, 0, 255, 255, 0, 255, 0, 255,
            255, 0, 0, 255, 255, 255, 255, 255,
        ])
    }

    private func makeFrame() throws -> CaptureImageFrame {
        let pixelBytes: [UInt8] = [
            0, 0, 255, 255, 0, 255, 0, 255,
            255, 0, 0, 255, 255, 255, 255, 255,
        ]
        let provider = try #require(CGDataProvider(data: Data(pixelBytes) as CFData))
        let image = try #require(CGImage(
            width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue |
                CGImageAlphaInfo.premultipliedFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let window = WindowInfo(
            id: 42, ownerPID: 10, ownerName: "wine", title: "原神",
            frame: CGRect(x: 100, y: 200, width: 2, height: 2), layer: 0,
            isOnScreen: true, scaleFactor: 1
        )
        let metadata = CapturedFrame(
            frameIndex: 1, timestamp: Date(timeIntervalSince1970: 1), width: 2, height: 2,
            scaleFactor: 1, pixelFormat: 0x42475241, bytesPerRow: 8, sourceWindow: window
        )
        return CaptureImageFrame(metadata: metadata, cgImage: image, backendName: "Test")
    }

    private func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        data[offset ..< offset + 8].enumerated().reduce(0) { value, byte in
            value | UInt64(byte.element) << UInt64(byte.offset * 8)
        }
    }
}
