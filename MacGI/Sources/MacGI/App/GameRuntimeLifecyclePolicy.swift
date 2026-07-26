import Darwin

enum GameRuntimeLifecyclePolicy {
    static func shouldStopAfterTermination(
        runtimeLifecycle: RuntimeLifecycle,
        targetProcessID: pid_t?,
        terminatedProcessID: pid_t
    ) -> Bool {
        runtimeLifecycle == .running
            && targetProcessID != nil
            && targetProcessID == terminatedProcessID
    }

    static func shouldStopWhenWindowUnavailable(
        runtimeLifecycle: RuntimeLifecycle,
        targetProcessID: pid_t?,
        targetProcessAlive: Bool
    ) -> Bool {
        runtimeLifecycle == .running
            && targetProcessID != nil
            && !targetProcessAlive
    }
}
