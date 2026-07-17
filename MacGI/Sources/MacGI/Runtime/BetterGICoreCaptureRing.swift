import CoreGraphics
import Darwin
import Foundation

final class BetterGICoreCaptureRing {
    static let headerSize = 128
    static let slotCount = 2
    static let minimumSlotCapacity = 64 * 1024 * 1024
    private static let magic: [UInt8] = Array("BGIRING1".utf8)

    private let fileURL: URL

    init(runURL: URL) {
        fileURL = runURL.appendingPathComponent("capture-ring.bin")
    }

    func write(_ frame: CaptureImageFrame) throws -> [String: Any] {
        let width = frame.cgImage.width
        let height = frame.cgImage.height
        let stride = width * 4
        let dataLength = stride * height
        let slotCapacity = max(Self.minimumSlotCapacity, Self.pageAligned(dataLength))
        let fileLength = Self.headerSize + Self.slotCount * slotCapacity
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let fd = Darwin.open(fileURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw posixError("open capture ring") }
        defer { Darwin.close(fd) }
        guard Darwin.ftruncate(fd, off_t(fileLength)) == 0 else { throw posixError("resize capture ring") }
        guard Darwin.fchmod(fd, S_IRUSR | S_IWUSR) == 0 else { throw posixError("chmod capture ring") }
        guard let mapping = Darwin.mmap(nil, fileLength, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0),
              mapping != MAP_FAILED
        else { throw posixError("mmap capture ring") }
        defer { Darwin.munmap(mapping, fileLength) }

        let bytes = mapping.assumingMemoryBound(to: UInt8.self)
        let hasValidHeader = Self.magic.enumerated().allSatisfy { bytes[$0.offset] == $0.element }
        let previousSlot = hasValidHeader ? Int(Self.readUInt32(bytes, offset: 24)) : 0
        let slot = (previousSlot + 1) % Self.slotCount
        let previousSequence = hasValidHeader ? Self.readUInt64(bytes, offset: 80) : 0
        let writingSequence = (previousSequence &+ 1) | 1
        Self.writeUInt64(writingSequence, to: bytes, offset: 80)
        OSMemoryBarrier()

        let destination = bytes.advanced(by: Self.headerSize + slot * slotCapacity)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: destination, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: stride, space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                    CGImageAlphaInfo.premultipliedFirst.rawValue
              )
        else { throw BetterGICoreRPCError.protocolViolation("Unable to create BGRA capture-ring context.") }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(frame.cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let previousFrameID = hasValidHeader ? Self.readUInt64(bytes, offset: 56) : 0
        let frameID = previousFrameID &+ 1
        _ = Self.magic.withUnsafeBytes { memcpy(bytes, $0.baseAddress!, Self.magic.count) }
        Self.writeUInt32(1, to: bytes, offset: 8)
        Self.writeUInt32(UInt32(Self.slotCount), to: bytes, offset: 12)
        Self.writeUInt64(UInt64(slotCapacity), to: bytes, offset: 16)
        Self.writeUInt32(UInt32(slot), to: bytes, offset: 24)
        Self.writeUInt32(UInt32(width), to: bytes, offset: 28)
        Self.writeUInt32(UInt32(height), to: bytes, offset: 32)
        Self.writeUInt32(UInt32(stride), to: bytes, offset: 36)
        Self.writeUInt32(0x42475241, to: bytes, offset: 40) // BGRA
        Self.writeUInt64(UInt64(dataLength), to: bytes, offset: 48)
        Self.writeUInt64(frameID, to: bytes, offset: 56)
        let rect = frame.metadata.sourceWindow.captureRect
        Self.writeInt32(Int32(rect.minX), to: bytes, offset: 64)
        Self.writeInt32(Int32(rect.minY), to: bytes, offset: 68)
        Self.writeUInt32(UInt32(rect.width), to: bytes, offset: 72)
        Self.writeUInt32(UInt32(rect.height), to: bytes, offset: 76)
        OSMemoryBarrier()
        let committedSequence = writingSequence &+ 1
        Self.writeUInt64(committedSequence, to: bytes, offset: 80)
        guard Darwin.msync(mapping, fileLength, MS_SYNC) == 0 else { throw posixError("commit capture ring") }

        return [
            "frameId": frameID, "sequence": committedSequence, "ringPath": fileURL.path,
            "slot": slot, "slotCapacity": slotCapacity, "headerSize": Self.headerSize,
            "width": width, "height": height, "stride": stride, "pixelFormat": "BGRA8",
            "dataLength": dataLength, "captureX": Int(rect.minX), "captureY": Int(rect.minY),
            "captureWidth": Int(rect.width), "captureHeight": Int(rect.height),
        ]
    }

    private static func pageAligned(_ value: Int) -> Int {
        let page = Int(getpagesize())
        return ((value + page - 1) / page) * page
    }
    private static func writeUInt32(_ value: UInt32, to bytes: UnsafeMutablePointer<UInt8>, offset: Int) {
        bytes.advanced(by: offset).withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee = value.littleEndian }
    }
    private static func writeInt32(_ value: Int32, to bytes: UnsafeMutablePointer<UInt8>, offset: Int) {
        writeUInt32(UInt32(bitPattern: value), to: bytes, offset: offset)
    }
    private static func writeUInt64(_ value: UInt64, to bytes: UnsafeMutablePointer<UInt8>, offset: Int) {
        bytes.advanced(by: offset).withMemoryRebound(to: UInt64.self, capacity: 1) { $0.pointee = value.littleEndian }
    }
    private static func readUInt32(_ bytes: UnsafeMutablePointer<UInt8>, offset: Int) -> UInt32 {
        bytes.advanced(by: offset).withMemoryRebound(to: UInt32.self, capacity: 1) { UInt32(littleEndian: $0.pointee) }
    }
    private static func readUInt64(_ bytes: UnsafeMutablePointer<UInt8>, offset: Int) -> UInt64 {
        bytes.advanced(by: offset).withMemoryRebound(to: UInt64.self, capacity: 1) { UInt64(littleEndian: $0.pointee) }
    }
    private func posixError(_ operation: String) -> BetterGICoreRPCError {
        .socket("\(operation) failed: \(String(cString: strerror(errno)))")
    }
}
