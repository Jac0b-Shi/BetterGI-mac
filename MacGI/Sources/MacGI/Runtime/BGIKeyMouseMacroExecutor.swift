import CoreGraphics
import Foundation

struct BGIKeyMouseScriptInfo: Equatable, Codable, Sendable {
    var name: String?
    var description: String?
    var author: String?
    var version: String?
    var bgiVersion: String?
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var recordDpi: Double

    init(
        name: String? = nil,
        description: String? = nil,
        author: String? = nil,
        version: String? = nil,
        bgiVersion: String? = nil,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        recordDpi: Double = 1
    ) {
        self.name = name
        self.description = description
        self.author = author
        self.version = version
        self.bgiVersion = bgiVersion
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.recordDpi = recordDpi
    }
}

enum BGIKeyMouseMacroEventType: String, Codable, Sendable {
    case keyDown = "KeyDown"
    case keyUp = "KeyUp"
    case mouseMoveTo = "MouseMoveTo"
    case mouseMoveBy = "MouseMoveBy"
    case mouseDown = "MouseDown"
    case mouseUp = "MouseUp"
    case mouseWheel = "MouseWheel"
}

struct BGIKeyMouseMacroEvent: Equatable, Codable, Sendable {
    var type: BGIKeyMouseMacroEventType
    var keyCode: Int?
    var mouseX: Int
    var mouseY: Int
    var mouseButton: String?
    var time: Double
    var cameraOrientation: Int?

    init(
        type: BGIKeyMouseMacroEventType,
        keyCode: Int? = nil,
        mouseX: Int = 0,
        mouseY: Int = 0,
        mouseButton: String? = nil,
        time: Double,
        cameraOrientation: Int? = nil
    ) {
        self.type = type
        self.keyCode = keyCode
        self.mouseX = mouseX
        self.mouseY = mouseY
        self.mouseButton = mouseButton
        self.time = time
        self.cameraOrientation = cameraOrientation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(BGIKeyMouseMacroEventType.self, forKey: .type)
        keyCode = try container.decodeIfPresent(Int.self, forKey: .keyCode)
        mouseX = try container.decodeIfPresent(Int.self, forKey: .mouseX) ?? 0
        mouseY = try container.decodeIfPresent(Int.self, forKey: .mouseY) ?? 0
        mouseButton = try container.decodeIfPresent(String.self, forKey: .mouseButton)
        time = try container.decodeIfPresent(Double.self, forKey: .time) ?? 0
        cameraOrientation = try container.decodeIfPresent(Int.self, forKey: .cameraOrientation)
    }
}

struct BGIKeyMouseScript: Equatable, Codable, Sendable {
    var macroEvents: [BGIKeyMouseMacroEvent]
    var info: BGIKeyMouseScriptInfo?
}

struct BGIKeyMousePlaybackAction: Equatable, Sendable {
    var eventTimeMs: Int
    var action: InputAction
}

struct BGIKeyMousePlaybackResult: Equatable, Sendable {
    var actionCount: Int
    var skippedEventCount: Int
    var durationMs: Int
}

enum BGIKeyMouseMacroExecutorError: LocalizedError, Equatable {
    case missingScript(String)
    case invalidScriptName(String)

    var errorDescription: String? {
        switch self {
        case let .missingScript(name):
            "BetterGI key-mouse script not found: \(name)"
        case let .invalidScriptName(name):
            "Invalid BetterGI key-mouse script name: \(name)"
        }
    }
}

final class BGIKeyMouseMacroExecutor {
    typealias DispatchHandler = @MainActor (InputAction) -> Void

    private let store: BGIRuntimeResourceStore
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    init(
        store: BGIRuntimeResourceStore = .defaultStore(),
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.store = store
        self.fileManager = fileManager
        self.decoder = decoder
    }

    @MainActor
    func executeInstalledScript(
        name: String,
        targetWindow: WindowInfo,
        dispatch: @escaping DispatchHandler
    ) async throws -> BGIKeyMousePlaybackResult {
        let script = try loadInstalledScript(name: name)
        return await Self.playback(script: script, targetWindow: targetWindow, dispatch: dispatch)
    }

    func loadInstalledScript(name: String) throws -> BGIKeyMouseScript {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              !normalizedName.contains("/"),
              !normalizedName.contains("\\"),
              !normalizedName.contains("..")
        else {
            throw BGIKeyMouseMacroExecutorError.invalidScriptName(name)
        }

        let scriptURL = store.userURL
            .appendingPathComponent("KeyMouseScript", isDirectory: true)
            .appendingPathComponent(normalizedName)
        guard fileManager.fileExists(atPath: scriptURL.path) else {
            throw BGIKeyMouseMacroExecutorError.missingScript(normalizedName)
        }
        let data = try Data(contentsOf: scriptURL)
        return try decoder.decode(BGIKeyMouseScript.self, from: data)
    }

    @MainActor
    static func playback(
        script: BGIKeyMouseScript,
        targetWindow: WindowInfo,
        currentMousePoint: CGPoint? = nil,
        dispatch: @escaping DispatchHandler
    ) async -> BGIKeyMousePlaybackResult {
        let playbackActions = actions(
            for: script,
            targetWindow: targetWindow,
            initialMousePoint: currentMousePoint ?? defaultMousePoint(in: targetWindow)
        )
        let startedAt = Date()
        var dispatched = 0

        for item in playbackActions {
            guard !Task.isCancelled else { break }
            let elapsedMs = Date().timeIntervalSince(startedAt) * 1000
            let waitMs = Double(item.eventTimeMs) - elapsedMs
            if waitMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(waitMs * 1_000_000))
            }
            dispatch(item.action)
            dispatched += 1
        }

        let duration = playbackActions.map(\.eventTimeMs).max() ?? 0
        return BGIKeyMousePlaybackResult(
            actionCount: dispatched,
            skippedEventCount: max(0, script.macroEvents.count - playbackActions.count),
            durationMs: duration
        )
    }

    static func actions(
        for script: BGIKeyMouseScript,
        targetWindow: WindowInfo,
        initialMousePoint: CGPoint? = nil
    ) -> [BGIKeyMousePlaybackAction] {
        var currentMousePoint = initialMousePoint ?? defaultMousePoint(in: targetWindow)
        let adaptedEvents = script.macroEvents
            .filter { $0.time >= 0 }
            .sorted { $0.time < $1.time }
            .map { adapt(event: $0, info: script.info, targetWindow: targetWindow) }

        return adaptedEvents.compactMap { event in
            guard let action = action(for: event, currentMousePoint: currentMousePoint) else {
                return nil
            }
            if let point = action.resolvedMousePoint {
                currentMousePoint = point
            }
            return BGIKeyMousePlaybackAction(
                eventTimeMs: max(0, Int(event.time.rounded())),
                action: action
            )
        }
    }

    private static func adapt(
        event: BGIKeyMouseMacroEvent,
        info: BGIKeyMouseScriptInfo?,
        targetWindow: WindowInfo
    ) -> BGIKeyMouseMacroEvent {
        guard let info, info.width > 0, info.height > 0 else {
            return event
        }

        var adapted = event
        switch event.type {
        case .mouseMoveTo, .mouseDown, .mouseUp:
            adapted.mouseX = Int(targetWindow.captureRect.minX) +
                Int(Double(event.mouseX - info.x) * Double(targetWindow.captureRect.width) / Double(info.width))
            adapted.mouseY = Int(targetWindow.captureRect.minY) +
                Int(Double(event.mouseY - info.y) * Double(targetWindow.captureRect.height) / Double(info.height))
        case .mouseMoveBy:
            let recordDpi = info.recordDpi == 0 ? 1 : info.recordDpi
            adapted.mouseX = Int((Double(event.mouseX) / recordDpi * Double(targetWindow.scaleFactor)).rounded())
            adapted.mouseY = Int((Double(event.mouseY) / recordDpi * Double(targetWindow.scaleFactor)).rounded())
        case .keyDown, .keyUp, .mouseWheel:
            break
        }
        return adapted
    }

    private static func action(
        for event: BGIKeyMouseMacroEvent,
        currentMousePoint: CGPoint
    ) -> InputAction? {
        switch event.type {
        case .keyDown:
            guard let key = event.keyCode.flatMap(keyCodeFromWindowsVirtualKey) else { return nil }
            return .keyDown(key: key)
        case .keyUp:
            guard let key = event.keyCode.flatMap(keyCodeFromWindowsVirtualKey) else { return nil }
            return .keyUp(key: key)
        case .mouseMoveTo:
            return .mouseMove(to: CGPoint(x: event.mouseX, y: event.mouseY))
        case .mouseMoveBy:
            return .mouseMove(to: currentMousePoint.applying(CGAffineTransform(
                translationX: CGFloat(event.mouseX),
                y: CGFloat(event.mouseY)
            )))
        case .mouseDown:
            guard let button = mouseButton(from: event.mouseButton) else { return nil }
            return .mouseButtonDown(button: button, at: CGPoint(x: event.mouseX, y: event.mouseY))
        case .mouseUp:
            guard let button = mouseButton(from: event.mouseButton) else { return nil }
            return .mouseButtonUp(button: button, at: CGPoint(x: event.mouseX, y: event.mouseY))
        case .mouseWheel:
            let clicks = Int(Double(event.mouseY) / 120.0)
            return clicks == 0 ? nil : .verticalScroll(clicks: clicks)
        }
    }

    static func keyCodeFromWindowsVirtualKey(_ virtualKey: Int) -> KeyCode? {
        if (0x41...0x5A).contains(virtualKey) {
            let scalar = UnicodeScalar(virtualKey)!
            return KeyCode(rawValue: String(Character(scalar)).lowercased())
        }
        if (0x30...0x39).contains(virtualKey) {
            return KeyCode(rawValue: "digit\(virtualKey - 0x30)")
        }
        if (0x70...0x7B).contains(virtualKey) {
            return KeyCode(rawValue: "f\(virtualKey - 0x6F)")
        }

        return switch virtualKey {
        case 0x08: .backspace
        case 0x09: .tab
        case 0x0D: .return
        case 0x10, 0xA0, 0xA1: .leftShift
        case 0x11, 0xA2, 0xA3: .leftControl
        case 0x12, 0xA4, 0xA5: .leftOption
        case 0x14: .capsLock
        case 0x1B: .escape
        case 0x20: .space
        case 0x21: .pageUp
        case 0x22: .pageDown
        case 0x23: .end
        case 0x24: .home
        case 0x25: .leftArrow
        case 0x26: .upArrow
        case 0x27: .rightArrow
        case 0x28: .downArrow
        case 0x2E: .delete
        case 0xBA: .semicolon
        case 0xBB: .equal
        case 0xBC: .comma
        case 0xBD: .minus
        case 0xBE: .period
        case 0xBF: .slash
        case 0xC0: .grave
        case 0xDB: .leftBracket
        case 0xDC: .backslash
        case 0xDD: .rightBracket
        case 0xDE: .apostrophe
        default: nil
        }
    }

    private static func mouseButton(from rawValue: String?) -> InputMouseButton? {
        return switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "left", "lbutton", "vk_lbutton":
            .left
        case "right", "rbutton", "vk_rbutton":
            .right
        case "middle", "mbutton", "vk_mbutton":
            .middle
        default:
            nil
        }
    }

    private static func defaultMousePoint(in targetWindow: WindowInfo) -> CGPoint {
        CGEvent(source: nil)?.location
            ?? CGPoint(x: targetWindow.captureRect.midX, y: targetWindow.captureRect.midY)
    }
}

private extension InputAction {
    var resolvedMousePoint: CGPoint? {
        switch self {
        case let .mouseMove(point):
            point
        case let .mouseButtonDown(_, point):
            point
        case let .mouseButtonUp(_, point):
            point
        case let .mouseClick(_, point):
            point
        case let .mouseButtonHold(_, _, point):
            point
        case let .leftClick(point):
            point
        case .keyPress, .keyDown, .keyUp, .keyHold, .verticalScroll, .releaseAll:
            nil
        }
    }
}
