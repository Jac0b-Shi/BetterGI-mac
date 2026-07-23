import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct MacHotKeySignature: Equatable, Sendable {
    let key: KeyCode?
    let mouseButton: CGMouseButton?
    let modifiers: ModifierFlags

    static func parse(_ value: String) -> MacHotKeySignature? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "< None >" else { return nil }
        if trimmed == "XButton1" {
            return .init(
                key: nil, mouseButton: CGMouseButton(rawValue: 3), modifiers: [])
        }
        if trimmed == "XButton2" {
            return .init(
                key: nil, mouseButton: CGMouseButton(rawValue: 4), modifiers: [])
        }

        var modifiers: ModifierFlags = []
        var key: KeyCode?
        for part in trimmed.split(separator: "+") {
            let component = part.trimmingCharacters(in: .whitespaces)
            switch component {
            case "Ctrl": modifiers.insert(.control)
            case "Shift": modifiers.insert(.shift)
            case "Alt": modifiers.insert(.option)
            case "Win": modifiers.insert(.command)
            default: key = KeyCode(upstreamHotKeyName: component)
            }
        }
        guard let key else { return nil }
        return .init(key: key, mouseButton: nil, modifiers: modifiers)
    }

    static func from(type: CGEventType, event: CGEvent) -> MacHotKeySignature? {
        if type == .otherMouseDown || type == .otherMouseUp {
            guard let button = CGMouseButton(
                rawValue: UInt32(event.getIntegerValueField(.mouseEventButtonNumber)))
            else {
                return nil
            }
            guard button.rawValue == 3 || button.rawValue == 4 else { return nil }
            return .init(key: nil, mouseButton: button, modifiers: [])
        }
        guard type == .keyDown || type == .keyUp else { return nil }
        let cgKeyCode = CGKeyCode(
            event.getIntegerValueField(.keyboardEventKeycode))
        guard let key = KeyCode.allCases.first(where: { $0.cgKeyCode == cgKeyCode })
        else {
            return nil
        }
        var modifiers: ModifierFlags = []
        if event.flags.contains(.maskShift) { modifiers.insert(.shift) }
        if event.flags.contains(.maskControl) { modifiers.insert(.control) }
        if event.flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if event.flags.contains(.maskCommand) { modifiers.insert(.command) }
        return .init(key: key, mouseButton: nil, modifiers: modifiers)
    }

    var upstreamValue: String {
        if mouseButton?.rawValue == 3 { return "XButton1" }
        if mouseButton?.rawValue == 4 { return "XButton2" }
        guard let key else { return "" }
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.option) { parts.append("Alt") }
        if modifiers.contains(.command) { parts.append("Win") }
        parts.append(key.upstreamHotKeyName)
        return parts.joined(separator: " + ")
    }

    func validationMessage(for hotKeyType: String) -> String? {
        if mouseButton != nil {
            return hotKeyType == "KeyboardMonitor"
                ? nil
                : "鼠标侧键只能使用键鼠监听。"
        }
        guard let key else { return "未识别按键。" }
        if [.leftShift, .leftControl, .leftOption, .rightCommand].contains(key) {
            return "不能单独使用修饰键。"
        }
        if hotKeyType == "KeyboardMonitor" {
            return modifiers.isEmpty ? nil : "键鼠监听不支持组合键。"
        }
        guard hotKeyType == "GlobalRegister" else {
            return "未知快捷键类型。"
        }
        if [.return, .space, .tab].contains(key), modifiers.isEmpty {
            return "全局热键不能使用未修饰的 Return、Space 或 Tab。"
        }
        if key.isCharacterKey,
           modifiers.isEmpty || modifiers == [.shift] {
            return "全局热键的字符键必须包含 Control、Option 或 Command。"
        }
        return nil
    }
}

final class MacHotKeyMonitor {
    private struct RegisteredBinding {
        let binding: BetterGIHotKeyBinding
        let signature: MacHotKeySignature
    }

    private let handler: (BetterGIHotKeyBinding) -> Void
    private let captureHandler: (String, String?, String?) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var bindings: [RegisteredBinding] = []
    private var targetProcessID: pid_t = 0
    private var runtimeActive = false
    private var capture: (id: String, hotKeyType: String)?

    init(
        handler: @escaping (BetterGIHotKeyBinding) -> Void,
        captureHandler: @escaping (String, String?, String?) -> Void
    ) {
        self.handler = handler
        self.captureHandler = captureHandler
    }

    func update(
        bindings: [BetterGIHotKeyBinding],
        targetProcessID: pid_t?,
        runtimeActive: Bool
    ) throws {
        self.bindings = bindings.compactMap { binding in
            guard let signature = MacHotKeySignature.parse(binding.hotKey) else {
                return nil
            }
            return RegisteredBinding(binding: binding, signature: signature)
        }
        self.targetProcessID = targetProcessID ?? 0
        self.runtimeActive = runtimeActive
        if self.bindings.isEmpty, capture == nil {
            stop()
        } else {
            try startIfNeeded()
        }
    }

    func beginCapture(id: String, hotKeyType: String) throws {
        capture = (id, hotKeyType)
        try startIfNeeded()
    }

    func cancelCapture() {
        capture = nil
        if bindings.isEmpty {
            stop()
        }
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        capture = nil
    }

    fileprivate func receive(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }
        guard event.getIntegerValueField(.eventSourceUserData) !=
                BetterGIInputEventMarker.value,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              let signature = MacHotKeySignature.from(type: type, event: event)
        else {
            return
        }

        if let capture {
            if signature.modifiers.isEmpty,
               let key = signature.key,
               [.delete, .backspace, .escape].contains(key) {
                self.capture = nil
                captureHandler(capture.id, "", nil)
                return
            }
            if let message = signature.validationMessage(
                for: capture.hotKeyType) {
                captureHandler(capture.id, nil, message)
                return
            }
            self.capture = nil
            captureHandler(capture.id, signature.upstreamValue, nil)
            return
        }

        guard let registered = bindings.first(where: {
            $0.signature == signature && $0.binding.dispatchOnPress
        }) else {
            return
        }
        if registered.binding.hotKeyType == "KeyboardMonitor" {
            guard runtimeActive,
                  targetProcessID > 0,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                    targetProcessID
            else {
                return
            }
        }
        handler(registered.binding)
    }

    private func startIfNeeded() throws {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
            throw MacKeyMouseRecordingError.accessibilityPermissionMissing
        }
        let mask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: macHotKeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw MacKeyMouseRecordingError.eventTapCreationFailed
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

private func macHotKeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<MacHotKeyMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    monitor.receive(type: type, event: event)
    return Unmanaged.passUnretained(event)
}

private extension KeyCode {
    init?(upstreamHotKeyName value: String) {
        if value.count == 1, let character = value.first {
            if character.isLetter {
                self.init(rawValue: String(character).lowercased())
                return
            }
        }
        if value.hasPrefix("D"), let digit = Int(value.dropFirst()),
           (0...9).contains(digit) {
            self.init(rawValue: "digit\(digit)")
            return
        }
        if value.hasPrefix("F"), let number = Int(value.dropFirst()),
           (1...12).contains(number) {
            self.init(rawValue: "f\(number)")
            return
        }
        let key: KeyCode? = switch value {
        case "Escape": .escape
        case "Return", "Enter": .return
        case "Tab": .tab
        case "Space": .space
        case "Back", "Backspace": .backspace
        case "Delete": .delete
        case "Left": .leftArrow
        case "Right": .rightArrow
        case "Up": .upArrow
        case "Down": .downArrow
        case "Home": .home
        case "End": .end
        case "PageUp": .pageUp
        case "PageDown": .pageDown
        case "OemComma": .comma
        case "OemMinus": .minus
        case "OemPlus": .equal
        case "OemPeriod": .period
        case "OemQuestion": .slash
        case "OemPipe": .backslash
        case "OemSemicolon": .semicolon
        case "OemOpenBrackets": .leftBracket
        case "OemCloseBrackets": .rightBracket
        case "OemQuotes": .apostrophe
        case "OemTilde": .grave
        default: nil
        }
        guard let key else { return nil }
        self = key
    }

    var upstreamHotKeyName: String {
        if rawValue.count == 1 { return rawValue.uppercased() }
        if rawValue.hasPrefix("digit") { return "D\(rawValue.dropFirst(5))" }
        if rawValue.hasPrefix("f") { return rawValue.uppercased() }
        return switch self {
        case .escape: "Escape"
        case .return: "Return"
        case .tab: "Tab"
        case .space: "Space"
        case .backspace: "Back"
        case .delete: "Delete"
        case .leftArrow: "Left"
        case .rightArrow: "Right"
        case .upArrow: "Up"
        case .downArrow: "Down"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "PageUp"
        case .pageDown: "PageDown"
        case .comma: "OemComma"
        case .minus: "OemMinus"
        case .equal: "OemPlus"
        case .period: "OemPeriod"
        case .slash: "OemQuestion"
        case .backslash: "OemPipe"
        case .semicolon: "OemSemicolon"
        case .leftBracket: "OemOpenBrackets"
        case .rightBracket: "OemCloseBrackets"
        case .apostrophe: "OemQuotes"
        case .grave: "OemTilde"
        default: displayName
        }
    }

    var isCharacterKey: Bool {
        rawValue.count == 1
            || rawValue.hasPrefix("digit")
            || [
                .apostrophe, .comma, .minus, .equal, .period, .slash,
                .backslash, .semicolon, .leftBracket, .rightBracket, .grave,
            ].contains(self)
    }
}
