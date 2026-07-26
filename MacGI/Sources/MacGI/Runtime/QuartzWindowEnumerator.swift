import AppKit
import CoreGraphics
import Foundation

/// macOS counterpart to BetterGI's `TaskContext.GameHandle` discovery path.
///
/// Windows BetterGI stores an HWND and derives process / bounds from it. The
/// macOS port uses `CGWindowID` as the stable capture handle, with PID and frame
/// carried alongside it for Accessibility, ScreenCaptureKit, and HUD following.
enum QuartzWindowEnumerator {
    static func enumerateApplicationWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        return rawWindows
            .compactMap(WindowInfo.fromQuartzWindowInfo)
            .filter { window in
                window.ownerPID != currentPID
                && window.layer == 0
                && window.isOnScreen
                && window.frame.width >= 80
                && window.frame.height >= 60
            }
            .sorted(by: sortForGameSelection)
    }

    static func bestGameWindow(from windows: [WindowInfo]) -> WindowInfo? {
        let rankedWindows = windows.sorted(by: sortForGameSelection)
        return rankedWindows.first(where: \.isLikelyGameWindow)
    }

    private static func sortForGameSelection(_ lhs: WindowInfo, _ rhs: WindowInfo) -> Bool {
        let lhsPriority = lhs.gameWindowSelectionPriority
        let rhsPriority = rhs.gameWindowSelectionPriority
        if lhsPriority != rhsPriority {
            return lhsPriority > rhsPriority
        }
        let lhsArea = lhs.frame.width * lhs.frame.height
        let rhsArea = rhs.frame.width * rhs.frame.height
        if lhsArea != rhsArea {
            return lhsArea > rhsArea
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}

private extension WindowInfo {
    static func fromQuartzWindowInfo(_ info: [String: Any]) -> WindowInfo? {
        guard
            let windowNumber = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
            let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
            let bounds = info[kCGWindowBounds as String] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else {
            return nil
        }

        let ownerName = info[kCGWindowOwnerName as String] as? String ?? "Unknown"
        let title = info[kCGWindowName as String] as? String ?? ""
        let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false

        return WindowInfo(
            id: windowNumber,
            ownerPID: pid_t(ownerPID),
            ownerName: ownerName,
            title: title,
            frame: frame,
            layer: layer,
            isOnScreen: isOnScreen,
            scaleFactor: backingScaleFactor(for: frame),
            isSynthetic: false
        )
    }

    static func backingScaleFactor(for frame: CGRect) -> CGFloat {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let matchingScreen = NSScreen.screens.first { screen in
            screen.frame.contains(center) || screen.frame.intersects(frame)
        }
        return matchingScreen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
    }
}
