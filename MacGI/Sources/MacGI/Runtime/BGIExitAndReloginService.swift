import CoreGraphics
import Foundation

struct BGIExitAndReloginConfig: Equatable, Sendable {
    var menuAppearAttempts: Int = 10
    var menuAppearIntervalMs: UInt64 = 1_200
    var confirmAppearAttempts: Int = 5
    var confirmAppearIntervalMs: UInt64 = 800
    var confirmDisappearAttempts: Int = 5
    var confirmDisappearIntervalMs: UInt64 = 1_000
    var afterConfirmDisappearWaitMs: UInt64 = 1_000
    var enterGameAppearAttempts: Int = 120
    var enterGameAppearIntervalMs: UInt64 = 1_000
    var enterGameDisappearAttempts: Int = 120
    var enterGameDisappearIntervalMs: UInt64 = 1_000
    var mainUIAppearAttempts: Int = 120
    var mainUIAppearIntervalMs: UInt64 = 1_000
    var finalWaitMs: UInt64 = 500
}

enum BGIExitAndReloginError: LocalizedError, Equatable {
    case captureUnavailable
    case enterGameUnavailable
    case enterGameDidNotDisappear

    var errorDescription: String? {
        switch self {
        case .captureUnavailable:
            "Relogin requires a capture provider"
        case .enterGameUnavailable:
            "Enter game button was not detected"
        case .enterGameDidNotDisappear:
            "Enter game button did not disappear after clicking"
        }
    }
}

final class BGIExitAndReloginService: @unchecked Sendable {
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias RecognitionObjectProvider = BGIMainUIStatusChecker.RecognitionObjectProvider

    private let targetWindow: WindowInfo
    private let inputHandler: InputHandler
    private let captureFrameProvider: CaptureFrameProvider?
    private let recognitionObjectProvider: RecognitionObjectProvider?
    private let templateRecognitionEngine: TemplateMatchingRecognitionEngine
    private let config: BGIExitAndReloginConfig

    init(
        targetWindow: WindowInfo,
        inputHandler: @escaping InputHandler,
        captureFrameProvider: CaptureFrameProvider? = nil,
        recognitionObjectProvider: RecognitionObjectProvider? = nil,
        templateRecognitionEngine: TemplateMatchingRecognitionEngine = TemplateMatchingRecognitionEngine(),
        config: BGIExitAndReloginConfig = BGIExitAndReloginConfig()
    ) {
        self.targetWindow = targetWindow
        self.inputHandler = inputHandler
        self.captureFrameProvider = captureFrameProvider
        self.recognitionObjectProvider = recognitionObjectProvider
        self.templateRecognitionEngine = templateRecognitionEngine
        self.config = config
    }

    @discardableResult
    func exitAndRelogin() async throws -> Bool {
        guard captureFrameProvider != nil else {
            throw BGIExitAndReloginError.captureUnavailable
        }

        _ = try await waitForElementAppear(
            RecognitionObject.bgiAutoWoodMenuBagObject,
            attempts: config.menuAppearAttempts,
            intervalMs: config.menuAppearIntervalMs
        ) {
            await self.perform(.keyPress(key: .escape))
        }

        _ = try await waitForElementAppear(
            RecognitionObject.bgiAutoWoodConfirmObject,
            attempts: config.confirmAppearAttempts,
            intervalMs: config.confirmAppearIntervalMs
        ) {
            await self.perform(.mouseClick(button: .left, at: self.gamePoint(x: 50, y: 1_030)))
        }

        _ = try await waitForElementDisappear(
            RecognitionObject.bgiAutoWoodConfirmObject,
            attempts: config.confirmDisappearAttempts,
            intervalMs: config.confirmDisappearIntervalMs
        ) { observations in
            if let observation = observations.first,
               let point = self.screenPoint(for: observation.normalizedRect) {
                await self.perform(.mouseClick(button: .left, at: point))
            }
        }

        try await sleep(config.afterConfirmDisappearWaitMs)

        let enterGameAppear = try await waitForElementAppear(
            RecognitionObject.bgiAutoWoodEnterGameObject,
            attempts: config.enterGameAppearAttempts,
            intervalMs: config.enterGameAppearIntervalMs,
            action: nil
        )
        guard enterGameAppear else {
            throw BGIExitAndReloginError.enterGameUnavailable
        }

        let enterGameDisappear = try await waitForElementDisappear(
            RecognitionObject.bgiAutoWoodEnterGameObject,
            attempts: config.enterGameDisappearAttempts,
            intervalMs: config.enterGameDisappearIntervalMs
        ) { _ in
            await self.perform(.mouseClick(button: .left, at: self.gamePoint(x: 955, y: 666)))
        }
        guard enterGameDisappear else {
            throw BGIExitAndReloginError.enterGameDidNotDisappear
        }

        let mainUIFound = try await waitForElementAppear(
            RecognitionObject.bgiCommonElementPaimonMenuObject,
            attempts: config.mainUIAppearAttempts,
            intervalMs: config.mainUIAppearIntervalMs,
            action: nil
        )

        try await sleep(config.finalWaitMs)
        return mainUIFound
    }

    private func waitForElementAppear(
        _ object: RecognitionObject,
        attempts: Int,
        intervalMs: UInt64,
        action: (() async -> Void)?
    ) async throws -> Bool {
        for _ in 0..<max(1, attempts) {
            await action?()
            try await sleep(intervalMs)
            let frame = try await captureFrame()
            let current = try await observations(for: object, in: frame)
            if !current.isEmpty {
                return true
            }
        }
        return false
    }

    private func waitForElementDisappear(
        _ object: RecognitionObject,
        attempts: Int,
        intervalMs: UInt64,
        action: @escaping ([RecognitionObservation]) async -> Void
    ) async throws -> Bool {
        for _ in 0..<max(1, attempts) {
            let frame = try await captureFrame()
            let current = try await observations(for: object, in: frame)
            if current.isEmpty {
                return true
            }
            await action(current)
            try await sleep(intervalMs)
        }
        return false
    }

    private func observations(
        for object: RecognitionObject,
        in frame: CaptureImageFrame
    ) async throws -> [RecognitionObservation] {
        if let recognitionObjectProvider {
            return try await recognitionObjectProvider(frame, object)
        }
        return templateRecognitionEngine.recognize(imageFrame: frame, objects: [object]).observations
    }

    private func captureFrame() async throws -> CaptureImageFrame {
        guard let captureFrameProvider else {
            throw BGIExitAndReloginError.captureUnavailable
        }
        return try await captureFrameProvider()
    }

    private func screenPoint(for normalizedRect: CGRect) -> CGPoint? {
        InputTargetResolver.screenPoint(for: normalizedRect, in: CapturedFrame(
            frameIndex: 0,
            timestamp: Date(timeIntervalSince1970: 0),
            width: Int(max(1, targetWindow.captureRect.width)),
            height: Int(max(1, targetWindow.captureRect.height)),
            scaleFactor: targetWindow.scaleFactor,
            pixelFormat: 0,
            bytesPerRow: 0,
            sourceWindow: targetWindow
        ))
    }

    private func gamePoint(x: Double, y: Double) -> CGPoint {
        let rect = targetWindow.captureRect
        return CGPoint(
            x: rect.minX + CGFloat(x / 1_920.0) * rect.width,
            y: rect.minY + CGFloat(y / 1_080.0) * rect.height
        )
    }

    private func perform(_ action: InputAction) async {
        _ = await inputHandler(action)
    }

    private func sleep(_ ms: UInt64) async throws {
        try await Task.sleep(nanoseconds: ms * 1_000_000)
    }
}
