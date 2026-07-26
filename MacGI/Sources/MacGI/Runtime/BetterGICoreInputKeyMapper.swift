import Foundation
import CoreGraphics

/// Translates BetterGI Core's semantic key payloads into macOS input codes.
/// This is a platform adapter only; key/mouse execution semantics remain in C# Core.
enum BetterGICoreInputKeyMapper {
    static func windowsVirtualKey(fromCGKeyCode cgKeyCode: CGKeyCode) -> Int? {
        guard let key = KeyCode.allCases.first(where: { $0.cgKeyCode == cgKeyCode }) else {
            return nil
        }
        return windowsVirtualKey(from: key)
    }

    static func windowsVirtualKey(from key: KeyCode) -> Int? {
        if key.rawValue.count == 1, let scalar = key.rawValue.uppercased().unicodeScalars.first {
            return Int(scalar.value)
        }
        if key.rawValue.hasPrefix("digit"), let digit = Int(key.rawValue.dropFirst(5)) {
            return 0x30 + digit
        }
        if key.rawValue.hasPrefix("f"), let number = Int(key.rawValue.dropFirst()),
           (1...12).contains(number) {
            return 0x6F + number
        }
        return switch key {
        case .backspace: 0x08; case .tab: 0x09; case .return: 0x0D
        case .leftShift: 0xA0; case .leftControl: 0xA2; case .leftOption: 0xA4
        case .capsLock: 0x14; case .escape: 0x1B; case .space: 0x20
        case .pageUp: 0x21; case .pageDown: 0x22; case .end: 0x23; case .home: 0x24
        case .leftArrow: 0x25; case .upArrow: 0x26
        case .rightArrow: 0x27; case .downArrow: 0x28
        case .delete: 0x2E
        case .semicolon: 0xBA; case .equal: 0xBB; case .comma: 0xBC; case .minus: 0xBD
        case .period: 0xBE; case .slash: 0xBF; case .grave: 0xC0
        case .leftBracket: 0xDB; case .backslash: 0xDC
        case .rightBracket: 0xDD; case .apostrophe: 0xDE
        case .rightCommand: nil
        default: nil
        }
    }

    static func keyCode(fromWindowsVirtualKey virtualKey: Int) -> KeyCode? {
        if (0x30...0x39).contains(virtualKey) {
            return KeyCode(rawValue: "digit\(virtualKey - 0x30)")
        }
        if (0x41...0x5A).contains(virtualKey), let scalar = UnicodeScalar(virtualKey) {
            return KeyCode(rawValue: String(Character(scalar)).lowercased())
        }
        if (0x70...0x7B).contains(virtualKey) {
            return KeyCode(rawValue: "f\(virtualKey - 0x6F)")
        }
        return switch virtualKey {
        case 0x08: .backspace; case 0x09: .tab; case 0x0D: .return
        case 0x10, 0xA0, 0xA1: .leftShift
        case 0x11, 0xA2, 0xA3: .leftControl
        case 0x12, 0xA4, 0xA5: .leftOption
        case 0x14: .capsLock; case 0x1B: .escape; case 0x20: .space
        case 0x21: .pageUp; case 0x22: .pageDown; case 0x23: .end; case 0x24: .home
        case 0x25: .leftArrow; case 0x26: .upArrow; case 0x27: .rightArrow; case 0x28: .downArrow
        case 0x2E: .delete
        case 0xBA: .semicolon; case 0xBB: .equal; case 0xBC: .comma; case 0xBD: .minus
        case 0xBE: .period; case 0xBF: .slash; case 0xC0: .grave
        case 0xDB: .leftBracket; case 0xDC: .backslash; case 0xDD: .rightBracket; case 0xDE: .apostrophe
        default: nil
        }
    }

    static func keyCode(from rawKey: String) -> KeyCode? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_").uppercased()
        if key.count == 1, let character = key.first {
            if character >= "A", character <= "Z" { return KeyCode(rawValue: character.lowercased()) }
            if character >= "0", character <= "9" { return KeyCode(rawValue: "digit\(character)") }
        }
        if key.hasPrefix("D"), let digit = Int(key.dropFirst()), (0...9).contains(digit) {
            return KeyCode(rawValue: "digit\(digit)")
        }
        if key.hasPrefix("F"), let number = Int(key.dropFirst()), (1...12).contains(number) {
            return KeyCode(rawValue: "f\(number)")
        }
        return switch key {
        case "VK_ESCAPE", "ESCAPE", "ESC": .escape
        case "VK_RETURN", "RETURN", "ENTER": .return
        case "VK_SPACE", "SPACE": .space
        case "VK_TAB", "TAB": .tab
        case "VK_BACK", "BACKSPACE": .backspace
        case "VK_DELETE", "DELETE", "DEL": .delete
        case "VK_LEFT", "LEFT": .leftArrow
        case "VK_RIGHT", "RIGHT": .rightArrow
        case "VK_UP", "UP": .upArrow
        case "VK_DOWN", "DOWN": .downArrow
        case "VK_SHIFT", "VK_LSHIFT", "SHIFT", "LSHIFT": .leftShift
        case "VK_CONTROL", "VK_LCONTROL", "VK_CTRL", "VK_LCTRL", "CONTROL", "CTRL": .leftControl
        case "VK_MENU", "VK_LMENU", "VK_ALT", "ALT": .leftOption
        case "VK_OEM_COMMA", "COMMA", ",": .comma
        case "VK_OEM_MINUS", "OEMMINUS", "MINUS", "-": .minus
        case "VK_OEM_PLUS", "OEMPLUS", "EQUAL", "=": .equal
        case "VK_OEM_PERIOD", "OEMPERIOD", "PERIOD", ".": .period
        case "VK_OEM_2", "OEMQUESTION", "SLASH", "/": .slash
        case "VK_OEM_5", "OEMPIPE", "BACKSLASH", "\\": .backslash
        case "VK_OEM_1", "OEMSEMICOLON", "SEMICOLON", ";": .semicolon
        case "VK_OEM_4", "OEMOPENBRACKETS", "LBRACKET", "[": .leftBracket
        case "VK_OEM_6", "OEMCLOSEBRACKETS", "RBRACKET", "]": .rightBracket
        case "OEMQUOTES", "APOSTROPHE", "'": .apostrophe
        case "VK_OEM_3", "OEMTILDE", "GRAVE", "TILDE", "`": .grave
        default: key.hasPrefix("VK_") ? keyCode(from: String(key.dropFirst(3))) : nil
        }
    }

    static func mouseButton(from rawKey: String) -> CGMouseButton? {
        switch rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "LEFT", "LEFTBUTTON", "MOUSELEFT": .left
        case "RIGHT", "RIGHTBUTTON", "MOUSERIGHT": .right
        case "MIDDLE", "MIDDLEBUTTON", "MOUSEMIDDLE": .center
        case "XBUTTON1", "MOUSE4": CGMouseButton(rawValue: 3)
        case "XBUTTON2", "MOUSE5": CGMouseButton(rawValue: 4)
        default: nil
        }
    }
}
