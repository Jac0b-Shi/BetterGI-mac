import Foundation

// MARK: - ActionSource

/// Identifies where an action originated.
enum ActionSource: Equatable {
    /// Manual action from a UI button or debug panel.
    case manual
    /// Action produced by the runtime trigger loop (AutoPick, AutoSkip, etc.).
    case runtimeTrigger
}

// MARK: - InputSafetyGate

/// Controls the input dispatch safety boundary.
///
/// Priority stack (first match wins):
/// ```text
/// OCRDecision → ActionDispatcher → SafetyGate.check()
///                                     │
///           1. emergencyStop?  ───→  blocked
///           2. !isAppRunning?  ───→  blocked
///           3. window invalid? ───→  blocked
///           4. window.isMock?  ───→  blocked
///           5. dryRun?         ───→  dryRun (no CGEvent, skips runtime guards)
///           6. !realInput?     ───→  blocked
///           7. runtimeTrigger && !allowRuntimeRealInput? → blocked
///           8. runtimeTrigger && !foreground? → blocked
///           9. rate limit?     ───→  blocked
///          10. all clear       ───→  allow
///                                     └──→ InputService.execute()
/// ```
///
/// Upstream BetterGI achieves safety via `TaskControl.TrySuspend()`,
/// foreground checks (`IsGenshinImpactActive`), and the absence of a
/// "real input" toggle — input is always real once started.
/// On macOS we add an explicit dry-run mode for development safety.
@MainActor
final class InputSafetyGate: ObservableObject {

    // MARK: Published state

    /// When `true`, all input actions are logged but NOT dispatched.
    /// Priority: checked BEFORE `realInputEnabled`.
    @Published var dryRun = true

    /// When `true`, the automation loop and ALL input is halted immediately.
    /// Must be manually reset by the user (NOT auto-cleared by start).
    @Published var emergencyStop = false

    /// Armed signal: must be `true` for real input to leave the gate.
    /// Even when `dryRun == false`, this must be ON before CGEvent dispatch.
    @Published var realInputEnabled = false

    /// Minimum interval between two consecutive real input actions (seconds).
    @Published var rateLimit: TimeInterval = 0.05

    // MARK: Read-only counters

    /// Timestamp of the last dispatched `allow` action.
    private(set) var lastDispatchTime: Date = .distantPast

    /// Count of `blocked` results since last reset.
    private(set) var blockedActionCount: Int = 0

    /// Count of `allow` dispatches since last reset.
    private(set) var dispatchCount: Int = 0

    /// Count of `dryRun` results since last reset.
    private(set) var dryRunCount: Int = 0

    /// Total actions processed (sum of all three).
    var totalActionCount: Int {
        blockedActionCount + dispatchCount + dryRunCount
    }

    // MARK: Gate result

    /// Three-state result from `check()`.
    enum GateResult: Equatable, Sendable {
        /// Real input allowed — dispatch to CGEvent.
        case allow

        /// Dry-run mode — log only, no real input.
        case dryRun(reason: String = "Dry-run mode")

        /// Blocked — do not dispatch, do not log as action.
        case blocked(reason: String)

        var allowed: Bool { self == .allow }
        var isDryRun: Bool { if case .dryRun = self { return true }; return false }
        var isBlocked: Bool { if case .blocked = self { return true }; return false }

        var reason: String {
            switch self {
            case .allow: ""
            case let .dryRun(reason): reason
            case let .blocked(reason): reason
            }
        }
    }

    // MARK: Check

    /// Run an action through the safety gate.
    ///
    /// - Parameters:
    ///   - window: Target game window.
    ///   - isAppRunning: Whether the automation loop is active.
    ///   - source: Where the action came from (manual vs runtime trigger).
    ///   - allowRuntimeRealInput: Whether runtime-triggered real input is permitted.
    ///   - isTargetFrontmost: Whether the target window is the frontmost application.
    /// - Returns: `.allow`, `.dryRun`, or `.blocked(reason:)`.
    func check(
        window: WindowInfo,
        isAppRunning: Bool,
        source: ActionSource = .manual,
        allowRuntimeRealInput: Bool = false,
        isTargetFrontmost: Bool = true
    ) -> GateResult {
        // 1. Emergency stop
        if emergencyStop {
            blockedActionCount += 1
            return .blocked(reason: "Emergency stop active")
        }

        // 2. Not running
        if !isAppRunning {
            blockedActionCount += 1
            return .blocked(reason: "Automation not running (appStatus != .running)")
        }

        // 3. Invalid window
        if window.id == 0 || !window.isOnScreen {
            blockedActionCount += 1
            return .blocked(reason: "Target window invalid or off-screen (id=\(window.id))")
        }

        // 4. Mock window — never dispatch real input into a mock
        if window.isMock {
            blockedActionCount += 1
            return .blocked(reason: "Mock window cannot receive real input")
        }

        // 5. Dry-run — log but no dispatch, skip runtime guards
        if dryRun {
            dryRunCount += 1
            return .dryRun()
        }

        // 6. Real input not armed
        if !realInputEnabled {
            blockedActionCount += 1
            return .blocked(reason: "Real input disabled")
        }

        // 7. Runtime trigger requires explicit allowRuntimeRealInput
        if source == .runtimeTrigger && !allowRuntimeRealInput {
            blockedActionCount += 1
            return .blocked(reason: "Runtime real input disabled")
        }

        // 8. Runtime trigger requires foreground match
        if source == .runtimeTrigger && !isTargetFrontmost {
            blockedActionCount += 1
            return .blocked(reason: "Target window is not frontmost")
        }

        // 9. Rate limit
        let elapsed = Date().timeIntervalSince(lastDispatchTime)
        if elapsed < rateLimit {
            blockedActionCount += 1
            return .blocked(reason: String(format: "Rate limit: %.0fms since last action", elapsed * 1000))
        }

        // 10. All clear
        dispatchCount += 1
        lastDispatchTime = Date()
        return .allow
    }

    /// Record a dry-run hit from external dispatch (used when `check()` is bypassed in mock).
    func recordDryRun() {
        dryRunCount += 1
    }

    // MARK: Reset

    /// Reset all counters (used when automation starts).
    func resetCounters() {
        blockedActionCount = 0
        dispatchCount = 0
        dryRunCount = 0
        lastDispatchTime = .distantPast
    }
}
