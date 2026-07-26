import AppKit
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

enum WineRelativeMouseMode: String, Equatable {
    case scaled
    case raw
}

enum WineForegroundExperiment: String, Equatable {
    case none
    case once
    case always
    case mousePrime = "mouse-prime"
}

struct WineBridgeConfiguration: Equatable {
    let wineExecutableURL: URL
    let winePrefixURL: URL
    let bridgeExecutableURL: URL
    let targetExecutableNames: [String]
    let startupTimeout: TimeInterval
    let backgroundDiagnosticEnabled: Bool
    let relativeMouseMode: WineRelativeMouseMode
    let foregroundExperiment: WineForegroundExperiment

    var capabilities: InputDeliveryCapabilities {
        let supportsBackgroundDelivery = foregroundExperiment == .mousePrime
        return InputDeliveryCapabilities(
            requiresHostForeground: !supportsBackgroundDelivery,
            supportsBackgroundDelivery: supportsBackgroundDelivery)
    }

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
        let backgroundDiagnosticEnabled =
            launchArguments.contains("--wine-background-diagnostic")
        let relativeMouseMode = try enumValue(
            arguments.value(after: "--wine-relative-mouse") ?? "scaled",
            description: "--wine-relative-mouse",
            type: WineRelativeMouseMode.self)
        let foregroundExperiment = try enumValue(
            arguments.value(after: "--wine-foreground-experiment") ?? "mouse-prime",
            description: "--wine-foreground-experiment",
            type: WineForegroundExperiment.self)
        guard backgroundDiagnosticEnabled
                || foregroundExperiment == .none
                || foregroundExperiment == .mousePrime else {
            throw WineBridgeError.invalidConfiguration(
                "once/always foreground experiments require "
                    + "--wine-background-diagnostic")
        }

        return WineBridgeConfiguration(
            wineExecutableURL: wineExecutableURL,
            winePrefixURL: winePrefixURL,
            bridgeExecutableURL: bridgeExecutableURL,
            targetExecutableNames: targetExecutableNames,
            startupTimeout: 12,
            backgroundDiagnosticEnabled: backgroundDiagnosticEnabled,
            relativeMouseMode: relativeMouseMode,
            foregroundExperiment: foregroundExperiment)
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

    private static func enumValue<Value: RawRepresentable>(
        _ value: String,
        description: String,
        type: Value.Type
    ) throws -> Value where Value.RawValue == String {
        guard let parsed = Value(rawValue: value) else {
            throw WineBridgeError.invalidConfiguration(
                "Unsupported \(description) value \(value)")
        }
        return parsed
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
    case wineBridge = "wine-bridge"
    case foregroundCGEvent = "foreground-cgevent"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .foregroundCGEvent: "macOS CGEvent"
        case .wineBridge: "Wine Bridge"
        }
    }

    var subtitle: String {
        switch self {
        case .foregroundCGEvent:
            "兼容云游戏、远程客户端等非 Wine 场景；通过 macOS 事件发送输入。"
        case .wineBridge:
            "推荐，通过原神所在 Wine prefix 内的 SendInput helper 发送输入。"
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
            ?? .wineBridge
    }

    static func make(
        launchArguments: [String],
        fallbackSelection: InputBackendSelection = .wineBridge
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
    let capabilities = InputDeliveryCapabilities.foregroundOnly
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

final class WineBridgeInputDispatcher: InputDispatching, @unchecked Sendable {
    private static let inputContextWakeTimeoutMs: UInt16 = 3_000

    let deliveryMode = InputDeliveryMode.wineBridge
    let capabilities: InputDeliveryCapabilities

    private let configurationResult: Result<WineBridgeConfiguration, Error>
    private let lock = NSLock()
    private let hostFocusLock = NSLock()
    private var process: Process?
    private var connection: WineBridgeConnection?
    private var registeredTarget: WineBridgeTarget?
    private var hostTargetPID: pid_t?
    private var outputPipe: Pipe?
    private var backgroundEpisodeForegroundAttempted = false
    private var hostFocusObserver: NSObjectProtocol?
    private var observedHostTargetPID: pid_t?
    private var targetWasHostFrontmost = false
    private var hostFocusGeneration: UInt64 = 0
    private var appliedHostFocusGeneration: UInt64 = 0

    init(configuration: Result<WineBridgeConfiguration, Error>) {
        configurationResult = configuration
        capabilities = (try? configuration.get().capabilities) ?? .foregroundOnly
        hostFocusObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else {
                return
            }
            self?.recordHostApplicationActivation(application.processIdentifier)
        }
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
        if let hostFocusObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(hostFocusObserver)
        }
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

        if action == .releaseAll {
            guard let connection else {
                return CGEventDispatchReport(
                    eventCount: 0,
                    detail: "releaseAll (bridge inactive)")
            }
            try connection.request(.releaseAll)
            return CGEventDispatchReport(eventCount: 1, detail: "releaseAll")
        }
        let session = try ensureSession(targetWindow: targetWindow)
        try resetInputContextAfterHostFocusCycle(through: session)
        let diagnostic = try prepareDiagnostic(
            action: action,
            targetWindow: targetWindow,
            through: session)
        let eventCount = try send(
            action,
            targetWindow: targetWindow,
            through: session)
        let windowHandle = String(registeredTarget?.windowHandle ?? 0, radix: 16)
        if try configurationResult.get().backgroundDiagnosticEnabled {
            logDiagnostic(
                try queryForeground(through: session),
                phase: "after \(action.displayName)",
                hostIsFrontmost: isHostTargetFrontmost(targetWindow))
        }
        return CGEventDispatchReport(
            eventCount: eventCount,
            detail: "\(action.displayName) hwnd=0x\(windowHandle)"
                + (diagnostic.map {
                    " foreground=0x\(String($0.foregroundWindow, radix: 16))"
                } ?? ""))
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
        clearObservedHostTarget()
        backgroundEpisodeForegroundAttempted = false
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
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
            _ = try connection.request(
                .configureInputContext,
                payload: Self.inputContextPolicyPayload(
                    enabled: configuration.capabilities.supportsBackgroundDelivery))
            self.connection = connection
            registeredTarget = target
            hostTargetPID = targetWindow.ownerPID
            observeHostTarget(targetWindow.ownerPID)
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
            let outputPipe = Pipe()
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let text = String(data: data, encoding: .utf8) else { return }
                let bounded = String(text.prefix(2_048))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !bounded.isEmpty {
                    NSLog("Wine bridge: %@", bounded)
                }
            }
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            self.outputPipe = outputPipe

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
                outputPipe.fileHandleForReading.readabilityHandler = nil
                self.outputPipe = nil
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
            try requestInput(
                .keyDown,
                payload: try Self.keyPayload(key, modifiers: modifiers, durationMs: 0),
                through: connection)
            return 1
        case let .keyUp(key, modifiers):
            try requestInput(
                .keyUp,
                payload: try Self.keyPayload(key, modifiers: modifiers, durationMs: 0),
                through: connection)
            return 1
        case let .keyPress(key, modifiers):
            try requestInput(
                .keyPress,
                payload: try Self.keyPayload(key, modifiers: modifiers, durationMs: 0),
                through: connection)
            return 2
        case let .keyHold(key, durationMs, modifiers):
            try requestInput(
                .keyPress,
                payload: try Self.keyPayload(
                    key,
                    modifiers: modifiers,
                    durationMs: durationMs),
                through: connection)
            return 2
        case let .mouseMove(point):
            try requestInput(
                .mouseMoveAbsolute,
                payload: Self.mouseMovePayload(
                    point: Self.wineClientPoint(point, targetWindow: targetWindow)),
                through: connection)
            return 1
        case let .mouseMoveRelative(deltaX, deltaY):
            let configuration = try configurationResult.get()
            let delta = Self.wineRelativeDelta(
                deltaX: deltaX,
                deltaY: deltaY,
                targetWindow: targetWindow,
                mode: configuration.relativeMouseMode)
            try requestInput(
                .mouseMoveRelative,
                payload: Self.mouseMovePayload(x: delta.x, y: delta.y),
                through: connection)
            return 1
        case let .mouseButtonDown(button, point):
            try requestInput(
                .mouseButtonDown,
                payload: try Self.mouseButtonPayload(
                    button,
                    point: point.map {
                        Self.wineClientPoint($0, targetWindow: targetWindow)
                    },
                    durationMs: 0),
                through: connection)
            return point == nil ? 1 : 2
        case let .mouseButtonUp(button, point):
            try requestInput(
                .mouseButtonUp,
                payload: try Self.mouseButtonPayload(
                    button,
                    point: point.map {
                        Self.wineClientPoint($0, targetWindow: targetWindow)
                    },
                    durationMs: 0),
                through: connection)
            return point == nil ? 1 : 2
        case let .mouseClick(button, point):
            try requestInput(
                .mouseClick,
                payload: try Self.mouseButtonPayload(
                    button,
                    point: point.map {
                        Self.wineClientPoint($0, targetWindow: targetWindow)
                    },
                    durationMs: 50),
                through: connection)
            return point == nil ? 2 : 3
        case let .mouseButtonHold(button, durationMs, point):
            try requestInput(
                .mouseClick,
                payload: try Self.mouseButtonPayload(
                    button,
                    point: point.map {
                        Self.wineClientPoint($0, targetWindow: targetWindow)
                    },
                    durationMs: durationMs),
                through: connection)
            return point == nil ? 2 : 3
        case let .verticalScroll(clicks):
            var payload = Data()
            payload.appendLittleEndian(Int32(clamping: clicks * 120))
            try requestInput(.mouseWheel, payload: payload, through: connection)
            return 1
        case let .inputText(text):
            guard let payload = text.data(using: .utf16LittleEndian), !payload.isEmpty else {
                throw WineBridgeError.invalidConfiguration("Text cannot be encoded as UTF-16LE")
            }
            try requestInput(.inputText, payload: payload, through: connection)
            return payload.count
        case let .leftClick(point):
            try requestInput(
                .mouseClick,
                payload: try Self.mouseButtonPayload(
                    .left,
                    point: point.map {
                        Self.wineClientPoint($0, targetWindow: targetWindow)
                    },
                    durationMs: 50),
                through: connection)
            return point == nil ? 2 : 3
        case .releaseAll:
            try connection.request(.releaseAll)
            return 1
        }
    }

    private func requestInput(
        _ command: WineBridgeCommand,
        payload: Data = Data(),
        through connection: WineBridgeConnection
    ) throws {
        var pollDelay: TimeInterval = 0.02
        while true {
            do {
                _ = try connection.request(command, payload: payload)
                return
            } catch let error as WineBridgeError {
                guard case let .requestFailed(failedCommand, status) = error,
                      failedCommand == command,
                      status == WineBridgeStatus.inputContextWakePending.rawValue else {
                    throw error
                }
                Thread.sleep(forTimeInterval: pollDelay)
                if pollDelay < 0.04 {
                    pollDelay = 0.04
                } else if pollDelay < 0.08 {
                    pollDelay = 0.08
                } else if pollDelay < 0.12 {
                    pollDelay = 0.12
                } else {
                    pollDelay = 0.2
                }
            }
        }
    }

    private func observeHostTarget(_ processIdentifier: pid_t) {
        hostFocusLock.lock()
        observedHostTargetPID = processIdentifier
        targetWasHostFrontmost =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
                == processIdentifier
        appliedHostFocusGeneration = hostFocusGeneration
        hostFocusLock.unlock()
    }

    private func clearObservedHostTarget() {
        hostFocusLock.lock()
        observedHostTargetPID = nil
        targetWasHostFrontmost = false
        appliedHostFocusGeneration = hostFocusGeneration
        hostFocusLock.unlock()
    }

    private func recordHostApplicationActivation(_ processIdentifier: pid_t) {
        hostFocusLock.lock()
        defer { hostFocusLock.unlock() }
        guard let observedHostTargetPID else { return }
        if processIdentifier == observedHostTargetPID {
            targetWasHostFrontmost = true
        } else if targetWasHostFrontmost {
            targetWasHostFrontmost = false
            hostFocusGeneration &+= 1
        }
    }

    private func resetInputContextAfterHostFocusCycle(
        through connection: WineBridgeConnection
    ) throws {
        hostFocusLock.lock()
        let generation = hostFocusGeneration
        let requiresReset = generation != appliedHostFocusGeneration
        if requiresReset {
            appliedHostFocusGeneration = generation
        }
        hostFocusLock.unlock()
        guard requiresReset else { return }

        let configuration = try configurationResult.get()
        _ = try connection.request(
            .configureInputContext,
            payload: Self.inputContextPolicyPayload(
                enabled: configuration.capabilities.supportsBackgroundDelivery))
        NSLog(
            "Wine bridge input context invalidated after host focus cycle generation=%llu",
            generation)
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
        targetWindow: WindowInfo,
        mode: WineRelativeMouseMode = .scaled
    ) -> CGPoint {
        guard mode == .scaled else {
            return CGPoint(x: deltaX, y: deltaY)
        }
        let scale = max(1, targetWindow.scaleFactor)
        return CGPoint(x: deltaX / scale, y: deltaY / scale)
    }

    static func needsInputContextPriming(
        _ diagnostic: WineBridgeForegroundDiagnostic
    ) -> Bool {
        diagnostic.foregroundWindow != diagnostic.targetWindow
    }

    private func prepareDiagnostic(
        action: InputAction,
        targetWindow: WindowInfo,
        through connection: WineBridgeConnection
    ) throws -> WineBridgeForegroundDiagnostic? {
        let configuration = try configurationResult.get()
        guard configuration.backgroundDiagnosticEnabled else { return nil }
        let hostIsFrontmost = isHostTargetFrontmost(targetWindow)
        if hostIsFrontmost {
            backgroundEpisodeForegroundAttempted = false
        }

        let shouldSetForeground: Bool
        switch configuration.foregroundExperiment {
        case .none:
            shouldSetForeground = false
        case .once:
            shouldSetForeground = !hostIsFrontmost
                && !backgroundEpisodeForegroundAttempted
        case .always:
            shouldSetForeground = !hostIsFrontmost
        case .mousePrime:
            let beforePrime = try queryForeground(through: connection)
            logDiagnostic(
                beforePrime,
                phase: "before input",
                hostIsFrontmost: hostIsFrontmost)
            return beforePrime
        }
        if shouldSetForeground {
            backgroundEpisodeForegroundAttempted = true
        }
        let diagnostic = shouldSetForeground
            ? try setForeground(through: connection)
            : try queryForeground(through: connection)
        logDiagnostic(
            diagnostic,
            phase: shouldSetForeground ? "before input, SetForegroundWindow" : "before input",
            hostIsFrontmost: hostIsFrontmost)
        return diagnostic
    }

    private func queryForeground(
        through connection: WineBridgeConnection
    ) throws -> WineBridgeForegroundDiagnostic {
        try foregroundDiagnostic(.queryForeground, through: connection)
    }

    private func setForeground(
        through connection: WineBridgeConnection
    ) throws -> WineBridgeForegroundDiagnostic {
        try foregroundDiagnostic(.setForeground, through: connection)
    }

    static func inputContextPolicyPayload(enabled: Bool) -> Data {
        var payload = Data([enabled ? 1 : 0, 0])
        payload.appendLittleEndian(inputContextWakeTimeoutMs)
        return payload
    }

    private func foregroundDiagnostic(
        _ command: WineBridgeCommand,
        through connection: WineBridgeConnection
    ) throws -> WineBridgeForegroundDiagnostic {
        var payload = Data()
        payload.appendLittleEndian(UInt16(0x46))
        payload.appendLittleEndian(UInt16(0))
        return try WineBridgeForegroundDiagnostic.decode(
            connection.request(command, payload: payload))
    }

    private func isHostTargetFrontmost(_ targetWindow: WindowInfo) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == targetWindow.ownerPID
    }

    private func logDiagnostic(
        _ diagnostic: WineBridgeForegroundDiagnostic,
        phase: String,
        hostIsFrontmost: Bool
    ) {
        NSLog(
            "Wine bridge diagnostic [%@] macOSFrontmost=%@ %@",
            phase,
            hostIsFrontmost.description,
            diagnostic.logDescription)
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
