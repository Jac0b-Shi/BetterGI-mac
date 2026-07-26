import Darwin
import Foundation
import Security

enum WineBridgeError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case bridgeUnavailable(String)
    case bridgeExited(Int32)
    case connectionFailed(String)
    case invalidResponse(String)
    case requestFailed(WineBridgeCommand, UInt32)
    case unsupportedKey(KeyCode)
    case unsupportedModifier
    case unsupportedMouseButton(InputMouseButton)
    case syntheticWindow

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(detail):
            "Wine bridge configuration is invalid: \(detail)"
        case let .bridgeUnavailable(detail):
            "Wine bridge is unavailable: \(detail)"
        case let .bridgeExited(status):
            "Wine bridge exited with status \(status)"
        case let .connectionFailed(detail):
            "Wine bridge connection failed: \(detail)"
        case let .invalidResponse(detail):
            "Wine bridge returned an invalid response: \(detail)"
        case let .requestFailed(command, status):
            "Wine bridge command \(command) failed with status \(status)"
        case let .unsupportedKey(key):
            "Wine bridge has no Windows virtual-key mapping for \(key.displayName)"
        case .unsupportedModifier:
            "Wine bridge does not support the Command modifier"
        case let .unsupportedMouseButton(button):
            "Wine bridge does not support mouse button \(button.displayName)"
        case .syntheticWindow:
            "Wine bridge cannot target a synthetic window sentinel"
        }
    }
}

struct WineBridgeConfiguration: Equatable {
    let wineExecutableURL: URL
    let winePrefixURL: URL
    let bridgeExecutableURL: URL
    let targetExecutableNames: [String]
    let startupTimeout: TimeInterval

    static func resolve(
        launchArguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> WineBridgeConfiguration {
        let arguments = CommandLineOptions(launchArguments)
        let home = fileManager.homeDirectoryForCurrentUser
        let yaaglRoot = home
            .appendingPathComponent("Library/Application Support/Yaagl OS", isDirectory: true)

        let wineExecutableURL = try resolveFile(
            explicit: arguments.value(after: "--wine-executable")
                ?? environment["BETTERGI_WINE_EXECUTABLE"],
            candidates: [
                yaaglRoot.appendingPathComponent("wine/bin/wine")
            ],
            description: "Wine executable",
            fileManager: fileManager)
        let winePrefixURL = URL(fileURLWithPath:
            arguments.value(after: "--wine-prefix")
                ?? environment["BETTERGI_WINE_PREFIX"]
                ?? yaaglRoot.appendingPathComponent("wineprefix").path,
            isDirectory: true)
        guard fileManager.fileExists(atPath: winePrefixURL.path) else {
            throw WineBridgeError.invalidConfiguration(
                "Wine prefix does not exist at \(winePrefixURL.path)")
        }

        let explicitBridge = arguments.value(after: "--wine-bridge-executable")
            ?? environment["BETTERGI_WINE_BRIDGE_EXE"]
        let bridgeExecutableURL = try resolveFile(
            explicit: explicitBridge,
            candidates: bridgeCandidates(fileManager: fileManager),
            description: "BetterGIWineInputBridge.exe",
            fileManager: fileManager)
        let targetExecutableNames = try targetExecutableNames(from:
            arguments.value(after: "--wine-target-executable")
                ?? environment["BETTERGI_WINE_TARGET_EXECUTABLE"]
        )

        return WineBridgeConfiguration(
            wineExecutableURL: wineExecutableURL,
            winePrefixURL: winePrefixURL,
            bridgeExecutableURL: bridgeExecutableURL,
            targetExecutableNames: targetExecutableNames,
            startupTimeout: 12)
    }

    static func targetExecutableNames(from explicitValue: String?) throws -> [String] {
        let values = explicitValue.map {
            $0.split(whereSeparator: { $0 == "," || $0 == ";" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } ?? ["YuanShen.exe", "GenshinImpact.exe"]
        guard !values.isEmpty,
              values.allSatisfy({
                  !$0.isEmpty && !$0.contains("/") && !$0.contains("\\")
              }) else {
            throw WineBridgeError.invalidConfiguration("Invalid target executable name")
        }
        return values
    }

    private static func resolveFile(
        explicit: String?,
        candidates: [URL],
        description: String,
        fileManager: FileManager
    ) throws -> URL {
        let urls = explicit.map { [URL(fileURLWithPath: $0)] } ?? candidates
        guard let match = urls.first(where: {
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: $0.path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }) else {
            throw WineBridgeError.invalidConfiguration(
                "\(description) was not found; pass an explicit development path")
        }
        return match.standardizedFileURL
    }

    private static func bridgeCandidates(fileManager: FileManager) -> [URL] {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL
                .appendingPathComponent("WineIntegration/BetterGIWineInputBridge.exe"))
        }

        var roots = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
            Bundle.main.bundleURL
        ]
        if let executableURL = Bundle.main.executableURL {
            roots.append(executableURL.deletingLastPathComponent())
        }
        for root in roots {
            var cursor = root
            for _ in 0 ..< 8 {
                candidates.append(cursor
                    .appendingPathComponent(
                        "WineIntegration/bridge/build/BetterGIWineInputBridge.exe"))
                let parent = cursor.deletingLastPathComponent()
                if parent.path == cursor.path { break }
                cursor = parent
            }
        }
        return candidates
    }
}

struct CommandLineOptions {
    let arguments: [String]

    init(_ arguments: [String]) {
        self.arguments = arguments
    }

    func value(after name: String) -> String? {
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

enum InputBackendSelection: String, CaseIterable, Identifiable {
    case foregroundCGEvent = "foreground-cgevent"
    case wineBridge = "wine-bridge"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .foregroundCGEvent: "macOS CGEvent"
        case .wineBridge: "Wine Bridge（实验）"
        }
    }

    var subtitle: String {
        switch self {
        case .foregroundCGEvent:
            "兼容模式，通过 macOS 事件发送输入，要求原神保持前台。"
        case .wineBridge:
            "通过原神所在 Wine prefix 内的 SendInput helper 发送输入；当前仍要求原神保持前台。"
        }
    }

    var deliveryMode: InputDeliveryMode {
        switch self {
        case .foregroundCGEvent: .foregroundCGEvent
        case .wineBridge: .wineBridge
        }
    }
}

enum InputDispatcherFactory {
    static func selection(
        launchArguments: [String],
        storedValue: String?
    ) -> InputBackendSelection {
        let arguments = CommandLineOptions(launchArguments)
        if let commandLineValue = arguments.value(after: "--input-backend"),
           let selection = InputBackendSelection(rawValue: commandLineValue) {
            return selection
        }
        return storedValue.flatMap(InputBackendSelection.init(rawValue:))
            ?? .foregroundCGEvent
    }

    static func make(
        launchArguments: [String],
        fallbackSelection: InputBackendSelection = .foregroundCGEvent
    ) -> any InputDispatching {
        let selection = CommandLineOptions(launchArguments)
            .value(after: "--input-backend")
        guard let selection else {
            return make(selection: fallbackSelection, launchArguments: launchArguments)
        }
        switch selection {
        case InputBackendSelection.foregroundCGEvent.rawValue:
            return make(selection: .foregroundCGEvent, launchArguments: launchArguments)
        case InputBackendSelection.wineBridge.rawValue:
            return make(selection: .wineBridge, launchArguments: launchArguments)
        default:
            return UnavailableInputDispatcher(
                error: WineBridgeError.invalidConfiguration(
                    "Unsupported --input-backend value \(selection)"))
        }
    }

    static func make(
        selection: InputBackendSelection,
        launchArguments: [String]
    ) -> any InputDispatching {
        switch selection {
        case .foregroundCGEvent:
            CGEventInputDispatcher()
        case .wineBridge:
            WineBridgeInputDispatcher(launchArguments: launchArguments)
        }
    }
}

private struct UnavailableInputDispatcher: InputDispatching {
    let deliveryMode = InputDeliveryMode.wineBridge
    let error: Error

    func perform(
        _ action: InputAction,
        targetWindow: WindowInfo
    ) throws -> CGEventDispatchReport {
        throw error
    }

    func query(_ query: InputQuery, targetWindow: WindowInfo) throws -> Bool {
        throw error
    }
}

final class WineBridgeInputDispatcher: InputDispatching {
    let deliveryMode = InputDeliveryMode.wineBridge

    private let configurationResult: Result<WineBridgeConfiguration, Error>
    private let lock = NSLock()
    private var process: Process?
    private var connection: WineBridgeConnection?
    private var registeredTarget: WineBridgeTarget?
    private var hostTargetPID: pid_t?

    init(configuration: Result<WineBridgeConfiguration, Error>) {
        configurationResult = configuration
    }

    convenience init(launchArguments: [String]) {
        do {
            self.init(configuration: .success(
                try WineBridgeConfiguration.resolve(launchArguments: launchArguments)))
        } catch {
            self.init(configuration: .failure(error))
        }
    }

    deinit {
        shutdown()
    }

    func perform(
        _ action: InputAction,
        targetWindow: WindowInfo
    ) throws -> CGEventDispatchReport {
        guard !targetWindow.isSynthetic else {
            throw WineBridgeError.syntheticWindow
        }
        lock.lock()
        defer { lock.unlock() }

        if action == .releaseAll, connection == nil {
            return CGEventDispatchReport(eventCount: 0, detail: "releaseAll (bridge inactive)")
        }
        let session = try ensureSession(targetWindow: targetWindow)
        let eventCount = try send(
            action,
            targetWindow: targetWindow,
            through: session)
        let windowHandle = String(registeredTarget?.windowHandle ?? 0, radix: 16)
        return CGEventDispatchReport(
            eventCount: eventCount,
            detail: "\(action.displayName) hwnd=0x\(windowHandle)")
    }

    func query(_ query: InputQuery, targetWindow: WindowInfo) throws -> Bool {
        guard !targetWindow.isSynthetic else {
            throw WineBridgeError.syntheticWindow
        }
        lock.lock()
        defer { lock.unlock() }
        let session = try ensureSession(targetWindow: targetWindow)
        switch query {
        case let .key(key):
            guard let virtualKey = BetterGICoreInputKeyMapper.windowsVirtualKey(from: key) else {
                throw WineBridgeError.unsupportedKey(key)
            }
            var payload = Data()
            payload.appendLittleEndian(UInt16(virtualKey))
            payload.appendLittleEndian(UInt16(0))
            return try session.query(.queryKeyState, payload: payload)
        case let .mouseButton(button):
            return try session.query(
                .queryMouseButtonState,
                payload: Data([try Self.mouseButton(button), 0, 0, 0]))
        }
    }

    func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        if let connection {
            _ = try? connection.request(.releaseAll)
            _ = try? connection.request(.shutdown)
            connection.close()
        }
        connection = nil
        registeredTarget = nil
        hostTargetPID = nil
        if let process, process.isRunning {
            Self.stopProcess(process)
        }
        process = nil
    }

    private func ensureSession(targetWindow: WindowInfo) throws -> WineBridgeConnection {
        if hostTargetPID != nil, hostTargetPID != targetWindow.ownerPID {
            connection?.close()
            connection = nil
            registeredTarget = nil
            if let process, process.isRunning {
                Self.stopProcess(process)
            }
            self.process = nil
        }
        if let process, !process.isRunning {
            let status = process.terminationStatus
            connection?.close()
            connection = nil
            registeredTarget = nil
            self.process = nil
            throw WineBridgeError.bridgeExited(status)
        }
        if let connection, registeredTarget != nil {
            return connection
        }

        let configuration = try configurationResult.get()
        let (process, connection) = try startAuthenticatedConnection(
            configuration: configuration)
        self.process = process
        do {
            var discoveredTarget: WineBridgeTarget?
            var discoveryError: Error?
            for executableName in configuration.targetExecutableNames {
                do {
                    let discovery = try connection.request(
                        .discoverTarget,
                        payload: Data(executableName.utf8))
                    discoveredTarget = try WineBridgeTarget.decode(discovery)
                    break
                } catch {
                    discoveryError = error
                }
            }
            guard let target = discoveredTarget else {
                throw discoveryError ?? WineBridgeError.bridgeUnavailable(
                    "No supported Genshin executable was found")
            }
            _ = try connection.request(.registerTarget, payload: try target.encoded())
            self.connection = connection
            registeredTarget = target
            hostTargetPID = targetWindow.ownerPID
            NSLog(
                "Wine bridge ready hostPID=%d windowsPID=%u hwnd=0x%llx",
                targetWindow.ownerPID,
                target.processID,
                target.windowHandle)
            return connection
        } catch {
            if process.isRunning {
                Self.stopProcess(process)
            }
            self.process = nil
            throw error
        }
    }

    private func startAuthenticatedConnection(
        configuration: WineBridgeConfiguration
    ) throws -> (Process, WineBridgeConnection) {
        var lastError: Error?
        for attempt in 1 ... 3 {
            let port = try Self.reserveLoopbackPort()
            let token = try Self.randomToken()
            let process = Process()
            process.executableURL = configuration.wineExecutableURL
            process.arguments = [
                configuration.bridgeExecutableURL.path,
                "--port",
                String(port),
            ]
            var environment = ProcessInfo.processInfo.environment
            environment["WINEPREFIX"] = configuration.winePrefixURL.path
            environment["BETTERGI_WINE_BRIDGE_TOKEN"] = token
            environment["WINEDEBUG"] = "-all"
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                throw WineBridgeError.bridgeUnavailable(error.localizedDescription)
            }

            var connection: WineBridgeConnection?
            do {
                let connected = try WineBridgeConnection.connect(
                    port: port,
                    timeout: configuration.startupTimeout,
                    processIsRunning: { process.isRunning })
                connection = connected
                _ = try connected.request(.hello)
                _ = try connected.request(
                    .authenticate,
                    payload: Data(token.utf8))
                return (process, connected)
            } catch {
                connection?.close()
                if process.isRunning {
                    Self.stopProcess(process)
                }
                lastError = error
                guard attempt < 3, Self.isRetryableStartupError(error) else {
                    throw error
                }
                NSLog(
                    "Wine bridge startup failed before authentication; retrying port allocation (%d/3): %@",
                    attempt,
                    error.localizedDescription)
            }
        }
        throw lastError ?? WineBridgeError.bridgeUnavailable(
            "Wine bridge startup failed")
    }

    static func isRetryableStartupError(_ error: Error) -> Bool {
        switch error {
        case WineBridgeError.connectionFailed, WineBridgeError.bridgeExited:
            true
        default:
            false
        }
    }

    private func send(
        _ action: InputAction,
        targetWindow: WindowInfo,
        through connection: WineBridgeConnection
    ) throws -> Int {
        switch action {
        case let .keyDown(key, modifiers):
            try connection.request(
                .keyDown,
                payload: try Self.keyPayload(key, modifiers: modifiers, durationMs: 0))
            return 1
        case let .keyUp(key, modifiers):
            try connection.request(
                .keyUp,
                payload: try Self.keyPayload(key, modifiers: modifiers, durationMs: 0))
            return 1
        case let .keyPress(key, modifiers):
            try connection.request(
                .keyPress,
                payload: try Self.keyPayload(key, modifiers: modifiers, durationMs: 0))
            return 2
        case let .keyHold(key, durationMs, modifiers):
            try connection.request(
                .keyPress,
                payload: try Self.keyPayload(
                    key,
                    modifiers: modifiers,
                    durationMs: durationMs))
            return 2
        case let .mouseMove(point):
            try connection.request(
                .mouseMoveAbsolute,
                payload: Self.mouseMovePayload(
                    point: Self.wineClientPoint(point, targetWindow: targetWindow)))
            return 1
        case let .mouseMoveRelative(deltaX, deltaY):
            let delta = Self.wineRelativeDelta(
                deltaX: deltaX,
                deltaY: deltaY,
                targetWindow: targetWindow)
            try connection.request(
                .mouseMoveRelative,
                payload: Self.mouseMovePayload(x: delta.x, y: delta.y))
            return 1
        case let .mouseButtonDown(button, point):
            try connection.request(
                .mouseButtonDown,
                payload: try Self.mouseButtonPayload(
                    button,
                    point: point.map {
                        Self.wineClientPoint($0, targetWindow: targetWindow)
                    },
                    durationMs: 0))
            return point == nil ? 1 : 2
        case let .mouseButtonUp(button, point):
            try connection.request(
                .mouseButtonUp,
                payload: try Self.mouseButtonPayload(
                    button,
                    point: point.map {
                        Self.wineClientPoint($0, targetWindow: targetWindow)
                    },
                    durationMs: 0))
            return point == nil ? 1 : 2
        case let .mouseClick(button, point):
            try connection.request(
                .mouseClick,
                payload: try Self.mouseButtonPayload(
                    button,
                    point: point.map {
                        Self.wineClientPoint($0, targetWindow: targetWindow)
                    },
                    durationMs: 50))
            return point == nil ? 2 : 3
        case let .mouseButtonHold(button, durationMs, point):
            try connection.request(
                .mouseClick,
                payload: try Self.mouseButtonPayload(
                    button,
                    point: point.map {
                        Self.wineClientPoint($0, targetWindow: targetWindow)
                    },
                    durationMs: durationMs))
            return point == nil ? 2 : 3
        case let .verticalScroll(clicks):
            var payload = Data()
            payload.appendLittleEndian(Int32(clamping: clicks * 120))
            try connection.request(.mouseWheel, payload: payload)
            return 1
        case let .inputText(text):
            guard let payload = text.data(using: .utf16LittleEndian), !payload.isEmpty else {
                throw WineBridgeError.invalidConfiguration("Text cannot be encoded as UTF-16LE")
            }
            try connection.request(.inputText, payload: payload)
            return payload.count
        case let .leftClick(point):
            try connection.request(
                .mouseClick,
                payload: try Self.mouseButtonPayload(
                    .left,
                    point: point.map {
                        Self.wineClientPoint($0, targetWindow: targetWindow)
                    },
                    durationMs: 50))
            return point == nil ? 2 : 3
        case .releaseAll:
            try connection.request(.releaseAll)
            return 1
        }
    }

    private static func keyPayload(
        _ key: KeyCode,
        modifiers: ModifierFlags,
        durationMs: Int
    ) throws -> Data {
        guard let virtualKey = BetterGICoreInputKeyMapper.windowsVirtualKey(from: key) else {
            throw WineBridgeError.unsupportedKey(key)
        }
        guard !modifiers.contains(.command) else {
            throw WineBridgeError.unsupportedModifier
        }
        var modifierValue: UInt16 = 0
        if modifiers.contains(.shift) { modifierValue |= 1 }
        if modifiers.contains(.control) { modifierValue |= 2 }
        if modifiers.contains(.option) { modifierValue |= 4 }
        var payload = Data()
        payload.appendLittleEndian(UInt16(virtualKey))
        payload.appendLittleEndian(modifierValue)
        payload.appendLittleEndian(UInt32(clamping: max(0, min(durationMs, 10_000))))
        return payload
    }

    private static func mouseButtonPayload(
        _ button: InputMouseButton,
        point: CGPoint?,
        durationMs: Int
    ) throws -> Data {
        var payload = Data()
        payload.append(try mouseButton(button))
        payload.append(point == nil ? 0 : 1)
        payload.appendLittleEndian(UInt16(0))
        payload.appendLittleEndian(Int32(clamping: Int(point?.x.rounded() ?? 0)))
        payload.appendLittleEndian(Int32(clamping: Int(point?.y.rounded() ?? 0)))
        payload.appendLittleEndian(UInt32(clamping: max(0, min(durationMs, 10_000))))
        return payload
    }

    static func mouseMovePayload(x: CGFloat, y: CGFloat) -> Data {
        var payload = Data()
        payload.appendLittleEndian(Int32(clamping: Int(x.rounded())))
        payload.appendLittleEndian(Int32(clamping: Int(y.rounded())))
        return payload
    }

    static func mouseMovePayload(point: CGPoint) -> Data {
        mouseMovePayload(x: point.x, y: point.y)
    }

    static func wineClientPoint(
        _ quartzPoint: CGPoint,
        targetWindow: WindowInfo
    ) -> CGPoint {
        let captureRect = targetWindow.captureRect
        let scale = max(1, targetWindow.scaleFactor)
        return CGPoint(
            x: (quartzPoint.x - captureRect.minX) * scale,
            y: (quartzPoint.y - captureRect.minY) * scale)
    }

    static func wineRelativeDelta(
        deltaX: CGFloat,
        deltaY: CGFloat,
        targetWindow: WindowInfo
    ) -> CGPoint {
        let scale = max(1, targetWindow.scaleFactor)
        return CGPoint(x: deltaX / scale, y: deltaY / scale)
    }

    private static func mouseButton(_ button: InputMouseButton) throws -> UInt8 {
        switch button {
        case .left: 1
        case .right: 2
        case .middle: 3
        case .side1: 4
        case .side2: 5
        }
    }

    private static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw WineBridgeError.bridgeUnavailable("Unable to generate session token")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func stopProcess(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    private static func reserveLoopbackPort() throws -> UInt16 {
        let socketDescriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw WineBridgeError.connectionFailed(String(cString: strerror(errno)))
        }
        defer { Darwin.close(socketDescriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw WineBridgeError.connectionFailed(String(cString: strerror(errno)))
        }
        var resolved = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &resolved) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketDescriptor, $0, &length)
            }
        }
        guard nameResult == 0 else {
            throw WineBridgeError.connectionFailed(String(cString: strerror(errno)))
        }
        return UInt16(bigEndian: resolved.sin_port)
    }
}

private final class WineBridgeConnection {
    private var socketDescriptor: Int32
    private var nextRequestID: UInt32 = 1

    private init(socketDescriptor: Int32) {
        self.socketDescriptor = socketDescriptor
    }

    deinit {
        close()
    }

    static func connect(
        port: UInt16,
        timeout: TimeInterval,
        processIsRunning: () -> Bool
    ) throws -> WineBridgeConnection {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError = "startup timeout"
        while Date() < deadline, processIsRunning() {
            let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                throw WineBridgeError.connectionFailed(String(cString: strerror(errno)))
            }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(
                        descriptor,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result == 0 {
                var noDelay: Int32 = 1
                setsockopt(
                    descriptor,
                    IPPROTO_TCP,
                    TCP_NODELAY,
                    &noDelay,
                    socklen_t(MemoryLayout<Int32>.size))
                return WineBridgeConnection(socketDescriptor: descriptor)
            }
            lastError = String(cString: strerror(errno))
            Darwin.close(descriptor)
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw WineBridgeError.connectionFailed(lastError)
    }

    @discardableResult
    func request(_ command: WineBridgeCommand, payload: Data = Data()) throws -> Data {
        guard payload.count <= WineBridgeProtocol.maximumPayloadSize else {
            throw WineBridgeError.invalidConfiguration("Bridge payload is too large")
        }
        let requestID = nextRequestID
        nextRequestID &+= 1
        let header = WineBridgePacketHeader(
            command: command,
            requestID: requestID,
            payloadLength: UInt32(payload.count),
            status: 0)
        try send(header.encoded())
        if !payload.isEmpty { try send(payload) }

        let responseHeader = try WineBridgePacketHeader.decode(
            receive(count: WineBridgeProtocol.headerSize))
        guard responseHeader.command == command,
              responseHeader.requestID == requestID else {
            throw WineBridgeError.invalidResponse("request correlation")
        }
        let response = try receive(count: Int(responseHeader.payloadLength))
        guard responseHeader.status == WineBridgeStatus.ok.rawValue else {
            throw WineBridgeError.requestFailed(command, responseHeader.status)
        }
        return response
    }

    func query(_ command: WineBridgeCommand, payload: Data) throws -> Bool {
        let response = try request(command, payload: payload)
        guard response.count == 4 else {
            throw WineBridgeError.invalidResponse("query response length \(response.count)")
        }
        return response[response.startIndex] != 0
    }

    func close() {
        guard socketDescriptor >= 0 else { return }
        Darwin.shutdown(socketDescriptor, SHUT_RDWR)
        Darwin.close(socketDescriptor)
        socketDescriptor = -1
    }

    private func send(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            var offset = 0
            while offset < rawBuffer.count {
                let result = Darwin.send(
                    socketDescriptor,
                    rawBuffer.baseAddress!.advanced(by: offset),
                    rawBuffer.count - offset,
                    0)
                guard result > 0 else {
                    throw WineBridgeError.connectionFailed(String(cString: strerror(errno)))
                }
                offset += result
            }
        }
    }

    private func receive(count: Int) throws -> Data {
        guard count >= 0, count <= WineBridgeProtocol.maximumPayloadSize else {
            throw WineBridgeError.invalidResponse("payload length \(count)")
        }
        if count == 0 { return Data() }
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { rawBuffer in
            var offset = 0
            while offset < count {
                let result = Darwin.recv(
                    socketDescriptor,
                    rawBuffer.baseAddress!.advanced(by: offset),
                    count - offset,
                    0)
                guard result > 0 else {
                    throw WineBridgeError.connectionFailed(
                        result == 0 ? "connection closed" : String(cString: strerror(errno)))
                }
                offset += result
            }
        }
        return data
    }
}
