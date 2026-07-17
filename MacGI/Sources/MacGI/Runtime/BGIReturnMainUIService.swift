import Foundation

struct BGIReturnMainUIConfig: Equatable, Sendable {
    var maxEscapeAttempts: Int = 8
    var escapeWaitMs: UInt64 = 900
    var finalKeyWaitMs: UInt64 = 500
}

final class BGIReturnMainUIService: @unchecked Sendable {
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias RecognitionObjectProvider = BGIMainUIStatusChecker.RecognitionObjectProvider

    private let inputHandler: InputHandler
    private let captureFrameProvider: CaptureFrameProvider?
    private let mainUIStatusChecker: BGIMainUIStatusChecker
    private let config: BGIReturnMainUIConfig

    init(
        inputHandler: @escaping InputHandler,
        captureFrameProvider: CaptureFrameProvider? = nil,
        recognitionObjectProvider: RecognitionObjectProvider? = nil,
        config: BGIReturnMainUIConfig = BGIReturnMainUIConfig(),
        statusRecognizer: BGIGameUIStatusRecognizer = BGIGameUIStatusRecognizer(),
        templateRecognitionEngine: TemplateMatchingRecognitionEngine = TemplateMatchingRecognitionEngine()
    ) {
        self.inputHandler = inputHandler
        self.captureFrameProvider = captureFrameProvider
        self.mainUIStatusChecker = BGIMainUIStatusChecker(
            statusRecognizer: statusRecognizer,
            templateRecognitionEngine: templateRecognitionEngine,
            recognitionObjectProvider: recognitionObjectProvider
        )
        self.config = config
    }

    @discardableResult
    func returnToMainUI() async throws -> Bool {
        if try await isInMainUI() {
            return true
        }

        for _ in 0..<max(1, config.maxEscapeAttempts) {
            await perform(.keyPress(key: .escape))
            try await sleep(config.escapeWaitMs)
            if try await isInMainUI() {
                return true
            }
        }

        try await sleep(config.finalKeyWaitMs)
        await perform(.keyPress(key: .return))
        try await sleep(config.finalKeyWaitMs)
        await perform(.keyPress(key: .escape))
        return false
    }

    private func isInMainUI() async throws -> Bool {
        guard let captureFrameProvider else { return false }
        let frame = try await captureFrameProvider()
        return try await mainUIStatusChecker.isInMainUI(frame: frame)
    }

    private func perform(_ action: InputAction) async {
        _ = await inputHandler(action)
    }

    private func sleep(_ ms: UInt64) async throws {
        try await Task.sleep(nanoseconds: ms * 1_000_000)
    }
}
