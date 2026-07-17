import CoreGraphics
import Foundation

// MARK: - WindowInfo

/// Stable window identity for ScreenCaptureKit, HUD following, and input routing.
///
/// In upstream BetterGI, `TaskContext.GameHandle` (HWND) + `ISystemInfo` serve this role.
/// On macOS, `CGWindowID` is the equivalent stable handle.
///
/// Why not use strings:
/// - SCK needs `CGWindowID`, not a title string.
/// - Window titles change / are empty / differ by locale.
/// - YAAGL wrapper titles differ from Wine game titles.
/// - HUD overlay needs a `CGRect` and `scaleFactor`, not a string.
/// - Input dispatch needs PID for `AXUIElement` and foreground check.
///
/// Keep `title` / `ownerName` as display helpers only — never as identity.
struct WindowInfo: Identifiable, Equatable, Hashable, Sendable {

    // MARK: Identity

    /// Stable `CGWindowID`. Zero means "no window".
    let id: CGWindowID

    /// Owner process identifier (for `AXUIElementCreateApplication` and foreground checks).
    let ownerPID: pid_t

    // MARK: Display

    /// Bundle/process name, e.g. "YAAGL", "wine64-preloader".
    let ownerName: String

    /// Current window title (unstable — do not use for identity).
    let title: String

    // MARK: Geometry

    /// Window frame in screen coordinates.
    let frame: CGRect

    /// Quartz window layer (filters utility panels, overlays, etc.).
    let layer: Int

    /// `true` when the window is currently on-screen.
    let isOnScreen: Bool

    /// Backing scale factor (1.0 = non-Retina, 2.0 = Retina, 3.0 = Retina 3×).
    let scaleFactor: CGFloat

    /// `true` when this is a mock window (no real backing window).
    /// Safety gate blocks real input into mock windows.
    let isMock: Bool

    // MARK: Init

    init(id: CGWindowID, ownerPID: pid_t, ownerName: String,
         title: String, frame: CGRect, layer: Int,
         isOnScreen: Bool, scaleFactor: CGFloat, isMock: Bool = false) {
        self.id = id
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
        self.frame = frame
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.scaleFactor = scaleFactor
        self.isMock = isMock
    }

    // MARK: Derived

    /// Estimated capture rectangle in screen coordinates.
    /// For Wine/YAAGL the title-bar offset may need per-window tuning.
    var captureRect: CGRect { frame }

    /// Human-readable label for UI pickers and status lines.
    var displayName: String {
        let label = title.isEmpty ? "(untitled)" : title
        return "\(ownerName) — \(label)"
    }

    /// Higher score means this window is a better capture/input target.
    ///
    /// This mirrors BetterGI's `TaskContext.GameHandle` preference: the real game
    /// handle wins over launcher/helper windows, even when the launcher is larger.
    var gameWindowSelectionPriority: Int {
        let lowerTitle = title.lowercased()
        let lowerOwner = ownerName.lowercased()
        let hasLocalizedGameTitle = lowerTitle.contains("原神")
        let hasEnglishGameTitle = lowerTitle.contains("genshin")
            || lowerTitle.contains("yuan shen")
            || lowerTitle.contains("yuanshen")
        let hasImpactTitle = lowerTitle.contains("impact")
        let isWine = lowerOwner.contains("wine")
        let isYaagl = lowerOwner.contains("yaagl")

        if isWine && (hasLocalizedGameTitle || hasEnglishGameTitle) {
            return 100
        }
        if hasLocalizedGameTitle || hasEnglishGameTitle {
            return 90
        }
        if isWine && hasImpactTitle {
            return 80
        }
        if isWine && !title.isEmpty && !lowerTitle.contains("launcher") {
            return 60
        }
        if isYaagl && (hasLocalizedGameTitle || hasEnglishGameTitle || hasImpactTitle) {
            return 30
        }
        return 0
    }

    /// Quick heuristic for Genshin Impact windows.
    var isLikelyGameWindow: Bool {
        gameWindowSelectionPriority > 0
    }
}

// MARK: - Presets

extension WindowInfo {
    /// Sentinel for "no window selected".
    static let none = WindowInfo(
        id: 0, ownerPID: 0, ownerName: "None",
        title: "No game window", frame: .zero,
        layer: 0, isOnScreen: false, scaleFactor: 1.0,
        isMock: true
    )

    /// Mock window for UI development. `id: .max` and `isMock: true`
    /// prevent the safety gate from dispatching real input.
    static func mock(title: String = "YAAGL - Genshin Impact") -> WindowInfo {
        WindowInfo(
            id: .max,
            ownerPID: 99999,
            ownerName: "YAAGL",
            title: title,
            frame: CGRect(x: 0, y: 44, width: 2560, height: 1440 - 44),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 2.0,
            isMock: true
        )
    }
}
