import CoreGraphics
import Foundation

/// Sends upstream ClientCore packets in the hosted page, without global CGEvents.
final class CloudWebInputDispatcher: InputDispatching, Sendable {
    let deliveryMode = InputDeliveryMode.webSdk
    // Keep the first release foreground-gated until real background playback is verified.
    let capabilities = InputDeliveryCapabilities.foregroundOnly
    private let bridge: WKWebInputBridge
    private let windowID: CGWindowID

    init(bridge: WKWebInputBridge, windowID: CGWindowID) {
        self.bridge = bridge; self.windowID = windowID
    }

    func perform(_ action: InputAction, targetWindow: WindowInfo) throws -> CGEventDispatchReport {
        guard targetWindow.id == windowID, !targetWindow.isSynthetic else { throw CloudWebInputError.unavailable }
        if Thread.isMainThread, action == .releaseAll {
            MainActor.assumeIsolated { bridge.suspend() }
            return CGEventDispatchReport(eventCount: 0, detail: "Web SDK session suspended; owned release requested")
        }
        let commands = try Self.commands(for: action, viewport: targetWindow.captureRect)
        let hold: Int
        switch action {
        case .keyHold(_, let duration, _), .mouseButtonHold(_, let duration, _): hold = duration
        default: hold = 0
        }
        _ = try bridge.execute(commands, timeout: Double(max(0, hold)) / 1000 + 8)
        return CGEventDispatchReport(eventCount: commands.filter { $0["method"] as? String != "wait" }.count,
                                     detail: "Web SDK: \(action.displayName)")
    }

    func query(_ query: InputQuery, targetWindow: WindowInfo) throws -> Bool {
        guard targetWindow.id == windowID, !targetWindow.isSynthetic else { throw CloudWebInputError.unavailable }
        let status = try bridge.execute([])
        // ClientCore's injected set omits real keyboard/mouse events. Existing passive
        // triggers (e.g. SkillCd) need both, but physical state is scoped to this key window.
        let frontmost = DispatchQueue.main.sync {
            MainActor.assumeIsolated { ForegroundWindowGuard.isTargetFrontmost(targetWindow) }
        }
        let physical = frontmost ? try CGEventInputDispatcher().query(query, targetWindow: targetWindow) : false
        switch query {
        case .key(let key):
            let injected = (status["pressedKeys"] as? [String] ?? []).contains(Self.code(key))
            return injected || physical
        case .mouseButton(let button):
            let name = try? Self.button(button)
            let injected = name.map { (status["pressedButtons"] as? [String] ?? []).contains($0) } ?? false
            return injected || physical
        }
    }

    func shutdown() {
        DispatchQueue.main.async { [bridge] in MainActor.assumeIsolated { bridge.suspend() } }
    }

    static func commands(for action: InputAction, viewport: CGRect) throws -> [[String: Any]] {
        func command(_ method: String, _ args: [Any] = []) -> [String: Any] { ["method": method, "args": args] }
        func wait(_ duration: Int) throws -> [String: Any] {
            guard (0...60_000).contains(duration) else { throw CloudWebInputError.pageFailure("输入持续时间必须在 0–60000ms 内") }
            return command("wait", [duration])
        }
        func position(_ point: CGPoint?) throws -> [[String: Any]] {
            guard let point else { return [] }
            let p = try CloudGameGeometry.normalizedPoint(point, in: viewport)
            return [command("setAbsPosition", [p.x, p.y]), command("mouseMove", [0, 0])]
        }
        func extra(_ flags: ModifierFlags) -> [String: Bool] {
            var result: [String: Bool] = [:]
            if flags.contains(.shift) { result["shiftKey"] = true }
            if flags.contains(.control) { result["ctrlKey"] = true }
            if flags.contains(.option) { result["altKey"] = true }
            if flags.contains(.command) { result["metaKey"] = true }
            return result
        }
        switch action {
        case .keyDown(let key, let flags): return [command("keyDown", [code(key), extra(flags)])]
        case .keyUp(let key, let flags): return [command("keyUp", [code(key), extra(flags)])]
        case .keyPress(let key, let flags):
            return [command("keyDown", [code(key), extra(flags)]), try wait(60), command("keyUp", [code(key), extra(flags)])]
        case .keyHold(let key, let duration, let flags):
            return [command("keyDown", [code(key), extra(flags)]), try wait(duration), command("keyUp", [code(key), extra(flags)])]
        case .mouseMove(let point): return try position(point)
        case .mouseMoveRelative(let x, let y):
            guard x.isFinite, y.isFinite else { throw CloudWebInputError.invalidCoordinates }
            return [command("mouseMove", [x, y])]
        case .mouseButtonDown(let button, let point): return try position(point) + [command("mouseDown", [Self.button(button)])]
        case .mouseButtonUp(let button, let point): return try position(point) + [command("mouseUp", [Self.button(button)])]
        case .mouseClick(let button, let point):
            return try position(point) + [command("mouseDown", [Self.button(button)]), wait(60), command("mouseUp", [Self.button(button)])]
        case .mouseButtonHold(let button, let duration, let point):
            return try position(point) + [command("mouseDown", [Self.button(button)]), wait(duration), command("mouseUp", [Self.button(button)])]
        case .leftClick(let point): return try commands(for: .mouseClick(button: .left, at: point), viewport: viewport)
        case .verticalScroll(let clicks): return [command("scroll", [Double(clicks) * 120])]
        case .inputText(let text): return [command("sendIme", [text])]
        case .releaseAll: return [command("releaseAll")]
        }
    }

    private static func button(_ value: InputMouseButton) throws -> String {
        switch value {
        case .left: return "left"
        case .right: return "right"
        case .middle: return "middle"
        case .side1, .side2: throw CGEventInputDispatchError.unsupportedMouseButton(value)
        }
    }

    static func code(_ key: KeyCode) -> String {
        if key.rawValue.count == 1 { return "Key" + key.rawValue.uppercased() }
        if key.rawValue.hasPrefix("digit") { return "Digit" + key.rawValue.suffix(1) }
        if Int(key.rawValue.dropFirst()) != nil, key.rawValue.hasPrefix("f") { return key.rawValue.uppercased() }
        switch key {
        case .leftArrow: return "ArrowLeft"
        case .rightArrow: return "ArrowRight"
        case .upArrow: return "ArrowUp"
        case .downArrow: return "ArrowDown"
        case .return: return "Enter"
        case .leftShift: return "ShiftLeft"
        case .leftControl: return "ControlLeft"
        case .leftOption: return "AltLeft"
        case .rightCommand: return "MetaRight"
        case .apostrophe: return "Quote"
        case .equal: return "Equal"
        case .leftBracket: return "BracketLeft"
        case .rightBracket: return "BracketRight"
        case .grave: return "Backquote"
        default: return key.rawValue.prefix(1).uppercased() + key.rawValue.dropFirst()
        }
    }
}
