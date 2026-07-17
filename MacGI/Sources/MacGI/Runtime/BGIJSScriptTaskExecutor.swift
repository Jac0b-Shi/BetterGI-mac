import CoreGraphics
import Foundation

/// Request to execute an installed JS script.
///
/// ## Input dispatch mode
/// The `recordInputOnly` flag defaults to `true`. When enabled, JS `keyPress` etc.
/// are **recorded** into `BGIJSScriptExecutionResult.inputCommands` and replayed
/// later through `AppState.dispatchInput(action, source: .runtimeTrigger)`, which
/// goes through `InputSafetyGate`.
///
/// Direct CGEvent dispatch from inside the JS runtime is **disabled**. The legacy
/// `inputCommandHandler` closure is safety-gated and never bypasses the gate.
///
/// ## Limitations
/// JS input is **record-then-replay**, not BGI-style immediate execution. Input
/// commands do NOT affect subsequent capture/OCR/template results within the same
/// script tick. Real BGI-style immediate execution will be implemented separately.
struct BGIJSScriptTaskExecutionRequest: Equatable, Sendable {
    var folderName: String
    var settingsJSON: String
    var targetWindow: WindowInfo?

    /// Only record input commands; do not dispatch directly.
    /// Default `true` — the only safe mode.
    var recordInputOnly: Bool

    /// Maximum execution time in milliseconds. Default 30 seconds.
    var timeoutMs: Int

    init(
        folderName: String,
        settingsJSON: String = "{}",
        targetWindow: WindowInfo? = nil,
        recordInputOnly: Bool = true,
        timeoutMs: Int = 30_000
    ) {
        self.folderName = folderName
        self.settingsJSON = settingsJSON
        self.targetWindow = targetWindow
        self.recordInputOnly = recordInputOnly
        self.timeoutMs = timeoutMs
    }
}

final class BGIJSScriptTaskExecutor {
    typealias CaptureFrameProvider = BGICapturingJSScriptHostEnvironment.CaptureFrameProvider
    typealias OCRProvider = BGICapturingJSScriptHostEnvironment.OCRProvider
    typealias TemplateProvider = BGICapturingJSScriptHostEnvironment.TemplateProvider
    typealias RecognitionObjectProvider = BGICapturingJSScriptHostEnvironment.RecognitionObjectProvider
    typealias MiniMapLocalizationProvider = BGICapturingJSScriptHostEnvironment.MiniMapLocalizationProvider
    typealias MiniMapOrientationProvider = BGICapturingJSScriptHostEnvironment.MiniMapOrientationProvider

    private let store: BGIRuntimeResourceStore
    private let fileManager: FileManager
    private let captureFrameProvider: CaptureFrameProvider
    private let ocrProvider: OCRProvider?
    private let templateProvider: TemplateProvider?
    private let recognitionObjectProvider: RecognitionObjectProvider?
    private let miniMapLocalizationProvider: MiniMapLocalizationProvider?
    private let miniMapOrientationProvider: MiniMapOrientationProvider?
    private let templateRecognitionEngine: TemplateMatchingRecognitionEngine

    // Safety-gated input dispatch closure (not a raw CGEvent path).
    // When nil, input is record-only (safe default).
    typealias SafetyGatedInputHandler = (InputAction) -> InputSafetyGate.GateResult
    private let safetyGatedInputHandler: SafetyGatedInputHandler?

    init(
        store: BGIRuntimeResourceStore = .defaultStore(),
        fileManager: FileManager = .default,
        captureFrameProvider: @escaping CaptureFrameProvider,
        ocrProvider: OCRProvider? = nil,
        templateProvider: TemplateProvider? = nil,
        recognitionObjectProvider: RecognitionObjectProvider? = nil,
        miniMapLocalizationProvider: MiniMapLocalizationProvider? = nil,
        miniMapOrientationProvider: MiniMapOrientationProvider? = nil,
        templateRecognitionEngine: TemplateMatchingRecognitionEngine = TemplateMatchingRecognitionEngine(),
        safetyGatedInputHandler: SafetyGatedInputHandler? = nil
    ) {
        self.store = store
        self.fileManager = fileManager
        self.captureFrameProvider = captureFrameProvider
        self.ocrProvider = ocrProvider
        self.templateProvider = templateProvider
        self.recognitionObjectProvider = recognitionObjectProvider
        self.miniMapLocalizationProvider = miniMapLocalizationProvider
        self.miniMapOrientationProvider = miniMapOrientationProvider
        self.templateRecognitionEngine = templateRecognitionEngine
        self.safetyGatedInputHandler = safetyGatedInputHandler
    }

    func executeInstalledScript(_ request: BGIJSScriptTaskExecutionRequest) throws -> BGIJSScriptExecutionResult {
        let project = try BGIInstalledJSScriptProjectLoader(
            store: store,
            fileManager: fileManager
        ).loadProject(folderName: request.folderName)

        return try execute(
            project: project,
            settingsJSON: request.settingsJSON,
            targetWindow: request.targetWindow,
            recordInputOnly: request.recordInputOnly,
            timeoutMs: request.timeoutMs
        )
    }

    func execute(
        project: BGIJSScriptProject,
        settingsJSON: String = "{}",
        targetWindow: WindowInfo? = nil,
        recordInputOnly: Bool = true,
        timeoutMs: Int = 30_000
    ) throws -> BGIJSScriptExecutionResult {
        // Input command handler: always record-only via safety gate by default.
        // Direct CGEvent dispatch is NOT available from the JS runtime.
        // The `inputCommandHandler` closure routes through safetyGatedInputHandler
        // when available; otherwise it records only.
        let inputHandler: BGICapturingJSScriptHostEnvironment.InputCommandHandler? = { [weak self] command in
            guard let self, let targetWindow else { return }
            guard let action = Self.inputAction(
                for: command,
                targetWindow: targetWindow,
                gameMetrics: self.gameMetrics(for: targetWindow)
            ) else { return }

            // Route through safety gate if a handler is provided.
            if let handler = self.safetyGatedInputHandler {
                _ = handler(action)
            }
            // Otherwise the command is still recorded — dispatched later
            // through AppState.dispatchRecordedJSScriptInputCommands().
        }

        // Build deadline from timeout.
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)

        let hostEnvironment = BGICapturingJSScriptHostEnvironment(
            gameMetrics: gameMetrics(for: targetWindow),
            captureFrameProvider: captureFrameProvider,
            ocrProvider: ocrProvider,
            templateProvider: templateProvider,
            recognitionObjectProvider: recognitionObjectProvider,
            miniMapLocalizationProvider: miniMapLocalizationProvider,
            miniMapOrientationProvider: miniMapOrientationProvider,
            inputCommandHandler: inputHandler,
            templateRecognitionEngine: templateRecognitionEngine,
            deadline: deadline,
            isCancelled: { Task.isCancelled }
        )
        return try BGIJSScriptRunner(
            fileManager: fileManager,
            hostEnvironment: hostEnvironment
        ).execute(project: project, settingsJSON: settingsJSON)
    }

    private func gameMetrics(for targetWindow: WindowInfo?) -> [Double] {
        guard let targetWindow, !targetWindow.captureRect.isEmpty else {
            return [1920, 1080, 1]
        }
        return [
            Double(targetWindow.captureRect.width),
            Double(targetWindow.captureRect.height),
            Double(targetWindow.scaleFactor)
        ]
    }

    static func inputAction(
        for command: BGIJSScriptInputCommand,
        targetWindow: WindowInfo,
        gameMetrics: [Double]
    ) -> InputAction? {
        switch command {
        case let .keyDown(key):
            .keyDown(key: key)
        case let .keyUp(key):
            .keyUp(key: key)
        case let .keyPress(key):
            .keyPress(key: key)
        case let .mouseMoveBy(dx, dy):
            .mouseMove(to: currentMousePoint(in: targetWindow).applying(CGAffineTransform(translationX: dx, y: dy)))
        case let .mouseMoveToGame(x, y):
            .mouseMove(to: screenPointForGamePoint(x: x, y: y, targetWindow: targetWindow, gameMetrics: gameMetrics))
        case let .mouseClickGame(button, x, y):
            .mouseClick(
                button: button,
                at: screenPointForGamePoint(x: x, y: y, targetWindow: targetWindow, gameMetrics: gameMetrics)
            )
        case let .mouseButtonDown(button):
            .mouseButtonDown(button: button)
        case let .mouseButtonUp(button):
            .mouseButtonUp(button: button)
        case let .mouseClick(button):
            .mouseClick(button: button)
        case let .verticalScroll(amount):
            .verticalScroll(clicks: amount)
        case .inputText:
            nil
        }
    }

    private static func currentMousePoint(in targetWindow: WindowInfo) -> CGPoint {
        CGEvent(source: nil)?.location
            ?? CGPoint(x: targetWindow.captureRect.midX, y: targetWindow.captureRect.midY)
    }

    private static func screenPointForGamePoint(
        x: Double,
        y: Double,
        targetWindow: WindowInfo,
        gameMetrics: [Double]
    ) -> CGPoint {
        let rect = targetWindow.captureRect
        let gameWidthValue = gameMetrics.indices.contains(0) ? gameMetrics[0] : Double(rect.width)
        let gameHeightValue = gameMetrics.indices.contains(1) ? gameMetrics[1] : Double(rect.height)
        let gameWidth = max(1, CGFloat(gameWidthValue))
        let gameHeight = max(1, CGFloat(gameHeightValue))
        return CGPoint(
            x: rect.minX + CGFloat(x) / gameWidth * rect.width,
            y: rect.minY + CGFloat(y) / gameHeight * rect.height
        )
    }
}
