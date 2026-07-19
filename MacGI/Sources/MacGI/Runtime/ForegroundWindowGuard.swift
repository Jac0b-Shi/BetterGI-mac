import AppKit
import Foundation

/// Guards real input dispatch by verifying the target window is frontmost.
///
/// ## Purpose
/// When the user switches away from the game (e.g., to a browser or terminal),
/// runtime trigger actions must not be dispatched as real CGEvent input into
/// the wrong foreground application.
///
/// This guard checks the frontmost app's PID against the selected game window's
/// owner PID. It does NOT automatically activate the game window — that decision
/// belongs to the user or a higher-level "focus game" command.
struct ForegroundWindowGuard {

    /// Check whether `window` belongs to the currently frontmost application.
    static func isTargetFrontmost(_ window: WindowInfo) -> Bool {
        guard !window.isSynthetic else { return false }
        guard let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return false
        }
        return frontPID == window.ownerPID
    }

    /// Human-readable description of the current foreground state.
    static func frontmostDescription(for window: WindowInfo) -> String {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return "Frontmost app: unknown | Target: \(window.displayName)"
        }
        let frontName = frontApp.localizedName ?? "unknown"
        return "Frontmost: \(frontName) (PID \(frontApp.processIdentifier)) | Target: \(window.displayName) (PID \(window.ownerPID))"
    }
}
