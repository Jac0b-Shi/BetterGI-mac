import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

enum CGEventInputDispatchError: LocalizedError, Equatable {
    case accessibilityPermissionMissing
    case syntheticWindow
    case invalidClickTarget
    case unsupportedKey(KeyCode)
    case unsupportedMouseButton(InputMouseButton)
    case eventCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "Accessibility permission is required before posting CGEvent input"
        case .syntheticWindow:
            "CGEvent input cannot target a synthetic window sentinel"
        case .invalidClickTarget:
            "Unable to resolve a valid click target"
        case let .unsupportedKey(key):
            "No macOS CGKeyCode mapping for \(key.displayName)"
        case let .unsupportedMouseButton(button):
            "No CGEvent mouse mapping for \(button.displayName)"
        case let .eventCreationFailed(name):
            "Failed to create CGEvent for \(name)"
        }
    }
}

struct CGEventDispatchReport: Equatable {
    let eventCount: Int
    let detail: String
}

/// macOS counterpart to BetterGI's `InputSimulator` + `WindowsInputMessageDispatcher`.
///
/// Upstream builds a `User32.INPUT[]` sequence, then calls `SendInput` once. CoreGraphics does
/// not expose the same batch API, so this dispatcher keeps the same typed action boundary and
/// posts the equivalent CGEvents in order.
final class CGEventInputDispatcher {
    private let tap: CGEventTapLocation = .cghidEventTap
    private let clickDelayUsec: useconds_t = 50_000

    func perform(_ action: InputAction, targetWindow: WindowInfo) throws -> CGEventDispatchReport {
        guard !targetWindow.isSynthetic else {
            throw CGEventInputDispatchError.syntheticWindow
        }
        guard AXIsProcessTrusted() else {
            throw CGEventInputDispatchError.accessibilityPermissionMissing
        }

        switch action {
        case let .keyDown(key, modifiers):
            let event = try makeKeyboardEvent(key: key, keyDown: true, modifiers: modifiers)
            event.post(tap: tap)
            return CGEventDispatchReport(eventCount: 1, detail: "keyDown \(key.displayName)")

        case let .keyUp(key, modifiers):
            let event = try makeKeyboardEvent(key: key, keyDown: false, modifiers: modifiers)
            event.post(tap: tap)
            return CGEventDispatchReport(eventCount: 1, detail: "keyUp \(key.displayName)")

        case let .keyPress(key, modifiers):
            let events = [
                try makeKeyboardEvent(key: key, keyDown: true, modifiers: modifiers),
                try makeKeyboardEvent(key: key, keyDown: false, modifiers: modifiers)
            ]
            events.forEach { $0.post(tap: tap) }
            return CGEventDispatchReport(eventCount: events.count, detail: "keyPress \(key.displayName)")

        case let .keyHold(key, durationMs, modifiers):
            let down = try makeKeyboardEvent(key: key, keyDown: true, modifiers: modifiers)
            let up = try makeKeyboardEvent(key: key, keyDown: false, modifiers: modifiers)
            down.post(tap: tap)
            usleep(useconds_t(max(0, min(durationMs, 10_000)) * 1000))
            up.post(tap: tap)
            return CGEventDispatchReport(
                eventCount: 2,
                detail: "keyHold \(key.displayName) \(max(0, durationMs))ms"
            )

        case let .mouseMove(point):
            let event = try makeMouseEvent(type: .mouseMoved, at: point, button: .left)
            event.post(tap: tap)
            return CGEventDispatchReport(eventCount: 1, detail: "mouseMove")

        case let .mouseButtonDown(button, point):
            let destination = try clickPoint(point, targetWindow: targetWindow)
            let event = try makeMouseEvent(type: button.downEventType, at: destination, button: button.cgMouseButton)
            event.post(tap: tap)
            return CGEventDispatchReport(eventCount: 1, detail: "\(button.displayName) down")

        case let .mouseButtonUp(button, point):
            let destination = try clickPoint(point, targetWindow: targetWindow)
            let event = try makeMouseEvent(type: button.upEventType, at: destination, button: button.cgMouseButton)
            event.post(tap: tap)
            return CGEventDispatchReport(eventCount: 1, detail: "\(button.displayName) up")

        case let .mouseClick(button, point):
            let destination = try clickPoint(point, targetWindow: targetWindow)
            let events = [
                try makeMouseEvent(type: .mouseMoved, at: destination, button: button.cgMouseButton),
                try makeMouseEvent(type: button.downEventType, at: destination, button: button.cgMouseButton),
                try makeMouseEvent(type: button.upEventType, at: destination, button: button.cgMouseButton)
            ]
            events[0].post(tap: tap)
            events[1].post(tap: tap)
            usleep(clickDelayUsec)
            events[2].post(tap: tap)
            return CGEventDispatchReport(eventCount: events.count, detail: "\(button.displayName) click")

        case let .mouseButtonHold(button, durationMs, point):
            let destination = try clickPoint(point, targetWindow: targetWindow)
            let down = try makeMouseEvent(type: button.downEventType, at: destination, button: button.cgMouseButton)
            let up = try makeMouseEvent(type: button.upEventType, at: destination, button: button.cgMouseButton)
            down.post(tap: tap)
            usleep(useconds_t(max(0, min(durationMs, 10_000)) * 1000))
            up.post(tap: tap)
            return CGEventDispatchReport(
                eventCount: 2,
                detail: "\(button.displayName) hold \(max(0, durationMs))ms"
            )

        case let .verticalScroll(clicks):
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: Int32(clicks),
                wheel2: 0,
                wheel3: 0
            ) else {
                throw CGEventInputDispatchError.eventCreationFailed("verticalScroll \(clicks)")
            }
            event.post(tap: tap)
            return CGEventDispatchReport(eventCount: 1, detail: "verticalScroll \(clicks)")

        case let .leftClick(point):
            let destination = try clickPoint(point, targetWindow: targetWindow)
            let events = [
                try makeMouseEvent(type: .mouseMoved, at: destination, button: .left),
                try makeMouseEvent(type: .leftMouseDown, at: destination, button: .left),
                try makeMouseEvent(type: .leftMouseUp, at: destination, button: .left)
            ]
            events[0].post(tap: tap)
            events[1].post(tap: tap)
            usleep(clickDelayUsec)
            events[2].post(tap: tap)
            return CGEventDispatchReport(eventCount: events.count, detail: "leftClick")

        case .releaseAll:
            return try releaseAll(targetWindow: targetWindow)
        }
    }

    private func makeKeyboardEvent(key: KeyCode, keyDown: Bool, modifiers: ModifierFlags) throws -> CGEvent {
        guard let keyCode = key.cgKeyCode else {
            throw CGEventInputDispatchError.unsupportedKey(key)
        }
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: keyDown
        ) else {
            throw CGEventInputDispatchError.eventCreationFailed("\(key.displayName) \(keyDown ? "down" : "up")")
        }
        event.flags = modifiers.cgEventFlags
        return event
    }

    private func makeMouseEvent(type: CGEventType, at point: CGPoint, button: CGMouseButton) throws -> CGEvent {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else {
            throw CGEventInputDispatchError.eventCreationFailed("\(type.rawValue)")
        }
        return event
    }

    private func clickPoint(_ point: CGPoint?, targetWindow: WindowInfo) throws -> CGPoint {
        if let point {
            return point
        }
        guard !targetWindow.frame.isEmpty else {
            throw CGEventInputDispatchError.invalidClickTarget
        }
        return CGPoint(x: targetWindow.frame.midX, y: targetWindow.frame.midY)
    }

    private func releaseAll(targetWindow: WindowInfo) throws -> CGEventDispatchReport {
        let mousePoint = CGEvent(source: nil)?.location
            ?? CGPoint(x: targetWindow.frame.midX, y: targetWindow.frame.midY)
        var count = 0

        for key in KeyCode.allCases {
            guard let keyCode = key.cgKeyCode,
                  let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            else {
                continue
            }
            event.post(tap: tap)
            count += 1
        }

        let mouseUps: [(CGEventType, CGMouseButton)] = [
            (.leftMouseUp, .left),
            (.rightMouseUp, .right),
            (.otherMouseUp, .center)
        ]
        for mouseUp in mouseUps {
            let event = try makeMouseEvent(type: mouseUp.0, at: mousePoint, button: mouseUp.1)
            event.post(tap: tap)
            count += 1
        }

        return CGEventDispatchReport(eventCount: count, detail: "releaseAll")
    }
}

private extension ModifierFlags {
    var cgEventFlags: CGEventFlags {
        var flags = CGEventFlags()
        if contains(.shift) {
            flags.insert(.maskShift)
        }
        if contains(.control) {
            flags.insert(.maskControl)
        }
        if contains(.option) {
            flags.insert(.maskAlternate)
        }
        if contains(.command) {
            flags.insert(.maskCommand)
        }
        return flags
    }
}

private extension InputMouseButton {
    var cgMouseButton: CGMouseButton {
        switch self {
        case .left: .left
        case .right: .right
        case .middle: .center
        }
    }

    var downEventType: CGEventType {
        switch self {
        case .left: .leftMouseDown
        case .right: .rightMouseDown
        case .middle: .otherMouseDown
        }
    }

    var upEventType: CGEventType {
        switch self {
        case .left: .leftMouseUp
        case .right: .rightMouseUp
        case .middle: .otherMouseUp
        }
    }
}

extension KeyCode {
    var cgKeyCode: CGKeyCode? {
        switch self {
        case .a: 0
        case .s: 1
        case .d: 2
        case .f: 3
        case .h: 4
        case .g: 5
        case .z: 6
        case .x: 7
        case .c: 8
        case .v: 9
        case .b: 11
        case .q: 12
        case .w: 13
        case .e: 14
        case .r: 15
        case .y: 16
        case .t: 17
        case .digit1: 18
        case .digit2: 19
        case .digit3: 20
        case .digit4: 21
        case .digit6: 22
        case .digit5: 23
        case .equal: 24
        case .digit9: 25
        case .digit7: 26
        case .minus: 27
        case .digit8: 28
        case .digit0: 29
        case .rightBracket: 30
        case .o: 31
        case .u: 32
        case .leftBracket: 33
        case .i: 34
        case .p: 35
        case .return: 36
        case .l: 37
        case .j: 38
        case .apostrophe: 39
        case .k: 40
        case .semicolon: 41
        case .backslash: 42
        case .comma: 43
        case .slash: 44
        case .n: 45
        case .m: 46
        case .period: 47
        case .tab: 48
        case .space: 49
        case .grave: 50
        case .backspace: 51
        case .escape: 53
        case .rightCommand: 54
        case .leftShift: 56
        case .capsLock: 57
        case .leftOption: 58
        case .leftControl: 59
        case .f9: 101
        case .f11: 103
        case .f10: 109
        case .f12: 111
        case .home: 115
        case .pageUp: 116
        case .delete: 117
        case .end: 119
        case .f1: 122
        case .f2: 120
        case .pageDown: 121
        case .f3: 99
        case .f4: 118
        case .f5: 96
        case .f6: 97
        case .f7: 98
        case .f8: 100
        case .leftArrow: 123
        case .rightArrow: 124
        case .downArrow: 125
        case .upArrow: 126
        }
    }
}
