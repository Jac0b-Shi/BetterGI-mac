import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum MacKeyMouseRecordingError: LocalizedError {
    case accessibilityPermissionMissing
    case alreadyRecording
    case eventTapCreationFailed
    case notRecording

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "录制键鼠事件需要辅助功能权限。"
        case .alreadyRecording:
            "键鼠录制已经在运行。"
        case .eventTapCreationFailed:
            "无法创建 macOS 键鼠监听。"
        case .notRecording:
            "键鼠录制尚未启动。"
        }
    }
}

struct BetterGIRecordedMacroEvent: Sendable {
    let type: Int
    let keyCode: Int?
    let mouseX: Int
    let mouseY: Int
    let mouseButton: String?
    let time: Double

    var rpcPayload: [String: Any] {
        var payload: [String: Any] = [
            "type": type,
            "mouseX": mouseX,
            "mouseY": mouseY,
            "time": time,
        ]
        if let keyCode {
            payload["keyCode"] = keyCode
        }
        if let mouseButton {
            payload["mouseButton"] = mouseButton
        }
        return payload
    }
}

struct MacKeyMouseRecording: Sendable {
    let events: [BetterGIRecordedMacroEvent]
    let captureX: Int
    let captureY: Int
    let captureWidth: Int
    let captureHeight: Int
    let recordDPI: Double

    var infoPayload: [String: Any] {
        [
            "x": captureX,
            "y": captureY,
            "width": captureWidth,
            "height": captureHeight,
            "recordDpi": recordDPI,
        ]
    }
}

final class MacKeyMouseEventRecorder {
    private static let maximumEventCount = 200_000
    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var events: [BetterGIRecordedMacroEvent] = []
    private var pressedKeyCodes: Set<CGKeyCode> = []
    private var startTimestamp: UInt64 = 0
    private var targetProcessID: pid_t = 0
    private var captureRect = CGRect.zero
    private var scaleFactor = 1.0
    private var ignoredHotKey: MacHotKeySignature?

    var isRecording: Bool {
        lock.withLock { eventTap != nil }
    }

    func start(
        targetWindow: WindowInfo,
        ignoring ignoredHotKey: MacHotKeySignature? = nil
    ) throws {
        guard AXIsProcessTrusted() else {
            throw MacKeyMouseRecordingError.accessibilityPermissionMissing
        }
        guard !isRecording else {
            throw MacKeyMouseRecordingError.alreadyRecording
        }

        let eventTypes: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .scrollWheel,
        ]
        let mask = eventTypes.reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: macKeyMouseEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw MacKeyMouseRecordingError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        lock.withLock {
            events.removeAll(keepingCapacity: true)
            pressedKeyCodes.removeAll(keepingCapacity: true)
            startTimestamp = mach_absolute_time()
            targetProcessID = targetWindow.ownerPID
            captureRect = targetWindow.captureRect
            scaleFactor = targetWindow.scaleFactor
            self.ignoredHotKey = ignoredHotKey
            eventTap = tap
            runLoopSource = source
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() throws -> MacKeyMouseRecording {
        let snapshot: (
            tap: CFMachPort,
            source: CFRunLoopSource,
            events: [BetterGIRecordedMacroEvent],
            rect: CGRect,
            scale: Double
        ) = try lock.withLock {
            guard let eventTap, let runLoopSource else {
                throw MacKeyMouseRecordingError.notRecording
            }
            let snapshot = (eventTap, runLoopSource, events, captureRect, scaleFactor)
            self.eventTap = nil
            self.runLoopSource = nil
            events = []
            pressedKeyCodes = []
            ignoredHotKey = nil
            return snapshot
        }

        CGEvent.tapEnable(tap: snapshot.tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), snapshot.source, .commonModes)
        return MacKeyMouseRecording(
            events: snapshot.events,
            captureX: Int((snapshot.rect.minX * snapshot.scale).rounded()),
            captureY: Int((snapshot.rect.minY * snapshot.scale).rounded()),
            captureWidth: Int((snapshot.rect.width * snapshot.scale).rounded()),
            captureHeight: Int((snapshot.rect.height * snapshot.scale).rounded()),
            recordDPI: snapshot.scale
        )
    }

    fileprivate func receive(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = lock.withLock({ eventTap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        guard event.getIntegerValueField(.eventSourceUserData) !=
                BetterGIInputEventMarker.value
        else {
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                lock.withLock({ targetProcessID })
        else {
            return
        }
        if let signature = MacHotKeySignature.from(type: type, event: event),
           signature == lock.withLock({ ignoredHotKey }) {
            return
        }

        let time = elapsedMilliseconds(for: event)
        switch type {
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            appendKeyboardEvent(type: 0, event: event, time: time)
        case .keyUp:
            appendKeyboardEvent(type: 1, event: event, time: time)
        case .flagsChanged:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard let windowsVirtualKey =
                    BetterGICoreInputKeyMapper.windowsVirtualKey(fromCGKeyCode: keyCode)
            else {
                return
            }
            lock.withLock {
                let isDown = !pressedKeyCodes.contains(keyCode)
                if isDown {
                    pressedKeyCodes.insert(keyCode)
                } else {
                    pressedKeyCodes.remove(keyCode)
                }
                appendLocked(BetterGIRecordedMacroEvent(
                    type: isDown ? 0 : 1,
                    keyCode: windowsVirtualKey,
                    mouseX: 0,
                    mouseY: 0,
                    mouseButton: nil,
                    time: time
                ))
            }
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let scale = lock.withLock { scaleFactor }
            let deltaX = Int((Double(event.getIntegerValueField(.mouseEventDeltaX)) * scale).rounded())
            let deltaY = Int((Double(event.getIntegerValueField(.mouseEventDeltaY)) * scale).rounded())
            guard deltaX != 0 || deltaY != 0 else { return }
            append(BetterGIRecordedMacroEvent(
                type: 3,
                keyCode: nil,
                mouseX: deltaX,
                mouseY: deltaY,
                mouseButton: nil,
                time: time
            ))
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp:
            guard let descriptor = mouseDescriptor(for: type, event: event) else { return }
            let scale = lock.withLock { scaleFactor }
            append(BetterGIRecordedMacroEvent(
                type: descriptor.isDown ? 4 : 5,
                keyCode: nil,
                mouseX: Int((event.location.x * scale).rounded()),
                mouseY: Int((event.location.y * scale).rounded()),
                mouseButton: descriptor.button,
                time: time
            ))
        case .scrollWheel:
            let delta = Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            guard delta != 0 else { return }
            append(BetterGIRecordedMacroEvent(
                type: 6,
                keyCode: nil,
                mouseX: 0,
                mouseY: delta * 120,
                mouseButton: nil,
                time: time
            ))
        default:
            break
        }
    }

    private func appendKeyboardEvent(type: Int, event: CGEvent, time: Double) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard let windowsVirtualKey =
                BetterGICoreInputKeyMapper.windowsVirtualKey(fromCGKeyCode: keyCode)
        else {
            return
        }
        lock.withLock {
            if type == 0 {
                guard !pressedKeyCodes.contains(keyCode) else { return }
                pressedKeyCodes.insert(keyCode)
            } else {
                guard pressedKeyCodes.contains(keyCode) else { return }
                pressedKeyCodes.remove(keyCode)
            }
            appendLocked(BetterGIRecordedMacroEvent(
                type: type,
                keyCode: windowsVirtualKey,
                mouseX: 0,
                mouseY: 0,
                mouseButton: nil,
                time: time
            ))
        }
    }

    private func append(_ event: BetterGIRecordedMacroEvent) {
        lock.withLock {
            appendLocked(event)
        }
    }

    private func appendLocked(_ event: BetterGIRecordedMacroEvent) {
        guard events.count < Self.maximumEventCount else { return }
        events.append(event)
    }

    private func elapsedMilliseconds(for event: CGEvent) -> Double {
        let start = lock.withLock { startTimestamp }
        let current = event.timestamp
        guard current >= start else { return 0 }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanoseconds = Double(current - start)
            * Double(timebase.numer) / Double(timebase.denom)
        return nanoseconds / 1_000_000
    }

    private func mouseDescriptor(
        for type: CGEventType,
        event: CGEvent
    ) -> (button: String, isDown: Bool)? {
        switch type {
        case .leftMouseDown: ("Left", true)
        case .leftMouseUp: ("Left", false)
        case .rightMouseDown: ("Right", true)
        case .rightMouseUp: ("Right", false)
        case .otherMouseDown:
            (otherMouseButtonName(event), true)
        case .otherMouseUp:
            (otherMouseButtonName(event), false)
        default: nil
        }
    }

    private func otherMouseButtonName(_ event: CGEvent) -> String {
        return switch event.getIntegerValueField(.mouseEventButtonNumber) {
        case 3: "XButton1"
        case 4: "XButton2"
        default: "Middle"
        }
    }
}

private func macKeyMouseEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let recorder = Unmanaged<MacKeyMouseEventRecorder>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    recorder.receive(type: type, event: event)
    return Unmanaged.passUnretained(event)
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
