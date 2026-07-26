import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI Core shared capture ring", .serialized)
struct BetterGICoreCaptureRingTests {
    @Test("Writes committed BGRA frames with monotonic IDs and alternating slots")
    func writesCommittedFrames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-capture-ring-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ring = BetterGICoreCaptureRing(runURL: root)
        let first = try ring.write(makeFrame())
        let second = try ring.write(makeFrame())

        #expect(first["frameId"] as? UInt64 == 1)
        #expect(second["frameId"] as? UInt64 == 2)
        #expect(first["slot"] as? Int == 1)
        #expect(second["slot"] as? Int == 0)
        #expect(second["width"] as? Int == 2)
        #expect(second["height"] as? Int == 2)
        #expect(second["stride"] as? Int == 8)
        #expect(second["pixelFormat"] as? String == "BGRA8")
        #expect(second["captureX"] as? Int == 200)
        #expect(second["captureY"] as? Int == 400)
        #expect(second["captureWidth"] as? Int == 4)
        #expect(second["captureHeight"] as? Int == 4)
        #expect(second["ringName"] as? String == ring.sharedMemoryName)
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("capture-ring.bin").path))

        let descriptor = openBetterGISharedMemory(
            named: ring.sharedMemoryName,
            flags: O_RDONLY)
        let openError = errno
        try #require(
            descriptor >= 0,
            "shm_open failed: \(String(cString: strerror(openError)))")
        defer { Darwin.close(descriptor) }
        let length = BetterGICoreCaptureRing.headerSize +
            BetterGICoreCaptureRing.slotCount * (second["slotCapacity"] as? Int ?? 0)
        let mapping = Darwin.mmap(nil, length, PROT_READ, MAP_SHARED, descriptor, 0)
        let mappingError = errno
        try #require(
            mapping != MAP_FAILED,
            "mmap failed: \(String(cString: strerror(mappingError)))")
        defer { Darwin.munmap(mapping, length) }
        let header = Data(bytes: mapping!, count: BetterGICoreCaptureRing.headerSize)
        #expect(Array(header.prefix(8)) == Array("BGIRING1".utf8))
        #expect(readUInt64(header, at: 56) == 2)
        #expect(readInt32(header, at: 64) == 200)
        #expect(readInt32(header, at: 68) == 400)
        #expect(readUInt32(header, at: 72) == 4)
        #expect(readUInt32(header, at: 76) == 4)
        #expect(readUInt64(header, at: 80) % 2 == 0)

        let slot = second["slot"] as? Int ?? 0
        let slotCapacity = second["slotCapacity"] as? Int ?? 0
        let pixelAddress = mapping!.advanced(
            by: BetterGICoreCaptureRing.headerSize + slot * slotCapacity)
        let pixels = Data(bytes: pixelAddress, count: 16)
        #expect(Array(pixels) == [
            0, 0, 255, 255, 0, 255, 0, 255,
            255, 0, 0, 255, 255, 255, 255, 255,
        ])
    }

    @Test("Keeps the POSIX ring usable when capture dimensions grow")
    func keepsRingUsableWhenDimensionsGrow() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "bettergi-capture-ring-resize-\(UUID().uuidString)",
                isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ring = BetterGICoreCaptureRing(runURL: root)
        let first = try ring.write(makeFrame())
        let larger = try ring.write(makeSolidFrame(width: 64, height: 64))

        #expect(first["ringName"] as? String == larger["ringName"] as? String)
        #expect(
            first["slotCapacity"] as? Int ==
                BetterGICoreCaptureRing.minimumSlotCapacity)
        #expect(
            larger["slotCapacity"] as? Int ==
                BetterGICoreCaptureRing.minimumSlotCapacity)
        #expect(larger["width"] as? Int == 64)
        #expect(larger["height"] as? Int == 64)
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
            isOnScreen: true, scaleFactor: 2
        )
        let metadata = CapturedFrame(
            frameIndex: 1, timestamp: Date(timeIntervalSince1970: 1), width: 2, height: 2,
            scaleFactor: 2, pixelFormat: 0x42475241, bytesPerRow: 8, sourceWindow: window
        )
        return CaptureImageFrame(metadata: metadata, cgImage: image, backendName: "Test")
    }

    private func makeSolidFrame(
        width: Int,
        height: Int
    ) throws -> CaptureImageFrame {
        let context = try #require(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                CGImageAlphaInfo.premultipliedFirst.rawValue
        ))
        let image = try #require(context.makeImage())
        let window = WindowInfo(
            id: 42, ownerPID: 10, ownerName: "wine", title: "原神",
            frame: CGRect(x: 100, y: 200, width: width, height: height),
            layer: 0, isOnScreen: true, scaleFactor: 2
        )
        let metadata = CapturedFrame(
            frameIndex: 2, timestamp: Date(timeIntervalSince1970: 2),
            width: width, height: height, scaleFactor: 2,
            pixelFormat: 0x42475241, bytesPerRow: width * 4,
            sourceWindow: window
        )
        return CaptureImageFrame(
            metadata: metadata, cgImage: image, backendName: "Test")
    }

    private func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        data[offset ..< offset + 8].enumerated().reduce(0) { value, byte in
            value | UInt64(byte.element) << UInt64(byte.offset * 8)
        }
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset ..< offset + 4].enumerated().reduce(0) { value, byte in
            value | UInt32(byte.element) << UInt32(byte.offset * 8)
        }
    }

    private func readInt32(_ data: Data, at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32(data, at: offset))
    }
}
