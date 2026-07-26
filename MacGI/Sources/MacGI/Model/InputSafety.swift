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
///           4. window.isSynthetic?  ───→  blocked
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
    @Published var dryRun: Bool

    /// When `true`, the automation loop and ALL input is halted immediately.
    /// Must be manually reset by the user (NOT auto-cleared by start).
    @Published var emergencyStop = false

    /// Internal dispatch state. Normal launches enable it; explicit `--dry-run`
    /// launches disable it before any Core callback can dispatch a CGEvent.
    @Published var realInputEnabled: Bool

    /// Minimum interval between two consecutive manual real-input actions (seconds).
    /// Core owns production action timing; applying this to runtime callbacks would
    /// split valid key and mouse sequences emitted by the shared BetterGI tasks.
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

    init(dryRun: Bool = false, realInputEnabled: Bool = true) {
        self.dryRun = dryRun
        self.realInputEnabled = realInputEnabled
    }

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
            return .blocked(reason: "Automation runtime is not running")
        }

        // 3. Invalid window
        if window.id == 0 || !window.isOnScreen {
            blockedActionCount += 1
            return .blocked(reason: "Target window invalid or off-screen (id=\(window.id))")
        }

        // 4. Synthetic sentinel — never dispatch real input without a backing window
        if window.isSynthetic {
            blockedActionCount += 1
            return .blocked(reason: "Synthetic window sentinel cannot receive real input")
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

        // 9. Manual-input rate limit. Runtime sequencing remains Core-owned.
        if source == .manual {
            let elapsed = Date().timeIntervalSince(lastDispatchTime)
            if elapsed < rateLimit {
                blockedActionCount += 1
                return .blocked(reason: String(format: "Rate limit: %.0fms since last action", elapsed * 1000))
            }
            lastDispatchTime = Date()
        }

        // 10. All clear
        dispatchCount += 1
        return .allow
    }

    /// Record a dry-run hit from external dispatch when `check()` is deliberately bypassed.
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
