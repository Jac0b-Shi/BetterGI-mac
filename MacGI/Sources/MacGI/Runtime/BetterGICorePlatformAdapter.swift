import AppKit
import CoreGraphics
import Foundation
import UserNotifications

enum BetterGICorePlatformAdapterError: LocalizedError {
    case invalidParameters(String)
    case unsupportedMethod(String)
    case inputRejected(String)
    case notificationRejected(String)
    case htmlMaskRejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidParameters(let message): message
        case .unsupportedMethod(let method): "Unsupported Core platform callback: \(method)"
        case .inputRejected(let reason): "InputSafetyGate rejected Core input: \(reason)"
        case .notificationRejected(let reason): "macOS rejected Core notification: \(reason)"
        case .htmlMaskRejected(let reason): "macOS rejected Core HTML mask: \(reason)"
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
    private let captureRing: BetterGICoreCaptureRing
    private let htmlMaskController: MacHTMLMaskController

    @MainActor
    init(appState: AppState) {
        self.appState = appState
        captureRing = BetterGICoreCaptureRing(runURL: appState.betterGICoreRunURL)
        htmlMaskController = MacHTMLMaskController(appState: appState)
    }

    func handle(method: String, parameters: [String: Any]?) throws -> Any {
        if method == "capture.request" { return try handleCaptureRequest() }
        if method.hasPrefix("htmlMask.") {
            return try handleHTMLMaskRequest(method: method, parameters: parameters)
        }
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

    private func handleHTMLMaskRequest(
        method: String,
        parameters: [String: Any]?
    ) throws -> Any {
        let semaphore = DispatchSemaphore(value: 0)
        let transfer = CallbackTransfer(method: method, parameters: parameters)
        Task { @MainActor [weak self] in
            do {
                guard let self else {
                    throw BetterGICorePlatformAdapterError.htmlMaskRejected(
                        "HTML mask controller is unavailable.")
                }
                transfer.result = .success(
                    try await self.htmlMaskController.handle(
                        method: transfer.method,
                        parameters: transfer.parameters))
            } catch {
                transfer.result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        guard let result = transfer.result else {
            throw BetterGICorePlatformAdapterError.htmlMaskRejected(
                "HTML mask callback produced no result.")
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
                guard let self else {
                    throw BetterGICorePlatformAdapterError.invalidParameters(
                        "Capture ring is unavailable.")
                }
                transfer.result = .success(try self.captureRing.write(frame))
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
            guard window.id != 0, window.isOnScreen, !window.isSynthetic else {
                throw BetterGICorePlatformAdapterError.invalidParameters("No real on-screen game window is selected.")
            }
            let rect = window.captureRect
            let workingArea = NSScreen.main?.visibleFrame ?? rect
            let pixelSize = window.capturePixelSize
            let scale = window.scaleFactor
            let isActive = NSWorkspace.shared.frontmostApplication?.processIdentifier == window.ownerPID
            return [
                "width": Int(pixelSize.width), "height": Int(pixelSize.height),
                "captureX": Int(rect.minX * scale), "captureY": Int(rect.minY * scale),
                "captureWidth": Int(pixelSize.width), "captureHeight": Int(pixelSize.height),
                "dpiScale": Double(scale), "processId": Int(window.ownerPID),
                "workingAreaX": Int(workingArea.minX * scale), "workingAreaY": Int(workingArea.minY * scale),
                "workingAreaWidth": Int(workingArea.width * scale), "workingAreaHeight": Int(workingArea.height * scale),
                "isActive": isActive,
            ]
        case "clipboard.write":
            guard let text = parameters?["text"] as? String, !text.isEmpty else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "clipboard.write requires non-empty text."
                )
            }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(text, forType: .string) else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "Failed to write text to the pasteboard."
                )
            }
            return ["acknowledged": true]
        case "clipboard.clear":
            NSPasteboard.general.clearContents()
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
        case "game.close":
            guard let application = NSRunningApplication(
                processIdentifier: appState.selectedWindow.ownerPID
            ), application.terminate() else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "Unable to terminate the selected game process."
                )
            }
            return ["acknowledged": true]
        case "application.restart":
            guard let parameters,
                  let taskProgressName = parameters["taskProgressName"] as? String,
                  !taskProgressName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "application.restart requires a non-empty taskProgressName."
                )
            }
            let bundleURL = Bundle.main.bundleURL
            guard bundleURL.pathExtension == "app" else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "application.restart requires an installed macOS app bundle."
                )
            }
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            relaunch.arguments = [
                "-n", bundleURL.path, "--args", "--TaskProgress", taskProgressName,
            ]
            try relaunch.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSApp.terminate(nil)
            }
            return ["acknowledged": true]
        case "url.canOpen":
            guard let rawURL = parameters?["url"] as? String,
                  let url = URL(string: rawURL), url.scheme != nil else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "url.canOpen requires an absolute URL."
                )
            }
            return ["available": NSWorkspace.shared.urlForApplication(toOpen: url) != nil]
        case "url.open":
            guard let rawURL = parameters?["url"] as? String,
                  let url = URL(string: rawURL), url.scheme != nil,
                  NSWorkspace.shared.open(url) else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "macOS could not open the requested URL."
                )
            }
            return ["acknowledged": true]
        case "window.biliLogin":
            let ownerPID = appState.selectedWindow.ownerPID
            let titles = QuartzWindowEnumerator.enumerateApplicationWindows()
                .filter { $0.ownerPID == ownerPID }
                .map(\.title)
                .filter { $0.localizedCaseInsensitiveContains("bilibili") }
            if titles.contains(where: { $0.contains("协议") }) {
                return ["type": "agreement"]
            }
            if titles.contains(where: { $0.contains("登录") }) {
                return ["type": "login"]
            }
            return ["type": "none"]
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
            guard let parameters, let query = parameters["action"] as? String else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "input.query requires an action."
                )
            }
            switch query {
            case "isGameActionDown":
                guard let rawAction = parameters["gameAction"] as? String,
                      GIAction(rawValue: rawAction) != nil else {
                    throw BetterGICorePlatformAdapterError.invalidParameters(
                        "isGameActionDown requires a BetterGI gameAction."
                    )
                }
                if let windowsVirtualKey = parameters["windowsVirtualKey"] as? Int,
                   let keyCode = BetterGICoreInputKeyMapper.keyCode(
                    fromWindowsVirtualKey: windowsVirtualKey),
                   let virtualKey = keyCode.cgKeyCode {
                    return ["isDown": CGEventSource.keyState(.combinedSessionState, key: virtualKey)]
                }
                if let mouseButton = mouseButton(parameters["mouseButton"] as? String) {
                    let button: CGMouseButton = switch mouseButton {
                    case .left: .left
                    case .right: .right
                    case .middle: .center
                    case .side1: CGMouseButton(rawValue: 3)!
                    case .side2: CGMouseButton(rawValue: 4)!
                    }
                    return ["isDown": CGEventSource.buttonState(.combinedSessionState, button: button)]
                }
            case "isKeyDown":
                guard let rawKey = parameters["key"] as? String else {
                    throw BetterGICorePlatformAdapterError.invalidParameters(
                        "isKeyDown requires a key."
                    )
                }
                if let key = BetterGICoreInputKeyMapper.keyCode(from: rawKey),
                   let virtualKey = key.cgKeyCode {
                    return ["isDown": CGEventSource.keyState(.combinedSessionState, key: virtualKey)]
                }
                if let button = BetterGICoreInputKeyMapper.mouseButton(from: rawKey) {
                    return ["isDown": CGEventSource.buttonState(.combinedSessionState, button: button)]
                }
            default:
                break
            }
            throw BetterGICorePlatformAdapterError.invalidParameters(
                "input.query contains an unsupported action or key mapping."
            )
        case "notification.emit":
            guard let parameters,
                  let eventCode = parameters["eventCode"] as? String,
                  let result = parameters["result"] as? String,
                  let message = parameters["message"] as? String,
                  !message.isEmpty
            else {
                throw BetterGICorePlatformAdapterError.invalidParameters(
                    "notification.emit requires eventCode, result and non-empty message."
                )
            }
            guard appState.notificationSettings?.macOSNotificationEnabled == true else {
                appState.addLog(.debug, "Core notification suppressed: \(message)")
                return ["acknowledged": true]
            }
            let content = UNMutableNotificationContent()
            content.title =
                result == "Fail" ? "BetterGI 任务错误" : "BetterGI 通知"
            content.subtitle = eventCode
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
            appState.addLog(
                result == "Fail" ? .error : .info,
                "Core notification [\(eventCode)]: \(message)")
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
            let error = parameters["error"] as? [String: Any]
            let message = error?["message"] as? String
            try appState.handleCoreSchedulerEvent(taskID: taskID, state: state, error: message)
            if let message {
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
            guard let parameters else {
                throw BetterGICorePlatformAdapterError.invalidParameters("overlay.command requires parameters.")
            }
            do {
                try appState.applyCoreOverlayCommand(parameters)
            } catch {
                throw BetterGICorePlatformAdapterError.invalidParameters(error.localizedDescription)
            }
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
                  GIAction(rawValue: rawAction) != nil,
                  let rawType = parameters["keyType"] as? String,
                  let keyType = GIKeyType(rawValue: rawType)
            else {
                throw BetterGICorePlatformAdapterError.invalidParameters("Unsupported BetterGI game action.")
            }
            if let windowsVirtualKey = parameters["windowsVirtualKey"] as? Int,
               let key = BetterGICoreInputKeyMapper.keyCode(
                fromWindowsVirtualKey: windowsVirtualKey) {
                return inputAction(for: key, type: keyType)
            }
            if let button = mouseButton(parameters["mouseButton"] as? String) {
                return inputAction(for: button, type: keyType)
            }
            throw BetterGICorePlatformAdapterError.invalidParameters(
                "BetterGI game action is missing its Core-resolved physical key."
            )
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
            let scale = coreInputScale(appState)
            return .mouseMove(to: CGPoint(x: current.x + x / scale, y: current.y + y / scale))
        case "moveMouseToScreen":
            guard let x = number(parameters["x"]), let y = number(parameters["y"]) else {
                throw BetterGICorePlatformAdapterError.invalidParameters("moveMouseToScreen requires x/y.")
            }
            return .mouseMove(to: quartzPoint(coreX: x, coreY: y, appState: appState))
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
            let point: CGPoint?
            if parameters["x"] != nil || parameters["y"] != nil {
                guard let x = number(parameters["x"]), let y = number(parameters["y"]) else {
                    throw BetterGICorePlatformAdapterError.invalidParameters(
                        "mouseClick coordinates require both x and y.")
                }
                point = quartzPoint(coreX: x, coreY: y, appState: appState)
            } else {
                point = nil
            }
            return .mouseClick(button: button, at: point)
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

    @MainActor
    private func quartzPoint(coreX: CGFloat, coreY: CGFloat, appState: AppState) -> CGPoint {
        let scale = coreInputScale(appState)
        return CGPoint(x: coreX / scale, y: coreY / scale)
    }

    @MainActor
    private func coreInputScale(_ appState: AppState) -> CGFloat {
        max(1, appState.selectedWindow.scaleFactor)
    }

    private func mouseButton(_ value: String?) -> InputMouseButton? {
        switch value {
        case "left": .left
        case "right": .right
        case "middle": .middle
        case "side1": .side1
        case "side2": .side2
        default: nil
        }
    }

    private func inputAction(for key: KeyCode, type: GIKeyType) -> InputAction {
        switch type {
        case .keyPress: .keyPress(key: key)
        case .keyDown: .keyDown(key: key)
        case .keyUp: .keyUp(key: key)
        case .hold: .keyHold(key: key, durationMs: 1_000)
        }
    }

    private func inputAction(
        for button: InputMouseButton,
        type: GIKeyType
    ) -> InputAction {
        switch type {
        case .keyPress: .mouseClick(button: button)
        case .keyDown: .mouseButtonDown(button: button)
        case .keyUp: .mouseButtonUp(button: button)
        case .hold: .mouseButtonHold(button: button, durationMs: 1_000)
        }
    }
}
