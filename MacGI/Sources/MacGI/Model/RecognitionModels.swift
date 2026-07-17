import CoreGraphics
import Foundation

// MARK: - NormalizedROI

/// A rectangular region of interest defined in [0, 1] space relative to a frame.
///
/// Example (auto-dialog bottom text):
/// ```
/// NormalizedROI(id: "dialog_bottom", x: 0.15, y: 0.68, w: 0.70, h: 0.25)
/// ```
///
/// Convert to pixel rect at capture time:
/// ```
/// let px = rect * frame.width, let py = rect * frame.height ...
/// ```
///
/// Equivalent to upstream `RecognitionObject.RegionOfInterest` (no template/OCR logic here).
struct NormalizedROI: Identifiable, Equatable, Codable {

    /// Stable identifier for this ROI (e.g. "dialog_bottom", "pickup_right").
    let id: String

    /// Human-readable label.
    let label: String

    /// Normalized origin X (0…1).
    let x: Double

    /// Normalized origin Y (0…1).
    let y: Double

    /// Normalized width (0…1).
    let w: Double

    /// Normalized height (0…1).
    let h: Double

    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    /// Pixel rect for a given frame size (raw, may be out of bounds).
    func pixelRect(for frame: CapturedFrame) -> CGRect {
        CGRect(
            x: x * Double(frame.width),
            y: y * Double(frame.height),
            width: w * Double(frame.width),
            height: h * Double(frame.height)
        )
    }

    /// Pixel rect clamped to frame bounds and rounded to integral pixels.
    /// Use this for cropping to avoid out-of-bounds failures.
    func clampedPixelRect(for frame: CapturedFrame) -> CGRect {
        let raw = pixelRect(for: frame)
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(frame.width), height: CGFloat(frame.height))
        return raw.intersection(bounds).integral
    }
}

// MARK: - OCRResult

/// Result of an OCR operation on a frame/ROI.
struct OCRResult: Identifiable, Equatable {

    /// Individual text region.
    struct Region: Identifiable, Equatable {
        /// Bounding box in frame pixel coordinates.
        let boundingBox: CGRect
        /// Recognized text.
        let text: String
        /// Confidence score (0…1).
        let confidence: Float

        var id: String { "\(boundingBox)" }
    }

    /// All detected text regions.
    let regions: [Region]

    /// Source ROI that produced this result (nil if full-frame).
    let sourceROI: NormalizedROI?

    /// Frame index that was processed.
    let frameIndex: UInt64

    /// Wall-clock time of the OCR pass.
    let timestamp: Date

    var id: String { "\(frameIndex)-\(timestamp.timeIntervalSince1970)" }

    /// All text joined in reading order (top-to-bottom, left-to-right).
    var combinedText: String {
        regions
            .sorted { a, b in
                if abs(a.boundingBox.midY - b.boundingBox.midY) < 8 {
                    return a.boundingBox.midX < b.boundingBox.midX
                }
                return a.boundingBox.midY < b.boundingBox.midY
            }
            .map(\.text)
            .joined(separator: "\n")
    }

    /// Check whether any region contains the given substring (case-insensitive, diacritic-insensitive).
    func contains(_ text: String) -> Bool {
        regions.contains { $0.text.localizedCaseInsensitiveContains(text) }
    }

    /// Check whether any region matches the regex.
    func containsRegex(_ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regions.contains { region in
            let range = NSRange(region.text.startIndex..., in: region.text)
            return regex.firstMatch(in: region.text, range: range) != nil
        }
    }
}

// MARK: - InputMouseButton

enum InputMouseButton: Equatable, Sendable {
    case left
    case right
    case middle

    var displayName: String {
        switch self {
        case .left: "LMB"
        case .right: "RMB"
        case .middle: "MMB"
        }
    }
}

// MARK: - InputAction

/// Typed input action — replaces the `String` action name in mock InputService.
enum InputAction: Equatable, Sendable {

    /// Key press (down + up).
    case keyPress(key: KeyCode, modifiers: ModifierFlags = [])

    /// Key down only (no auto-release).
    case keyDown(key: KeyCode, modifiers: ModifierFlags = [])

    /// Key up only.
    case keyUp(key: KeyCode, modifiers: ModifierFlags = [])

    /// Key press + hold for a duration, then release.
    case keyHold(key: KeyCode, durationMs: Int, modifiers: ModifierFlags = [])

    /// Mouse move to absolute screen coordinates.
    case mouseMove(to: CGPoint)

    /// Mouse button down.
    case mouseButtonDown(button: InputMouseButton, at: CGPoint? = nil)

    /// Mouse button up.
    case mouseButtonUp(button: InputMouseButton, at: CGPoint? = nil)

    /// Mouse click (move + down + up).
    case mouseClick(button: InputMouseButton = .left, at: CGPoint? = nil)

    /// Mouse button hold.
    case mouseButtonHold(button: InputMouseButton, durationMs: Int, at: CGPoint? = nil)

    /// Vertical scroll wheel clicks. Positive values scroll up, negative down.
    case verticalScroll(clicks: Int)

    /// Left click at absolute screen coordinates.
    case leftClick(at: CGPoint? = nil)

    /// Release all currently-held keys (panic/safety).
    case releaseAll

    /// Convenience display name.
    var displayName: String {
        switch self {
        case let .keyPress(key, mods):
            return "\(mods.displayPrefix)\(key.displayName)"
        case let .keyDown(key, mods):
            return "\(mods.displayPrefix)\(key.displayName)↓"
        case let .keyUp(key, mods):
            return "\(mods.displayPrefix)\(key.displayName)↑"
        case let .keyHold(key, dur, mods):
            return "\(mods.displayPrefix)\(key.displayName) Hold \(dur)ms"
        case let .mouseMove(to):
            return "Mouse → (\(Int(to.x)), \(Int(to.y)))"
        case let .mouseButtonDown(btn, at):
            return at.map { "\(btn.displayName)↓ (\(Int($0.x)),\(Int($0.y)))" } ?? "\(btn.displayName)↓"
        case let .mouseButtonUp(btn, at):
            return at.map { "\(btn.displayName)↑ (\(Int($0.x)),\(Int($0.y)))" } ?? "\(btn.displayName)↑"
        case let .mouseClick(btn, at):
            return at.map { "\(btn.displayName) (\(Int($0.x)),\(Int($0.y)))" } ?? "\(btn.displayName)"
        case let .mouseButtonHold(btn, dur, at):
            let base = at.map { "\(btn.displayName) (\(Int($0.x)),\(Int($0.y)))" } ?? "\(btn.displayName)"
            return "\(base) Hold \(dur)ms"
        case let .verticalScroll(clicks):
            return "Scroll \(clicks)"
        case let .leftClick(at):
            if let pt = at { return "Click (\(Int(pt.x)), \(Int(pt.y)))" }
            return "Click Center"
        case .releaseAll:
            return "Release All"
        }
    }
}

// MARK: - KeyCode

/// Platform-independent key identifiers.
/// Real CGEvent dispatch maps these to `CGKeyCode` via a lookup table.
enum KeyCode: String, Equatable, Sendable, CaseIterable {
    // Letters
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z

    // Digits
    case digit0, digit1, digit2, digit3, digit4, digit5, digit6, digit7, digit8, digit9

    // Function keys
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    // Navigation
    case leftArrow, rightArrow, upArrow, downArrow
    case home, end, pageUp, pageDown

    // Editing
    case delete, backspace
    case escape, `return`, tab, capsLock, space

    // Modifiers
    case leftShift, leftControl, leftOption, rightCommand

    // Punctuation
    case apostrophe, comma, minus, equal, period
    case slash, backslash, semicolon
    case leftBracket, rightBracket
    case grave

    var displayName: String {
        switch self {
        // Letters
        case .a: "A"; case .b: "B"; case .c: "C"; case .d: "D"
        case .e: "E"; case .f: "F"; case .g: "G"; case .h: "H"
        case .i: "I"; case .j: "J"; case .k: "K"; case .l: "L"
        case .m: "M"; case .n: "N"; case .o: "O"; case .p: "P"
        case .q: "Q"; case .r: "R"; case .s: "S"; case .t: "T"
        case .u: "U"; case .v: "V"; case .w: "W"; case .x: "X"
        case .y: "Y"; case .z: "Z"
        // Digits
        case .digit0: "0"; case .digit1: "1"; case .digit2: "2"
        case .digit3: "3"; case .digit4: "4"; case .digit5: "5"
        case .digit6: "6"; case .digit7: "7"; case .digit8: "8"
        case .digit9: "9"
        // Function keys
        case .f1: "F1"; case .f2: "F2"; case .f3: "F3"
        case .f4: "F4"; case .f5: "F5"; case .f6: "F6"
        case .f7: "F7"; case .f8: "F8"; case .f9: "F9"
        case .f10: "F10"; case .f11: "F11"; case .f12: "F12"
        // Navigation
        case .leftArrow: "←"; case .rightArrow: "→"
        case .upArrow: "↑"; case .downArrow: "↓"
        case .home: "Home"; case .end: "End"
        case .pageUp: "PgUp"; case .pageDown: "PgDn"
        // Editing
        case .delete: "Del"; case .backspace: "⌫"
        case .escape: "ESC"; case .return: "Return"
        case .tab: "Tab"; case .capsLock: "CapsLock"
        case .space: "Space"
        // Modifiers
        case .leftShift: "⇧"; case .leftControl: "⌃"
        case .leftOption: "⌥"; case .rightCommand: "⌘"
        // Punctuation
        case .apostrophe: "'"; case .comma: ","
        case .minus: "-"; case .equal: "="
        case .period: "."; case .slash: "/"
        case .backslash: "\\"; case .semicolon: ";"
        case .leftBracket: "["; case .rightBracket: "]"
        case .grave: "`"
        }
    }
}

// MARK: - ModifierFlags

struct ModifierFlags: OptionSet, Equatable, Sendable {
    let rawValue: UInt
    static let shift   = ModifierFlags(rawValue: 1 << 0)
    static let control = ModifierFlags(rawValue: 1 << 1)
    static let option  = ModifierFlags(rawValue: 1 << 2)
    static let command = ModifierFlags(rawValue: 1 << 3)

    var displayPrefix: String {
        var parts: [String] = []
        if contains(.shift)   { parts.append("⇧") }
        if contains(.control) { parts.append("⌃") }
        if contains(.option)  { parts.append("⌥") }
        if contains(.command) { parts.append("⌘") }
        return parts.isEmpty ? "" : parts.joined() + " "
    }
}

// MARK: - Predefined ROIs

extension NormalizedROI {
    /// Auto-dialog: bottom third, roughly center.
    static let dialogBottom = NormalizedROI(
        id: "dialog_bottom", label: "剧情文本",
        x: 0.15, y: 0.68, w: 0.70, h: 0.25
    )

    /// Auto-pickup: center-right interaction hint area.
    static let pickupRight = NormalizedROI(
        id: "pickup_right", label: "交互提示",
        x: 0.55, y: 0.45, w: 0.40, h: 0.20
    )

    /// Dialog option selection (1–3 choices, bottom-center).
    static let dialogOptions = NormalizedROI(
        id: "dialog_options", label: "对话选项",
        x: 0.20, y: 0.58, w: 0.60, h: 0.35
    )

    /// Top-center notification / quest log area.
    static let topNotification = NormalizedROI(
        id: "top_notification", label: "顶部通知",
        x: 0.20, y: 0.02, w: 0.60, h: 0.12
    )

    /// UID detection area (bottom-right).
    static let uidRegion = NormalizedROI(
        id: "uid", label: "UID",
        x: 0.78, y: 0.94, w: 0.20, h: 0.05
    )
}
