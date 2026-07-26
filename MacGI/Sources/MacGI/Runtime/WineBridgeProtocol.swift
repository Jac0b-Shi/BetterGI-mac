import Foundation

enum WineBridgeCommand: UInt16 {
    case hello = 1
    case authenticate = 2
    case discoverTarget = 3
    case registerTarget = 4
    case ping = 5
    case queryForeground = 6
    case setForeground = 7
    case keyDown = 10
    case keyUp = 11
    case keyPress = 12
    case mouseButtonDown = 20
    case mouseButtonUp = 21
    case mouseClick = 22
    case mouseMoveAbsolute = 23
    case mouseMoveRelative = 24
    case mouseWheel = 25
    case inputText = 30
    case queryKeyState = 40
    case queryMouseButtonState = 41
    case releaseAll = 50
    case shutdown = 51
}

enum WineBridgeStatus: UInt32 {
    case ok = 0
    case invalidHeader = 1
    case unsupportedVersion = 2
    case unsupportedCommand = 3
    case authenticationRequired = 4
    case authenticationFailed = 5
    case alreadyAuthenticated = 6
    case invalidPayload = 7
    case targetRequired = 8
    case targetNotFound = 9
    case targetMismatch = 10
    case inputFailed = 11
    case internalError = 12
}

enum WineBridgeProtocol {
    static let magic: UInt32 = 0x3149_4742
    static let version: UInt16 = 1
    static let headerSize = 24
    static let maximumPayloadSize = 65_536
    static let inputMarker: UInt64 = 0x4247_4957_494E_45
}

struct WineBridgePacketHeader: Equatable {
    let command: WineBridgeCommand
    let requestID: UInt32
    let payloadLength: UInt32
    let status: UInt32

    func encoded() -> Data {
        var data = Data()
        data.appendLittleEndian(WineBridgeProtocol.magic)
        data.appendLittleEndian(WineBridgeProtocol.version)
        data.appendLittleEndian(command.rawValue)
        data.appendLittleEndian(requestID)
        data.appendLittleEndian(payloadLength)
        data.appendLittleEndian(status)
        data.appendLittleEndian(UInt32(0))
        return data
    }

    static func decode(_ data: Data) throws -> WineBridgePacketHeader {
        guard data.count == WineBridgeProtocol.headerSize else {
            throw WineBridgeError.invalidResponse("header length \(data.count)")
        }
        var reader = WineBridgeDataReader(data)
        guard try reader.readUInt32() == WineBridgeProtocol.magic else {
            throw WineBridgeError.invalidResponse("header magic")
        }
        guard try reader.readUInt16() == WineBridgeProtocol.version else {
            throw WineBridgeError.invalidResponse("protocol version")
        }
        let rawCommand = try reader.readUInt16()
        guard let command = WineBridgeCommand(rawValue: rawCommand) else {
            throw WineBridgeError.invalidResponse("command \(rawCommand)")
        }
        let requestID = try reader.readUInt32()
        let payloadLength = try reader.readUInt32()
        let status = try reader.readUInt32()
        guard try reader.readUInt32() == 0,
              payloadLength <= WineBridgeProtocol.maximumPayloadSize else {
            throw WineBridgeError.invalidResponse("reserved field or payload length")
        }
        return WineBridgePacketHeader(
            command: command,
            requestID: requestID,
            payloadLength: payloadLength,
            status: status)
    }
}

struct WineBridgeTarget: Equatable {
    let processID: UInt32
    let windowHandle: UInt64
    let executableName: String

    func encoded() throws -> Data {
        guard let name = executableName.data(using: .utf8), name.count < 64 else {
            throw WineBridgeError.invalidConfiguration("Invalid target executable name")
        }
        var data = Data()
        data.appendLittleEndian(processID)
        data.appendLittleEndian(UInt32(0))
        data.appendLittleEndian(windowHandle)
        data.append(name)
        data.append(Data(repeating: 0, count: 64 - name.count))
        return data
    }

    static func decode(_ data: Data) throws -> WineBridgeTarget {
        guard data.count == 80 else {
            throw WineBridgeError.invalidResponse("target length \(data.count)")
        }
        var reader = WineBridgeDataReader(data)
        let processID = try reader.readUInt32()
        _ = try reader.readUInt32()
        let windowHandle = try reader.readUInt64()
        let nameData = try reader.readData(count: 64)
        let bytes = nameData.prefix { $0 != 0 }
        guard let name = String(data: bytes, encoding: .utf8), !name.isEmpty else {
            throw WineBridgeError.invalidResponse("target executable name")
        }
        return WineBridgeTarget(
            processID: processID,
            windowHandle: windowHandle,
            executableName: name)
    }
}

struct WineBridgeForegroundDiagnostic: Equatable {
    static let encodedSize = 148

    let targetProcessID: UInt32
    let foregroundProcessID: UInt32
    let targetThreadID: UInt32
    let foregroundThreadID: UInt32
    let targetWindow: UInt64
    let foregroundWindow: UInt64
    let activeWindow: UInt64
    let focusWindow: UInt64
    let captureWindow: UInt64
    let menuOwnerWindow: UInt64
    let moveSizeWindow: UInt64
    let setForegroundResult: Int32
    let flags: UInt32
    let testVirtualKey: UInt16
    let asyncKeyState: UInt16
    let foregroundExecutableName: String

    var targetIsWindow: Bool { flags & 1 != 0 }
    var targetIsVisible: Bool { flags & 2 != 0 }

    static func decode(_ data: Data) throws -> WineBridgeForegroundDiagnostic {
        guard data.count == encodedSize else {
            throw WineBridgeError.invalidResponse(
                "foreground diagnostic length \(data.count)")
        }
        var reader = WineBridgeDataReader(data)
        let targetProcessID = try reader.readUInt32()
        let foregroundProcessID = try reader.readUInt32()
        let targetThreadID = try reader.readUInt32()
        let foregroundThreadID = try reader.readUInt32()
        let targetWindow = try reader.readUInt64()
        let foregroundWindow = try reader.readUInt64()
        let activeWindow = try reader.readUInt64()
        let focusWindow = try reader.readUInt64()
        let captureWindow = try reader.readUInt64()
        let menuOwnerWindow = try reader.readUInt64()
        let moveSizeWindow = try reader.readUInt64()
        let setForegroundResult = Int32(bitPattern: try reader.readUInt32())
        let flags = try reader.readUInt32()
        let testVirtualKey = try reader.readUInt16()
        let asyncKeyState = try reader.readUInt16()
        let executableData = try reader.readData(count: 64)
        let executableBytes = executableData.prefix { $0 != 0 }
        let executableName = String(data: executableBytes, encoding: .utf8) ?? ""
        return WineBridgeForegroundDiagnostic(
            targetProcessID: targetProcessID,
            foregroundProcessID: foregroundProcessID,
            targetThreadID: targetThreadID,
            foregroundThreadID: foregroundThreadID,
            targetWindow: targetWindow,
            foregroundWindow: foregroundWindow,
            activeWindow: activeWindow,
            focusWindow: focusWindow,
            captureWindow: captureWindow,
            menuOwnerWindow: menuOwnerWindow,
            moveSizeWindow: moveSizeWindow,
            setForegroundResult: setForegroundResult,
            flags: flags,
            testVirtualKey: testVirtualKey,
            asyncKeyState: asyncKeyState,
            foregroundExecutableName: executableName)
    }

    var logDescription: String {
        "targetPID=\(targetProcessID) hwnd=0x\(String(targetWindow, radix: 16)) "
            + "valid=\(targetIsWindow) visible=\(targetIsVisible) "
            + "foregroundPID=\(foregroundProcessID) "
            + "foregroundExe=\(foregroundExecutableName.isEmpty ? "<unknown>" : foregroundExecutableName) "
            + "foreground=0x\(String(foregroundWindow, radix: 16)) "
            + "active=0x\(String(activeWindow, radix: 16)) "
            + "focus=0x\(String(focusWindow, radix: 16)) "
            + "capture=0x\(String(captureWindow, radix: 16)) "
            + "menu=0x\(String(menuOwnerWindow, radix: 16)) "
            + "moveSize=0x\(String(moveSizeWindow, radix: 16)) "
            + "targetThread=\(targetThreadID) foregroundThread=\(foregroundThreadID) "
            + "testVK=0x\(String(testVirtualKey, radix: 16)) "
            + "async=0x\(String(asyncKeyState, radix: 16)) "
            + "setForeground=\(setForegroundResult)"
    }
}

struct WineBridgeDataReader {
    private let data: Data
    private var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    mutating func readUInt16() throws -> UInt16 {
        let bytes = try readData(count: 2)
        return bytes.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(as: UInt16.self)) }
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readData(count: 4)
        return bytes.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    }

    mutating func readUInt64() throws -> UInt64 {
        let bytes = try readData(count: 8)
        return bytes.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw WineBridgeError.invalidResponse("truncated payload")
        }
        defer { offset += count }
        return data.subdata(in: offset ..< offset + count)
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
