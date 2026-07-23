import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class MacAuxiliaryControlMonitor {
    private let handler: (KeyCode, Bool) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var targetProcessID: pid_t = 0
    private var pressedKeys: Set<KeyCode> = []

    init(handler: @escaping (KeyCode, Bool) -> Void) {
        self.handler = handler
    }

    func start(targetProcessID: pid_t) throws {
        self.targetProcessID = targetProcessID
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
            throw MacKeyMouseRecordingError.accessibilityPermissionMissing
        }
        let mask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: macAuxiliaryControlEventTapCallback,
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

    func stop() {
        let keysToRelease = pressedKeys
        pressedKeys.removeAll()
        for key in keysToRelease {
            handler(key, false)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
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
              NSWorkspace.shared.frontmostApplication?.processIdentifier == targetProcessID
        else {
            return
        }
        let cgKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard let key = KeyCode.allCases.first(where: { $0.cgKeyCode == cgKeyCode }) else {
            return
        }
        if type == .keyDown {
            if pressedKeys.insert(key).inserted {
                handler(key, true)
            }
        } else if type == .keyUp, pressedKeys.remove(key) != nil {
            handler(key, false)
        }
    }
}

private func macAuxiliaryControlEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<MacAuxiliaryControlMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    monitor.receive(type: type, event: event)
    return Unmanaged.passUnretained(event)
}
