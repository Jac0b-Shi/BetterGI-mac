import CoreGraphics
import Foundation

struct BGISetTimeConfig: Equatable, Sendable {
    var menuOpenWaitMs: UInt64 = 800
    var timePageOpenWaitMs: UInt64 = 900
    var mouseMoveSettleWaitMs: UInt64 = 50
    var mouseDownWaitMs: UInt64 = 50
    var clockStepWaitMs: UInt64 = 50
    var afterClockSetWaitMs: UInt64 = 100
    var confirmMoveWaitMs: UInt64 = 300
    var confirmClickWaitMs: UInt64 = 7
    var skipAnimationPreWaitMs: UInt64 = 10
    var skipAnimationMouseDownWaitMs: UInt64 = 10
    var skipAnimationPostWaitMs: UInt64 = 1_010
    var postAnimationWaitMs: UInt64 = 3_000
    var pageCloseRetryTimes: Int = 25
    var pageCloseRetryIntervalMs: UInt64 = 500
}

enum BGISetTimeError: LocalizedError, Equatable {
    case invalidHour(Int)
    case invalidMinute(Int)

    var errorDescription: String? {
        switch self {
        case let .invalidHour(hour):
            "Invalid hour value: \(hour), expected 0...24"
        case let .invalidMinute(minute):
            "Invalid minute value: \(minute), expected 0...59"
        }
    }
}

final class BGISetTimeService: @unchecked Sendable {
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias RecognitionObjectProvider = BGIMainUIStatusChecker.RecognitionObjectProvider

    private let targetWindow: WindowInfo
    private let inputHandler: InputHandler
    private let captureFrameProvider: CaptureFrameProvider?
    private let recognitionObjectProvider: RecognitionObjectProvider?
    private let returnMainUIConfig: BGIReturnMainUIConfig
    private let templateRecognitionEngine: TemplateMatchingRecognitionEngine
    private let config: BGISetTimeConfig

    init(
        targetWindow: WindowInfo,
        inputHandler: @escaping InputHandler,
        captureFrameProvider: CaptureFrameProvider? = nil,
        recognitionObjectProvider: RecognitionObjectProvider? = nil,
        returnMainUIConfig: BGIReturnMainUIConfig = BGIReturnMainUIConfig(),
        templateRecognitionEngine: TemplateMatchingRecognitionEngine = TemplateMatchingRecognitionEngine(),
        config: BGISetTimeConfig = BGISetTimeConfig()
    ) {
        self.targetWindow = targetWindow
        self.inputHandler = inputHandler
        self.captureFrameProvider = captureFrameProvider
        self.recognitionObjectProvider = recognitionObjectProvider
        self.returnMainUIConfig = returnMainUIConfig
        self.templateRecognitionEngine = templateRecognitionEngine
        self.config = config
    }

    func setTime(hour: Int, minute: Int, skipAnimation: Bool) async throws {
        try validate(hour: hour, minute: minute)
        try await returnMainUIService().returnToMainUI()
        try await setTimeOnce(hour: hour, minute: minute, skipAnimation: skipAnimation)
    }

    private func setTimeOnce(hour: Int, minute: Int, skipAnimation: Bool) async throws {
        let normalizedHour = ((Int(floor(Double(hour) + Double(minute) / 60.0)) % 24) + 24) % 24
        let normalizedMinute = hour * 60 + minute - normalizedHour * 60

        await perform(.keyPress(key: .escape))
        try await sleep(config.menuOpenWaitMs)
        await clickGamePoint(x: 50, y: 700)
        try await sleep(config.timePageOpenWaitMs)

        try await setClock(hour: normalizedHour, minute: normalizedMinute)

        try await sleep(config.afterClockSetWaitMs)
        await perform(.mouseMove(to: gamePoint(x: 1_500, y: 1_000)))
        try await sleep(config.confirmMoveWaitMs)
        await perform(.mouseClick(button: .left, at: gamePoint(x: 1_500, y: 1_000)))
        try await sleep(config.confirmClickWaitMs)

        if skipAnimation {
            try await sleep(config.skipAnimationPreWaitMs)
            await cancelAnimation()
            try await sleep(config.skipAnimationPostWaitMs)
            await clickGamePoint(x: 45, y: 715)
            try await sleep(100)
            await clickGamePoint(x: 45, y: 715)
            try await sleep(200)
            _ = try await returnMainUIService().returnToMainUI()
            return
        }

        try await sleep(config.postAnimationWaitMs)
        try await waitForPageCloseWhiteIfPossible()
        _ = try await returnMainUIService().returnToMainUI()
    }

    private func setClock(hour: Int, minute: Int) async throws {
        let end = (hour + 6) * 60 + minute - 20
        let n = 3
        for i in (-n + 1)..<1 {
            let position = clockPosition(radius: 30, index: Double(end) + Double(i) * 1_440.0 / Double(n))
            await mouseClickGamePoint(position, stepWaitMs: config.clockStepWaitMs)
        }

        let start = clockPosition(radius: 150, index: Double(end) + 5)
        let endPoint = clockPosition(radius: 300, index: Double(end) + 20.5)
        await mouseClickAndMove(from: start, to: endPoint, stepWaitMs: config.clockStepWaitMs)
    }

    private func clockPosition(radius: Double, index: Double) -> CGPoint {
        let angle = index * .pi / 720.0
        return CGPoint(
            x: 1_441.0 + radius * cos(angle),
            y: 501.6 + radius * sin(angle)
        )
    }

    private func mouseClickGamePoint(_ point: CGPoint, stepWaitMs: UInt64) async {
        let screenPoint = gamePoint(x: point.x, y: point.y)
        await perform(.mouseMove(to: screenPoint))
        try? await sleep(config.mouseMoveSettleWaitMs)
        await perform(.mouseButtonDown(button: .left, at: screenPoint))
        try? await sleep(config.mouseDownWaitMs)
        await perform(.mouseButtonUp(button: .left, at: screenPoint))
        try? await sleep(stepWaitMs)
    }

    private func mouseClickAndMove(from start: CGPoint, to end: CGPoint, stepWaitMs: UInt64) async {
        let startPoint = gamePoint(x: start.x, y: start.y)
        let endPoint = gamePoint(x: end.x, y: end.y)
        await perform(.mouseMove(to: startPoint))
        try? await sleep(config.mouseMoveSettleWaitMs)
        await perform(.mouseButtonDown(button: .left, at: startPoint))
        try? await sleep(config.mouseDownWaitMs)
        await perform(.mouseMove(to: endPoint))
        try? await sleep(config.mouseMoveSettleWaitMs)
        await perform(.mouseButtonUp(button: .left, at: endPoint))
        try? await sleep(stepWaitMs)
    }

    private func cancelAnimation() async {
        let point = gamePoint(x: 200, y: 200)
        await perform(.mouseMove(to: point))
        await perform(.mouseButtonDown(button: .left, at: point))
        try? await sleep(config.skipAnimationMouseDownWaitMs)
        await perform(.mouseButtonUp(button: .left, at: point))
    }

    private func waitForPageCloseWhiteIfPossible() async throws {
        guard let captureFrameProvider else { return }
        for attempt in 0..<max(1, config.pageCloseRetryTimes) {
            let frame = try await captureFrameProvider()
            let observations = try await pageCloseWhiteObservations(in: frame)
            if !observations.isEmpty {
                return
            }
            if attempt < max(1, config.pageCloseRetryTimes) - 1 {
                try await sleep(config.pageCloseRetryIntervalMs)
            }
        }
    }

    private func pageCloseWhiteObservations(in frame: CaptureImageFrame) async throws -> [RecognitionObservation] {
        let object = RecognitionObject.bgiCommonElementPageCloseWhiteObject
        if let recognitionObjectProvider {
            return try await recognitionObjectProvider(frame, object)
        }
        return templateRecognitionEngine.recognize(imageFrame: frame, objects: [object]).observations
    }

    private func returnMainUIService() -> BGIReturnMainUIService {
        BGIReturnMainUIService(
            inputHandler: inputHandler,
            captureFrameProvider: captureFrameProvider,
            recognitionObjectProvider: recognitionObjectProvider,
            config: returnMainUIConfig
        )
    }

    private func clickGamePoint(x: Double, y: Double) async {
        await perform(.mouseClick(button: .left, at: gamePoint(x: x, y: y)))
    }

    private func gamePoint(x: Double, y: Double) -> CGPoint {
        let rect = targetWindow.captureRect
        return CGPoint(
            x: rect.minX + CGFloat(x / 1_920.0) * rect.width,
            y: rect.minY + CGFloat(y / 1_080.0) * rect.height
        )
    }

    private func validate(hour: Int, minute: Int) throws {
        guard (0...24).contains(hour) else {
            throw BGISetTimeError.invalidHour(hour)
        }
        guard (0...59).contains(minute) else {
            throw BGISetTimeError.invalidMinute(minute)
        }
    }

    private func perform(_ action: InputAction) async {
        _ = await inputHandler(action)
    }

    private func sleep(_ ms: UInt64) async throws {
        try await Task.sleep(nanoseconds: ms * 1_000_000)
    }
}
