import CoreGraphics
import Darwin
import Foundation
@testable import MacGI
import Testing

@Suite("Wine bridge protocol")
struct WineBridgeProtocolTests {
    @Test("Process output EOF detaches its readability handler")
    func processOutputEOFStopsMonitoring() {
        let pipe = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { _ in }
        pipe.fileHandleForWriting.closeFile()

        #expect(readAvailableProcessOutput(from: pipe.fileHandleForReading) == nil)
        #expect(pipe.fileHandleForReading.readabilityHandler == nil)
    }

    @Test("Packet header round-trips fixed little-endian fields")
    func packetHeaderRoundTrip() throws {
        let header = WineBridgePacketHeader(
            command: .mouseMoveRelative,
            requestID: 42,
            payloadLength: 8,
            status: 0)

        let encoded = header.encoded()

        #expect(encoded.count == WineBridgeProtocol.headerSize)
        #expect(try WineBridgePacketHeader.decode(encoded) == header)
    }

    @Test("Target registration preserves PID HWND and executable")
    func targetRoundTrip() throws {
        let target = WineBridgeTarget(
            processID: 1234,
            windowHandle: 0x1234_5678_ABCD_EF01,
            executableName: "GenshinImpact.exe")

        let encoded = try target.encoded()

        #expect(encoded.count == 80)
        #expect(try WineBridgeTarget.decode(encoded) == target)
    }

    @Test("Target discovery defaults cover CN and global executables")
    func targetDiscoveryDefaults() throws {
        #expect(
            try WineBridgeConfiguration.targetExecutableNames(from: nil)
                == ["YuanShen.exe", "GenshinImpact.exe"])
        #expect(
            try WineBridgeConfiguration.targetExecutableNames(
                from: "YuanShen.exe,GenshinImpact.exe")
                == ["YuanShen.exe", "GenshinImpact.exe"])
    }

    @Test("Only pre-authentication connection failures retry port allocation")
    func startupRetryClassification() {
        #expect(WineBridgeInputDispatcher.isRetryableStartupError(
            WineBridgeError.connectionFailed("Address already in use")))
        #expect(WineBridgeInputDispatcher.isRetryableStartupError(
            WineBridgeError.bridgeExited(1)))
        #expect(!WineBridgeInputDispatcher.isRetryableStartupError(
            WineBridgeError.requestFailed(.authenticate, 1)))
        #expect(!WineBridgeInputDispatcher.isRetryableStartupError(
            WineBridgeError.invalidResponse("header")))
    }

    @Test("Window recreation invalidates a Wine bridge session identity")
    func sessionIdentityTracksHostWindowID() {
        let original = WindowInfo(
            id: 42,
            ownerPID: 100,
            ownerName: "wine",
            title: "Genshin Impact",
            frame: .zero,
            layer: 0,
            isOnScreen: true,
            scaleFactor: 2)
        let recreated = WindowInfo(
            id: 43,
            ownerPID: 100,
            ownerName: "wine",
            title: "Genshin Impact",
            frame: .zero,
            layer: 0,
            isOnScreen: true,
            scaleFactor: 2)

        #expect(!WineBridgeInputDispatcher.sessionIdentityChanged(
            currentHostPID: 100,
            currentWindowID: 42,
            targetWindow: original))
        #expect(WineBridgeInputDispatcher.sessionIdentityChanged(
            currentHostPID: 100,
            currentWindowID: 42,
            targetWindow: recreated))
        #expect(WineBridgeInputDispatcher.sessionIdentityChanged(
            currentHostPID: 101,
            currentWindowID: 42,
            targetWindow: original))
    }

    @Test("Only pre-delivery target rejection permits action replay")
    func targetRefreshErrorClassification() {
        #expect(WineBridgeInputDispatcher.isTargetRefreshError(
            WineBridgeError.requestFailed(
                .keyDown,
                WineBridgeStatus.targetMismatch.rawValue)))
        #expect(WineBridgeInputDispatcher.isTargetRefreshError(
            WineBridgeError.requestFailed(
                .keyDown,
                WineBridgeStatus.targetRequired.rawValue)))
        #expect(!WineBridgeInputDispatcher.isTargetRefreshError(
            WineBridgeError.requestFailed(
                .keyDown,
                WineBridgeStatus.inputFailed.rawValue)))
        #expect(!WineBridgeInputDispatcher.isTargetRefreshError(
            WineBridgeError.connectionFailed("closed")))
    }

    @Test("Target discovery continues only after an explicit not-found response")
    func targetDiscoveryErrorClassification() {
        #expect(WineBridgeInputDispatcher.isTargetNotFoundDiscoveryError(
            WineBridgeError.requestFailed(
                .discoverTarget,
                WineBridgeStatus.targetNotFound.rawValue)))
        #expect(!WineBridgeInputDispatcher.isTargetNotFoundDiscoveryError(
            WineBridgeError.requestFailed(
                .discoverTarget,
                WineBridgeStatus.targetMismatch.rawValue)))
        #expect(!WineBridgeInputDispatcher.isTargetNotFoundDiscoveryError(
            WineBridgeError.requestFailed(
                .registerTarget,
                WineBridgeStatus.targetNotFound.rawValue)))
        #expect(!WineBridgeInputDispatcher.isTargetNotFoundDiscoveryError(
            WineBridgeError.requestTimedOut(.discoverTarget)))
    }

    @Test("Helper receives a natural-exit grace period before termination")
    func helperNaturalExitGracePeriod() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.1; exit 0"]
        try process.run()

        WineBridgeInputDispatcher.stopProcess(
            process,
            naturalExitGrace: 0.5)

        #expect(process.terminationStatus == 0)
    }

    @Test("Input request deadline includes the requested hold duration")
    func inputRequestDeadlineIncludesHoldDuration() {
        #expect(WineBridgeInputDispatcher.inputRequestTimeout(durationMs: 0) == 6)
        #expect(WineBridgeInputDispatcher.inputRequestTimeout(durationMs: 10_000) == 16)
    }

    @Test("A silent bridge peer cannot block a request indefinitely")
    func requestReceiveTimeout() throws {
        let listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        #expect(listener >= 0)
        defer { Darwin.close(listener) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    listener,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        #expect(bindResult == 0)
        #expect(Darwin.listen(listener, 1) == 0)

        var resolved = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &resolved) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(listener, $0, &length)
            }
        }
        #expect(nameResult == 0)

        let connection = try WineBridgeConnection.connect(
            port: UInt16(bigEndian: resolved.sin_port),
            deadline: WineBridgeMonotonicClock.deadline(after: 1),
            processIsRunning: { true })
        defer { connection.close() }

        let started = DispatchTime.now().uptimeNanoseconds
        do {
            _ = try connection.request(.ping, timeout: 0.1)
            Issue.record("Silent bridge peer unexpectedly returned a response")
        } catch {
            #expect(error as? WineBridgeError == .requestTimedOut(.ping))
        }
        let elapsed = TimeInterval(
            DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        #expect(elapsed < 1)
    }

    @Test("Relative mouse payload preserves signed deltas")
    func relativeMousePayloadPreservesSignedDeltas() throws {
        let payload = WineBridgeInputDispatcher.mouseMovePayload(x: -37, y: 19)
        var reader = WineBridgeDataReader(payload)

        #expect(Int32(bitPattern: try reader.readUInt32()) == -37)
        #expect(Int32(bitPattern: try reader.readUInt32()) == 19)
    }

    @Test("Quartz points map into the Wine target client")
    func quartzPointMapsToWineClient() {
        let window = WindowInfo(
            id: 42,
            ownerPID: 42,
            ownerName: "wine",
            title: "Genshin Impact",
            frame: CGRect(x: 839, y: 233, width: 960, height: 572),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 2)

        let point = WineBridgeInputDispatcher.wineClientPoint(
            CGPoint(x: 1_719, y: 775),
            targetWindow: window)

        #expect(point == CGPoint(x: 1_760, y: 1_020))
    }

    @Test("Wine relative movement follows the host point scale")
    func relativeMovementUsesHostPointScale() {
        let window = WindowInfo(
            id: 42,
            ownerPID: 42,
            ownerName: "wine",
            title: "Genshin Impact",
            frame: CGRect(x: 839, y: 233, width: 960, height: 572),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 2)

        let delta = WineBridgeInputDispatcher.wineRelativeDelta(
            deltaX: -1_180,
            deltaY: 240,
            targetWindow: window)

        #expect(delta == CGPoint(x: -590, y: 120))
    }

    @Test("Raw Wine relative movement preserves Core deltas")
    func rawRelativeMovementPreservesCoreDeltas() {
        let window = WindowInfo(
            id: 42,
            ownerPID: 42,
            ownerName: "wine",
            title: "Genshin Impact",
            frame: CGRect(x: 839, y: 233, width: 960, height: 572),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 2)

        let delta = WineBridgeInputDispatcher.wineRelativeDelta(
            deltaX: -1_180,
            deltaY: 240,
            targetWindow: window,
            mode: .raw)

        #expect(delta == CGPoint(x: -1_180, y: 240))
    }

    @Test("Foreground diagnostic decodes Win32 focus state")
    func foregroundDiagnosticDecodes() throws {
        var payload = Data()
        [UInt32(123), 456, 12, 34].forEach { payload.appendLittleEndian($0) }
        [
            UInt64(0x100), 0x200, 0x300, 0x400, 0x500, 0x600, 0x700
        ].forEach { payload.appendLittleEndian($0) }
        payload.appendLittleEndian(UInt32(bitPattern: -1))
        payload.appendLittleEndian(UInt32(3))
        payload.appendLittleEndian(UInt16(0x46))
        payload.appendLittleEndian(UInt16(0x8001))
        let name = Data("GenshinImpact.exe".utf8)
        payload.append(name)
        payload.append(Data(repeating: 0, count: 64 - name.count))

        let diagnostic = try WineBridgeForegroundDiagnostic.decode(payload)

        #expect(payload.count == WineBridgeForegroundDiagnostic.encodedSize)
        #expect(diagnostic.targetProcessID == 123)
        #expect(diagnostic.foregroundProcessID == 456)
        #expect(diagnostic.targetIsWindow)
        #expect(diagnostic.targetIsVisible)
        #expect(diagnostic.focusWindow == 0x400)
        #expect(diagnostic.setForegroundResult == -1)
        #expect(diagnostic.foregroundExecutableName == "GenshinImpact.exe")
    }

    @Test("Input context priming is needed only when Wine foreground differs")
    func inputContextPrimingRequirementTracksWineForeground() throws {
        var payload = Data()
        [UInt32(123), 456, 12, 34].forEach { payload.appendLittleEndian($0) }
        [
            UInt64(0x30054), 0x10020, 0x30054, 0x30054, 0, 0, 0
        ].forEach { payload.appendLittleEndian($0) }
        payload.appendLittleEndian(UInt32(bitPattern: -1))
        payload.appendLittleEndian(UInt32(3))
        payload.appendLittleEndian(UInt16(0x46))
        payload.appendLittleEndian(UInt16(0))
        payload.append(Data(repeating: 0, count: 64))
        let background = try WineBridgeForegroundDiagnostic.decode(payload)

        #expect(WineBridgeInputDispatcher.needsInputContextPriming(background))

        payload.replaceSubrange(
            24 ..< 32,
            with: withUnsafeBytes(of: UInt64(0x30054).littleEndian, Array.init))
        let foreground = try WineBridgeForegroundDiagnostic.decode(payload)

        #expect(!WineBridgeInputDispatcher.needsInputContextPriming(foreground))
    }

    @Test("Input delivery capabilities require the validated mouse-prime configuration")
    func inputDeliveryCapabilities() {
        let base = WineBridgeConfiguration(
            wineExecutableURL: URL(fileURLWithPath: "/wine"),
            winePrefixURL: URL(fileURLWithPath: "/prefix"),
            bridgeExecutableURL: URL(fileURLWithPath: "/bridge.exe"),
            targetExecutableNames: ["YuanShen.exe", "GenshinImpact.exe"],
            startupTimeout: 12,
            backgroundDiagnosticEnabled: true,
            relativeMouseMode: .scaled,
            foregroundExperiment: .none)
        let validated = WineBridgeConfiguration(
            wineExecutableURL: base.wineExecutableURL,
            winePrefixURL: base.winePrefixURL,
            bridgeExecutableURL: base.bridgeExecutableURL,
            targetExecutableNames: base.targetExecutableNames,
            startupTimeout: base.startupTimeout,
            backgroundDiagnosticEnabled: false,
            relativeMouseMode: base.relativeMouseMode,
            foregroundExperiment: .inputContextWake)
        let middle = WineBridgeConfiguration(
            wineExecutableURL: base.wineExecutableURL,
            winePrefixURL: base.winePrefixURL,
            bridgeExecutableURL: base.bridgeExecutableURL,
            targetExecutableNames: base.targetExecutableNames,
            startupTimeout: base.startupTimeout,
            backgroundDiagnosticEnabled: true,
            relativeMouseMode: base.relativeMouseMode,
            foregroundExperiment: .inputContextWakeMiddle)

        #expect(base.capabilities == .foregroundOnly)
        #expect(validated.capabilities == InputDeliveryCapabilities(
            requiresHostForeground: false,
            supportsBackgroundDelivery: true))
        #expect(middle.capabilities.supportsBackgroundDelivery)
        #expect(WineForegroundExperiment.inputContextWake.wakeButton == .middle)
        #expect(WineForegroundExperiment.inputContextWakeLeft.wakeButton == .left)
        #expect(InputBackendSelection.allCases.first == .wineBridge)
    }

    @Test("Input-context policy encodes a monotonic wake deadline")
    func inputContextPolicyPayload() throws {
        var reader = WineBridgeDataReader(
            WineBridgeInputDispatcher.inputContextPolicyPayload(enabled: true))

        #expect(try reader.readUInt8() == 1)
        #expect(try reader.readUInt8() == 3)
        #expect(try reader.readUInt16() == 3_000)

        var leftReader = WineBridgeDataReader(
            WineBridgeInputDispatcher.inputContextPolicyPayload(
                enabled: true,
                wakeButton: .left))
        #expect(try leftReader.readUInt8() == 1)
        #expect(try leftReader.readUInt8() == 1)
        #expect(try leftReader.readUInt16() == 3_000)
    }

    @Test("Wine Bridge is the default and invalid overrides never fall back")
    func backendSelection() {
        let normal = InputDispatcherFactory.make(launchArguments: ["betterGI-mac"])
        let wine = InputDispatcherFactory.make(launchArguments: [
            "betterGI-mac", "--input-backend", "wine-bridge"
        ])
        let invalid = InputDispatcherFactory.make(launchArguments: [
            "betterGI-mac", "--input-backend", "unknown"
        ])

        #expect(normal.deliveryMode == .wineBridge)
        #expect(wine.deliveryMode == .wineBridge)
        #expect(invalid.deliveryMode == .wineBridge)
        #expect(!(invalid is CGEventInputDispatcher))
    }

    @Test("Normal Wine configuration enables validated background delivery")
    func normalWineConfigurationUsesBackgroundDelivery() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "bettergi-wine-default-\(UUID().uuidString)",
                isDirectory: true)
        let wine = root.appendingPathComponent("wine")
        let prefix = root.appendingPathComponent("prefix", isDirectory: true)
        let bridge = root.appendingPathComponent("bridge.exe")
        try FileManager.default.createDirectory(
            at: prefix,
            withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: wine.path, contents: Data())
        _ = FileManager.default.createFile(atPath: bridge.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = try WineBridgeConfiguration.resolve(
            launchArguments: ["betterGI-mac"],
            environment: [
                "BETTERGI_WINE_EXECUTABLE": wine.path,
                "BETTERGI_WINE_PREFIX": prefix.path,
                "BETTERGI_WINE_BRIDGE_EXE": bridge.path,
            ])

        #expect(configuration.foregroundExperiment == .inputContextWake)
        #expect(configuration.capabilities.supportsBackgroundDelivery)
        #expect(!configuration.capabilities.requiresHostForeground)
    }

    @MainActor
    @Test("Dry-run blocks Wine bridge process and input startup")
    func dryRunDoesNotStartWineBridge() {
        let launchArguments = [
            "betterGI-mac",
            "--dry-run",
            "--input-backend",
            "wine-bridge",
            "--wine-bridge-executable",
            "/definitely/missing/BetterGIWineInputBridge.exe",
        ]
        let appState = AppState(
            resourceStore: BGIRuntimeResourceStore(
                rootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "bettergi-wine-dry-run-\(UUID().uuidString)",
                        isDirectory: true)),
            inputDispatcher: InputDispatcherFactory.make(
                launchArguments: launchArguments),
            isTargetWindowFrontmost: { _ in true },
            launchArguments: launchArguments)
        appState.selectedWindow = WindowInfo(
            id: 42,
            ownerPID: 42,
            ownerName: "wine",
            title: "Genshin Impact",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1)
        appState.runtimeLifecycle = .running

        let result = appState.dispatchInput(
            .mouseMoveRelative(deltaX: -5, deltaY: 8),
            source: .runtimeTrigger)

        #expect(result.isDryRun)
    }

    @MainActor
    @Test("Diagnostic flag alone cannot bypass the runtime foreground gate")
    func diagnosticFlagDoesNotBypassRuntimeForegroundGate() {
        let dispatcher = DiagnosticRecordingInputDispatcher(
            capabilities: .foregroundOnly)
        let launchArguments = [
            "betterGI-mac",
            "--input-backend",
            "wine-bridge",
            "--wine-background-diagnostic",
        ]
        let appState = AppState(
            resourceStore: BGIRuntimeResourceStore(
                rootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "bettergi-wine-background-diagnostic-\(UUID().uuidString)",
                        isDirectory: true)),
            inputDispatcher: dispatcher,
            isTargetWindowFrontmost: { _ in false },
            launchArguments: launchArguments)
        appState.selectedWindow = WindowInfo(
            id: 42,
            ownerPID: 42,
            ownerName: "wine",
            title: "Genshin Impact",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1)
        appState.runtimeLifecycle = .running

        let result = appState.dispatchInput(
            .keyPress(key: .f),
            source: .runtimeTrigger)

        #expect(!result.allowed)
        #expect(dispatcher.actions.isEmpty)
        #expect(!appState.inputDeliveryCapabilities.supportsBackgroundDelivery)
        #expect(appState.inputDeliveryMode == .wineBridge)
    }

    @MainActor
    @Test("Validated Wine background capability bypasses the runtime foreground gate")
    func validatedCapabilityBypassesRuntimeForegroundGate() {
        let dispatcher = DiagnosticRecordingInputDispatcher(
            capabilities: InputDeliveryCapabilities(
                requiresHostForeground: false,
                supportsBackgroundDelivery: true))
        let launchArguments = [
            "betterGI-mac",
            "--input-backend",
            "wine-bridge",
            "--wine-background-diagnostic",
            "--wine-foreground-experiment",
            "mouse-prime",
        ]
        let appState = AppState(
            resourceStore: BGIRuntimeResourceStore(
                rootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "bettergi-wine-background-capability-\(UUID().uuidString)",
                        isDirectory: true)),
            inputDispatcher: dispatcher,
            isTargetWindowFrontmost: { _ in false },
            launchArguments: launchArguments)
        appState.selectedWindow = WindowInfo(
            id: 42,
            ownerPID: 42,
            ownerName: "wine",
            title: "Genshin Impact",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1)
        appState.runtimeLifecycle = .running

        let result = appState.dispatchInput(
            .keyPress(key: .f),
            source: .runtimeTrigger)

        #expect(result.allowed)
        #expect(dispatcher.actions == [.keyPress(key: .f)])
        #expect(appState.inputDeliveryCapabilities.supportsBackgroundDelivery)
    }
}

private final class DiagnosticRecordingInputDispatcher: InputDispatching {
    let deliveryMode = InputDeliveryMode.wineBridge
    let capabilities: InputDeliveryCapabilities
    private(set) var actions: [InputAction] = []

    init(capabilities: InputDeliveryCapabilities = .foregroundOnly) {
        self.capabilities = capabilities
    }

    func perform(
        _ action: InputAction,
        targetWindow: WindowInfo
    ) throws -> CGEventDispatchReport {
        actions.append(action)
        return CGEventDispatchReport(eventCount: 1, detail: action.displayName)
    }
}
