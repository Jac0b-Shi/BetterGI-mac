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

    @Test("Relative mouse payload preserves signed deltas")
    func relativeMousePayloadPreservesSignedDeltas() throws {
        let payload = WineBridgeInputDispatcher.mouseMovePayload(x: -37, y: 19)
        var reader = WineBridgeDataReader(payload)

        #expect(Int32(bitPattern: try reader.readUInt32()) == -37)
        #expect(Int32(bitPattern: try reader.readUInt32()) == 19)
    }

    @Test("Backend selection is explicit and never falls back for invalid values")
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
}
