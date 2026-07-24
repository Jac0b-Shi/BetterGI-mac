import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI Core one-dragon callbacks")
struct BetterGICoreOneDragonCallbackTests {
    @MainActor
    @Test("One-dragon lifecycle events are acknowledged")
    func lifecycleEventsAreAcknowledged() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "bettergi-one-dragon-callback-\(UUID().uuidString)",
                isDirectory: true)
        let appState = AppState(
            resourceStore: BGIRuntimeResourceStore(rootURL: root))
        let adapter = BetterGICorePlatformAdapter(appState: appState)

        for state in ["running", "completed"] {
            let parameters = OneDragonEventParameters([
                "taskId": "task-1",
                "state": state,
                "error": NSNull(),
            ])
            try await Task.detached { () throws -> Void in
                let result = try adapter.handle(
                    method: "oneDragon.event",
                    parameters: parameters.value) as? [String: Bool]
                guard result?["acknowledged"] == true else {
                    throw BetterGICorePlatformAdapterError.invalidParameters(
                        "oneDragon.event was not acknowledged.")
                }
            }.value
        }

        #expect(appState.oneDragonStatus.taskID == nil)
        #expect(appState.oneDragonStatus.state == "completed")
        #expect(appState.appStatus == .idle)
    }

    @MainActor
    @Test("Failed event retains error and clears the active task")
    func failedEventRetainsError() throws {
        let appState = makeOneDragonAppState("failed")
        appState.oneDragonStatus = BetterGIOneDragonStatus(
            taskID: "task-2",
            configName: "每日",
            state: "running",
            error: nil)

        try appState.handleCoreOneDragonEvent(
            taskID: "task-2",
            state: "failed",
            error: "verification failure")

        #expect(appState.oneDragonStatus.taskID == nil)
        #expect(appState.oneDragonStatus.state == "failed")
        #expect(appState.oneDragonStatus.error == "verification failure")
        #expect(appState.appStatus == .error)
    }

    @MainActor
    @Test("Terminal event cannot overwrite a new pending start")
    func terminalEventCannotOverwritePendingStart() {
        let appState = makeOneDragonAppState("stale")
        appState.oneDragonStatus = BetterGIOneDragonStatus(
            taskID: nil,
            configName: "夜班",
            state: "starting",
            error: nil)

        #expect(throws: BetterGICorePlatformAdapterError.self) {
            try appState.handleCoreOneDragonEvent(
                taskID: "old-task",
                state: "completed",
                error: nil)
        }
        #expect(appState.oneDragonStatus.state == "starting")
        #expect(appState.oneDragonStatus.configName == "夜班")
    }

    @MainActor
    @Test("Unsupported lifecycle state is rejected")
    func unsupportedStateIsRejected() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "bettergi-one-dragon-invalid-\(UUID().uuidString)",
                isDirectory: true)
        let appState = AppState(
            resourceStore: BGIRuntimeResourceStore(rootURL: root))
        let adapter = BetterGICorePlatformAdapter(appState: appState)
        let parameters = OneDragonEventParameters([
            "taskId": "task-1",
            "state": "paused",
        ])

        await #expect(throws: BetterGICorePlatformAdapterError.self) {
            try await Task.detached { () throws -> Void in
                _ = try adapter.handle(
                    method: "oneDragon.event",
                    parameters: parameters.value)
            }.value
        }
        #expect(appState.oneDragonStatus.state == "idle")
    }
}

@MainActor
private func makeOneDragonAppState(_ suffix: String) -> AppState {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bettergi-one-dragon-\(suffix)-\(UUID().uuidString)",
            isDirectory: true)
    return AppState(resourceStore: BGIRuntimeResourceStore(rootURL: root))
}

private final class OneDragonEventParameters: @unchecked Sendable {
    let value: [String: Any]

    init(_ value: [String: Any]) {
        self.value = value
    }
}
