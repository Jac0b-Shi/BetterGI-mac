import CoreGraphics
import Darwin
import Foundation
import MacGIShims

func openBetterGISharedMemory(
    named name: String,
    flags: Int32,
    mode: mode_t = 0
) -> Int32 {
    name.withCString {
        bettergi_shm_open($0, flags, UInt32(mode))
    }
}

final class BetterGICoreCaptureRing {
    static let headerSize = 128
    static let slotCount = 2
    static let minimumSlotCapacity = 64 * 1024 * 1024
    private static let magic: [UInt8] = Array("BGIRING1".utf8)

    let sharedMemoryName: String

    private let legacyFileURL: URL
    private var fileDescriptor: Int32 = -1
    private var mapping: UnsafeMutableRawPointer?
    private var mappingLength = 0
    private var slotCapacity = 0
    private var activeSlot = 0
    private var frameID: UInt64 = 0
    private var sequence: UInt64 = 0

    init(runURL: URL) {
        legacyFileURL = runURL.appendingPathComponent("capture-ring.bin")
        sharedMemoryName = "/bettergi-mac-capture-\(getuid())-\(getpid())"
        Darwin.shm_unlink(sharedMemoryName)
    }

    deinit {
        if let mapping {
            Darwin.munmap(mapping, mappingLength)
        }
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
        }
        Darwin.shm_unlink(sharedMemoryName)
    }

    func write(_ frame: CaptureImageFrame) throws -> [String: Any] {
        let width = frame.cgImage.width
        let height = frame.cgImage.height
        let stride = width * 4
        let dataLength = stride * height
        try ensureCapacity(for: dataLength)

        guard let mapping else {
            throw BetterGICoreRPCError.protocolViolation(
                "Capture shared memory is not mapped.")
        }
        let bytes = mapping.assumingMemoryBound(to: UInt8.self)
        activeSlot = (activeSlot + 1) % Self.slotCount
        sequence = (sequence &+ 1) | 1
        Self.writeUInt64(sequence, to: bytes, offset: 80)
        OSMemoryBarrier()

        let destination = bytes.advanced(
            by: Self.headerSize + activeSlot * slotCapacity)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: destination, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: stride, space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                    CGImageAlphaInfo.premultipliedFirst.rawValue
              )
        else {
            throw BetterGICoreRPCError.protocolViolation(
                "Unable to create BGRA capture-ring context.")
        }
        context.draw(
            frame.cgImage,
            in: CGRect(x: 0, y: 0, width: width, height: height))

        frameID &+= 1
        _ = Self.magic.withUnsafeBytes {
            memcpy(bytes, $0.baseAddress!, Self.magic.count)
        }
        Self.writeUInt32(1, to: bytes, offset: 8)
        Self.writeUInt32(UInt32(Self.slotCount), to: bytes, offset: 12)
        Self.writeUInt64(UInt64(slotCapacity), to: bytes, offset: 16)
        Self.writeUInt32(UInt32(activeSlot), to: bytes, offset: 24)
        Self.writeUInt32(UInt32(width), to: bytes, offset: 28)
        Self.writeUInt32(UInt32(height), to: bytes, offset: 32)
        Self.writeUInt32(UInt32(stride), to: bytes, offset: 36)
        Self.writeUInt32(0x42475241, to: bytes, offset: 40) // BGRA
        Self.writeUInt64(UInt64(dataLength), to: bytes, offset: 48)
        Self.writeUInt64(frameID, to: bytes, offset: 56)
        let rect = frame.metadata.sourceWindow.captureRect
        let scale = max(1, frame.metadata.scaleFactor)
        let captureX = Int((rect.minX * scale).rounded())
        let captureY = Int((rect.minY * scale).rounded())
        let captureWidth = Int((rect.width * scale).rounded())
        let captureHeight = Int((rect.height * scale).rounded())
        Self.writeInt32(Int32(captureX), to: bytes, offset: 64)
        Self.writeInt32(Int32(captureY), to: bytes, offset: 68)
        Self.writeUInt32(UInt32(captureWidth), to: bytes, offset: 72)
        Self.writeUInt32(UInt32(captureHeight), to: bytes, offset: 76)
        OSMemoryBarrier()
        sequence &+= 1
        Self.writeUInt64(sequence, to: bytes, offset: 80)

        return [
            "frameId": frameID,
            "sequence": sequence,
            "ringName": sharedMemoryName,
            "slot": activeSlot,
            "slotCapacity": slotCapacity,
            "headerSize": Self.headerSize,
            "width": width,
            "height": height,
            "stride": stride,
            "pixelFormat": "BGRA8",
            "dataLength": dataLength,
            "captureX": captureX,
            "captureY": captureY,
            "captureWidth": captureWidth,
            "captureHeight": captureHeight,
        ]
    }

    private func ensureCapacity(for dataLength: Int) throws {
        // macOS POSIX shm objects cannot grow after their first ftruncate.
        let requiredCapacity = max(
            Self.minimumSlotCapacity,
            Self.pageAligned(dataLength))
        guard mapping == nil || requiredCapacity > slotCapacity else {
            return
        }

        if fileDescriptor < 0 {
            fileDescriptor = openBetterGISharedMemory(
                named: sharedMemoryName,
                flags: O_RDWR | O_CREAT | O_EXCL,
                mode: S_IRUSR | S_IWUSR)
            if fileDescriptor < 0, errno == EEXIST {
                Darwin.shm_unlink(sharedMemoryName)
                fileDescriptor = openBetterGISharedMemory(
                    named: sharedMemoryName,
                    flags: O_RDWR | O_CREAT | O_EXCL,
                    mode: S_IRUSR | S_IWUSR)
            }
            guard fileDescriptor >= 0 else {
                throw posixError("open capture shared memory")
            }
            try? FileManager.default.removeItem(at: legacyFileURL)
        }

        let nextLength =
            Self.headerSize + Self.slotCount * requiredCapacity
        guard Darwin.ftruncate(fileDescriptor, off_t(nextLength)) == 0 else {
            throw posixError("resize capture shared memory")
        }
        guard let nextMapping = Darwin.mmap(
            nil, nextLength, PROT_READ | PROT_WRITE,
            MAP_SHARED, fileDescriptor, 0),
            nextMapping != MAP_FAILED
        else {
            throw posixError("mmap capture shared memory")
        }
        if let mapping {
            Darwin.munmap(mapping, mappingLength)
        }
        mapping = nextMapping
        mappingLength = nextLength
        slotCapacity = requiredCapacity
        memset(nextMapping, 0, Self.headerSize)
    }

    private static func pageAligned(_ value: Int) -> Int {
        let page = Int(getpagesize())
        return ((value + page - 1) / page) * page
    }

    private static func writeUInt32(
        _ value: UInt32,
        to bytes: UnsafeMutablePointer<UInt8>,
        offset: Int
    ) {
        bytes.advanced(by: offset).withMemoryRebound(
            to: UInt32.self, capacity: 1
        ) {
            $0.pointee = value.littleEndian
        }
    }

    private static func writeInt32(
        _ value: Int32,
        to bytes: UnsafeMutablePointer<UInt8>,
        offset: Int
    ) {
        writeUInt32(UInt32(bitPattern: value), to: bytes, offset: offset)
    }

    private static func writeUInt64(
        _ value: UInt64,
        to bytes: UnsafeMutablePointer<UInt8>,
        offset: Int
    ) {
        bytes.advanced(by: offset).withMemoryRebound(
            to: UInt64.self, capacity: 1
        ) {
            $0.pointee = value.littleEndian
        }
    }

    private func posixError(_ operation: String) -> BetterGICoreRPCError {
        .socket("\(operation) failed: \(String(cString: strerror(errno)))")
    }
}
