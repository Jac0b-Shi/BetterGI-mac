import CoreGraphics
import Foundation

// Platform input DTOs used by the Core input.dispatch callback.

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

/// Typed platform input action sent by the C# Core callback.
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
