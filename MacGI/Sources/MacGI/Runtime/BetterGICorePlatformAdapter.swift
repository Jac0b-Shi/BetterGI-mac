import AppKit
import CoreGraphics
import Foundation
import UserNotifications

enum BetterGICorePlatformAdapterError: LocalizedError {
    case invalidParameters(String)
    case unsupportedMethod(String)
    case inputRejected(String)
    case notificationRejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidParameters(let message): message
        case .unsupportedMethod(let method): "Unsupported Core platform callback: \(method)"
        case .inputRejected(let reason): "InputSafetyGate rejected Core input: \(reason)"
        case .notificationRejected(let reason): "macOS rejected Core notification: \(reason)"
        }
    }
}

/// Converts C# semantic platform callbacks into the existing macOS capture/input boundary.
/// It contains no BetterGI scheduling or script semantics.
final class BetterGICorePlatformAdapter: @unchecked Sendable {
    private final class CallbackTransfer: @unchecked Sendable {
        let method: String
        let parameters: [String: Any]?
        var result: Result<Any, Error>?

        init(method: String, parameters: [String: Any]?) {
            self.method = method
            self.parameters = parameters
        }
    }

    private final class NotificationTransfer: @unchecked Sendable {
        var error: Error?
    }

    private final class CaptureTransfer: @unchecked Sendable {
        var result: Result<Any, Error>?
    }

    private weak var appState: AppState?
    private var audioCapture: BGIAudioSampleProvider?

    init(appState: AppState) { self.appState = appState }

    func handle(method: String, parameters: [String: Any]?) throws -> Any {
        if method == "capture.request" { return try handleCaptureRequest() }
        let transfer = CallbackTransfer(method: method, parameters: parameters)
        DispatchQueue.main.sync { [weak self] in
            MainActor.assumeIsolated {
                do {
                    guard let self, let appState = self.appState else {
                        throw BetterGICorePlatformAdapterError.invalidParameters("AppState is unavailable.")
                    }
                    transfer.result = .success(try self.handleOnMain(
                        method: transfer.method,
                        parameters: transfer.parameters,
                        appState: appState
                    ))
                } catch {
                    transfer.result = .failure(error)
                }
            }
        }
        guard let result = transfer.result else {
            throw BetterGICorePlatformAdapterError.invalidParameters("Platform callback produced no result.")
        }
        return try result.get()
    }

    private func handleCaptureRequest() throws -> Any {
        let semaphore = DispatchSemaphore(value: 0)
        let transfer = CaptureTransfer()
        Task { @MainActor [weak self] in
            do {
                guard let appState = self?.appState else {
                    throw BetterGICorePlatformAdapterError.invalidParameters("AppState is unavailable.")
                }
                let frame = try await appState.captureFrameForBetterGICore()
                let ring = BetterGICoreCaptureRing(runURL: appState.betterGICoreRunURL)
                transfer.result = .success(try ring.write(frame))
            } catch {
                transfer.result = .failure(error)
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 15) == .success else {
            throw BetterGICorePlatformAdapterError.invalidParameters("capture.request timed out.")
        }
        guard let result = transfer.result else {
            throw BetterGICorePlatformAdapterError.invalidParameters("capture.request produced no result.")
        }
        return try result.get()
    }

    @MainActor
    private func handleOnMain(method: String, parameters: [String: Any]?, appState: AppState) throws -> Any {
        switch method {
        case "window.metrics":
            let window = appState.selectedWindow
            guard window.id != 0, window.isOnScreen, !window.isMock else {
                throw BetterGICorePlatformAdapterError.invalidParameters("No real on-screen game window is selected.")
            }
            let rect = window.captureRect
            let workingArea = NSScreen.main?.visibleFrame ?? rect
            let isActive = NSWorkspace.shared.frontmostApplication?.processIdentifier == window.ownerPID
            return [
                "width": Int(rect.width), "height": Int(rect.height),
                "captureX": Int(rect.minX), "captureY": Int(rect.minY),
                "captureWidth": Int(rect.width), "captureHeight": Int(rect.height),
                "dpiScale": Double(window.scaleFactor), "processId": Int(window.ownerPID),
                "workingAreaX": Int(workingArea.minX), "workingAreaY": Int(workingArea.minY),
                "workingAreaWidth": Int(workingArea.width), "workingAreaHeight": Int(workingArea.height),
                "isActive": isActive,
            ]
        case "window.activate":
            guard let application = NSRunningApplication(processIdentifier: appState.selectedWindow.ownerPID),
                  application.activate(options: [.activateAllWindows])
            else {
                throw BetterGICorePlatformAdapterError.invalidParameters("Unable to activate the selected game process.")
            }
            return ["acknowledged": true]
        case "audio.start":
            guard let parameters,
                  let processID = (parameters["processId"] as? NSNumber)?.int32Value,
                  processID == appState.selectedWindow.ownerPID,
                  (parameters["sampleRate"] as? NSNumber)?.intValue == 16_000,
                  (parameters["channels"] as? NSNumber)?.intValue == 1,
                  parameters["sampleFormat"] as? String == "float32le"
            else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "audio.start requires the selected PID and 16kHz mono float32le."
                )
            }
            guard audioCapture == nil else {
                throw BetterGICorePlatformAdapterError.invalidParameters("Core audio capture is already active.")
            }
            let capture = BGIScreenCaptureKitAudioCapture(targetProcessID: processID)
            try capture.startCapture()
            audioCapture = capture
            return ["acknowledged": true]
        case "audio.read":
            guard let audioCapture, audioCapture.isCapturing else {
                throw BetterGICorePlatformAdapterError.invalidParameters("Core audio capture is not active.")
            }
            let samples = audioCapture.readSamples()
            let data = samples.withUnsafeBytes { Data($0) }
            return [
                "sampleFormat": "float32le",
                "sampleCount": samples.count,
                "samplesBase64": data.base64EncodedString(),
            ]
        case "audio.discard":
            guard let audioCapture, audioCapture.isCapturing else {
                throw BetterGICorePlatformAdapterError.invalidParameters("Core audio capture is not active.")
            }
            _ = audioCapture.readSamples()
            return ["acknowledged": true]
        case "audio.stop":
            guard let audioCapture else {
                throw BetterGICorePlatformAdapterError.invalidParameters("Core audio capture is not active.")
            }
            audioCapture.stopCapture()
            self.audioCapture = nil
            return ["acknowledged": true]
        case "input.dispatch":
            let action = try makeInputAction(parameters, appState: appState)
            let gate = appState.dispatchInput(action, source: .runtimeTrigger)
            switch gate {
            case .allow:
                return ["acknowledged": true]
            case .dryRun(let reason), .blocked(let reason):
                throw BetterGICorePlatformAdapterError.inputRejected(reason)
            }
        case "input.query":
            guard let parameters,
                  parameters["action"] as? String == "isGameActionDown",
                  let rawAction = parameters["gameAction"] as? String,
                  let gameAction = GIAction(rawValue: rawAction)
            else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "input.query requires isGameActionDown and a BetterGI gameAction."
                )
            }
            let key = KeyBindingsConfig.bgiDefault.key(for: gameAction)
            if let keyCode = key.keyCode, let virtualKey = keyCode.cgKeyCode {
                return ["isDown": CGEventSource.keyState(.combinedSessionState, key: virtualKey)]
            }
            if let mouseButton = key.mouseButton {
                let button: CGMouseButton = switch mouseButton {
                case .left: .left
                case .right: .right
                case .middle: .center
                }
                return ["isDown": CGEventSource.buttonState(.combinedSessionState, button: button)]
            }
            throw BetterGICorePlatformAdapterError.invalidParameters(
                "BetterGI gameAction has no macOS key binding."
            )
        case "notification.emit":
            guard let parameters,
                  let kind = parameters["kind"] as? String,
                  let message = parameters["message"] as? String,
                  !message.isEmpty
            else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "notification.emit requires kind and non-empty message."
                )
            }
            let content = UNMutableNotificationContent()
            content.title = kind == "error" ? "BetterGI 脚本错误" : "BetterGI 脚本通知"
            content.body = message
            let request = UNNotificationRequest(
                identifier: "bettergi-core-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            let semaphore = DispatchSemaphore(value: 0)
            let delivery = NotificationTransfer()
            UNUserNotificationCenter.current().add(request) { error in
                delivery.error = error
                semaphore.signal()
            }
            guard semaphore.wait(timeout: .now() + 5) == .success else {
                throw BetterGICorePlatformAdapterError.notificationRejected("delivery timed out")
            }
            if let deliveryError = delivery.error {
                throw BetterGICorePlatformAdapterError.notificationRejected(deliveryError.localizedDescription)
            }
            appState.addLog(kind == "error" ? .error : .info, "Core notification: \(message)")
            return ["acknowledged": true]
        case "scheduler.event":
            guard let parameters,
                  let taskID = parameters["taskId"] as? String,
                  let state = parameters["state"] as? String,
                  !taskID.isEmpty, !state.isEmpty
            else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "scheduler.event requires taskId and state."
                )
            }
            appState.schedulerExecutionStatus = state
            if let error = parameters["error"] as? [String: Any],
               let message = error["message"] as? String {
                appState.addLog(.error, "Core scheduler \(taskID) \(state): \(message)")
            } else {
                appState.addLog(.info, "Core scheduler \(taskID) \(state)")
            }
            return ["acknowledged": true]
        case "pathing.current":
            guard let parameters,
                  let name = parameters["name"] as? String,
                  let waypointCount = parameters["waypointCount"] as? Int
            else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "pathing.current requires name and waypointCount."
                )
            }
            appState.addLog(.info, "Core pathing: \(name) (\(waypointCount) waypoints)")
            return ["acknowledged": true]
        case "pathing.position":
            guard let parameters,
                  parameters["x"] is NSNumber,
                  parameters["y"] is NSNumber
            else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "pathing.position requires numeric x and y."
                )
            }
            return ["acknowledged": true]
        case "overlay.command":
            guard let parameters,
                  let name = parameters["name"] as? String,
                  let operation = parameters["operation"] as? String
            else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "overlay.command requires name and operation."
                )
            }
            appState.addLog(.debug, "Core overlay \(operation): \(name)")
            return ["acknowledged": true]
        default:
            throw BetterGICorePlatformAdapterError.unsupportedMethod(method)
        }
    }

    @MainActor
    private func makeInputAction(_ parameters: [String: Any]?, appState: AppState) throws -> InputAction {
        guard let parameters, let action = parameters["action"] as? String else {
            throw BetterGICorePlatformAdapterError.invalidParameters("input.dispatch requires action.")
        }
        switch action {
        case "gameAction":
            guard let rawAction = parameters["gameAction"] as? String,
                  let gameAction = GIAction(rawValue: rawAction),
                  let rawType = parameters["keyType"] as? String,
                  let keyType = GIKeyType(rawValue: rawType),
                  let input = KeyBindingsConfig.bgiDefault.inputAction(for: gameAction, type: keyType)
            else {
                throw BetterGICorePlatformAdapterError.invalidParameters("Unsupported BetterGI game action.")
            }
            return input
        case "keyDown", "keyUp", "keyPress":
            let key: KeyCode?
            if let rawKey = parameters["key"] as? String {
                key = BetterGICoreInputKeyMapper.keyCode(from: rawKey)
            } else if let virtualKey = parameters["windowsVirtualKey"] as? Int {
                key = BetterGICoreInputKeyMapper.keyCode(fromWindowsVirtualKey: virtualKey)
            } else {
                key = nil
            }
            guard let key else { throw BetterGICorePlatformAdapterError.invalidParameters("Unsupported BetterGI virtual key.") }
            if action == "keyDown" { return .keyDown(key: key) }
            if action == "keyUp" { return .keyUp(key: key) }
            return .keyPress(key: key)
        case "moveMouseBy":
            guard let x = number(parameters["x"]), let y = number(parameters["y"]),
                  let current = CGEvent(source: nil)?.location
            else { throw BetterGICorePlatformAdapterError.invalidParameters("moveMouseBy requires x/y and a current cursor position.") }
            return .mouseMove(to: CGPoint(x: current.x + x, y: current.y + y))
        case "moveMouseToScreen":
            guard let x = number(parameters["x"]), let y = number(parameters["y"]) else {
                throw BetterGICorePlatformAdapterError.invalidParameters("moveMouseToScreen requires x/y.")
            }
            return .mouseMove(to: CGPoint(x: x, y: y))
        case "moveMouseToGame":
            guard let x = number(parameters["x"]), let y = number(parameters["y"]),
                  let gameWidth = number(parameters["gameWidth"]),
                  let gameHeight = number(parameters["gameHeight"]),
                  gameWidth > 0, gameHeight > 0
            else { throw BetterGICorePlatformAdapterError.invalidParameters("moveMouseToGame requires valid coordinates and game dimensions.") }
            let rect = appState.selectedWindow.captureRect
            return .mouseMove(to: CGPoint(
                x: rect.minX + x / gameWidth * rect.width,
                y: rect.minY + y / gameHeight * rect.height
            ))
        case "moveMouseToVirtualDesktop":
            guard let x = number(parameters["normalizedX"]), let y = number(parameters["normalizedY"]),
                  (0...65535).contains(x), (0...65535).contains(y),
                  let frame = NSScreen.main?.visibleFrame
            else { throw BetterGICorePlatformAdapterError.invalidParameters("moveMouseToVirtualDesktop requires normalized coordinates and a main screen.") }
            return .mouseMove(to: CGPoint(
                x: frame.minX + x / 65535 * frame.width,
                y: frame.minY + y / 65535 * frame.height
            ))
        case "mouseDown", "mouseUp", "mouseClick":
            guard let button = mouseButton(parameters["button"] as? String) else {
                throw BetterGICorePlatformAdapterError.invalidParameters("Unsupported mouse button.")
            }
            if action == "mouseDown" { return .mouseButtonDown(button: button) }
            if action == "mouseUp" { return .mouseButtonUp(button: button) }
            return .mouseClick(button: button)
        case "verticalScroll":
            guard let clicks = parameters["clicks"] as? Int else {
                throw BetterGICorePlatformAdapterError.invalidParameters("verticalScroll requires clicks.")
            }
            return .verticalScroll(clicks: clicks)
        case "inputText":
            guard let text = parameters["text"] as? String, !text.isEmpty else {
                throw BetterGICorePlatformAdapterError.invalidParameters("inputText requires non-empty text.")
            }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(text, forType: .string) else {
                throw BetterGICorePlatformAdapterError.invalidParameters("Failed to write text to the pasteboard.")
            }
            return .keyPress(key: .v, modifiers: .command)
        case "releaseAll":
            return .releaseAll
        default:
            throw BetterGICorePlatformAdapterError.invalidParameters("Unsupported input.dispatch action: \(action)")
        }
    }

    private func number(_ value: Any?) -> CGFloat? {
        if let value = value as? NSNumber { return CGFloat(value.doubleValue) }
        return nil
    }

    private func mouseButton(_ value: String?) -> InputMouseButton? {
        switch value {
        case "left": .left
        case "right": .right
        case "middle": .middle
        default: nil
        }
    }
}
