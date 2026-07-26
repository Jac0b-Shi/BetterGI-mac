import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("Wine bridge protocol")
struct WineBridgeProtocolTests {
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
            backgroundDiagnosticEnabled: true,
            relativeMouseMode: base.relativeMouseMode,
            foregroundExperiment: .mousePrime)

        #expect(base.capabilities == .foregroundOnly)
        #expect(validated.capabilities == InputDeliveryCapabilities(
            requiresHostForeground: false,
            supportsBackgroundDelivery: true))
    }

    @Test("Atomic input-context policy encodes finite retries")
    func atomicInputContextPolicyPayload() throws {
        var reader = WineBridgeDataReader(
            WineBridgeInputDispatcher.inputContextPolicyPayload(enabled: true))

        #expect(try reader.readUInt8() == 1)
        #expect(try reader.readUInt8() == 3)
        #expect(try reader.readUInt16() == 150)
    }

    @Test("Backend selection is explicit and invalid overrides never fall back")
    func backendSelection() {
        let normal = InputDispatcherFactory.make(launchArguments: ["betterGI-mac"])
        let wine = InputDispatcherFactory.make(launchArguments: [
            "betterGI-mac", "--input-backend", "wine-bridge"
        ])
        let invalid = InputDispatcherFactory.make(launchArguments: [
            "betterGI-mac", "--input-backend", "unknown"
        ])

        #expect(normal.deliveryMode == .foregroundCGEvent)
        #expect(wine.deliveryMode == .wineBridge)
        #expect(invalid.deliveryMode == .wineBridge)
        #expect(!(invalid is CGEventInputDispatcher))
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
