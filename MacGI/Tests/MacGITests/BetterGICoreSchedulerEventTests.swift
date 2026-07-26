import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI Core scheduler events")
struct BetterGICoreSchedulerEventTests {
    @MainActor
    @Test("Failed event clears the active task and exposes the Core error")
    func failedEventClearsActiveTask() async throws {
        let appState = makeSchedulerEventAppState()
        let adapter = BetterGICorePlatformAdapter(appState: appState)

        try await handle(adapter, state: "running")
        #expect(appState.currentSchedulerProjectID == "task-1")
        #expect(appState.appStatus == .running)

        try await handle(
            adapter,
            state: "failed",
            error: ["code": "PlatformCallbackException", "message": "verification activation failure"]
        )
        #expect(appState.schedulerExecutionStatus == "failed")
        #expect(appState.schedulerExecutionError == "verification activation failure")
        #expect(appState.currentSchedulerProjectID == nil)
        #expect(appState.appStatus == .error)
    }

    @MainActor
    @Test("Terminal event cannot be overwritten by a late run response")
    func terminalEventWinsRunResponseRace() throws {
        let appState = makeSchedulerEventAppState()
        try appState.handleCoreSchedulerEvent(taskID: "task-1", state: "completed", error: nil)
        appState.handleCoreSchedulerRunAccepted(taskID: "task-1", groupName: "verification")

        #expect(appState.schedulerExecutionStatus == "completed")
        #expect(appState.currentSchedulerProjectID == nil)
        #expect(appState.appStatus == .idle)
    }

    @MainActor
    @Test("Terminal event cannot be overwritten by late control responses")
    func terminalEventWinsControlResponseRace() throws {
        let appState = makeSchedulerEventAppState()
        try appState.handleCoreSchedulerEvent(
            taskID: "task-1",
            state: "failed",
            error: "verification failure"
        )

        for state in ["running", "paused", "stopping"] {
            appState.handleCoreSchedulerControlAccepted(taskID: "task-1", state: state)
        }
        appState.handleCoreSchedulerControlFailed(
            taskID: "task-1",
            operation: "stop",
            error: BetterGICoreRPCError.protocolViolation("late failure")
        )

        #expect(appState.schedulerExecutionStatus == "failed")
        #expect(appState.schedulerExecutionError == "verification failure")
        #expect(appState.currentSchedulerProjectID == nil)
        #expect(appState.appStatus == .error)
    }

    @MainActor
    @Test("Old task control failure cannot overwrite a newer running task")
    func staleControlFailureDoesNotOverwriteNewTask() throws {
        let appState = makeSchedulerEventAppState()
        try appState.handleCoreSchedulerEvent(taskID: "task-1", state: "running", error: nil)
        try appState.handleCoreSchedulerEvent(taskID: "task-1", state: "completed", error: nil)
        try appState.handleCoreSchedulerEvent(taskID: "task-2", state: "running", error: nil)

        appState.handleCoreSchedulerControlFailed(
            taskID: "task-1",
            operation: "stop",
            error: BetterGICoreRPCError.protocolViolation("late failure")
        )

        #expect(appState.schedulerExecutionStatus == "running")
        #expect(appState.schedulerExecutionError == nil)
        #expect(appState.currentSchedulerProjectID == "task-2")
        #expect(appState.appStatus == .running)
    }

    @MainActor
    private func makeSchedulerEventAppState() -> AppState {
        AppState(resourceStore: BGIRuntimeResourceStore(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("bettergi-scheduler-event-\(UUID().uuidString)", isDirectory: true)
        ))
    }

    private func handle(
        _ adapter: BetterGICorePlatformAdapter,
        state: String,
        error: [String: String]? = nil
    ) async throws {
        var parameters: [String: Any] = ["taskId": "task-1", "state": state]
        if let error { parameters["error"] = error }
        let transfer = SchedulerEventParameters(parameters)
        try await Task.detached { () throws -> Void in
            _ = try adapter.handle(method: "scheduler.event", parameters: transfer.value)
        }.value
    }
}

private final class SchedulerEventParameters: @unchecked Sendable {
    let value: [String: Any]

    init(_ value: [String: Any]) {
        self.value = value
    }
}
