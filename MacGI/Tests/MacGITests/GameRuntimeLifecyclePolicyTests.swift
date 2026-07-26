import Testing
@testable import MacGI

@Suite("Game runtime lifecycle policy")
struct GameRuntimeLifecyclePolicyTests {
    @Test("Stops only when the tracked game process terminates")
    func trackedProcessTermination() {
        #expect(GameRuntimeLifecyclePolicy.shouldStopAfterTermination(
            runtimeLifecycle: .running,
            targetProcessID: 100,
            terminatedProcessID: 100))
        #expect(!GameRuntimeLifecyclePolicy.shouldStopAfterTermination(
            runtimeLifecycle: .running,
            targetProcessID: 100,
            terminatedProcessID: 200))
        #expect(!GameRuntimeLifecyclePolicy.shouldStopAfterTermination(
            runtimeLifecycle: .stopped,
            targetProcessID: 100,
            terminatedProcessID: 100))
    }

    @Test("Keeps capture running while the tracked process survives window recreation")
    func windowRecreation() {
        #expect(!GameRuntimeLifecyclePolicy.shouldStopWhenWindowUnavailable(
            runtimeLifecycle: .running,
            targetProcessID: 100,
            targetProcessAlive: true))
    }

    @Test("Stops after a missing window confirms the tracked process exited")
    func missingWindowAfterExit() {
        #expect(GameRuntimeLifecyclePolicy.shouldStopWhenWindowUnavailable(
            runtimeLifecycle: .running,
            targetProcessID: 100,
            targetProcessAlive: false))
        #expect(!GameRuntimeLifecyclePolicy.shouldStopWhenWindowUnavailable(
            runtimeLifecycle: .running,
            targetProcessID: nil,
            targetProcessAlive: false))
    }
}
