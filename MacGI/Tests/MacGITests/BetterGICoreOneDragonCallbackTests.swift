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

        for state in ["running", "completed", "cancelled", "failed"] {
            let parameters = OneDragonEventParameters([
                "taskId": "task-1",
                "state": state,
                "error": state == "failed"
                    ? ["message": "verification failure"]
                    : NSNull(),
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
    }
}

private final class OneDragonEventParameters: @unchecked Sendable {
    let value: [String: Any]

    init(_ value: [String: Any]) {
        self.value = value
    }
}
