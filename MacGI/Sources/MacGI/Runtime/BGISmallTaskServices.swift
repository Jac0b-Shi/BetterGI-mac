import AppKit
import Foundation

// MARK: - GameLoading (自动进入游戏)

/// Upstream ref: `GameLoadingTrigger.cs`
/// Detects "enter game" door icon and clicks to enter the game world.
final class BGIGameLoadingService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    private let captureFrameProvider: CaptureFrameProvider?
    private let inputHandler: InputHandler
    private let templateEngine = TemplateMatchingRecognitionEngine()
    init(inputHandler: @escaping InputHandler, captureFrameProvider: CaptureFrameProvider? = nil) {
        self.inputHandler = inputHandler; self.captureFrameProvider = captureFrameProvider
    }
    func evaluate() async -> Bool {
        guard let provider = captureFrameProvider, let frame = try? await provider() else { return false }
        let results = templateEngine.recognize(imageFrame: frame, objects: RecognitionObject.bgiGameLoadingObjects).observations
        if let enter = results.first(where: { $0.objectID.contains("EnterGame") }) {
            let x = enter.normalizedRect.midX * Double(frame.metadata.width)
            let y = enter.normalizedRect.midY * Double(frame.metadata.height)
            _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: x, y: y)))
            return true
        }
        return false
    }
}

// MARK: - QuickSereniteaPot (快速尘歌壶)

/// Upstream ref: `QuickSereniteaPotTask.cs`
/// Detects teapot icon in Paimon menu and clicks to enter the Serenitea Pot.
final class BGIQuickSereniteaPotService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    private let captureFrameProvider: CaptureFrameProvider?
    private let inputHandler: InputHandler
    private let templateEngine = TemplateMatchingRecognitionEngine()
    init(inputHandler: @escaping InputHandler, captureFrameProvider: CaptureFrameProvider? = nil) {
        self.inputHandler = inputHandler; self.captureFrameProvider = captureFrameProvider
    }
    func enter() async -> Bool {
        guard let provider = captureFrameProvider, let frame = try? await provider() else { return false }
        let results = templateEngine.recognize(imageFrame: frame, objects: RecognitionObject.bgiSereniteaPotObjects).observations
        if let icon = results.first(where: { $0.objectID.contains("SereniteaPot") }) {
            let x = icon.normalizedRect.midX * Double(frame.metadata.width)
            let y = icon.normalizedRect.midY * Double(frame.metadata.height)
            _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: x, y: y)))
            return true
        }
        return false
    }
}

// MARK: - UseRedeemCode (兑换码)

/// Upstream ref: `UseRedemptionCodeTask.cs`
/// Opens Paimon menu → settings → account → redeem → pastes code → confirms.
final class BGIUseRedeemCodeService: @unchecked Sendable {
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    private let inputHandler: InputHandler
    init(inputHandler: @escaping InputHandler) { self.inputHandler = inputHandler }
    func redeem(code: String) async {
        // Esc to open Paimon menu
        _ = await inputHandler(.keyPress(key: .escape))
        try? await Task.sleep(nanoseconds: 500_000_000)
        // Click settings (roughly at 1080p 45,825)
        _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 45, y: 825)))
        try? await Task.sleep(nanoseconds: 500_000_000)
        // Click account (left 20%)
        _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 200, y: 500)))
        try? await Task.sleep(nanoseconds: 500_000_000)
        // Click redeem (right 30%)
        _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 1500, y: 500)))
        try? await Task.sleep(nanoseconds: 500_000_000)
        // Paste code via clipboard (upstream: copies to clipboard, clicks paste button)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        try? await Task.sleep(nanoseconds: 200_000_000)
        // Click paste button (right side of redeem input area)
        _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 1300, y: 500)))
        try? await Task.sleep(nanoseconds: 500_000_000)
        // Confirm
        _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 1500, y: 800)))
    }
}

// MARK: - AutoCook (自动烹饪)

/// Upstream ref: `AutoCookTrigger.cs`
/// Detects cooking pot UI → clicks cook → waits → clicks confirm.
final class BGIAutoCookService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    private let captureFrameProvider: CaptureFrameProvider?
    private let inputHandler: InputHandler
    private let templateEngine = TemplateMatchingRecognitionEngine()
    init(inputHandler: @escaping InputHandler, captureFrameProvider: CaptureFrameProvider? = nil) {
        self.inputHandler = inputHandler; self.captureFrameProvider = captureFrameProvider
    }
    func evaluate() async -> Bool {
        guard let provider = captureFrameProvider, let frame = try? await provider() else { return false }
        // Check for cooking UI elements (ui_left_top_cook_icon in Common/Element)
        let results = templateEngine.recognize(imageFrame: frame, objects: RecognitionObject.bgiCookObjects).observations
        if !results.isEmpty {
            // Click cook button and confirm
            _ = await inputHandler(.keyPress(key: .space))
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            _ = await inputHandler(.keyPress(key: .space))
            return true
        }
        return false
    }
}
