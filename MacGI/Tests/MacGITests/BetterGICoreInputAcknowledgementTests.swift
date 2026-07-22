import CoreGraphics
import Foundation
@testable import MacGI
import Testing
@Suite("BetterGI Core input acknowledgement")
struct BetterGICoreInputAcknowledgementTests {
    @MainActor
    @Test("Normal launch uses real input and dry-run is explicit")
    func launchInputPolicy() {
        let normal = AppState(
            resourceStore: temporaryStore("normal-input"),
            isTargetWindowFrontmost: { _ in true },
            launchArguments: ["betterGI-mac"])
        #expect(!normal.safetyGate.dryRun)
        #expect(normal.safetyGate.realInputEnabled)
        #expect(normal.allowRuntimeRealInput)

        let dryRun = AppState(
            resourceStore: temporaryStore("dry-run"),
            isTargetWindowFrontmost: { _ in true },
            launchArguments: ["betterGI-mac", "--dry-run"])
        #expect(dryRun.safetyGate.dryRun)
        #expect(!dryRun.safetyGate.realInputEnabled)
        #expect(!dryRun.allowRuntimeRealInput)
    }

    @MainActor
    @Test("Core input callback rejects a platform dispatch failure")
    func coreInputRejectsDispatchFailure() async throws {
        let appState = AppState(
            resourceStore: BGIRuntimeResourceStore(
                rootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("bettergi-core-input-ack-\(UUID().uuidString)", isDirectory: true)
            ),
            inputDispatcher: RejectingInputDispatcher(),
            isTargetWindowFrontmost: { _ in true }
        )
        appState.selectedWindow = WindowInfo(
            id: 42,
            ownerPID: 42,
            ownerName: "wine64-preloader",
            title: "Genshin Impact",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1
        )
        appState.appStatus = .running
        appState.runtimeLifecycle = .running
        let adapter = BetterGICorePlatformAdapter(appState: appState)
        let error = await Task.detached {
            do {
                _ = try adapter.handle(
                    method: "input.dispatch",
                    parameters: ["action": "keyPress", "key": "A"]
                )
                return nil as Error?
            } catch {
                return error
            }
        }.value

        let adapterError = try #require(error as? BetterGICorePlatformAdapterError)
        guard case .inputRejected(let reason) = adapterError else {
            Issue.record("Core input callback returned the wrong error: \(adapterError)")
            return
        }
        #expect(reason.contains("CGEvent dispatch failed"))
        #expect(appState.inputStatus == .error)
    }

    @MainActor
    @Test("Stopped runtime rejects trigger input even while scheduler is running")
    func stoppedRuntimeRejectsTriggerInput() async throws {
        let appState = AppState(
            resourceStore: BGIRuntimeResourceStore(
                rootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("bettergi-runtime-stopped-\(UUID().uuidString)", isDirectory: true)
            ),
            inputDispatcher: RejectingInputDispatcher(),
            isTargetWindowFrontmost: { _ in true }
        )
        appState.selectedWindow = WindowInfo(
            id: 42,
            ownerPID: 42,
            ownerName: "wine64-preloader",
            title: "Genshin Impact",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1
        )
        appState.appStatus = .running
        appState.runtimeLifecycle = .stopped

        let result = appState.dispatchInput(.keyPress(key: .a), source: .runtimeTrigger)

        #expect(result.isBlocked)
        #expect(result.reason == "Automation runtime is not running")
    }

}

private func temporaryStore(_ name: String) -> BGIRuntimeResourceStore {
    BGIRuntimeResourceStore(
        rootURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-\(name)-\(UUID().uuidString)", isDirectory: true))
}

private struct RejectingInputDispatcher: InputDispatching {
    func perform(_ action: InputAction, targetWindow: WindowInfo) throws -> CGEventDispatchReport {
        throw CGEventInputDispatchError.eventCreationFailed("verification")
    }
}
