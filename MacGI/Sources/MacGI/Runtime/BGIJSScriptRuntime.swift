import CoreGraphics
import Foundation
@preconcurrency import JavaScriptCore

struct BGIJSScriptHostCall: Equatable, Sendable {
    let name: String
    let arguments: [String]
}

enum BGIJSScriptInputCommand: Equatable, Sendable {
    case keyDown(KeyCode)
    case keyUp(KeyCode)
    case keyPress(KeyCode)
    case mouseMoveBy(dx: Double, dy: Double)
    case mouseMoveToGame(x: Double, y: Double)
    case mouseClickGame(button: InputMouseButton, x: Double, y: Double)
    case mouseButtonDown(InputMouseButton)
    case mouseButtonUp(InputMouseButton)
    case mouseClick(InputMouseButton)
    case verticalScroll(Int)
    case inputText(String)
}

enum BGIJSScriptGenshinCommand: Equatable, Sendable {
    case uid
    case teleport(x: Double, y: Double, mapName: String?, force: Bool?)
    case moveMapTo(x: Double, y: Double, forceCountry: String?)
    case moveIndependentMapTo(x: Int, y: Int, mapName: String, forceCountry: String?)
    case getBigMapZoomLevel
    case setBigMapZoomLevel(Double)
    case getPositionFromBigMap(mapName: String?)
    case getPositionFromMap(mapName: String?, matchingMethod: String?, cacheTimeMs: Int?, nearX: Double?, nearY: Double?)
    case getCameraOrientation
    case switchParty(String)
    case clearPartyCache
    case returnMainUI
    case teleportToStatueOfTheSeven
    case chooseTalkOption(option: String, skipTimes: Int, isOrange: Bool)
    case autoFishing(fishingTimePolicy: Int?)
    case relogin
    case setTime(hour: Int, minute: Int, skip: Bool)
}

struct BGIJSScriptCaptureRegion: Equatable, Sendable {
    let id: UInt64
    let width: Double
    let height: Double
    let dpi: Double
    let backendName: String
    let frameIndex: UInt64?
    let timestamp: Date?
    let pixelFormatName: String?
    let bytesPerRow: Int?
    let sourceWindowID: CGWindowID?
    let sourceWindowTitle: String?
    let captureRect: CGRect?

    init(
        id: UInt64 = 0,
        width: Double,
        height: Double,
        dpi: Double,
        backendName: String,
        frameIndex: UInt64? = nil,
        timestamp: Date? = nil,
        pixelFormatName: String? = nil,
        bytesPerRow: Int? = nil,
        sourceWindowID: CGWindowID? = nil,
        sourceWindowTitle: String? = nil,
        captureRect: CGRect? = nil
    ) {
        self.id = id
        self.width = width
        self.height = height
        self.dpi = dpi
        self.backendName = backendName
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.pixelFormatName = pixelFormatName
        self.bytesPerRow = bytesPerRow
        self.sourceWindowID = sourceWindowID
        self.sourceWindowTitle = sourceWindowTitle
        self.captureRect = captureRect
    }
}

struct BGIJSScriptOCRRegion: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let text: String
    let confidence: Double
}

struct BGIJSScriptOCRResult: Equatable, Sendable {
    let sourceCaptureID: UInt64?
    let frameIndex: UInt64?
    let timestamp: Date?
    let roi: CGRect?
    let combinedText: String
    let regions: [BGIJSScriptOCRRegion]

    init(
        sourceCaptureID: UInt64? = nil,
        frameIndex: UInt64? = nil,
        timestamp: Date? = nil,
        roi: CGRect? = nil,
        combinedText: String = "",
        regions: [BGIJSScriptOCRRegion] = []
    ) {
        self.sourceCaptureID = sourceCaptureID
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.roi = roi
        self.combinedText = combinedText
        self.regions = regions
    }

    init(sourceCaptureID: UInt64?, result: OCRResult, roi: CGRect?) {
        self.sourceCaptureID = sourceCaptureID
        frameIndex = result.frameIndex
        timestamp = result.timestamp
        self.roi = roi
        combinedText = result.combinedText
        regions = result.regions.map { region in
            BGIJSScriptOCRRegion(
                x: region.boundingBox.minX,
                y: region.boundingBox.minY,
                width: region.boundingBox.width,
                height: region.boundingBox.height,
                text: region.text,
                confidence: Double(region.confidence)
            )
        }
    }

    static func empty(for region: BGIJSScriptCaptureRegion) -> BGIJSScriptOCRResult {
        BGIJSScriptOCRResult(
            sourceCaptureID: region.id,
            frameIndex: region.frameIndex,
            timestamp: region.timestamp,
            roi: nil
        )
    }
}

struct BGIJSScriptVisionRegion: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let text: String?
    let confidence: Double
    let objectID: String
    let objectName: String
    let recognitionType: RecognitionType
}

struct BGIJSScriptTemplateLocator: Equatable, Sendable {
    let templateAssetName: String
    let roi: CGRect?
    let threshold: Double
    let findAll: Bool
}

struct BGIJSScriptGenshinResult: Equatable, Sendable {
    var boolValue: Bool = true
    var intValue: Int = 0
    var doubleValue: Double = 0
    var point: CGPoint = .zero
}

struct BGIJSScriptExecutionResult: Equatable, Sendable {
    let projectURL: URL
    let mainScriptURL: URL
    let loadedModulePaths: [String]
    let logs: [String]
    let hostCalls: [BGIJSScriptHostCall]
    let captureRegions: [BGIJSScriptCaptureRegion]
    let ocrResults: [BGIJSScriptOCRResult]
    let templateMatchRegions: [BGIJSScriptVisionRegion]
    let inputCommands: [BGIJSScriptInputCommand]
    let genshinCommands: [BGIJSScriptGenshinCommand]
}

enum BGIJSScriptRuntimeError: LocalizedError, Equatable, Sendable {
    case missingProjectDirectory(URL)
    case missingManifest(URL)
    case invalidManifest(String)
    case missingMainScript(String)
    case emptyMainScript(URL)
    case unsafePath(String)
    case moduleNotFound(String)
    case unsupportedModule(String)
    case unsupportedInputKey(String)
    case unsupportedImageRegionRecognitionType(String, findAll: Bool)
    case missingCaptureFrame(UInt64)
    case ocrUnavailable
    case bigMapUIUnavailable
    case templateRecognitionUnavailable
    case miniMapLocalizationUnavailable
    case miniMapOrientationUnavailable
    case scriptException(String)

    var errorDescription: String? {
        switch self {
        case let .missingProjectDirectory(url):
            "JS script directory does not exist: \(url.path)"
        case let .missingManifest(url):
            "manifest.json file does not exist: \(url.path)"
        case let .invalidManifest(message):
            message
        case let .missingMainScript(path):
            "main js file not found: \(path)"
        case let .emptyMainScript(url):
            "main js is empty: \(url.path)"
        case let .unsafePath(path):
            "Unsafe JS script path: \(path)"
        case let .moduleNotFound(specifier):
            "Unable to resolve JavaScript module import: \(specifier)"
        case let .unsupportedModule(specifier):
            "Unsupported JavaScript module import type: \(specifier)"
        case let .unsupportedInputKey(key):
            "Unsupported JavaScript input key: \(key)"
        case let .unsupportedImageRegionRecognitionType(typeName, findAll):
            if findAll {
                "ImageRegion.FindMulti does not support recognition type: \(typeName)"
            } else {
                "ImageRegion.Find does not support recognition type: \(typeName)"
            }
        case let .missingCaptureFrame(id):
            "Captured game region is no longer available: \(id)"
        case .ocrUnavailable:
            "OCR is unavailable for the current JavaScript host environment."
        case .bigMapUIUnavailable:
            "Current capture is not in big-map UI or the map scale button could not be recognized."
        case .templateRecognitionUnavailable:
            "Template recognition is unavailable for the current JavaScript host environment."
        case .miniMapLocalizationUnavailable:
            "Mini map localization is unavailable for the current JavaScript host environment."
        case .miniMapOrientationUnavailable:
            "Mini map orientation estimation is unavailable for the current JavaScript host environment."
        case let .scriptException(message):
            message
        }
    }
}

protocol BGIJSScriptHostEnvironment: AnyObject {
    var versionString: String { get }
    var gameMetrics: [Double] { get set }
    var avatars: [String] { get set }

    func sleep(milliseconds: Int)
    func performInputCommand(_ command: BGIJSScriptInputCommand) throws
    func captureGameRegion() throws -> BGIJSScriptCaptureRegion
    func recognizeText(in region: BGIJSScriptCaptureRegion, roi: CGRect?) throws -> BGIJSScriptOCRResult
    func recognizeTemplate(in region: BGIJSScriptCaptureRegion, locator: BGIJSScriptTemplateLocator) throws -> [BGIJSScriptVisionRegion]
    func recognizeObject(in region: BGIJSScriptCaptureRegion, object: RecognitionObject, findAll: Bool) throws -> [BGIJSScriptVisionRegion]
    func performGenshinCommand(_ command: BGIJSScriptGenshinCommand) throws -> BGIJSScriptGenshinResult
}

class BGIRecordingJSScriptHostEnvironment: BGIJSScriptHostEnvironment {
    typealias GenshinCommandHandler = (BGIJSScriptGenshinCommand) throws -> BGIJSScriptGenshinResult

    let versionString: String
    var gameMetrics: [Double]
    var avatars: [String]
    private(set) var inputCommands: [BGIJSScriptInputCommand] = []
    private(set) var genshinCommands: [BGIJSScriptGenshinCommand] = []
    private(set) var captureCount = 0
    let genshinCommandHandler: GenshinCommandHandler?

    func recordGenshinCommand(_ command: BGIJSScriptGenshinCommand) {
        genshinCommands.append(command)
    }

    /// Deadline after which sleep/capture/ocr loops should abort.
    var deadline: Date?
    /// Cancellation check — called before every sleep tick and blocking wait.
    var isCancelled: (() -> Bool)?

    init(
        versionString: String = "betterGI-mac",
        gameMetrics: [Double] = [1920, 1080, 1],
        avatars: [String] = [],
        genshinCommandHandler: GenshinCommandHandler? = nil,
        deadline: Date? = nil,
        isCancelled: (() -> Bool)? = nil
    ) {
        self.versionString = versionString
        self.gameMetrics = gameMetrics
        self.avatars = avatars
        self.genshinCommandHandler = genshinCommandHandler
        self.deadline = deadline
        self.isCancelled = isCancelled
    }

    /// Sleep with cancellation and deadline awareness.
    /// Uses short-tick loops of 50ms so that cancellation/timeout are checked
    /// frequently. Never blocks the calling thread for the full duration.
    func sleep(milliseconds: Int) {
        guard milliseconds > 0 else { return }

        let tickMs = 50
        var remaining = milliseconds
        let started = Date()

        while remaining > 0 {
            // Check Task cancellation.
            if isCancelled?() == true {
                return
            }
            // Check deadline.
            if let deadline, Date() >= deadline {
                return
            }
            let slice = min(tickMs, remaining)
            Thread.sleep(forTimeInterval: Double(slice) / 1000.0)
            // Time-based correctness: use elapsed, not the slice.
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            guard elapsed < milliseconds else { break }
            remaining = milliseconds - elapsed
        }
    }

    func performInputCommand(_ command: BGIJSScriptInputCommand) throws {
        inputCommands.append(command)
    }

    func captureGameRegion() throws -> BGIJSScriptCaptureRegion {
        let captureID = nextCaptureID()
        return BGIJSScriptCaptureRegion(
            id: captureID,
            width: gameMetrics[safe: 0] ?? 1920,
            height: gameMetrics[safe: 1] ?? 1080,
            dpi: gameMetrics[safe: 2] ?? 1,
            backendName: "Recording"
        )
    }

    func recognizeText(in region: BGIJSScriptCaptureRegion, roi: CGRect?) throws -> BGIJSScriptOCRResult {
        BGIJSScriptOCRResult.empty(for: region)
    }

    func recognizeTemplate(
        in region: BGIJSScriptCaptureRegion,
        locator: BGIJSScriptTemplateLocator
    ) throws -> [BGIJSScriptVisionRegion] {
        []
    }

    func recognizeObject(
        in region: BGIJSScriptCaptureRegion,
        object: RecognitionObject,
        findAll: Bool
    ) throws -> [BGIJSScriptVisionRegion] {
        []
    }

    func performGenshinCommand(_ command: BGIJSScriptGenshinCommand) throws -> BGIJSScriptGenshinResult {
        genshinCommands.append(command)
        if let genshinCommandHandler {
            return try genshinCommandHandler(command)
        }
        return BGIJSScriptGenshinResult()
    }

    func nextCaptureID() -> UInt64 {
        captureCount += 1
        return UInt64(captureCount)
    }
}

final class BGICapturingJSScriptHostEnvironment: BGIRecordingJSScriptHostEnvironment {
    typealias CaptureFrameProvider = () throws -> CaptureImageFrame
    typealias OCRProvider = (CaptureImageFrame, CGRect?) throws -> OCRResult
    typealias TemplateProvider = (CaptureImageFrame, BGIJSScriptTemplateLocator) throws -> [RecognitionObservation]
    typealias RecognitionObjectProvider = (CaptureImageFrame, RecognitionObject, Bool) throws -> [RecognitionObservation]
    typealias MiniMapLocalizationProvider = (CaptureImageFrame, CGPoint?, String?) throws -> BGIMiniMapLocalizationResult
    typealias MiniMapOrientationProvider = (CaptureImageFrame) throws -> BGIMiniMapOrientationEstimate
    typealias InputCommandHandler = (BGIJSScriptInputCommand) throws -> Void

    private let captureFrameProvider: CaptureFrameProvider
    private let ocrProvider: OCRProvider?
    private let templateProvider: TemplateProvider?
    private let recognitionObjectProvider: RecognitionObjectProvider?
    private let miniMapLocalizationProvider: MiniMapLocalizationProvider?
    private let miniMapOrientationProvider: MiniMapOrientationProvider?
    private let inputCommandHandler: InputCommandHandler?
    private let templateRecognitionEngine: TemplateMatchingRecognitionEngine
    private var framesByCaptureID: [UInt64: CaptureImageFrame] = [:]
    private var captureOrder: [UInt64] = []
    private let maximumStoredCaptures: Int

    init(
        versionString: String = "betterGI-mac",
        gameMetrics: [Double] = [1920, 1080, 1],
        avatars: [String] = [],
        maximumStoredCaptures: Int = 8,
        captureFrameProvider: @escaping CaptureFrameProvider,
        ocrProvider: OCRProvider? = nil,
        templateProvider: TemplateProvider? = nil,
        recognitionObjectProvider: RecognitionObjectProvider? = nil,
        miniMapLocalizationProvider: MiniMapLocalizationProvider? = nil,
        miniMapOrientationProvider: MiniMapOrientationProvider? = nil,
        inputCommandHandler: InputCommandHandler? = nil,
        templateRecognitionEngine: TemplateMatchingRecognitionEngine = TemplateMatchingRecognitionEngine(),
        deadline: Date? = nil,
        isCancelled: (() -> Bool)? = nil
    ) {
        self.captureFrameProvider = captureFrameProvider
        self.ocrProvider = ocrProvider
        self.templateProvider = templateProvider
        self.recognitionObjectProvider = recognitionObjectProvider
        self.miniMapLocalizationProvider = miniMapLocalizationProvider
        self.miniMapOrientationProvider = miniMapOrientationProvider
        self.inputCommandHandler = inputCommandHandler
        self.templateRecognitionEngine = templateRecognitionEngine
        self.maximumStoredCaptures = max(1, maximumStoredCaptures)
        super.init(versionString: versionString, gameMetrics: gameMetrics, avatars: avatars, deadline: deadline, isCancelled: isCancelled)
    }

    override func performInputCommand(_ command: BGIJSScriptInputCommand) throws {
        try super.performInputCommand(command)
        try inputCommandHandler?(command)
    }

    override func captureGameRegion() throws -> BGIJSScriptCaptureRegion {
        let imageFrame = try captureFrameProvider()
        let captureID = nextCaptureID()
        framesByCaptureID[captureID] = imageFrame
        captureOrder.append(captureID)
        pruneStoredCaptures()

        let metadata = imageFrame.metadata
        gameMetrics = [
            Double(metadata.width),
            Double(metadata.height),
            Double(metadata.scaleFactor)
        ]
        return BGIJSScriptCaptureRegion(
            id: captureID,
            width: Double(metadata.width),
            height: Double(metadata.height),
            dpi: Double(metadata.scaleFactor),
            backendName: imageFrame.backendName,
            frameIndex: metadata.frameIndex,
            timestamp: metadata.timestamp,
            pixelFormatName: metadata.pixelFormatName,
            bytesPerRow: metadata.bytesPerRow,
            sourceWindowID: metadata.sourceWindow.id,
            sourceWindowTitle: metadata.sourceWindow.title,
            captureRect: metadata.sourceWindow.captureRect
        )
    }

    override func recognizeText(in region: BGIJSScriptCaptureRegion, roi: CGRect?) throws -> BGIJSScriptOCRResult {
        guard let ocrProvider else {
            throw BGIJSScriptRuntimeError.ocrUnavailable
        }
        guard let imageFrame = framesByCaptureID[region.id] else {
            throw BGIJSScriptRuntimeError.missingCaptureFrame(region.id)
        }

        return try BGIJSScriptOCRResult(
            sourceCaptureID: region.id,
            result: ocrProvider(imageFrame, roi),
            roi: roi
        )
    }

    override func recognizeTemplate(
        in region: BGIJSScriptCaptureRegion,
        locator: BGIJSScriptTemplateLocator
    ) throws -> [BGIJSScriptVisionRegion] {
        guard let imageFrame = framesByCaptureID[region.id] else {
            throw BGIJSScriptRuntimeError.missingCaptureFrame(region.id)
        }

        let observations: [RecognitionObservation]
        if let templateProvider {
            observations = try templateProvider(imageFrame, locator)
        } else {
            let object = recognitionObject(for: locator, frame: imageFrame.metadata)
            observations = templateRecognitionEngine.recognize(
                imageFrame: imageFrame,
                objects: [object]
            ).observations
        }

        let regions = observations.map { observation in
            BGIJSScriptVisionRegion(
                x: observation.normalizedRect.minX * region.width,
                y: observation.normalizedRect.minY * region.height,
                width: observation.normalizedRect.width * region.width,
                height: observation.normalizedRect.height * region.height,
                text: observation.text,
                confidence: observation.confidence,
                objectID: observation.objectID,
                objectName: observation.objectName,
                recognitionType: observation.recognitionType
            )
        }
        return locator.findAll ? regions : Array(regions.prefix(1))
    }

    override func recognizeObject(
        in region: BGIJSScriptCaptureRegion,
        object: RecognitionObject,
        findAll: Bool
    ) throws -> [BGIJSScriptVisionRegion] {
        guard let imageFrame = framesByCaptureID[region.id] else {
            throw BGIJSScriptRuntimeError.missingCaptureFrame(region.id)
        }

        let observations: [RecognitionObservation]
        if let recognitionObjectProvider {
            observations = try recognitionObjectProvider(imageFrame, object, findAll)
        } else if object.recognitionType == .templateMatch {
            observations = templateRecognitionEngine.recognize(
                imageFrame: imageFrame,
                objects: [object]
            ).observations
        } else if let ocrProvider, object.recognitionType == .ocr || object.recognitionType == .ocrMatch {
            let roi = object.regionOfInterest.map { roi in
                CGRect(
                    x: roi.normalizedRect().minX * Double(imageFrame.metadata.width),
                    y: roi.normalizedRect().minY * Double(imageFrame.metadata.height),
                    width: roi.normalizedRect().width * Double(imageFrame.metadata.width),
                    height: roi.normalizedRect().height * Double(imageFrame.metadata.height)
                )
            }
            let result = try ocrProvider(imageFrame, roi)
            observations = result.regions.map { ocrRegion in
                RecognitionObservation(
                    id: "\(object.id)-\(imageFrame.metadata.frameIndex)-\(ocrRegion.id)",
                    objectID: object.id,
                    objectName: object.name ?? object.id,
                    recognitionType: object.recognitionType,
                    normalizedRect: CGRect(
                        x: ocrRegion.boundingBox.minX / CGFloat(imageFrame.metadata.width),
                        y: ocrRegion.boundingBox.minY / CGFloat(imageFrame.metadata.height),
                        width: ocrRegion.boundingBox.width / CGFloat(imageFrame.metadata.width),
                        height: ocrRegion.boundingBox.height / CGFloat(imageFrame.metadata.height)
                    ),
                    confidence: Double(ocrRegion.confidence),
                    text: ocrRegion.text,
                    frameIndex: imageFrame.metadata.frameIndex,
                    timestamp: imageFrame.metadata.timestamp
                )
            }
        } else {
            return []
        }

        let regions = observations.map { observation in
            BGIJSScriptVisionRegion(
                x: observation.normalizedRect.minX * region.width,
                y: observation.normalizedRect.minY * region.height,
                width: observation.normalizedRect.width * region.width,
                height: observation.normalizedRect.height * region.height,
                text: observation.text,
                confidence: observation.confidence,
                objectID: observation.objectID,
                objectName: observation.objectName,
                recognitionType: observation.recognitionType
            )
        }
        return findAll ? regions : Array(regions.prefix(1))
    }

    override func performGenshinCommand(_ command: BGIJSScriptGenshinCommand) throws -> BGIJSScriptGenshinResult {
        recordGenshinCommand(command)
        switch command {
        case .getBigMapZoomLevel, .getPositionFromMap, .getCameraOrientation:
            break
        default:
            if let genshinCommandHandler {
                return try genshinCommandHandler(command)
            }
            return BGIJSScriptGenshinResult()
        }

        // Map commands must use a fresh capture each time (upstream GetPositionFromMap / GetCameraOrientation
        // execute their own CaptureToRectArea).  Using the stored currentFrame() would return stale data.
        // FIXME: If the JS callback runs on @MainActor, the semaphore inside captureFrameProvider will
        //        deadlock.  Long-term fix is to maintain a LatestFrameStore fed by ScreenCaptureKit's
        //        continuous stream, then read synchronously without semaphore bridging.
        let imageFrame = try captureFrameProvider()

        switch command {
        case .getBigMapZoomLevel:
            let status = BGIGameUIStatusRecognizer(templateEngine: templateRecognitionEngine)
                .recognize(imageFrame)
            guard status.isInBigMapUI, let scale = status.bigMapScaleFraction else {
                throw BGIJSScriptRuntimeError.bigMapUIUnavailable
            }
            return BGIJSScriptGenshinResult(doubleValue: BGIBigMapInteractionService.zoomLevel(fromScaleFraction: scale))
        case let .getPositionFromMap(mapName, _, _, nearX, nearY):
            guard let miniMapLocalizationProvider else {
                throw BGIJSScriptRuntimeError.miniMapLocalizationUnavailable
            }
            let near: CGPoint? = (nearX != nil && nearY != nil) ? CGPoint(x: nearX!, y: nearY!) : nil
            let result = try miniMapLocalizationProvider(imageFrame, near, mapName)
            return BGIJSScriptGenshinResult(point: result.worldPoint)
        case .getCameraOrientation:
            guard let miniMapOrientationProvider else {
                throw BGIJSScriptRuntimeError.miniMapOrientationUnavailable
            }
            let result = try miniMapOrientationProvider(imageFrame)
            return BGIJSScriptGenshinResult(doubleValue: result.degrees)
        default:
            fatalError("Unexpected genshin command handled in switch: \(command)")
        }
    }

    private func currentCaptureID() -> UInt64 {
        captureOrder.last ?? 0
    }

    private func currentFrame() -> CaptureImageFrame? {
        framesByCaptureID[currentCaptureID()]
    }

    private func recognitionObject(
        for locator: BGIJSScriptTemplateLocator,
        frame: CapturedFrame
    ) -> RecognitionObject {
        RecognitionObject(
            id: locator.templateAssetName,
            recognitionType: .templateMatch,
            regionOfInterest: locator.roi.map { roi in
                RecognitionROI(
                    x: roi.minX / max(1, Double(frame.width)),
                    y: roi.minY / max(1, Double(frame.height)),
                    width: roi.width / max(1, Double(frame.width)),
                    height: roi.height / max(1, Double(frame.height)),
                    coordinateSpace: .normalized
                )
            },
            name: locator.templateAssetName,
            templateAssetName: locator.templateAssetName,
            threshold: locator.threshold,
            maxMatchCount: locator.findAll ? 8 : 1
        )
    }

    private func pruneStoredCaptures() {
        while captureOrder.count > maximumStoredCaptures {
            let removed = captureOrder.removeFirst()
            framesByCaptureID.removeValue(forKey: removed)
        }
    }
}

final class BGIInputDispatchingJSScriptHostEnvironment: BGIRecordingJSScriptHostEnvironment {
    private let targetWindow: WindowInfo
    private let dispatcher: CGEventInputDispatcher

    init(
        targetWindow: WindowInfo,
        dispatcher: CGEventInputDispatcher = CGEventInputDispatcher(),
        versionString: String = "betterGI-mac",
        gameMetrics: [Double] = [1920, 1080, 1],
        avatars: [String] = []
    ) {
        self.targetWindow = targetWindow
        self.dispatcher = dispatcher
        super.init(versionString: versionString, gameMetrics: gameMetrics, avatars: avatars)
    }

    override func performInputCommand(_ command: BGIJSScriptInputCommand) throws {
        try super.performInputCommand(command)
        guard let action = inputAction(for: command) else { return }
        _ = try dispatcher.perform(action, targetWindow: targetWindow)
    }

    private func inputAction(for command: BGIJSScriptInputCommand) -> InputAction? {
        switch command {
        case let .keyDown(key):
            .keyDown(key: key)
        case let .keyUp(key):
            .keyUp(key: key)
        case let .keyPress(key):
            .keyPress(key: key)
        case let .mouseMoveBy(dx, dy):
            .mouseMove(to: currentMousePoint().applying(CGAffineTransform(translationX: dx, y: dy)))
        case let .mouseMoveToGame(x, y):
            .mouseMove(to: screenPointForGamePoint(x: x, y: y))
        case let .mouseClickGame(button, x, y):
            .mouseClick(button: button, at: screenPointForGamePoint(x: x, y: y))
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

    private func currentMousePoint() -> CGPoint {
        CGEvent(source: nil)?.location
            ?? CGPoint(x: targetWindow.captureRect.midX, y: targetWindow.captureRect.midY)
    }

    private func screenPointForGamePoint(x: Double, y: Double) -> CGPoint {
        let width = max(1, gameMetrics[safe: 0] ?? 1920)
        let height = max(1, gameMetrics[safe: 1] ?? 1080)
        let rect = targetWindow.captureRect
        return CGPoint(
            x: rect.minX + CGFloat(x / width) * rect.width,
            y: rect.minY + CGFloat(y / height) * rect.height
        )
    }
}

final class BGIInstalledJSScriptProjectLoader {
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

    func loadProject(folderName: String) throws -> BGIJSScriptProject {
        let normalizedFolderName = try normalizeRelativePath(folderName)
        let projectURL = store.userURL
            .appendingPathComponent("JsScript", isDirectory: true)
            .appendingPathComponent(normalizedFolderName, isDirectory: true)
        return try loadProject(at: projectURL, folderName: normalizedFolderName)
    }

    func loadProject(at projectURL: URL, folderName: String? = nil) throws -> BGIJSScriptProject {
        guard isDirectory(projectURL) else {
            throw BGIJSScriptRuntimeError.missingProjectDirectory(projectURL)
        }

        let manifestURL = projectURL.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw BGIJSScriptRuntimeError.missingManifest(manifestURL)
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try decoder.decode(BGIJSScriptManifest.self, from: manifestData)
        guard !manifest.name.isEmpty else {
            throw BGIJSScriptRuntimeError.invalidManifest("manifest.json: name is required.")
        }
        guard !manifest.version.isEmpty else {
            throw BGIJSScriptRuntimeError.invalidManifest("manifest.json: version is required.")
        }
        guard !manifest.main.isEmpty else {
            throw BGIJSScriptRuntimeError.invalidManifest("manifest.json: main script is required.")
        }

        let mainScriptURL = projectURL.appendingPathComponent(manifest.main)
        guard fileManager.fileExists(atPath: mainScriptURL.path) else {
            throw BGIJSScriptRuntimeError.missingMainScript(manifest.main)
        }

        let settings = try loadSettings(projectURL: projectURL, manifest: manifest)
        let resolvedFolderName = folderName ?? projectURL.lastPathComponent
        return BGIJSScriptProject(
            folderName: resolvedFolderName,
            repositoryPath: "js/\(resolvedFolderName)",
            projectURL: projectURL,
            manifest: manifest,
            settings: settings,
            mainScriptURL: mainScriptURL
        )
    }

    private func loadSettings(projectURL: URL, manifest: BGIJSScriptManifest) throws -> [BGIJSScriptSettingItem] {
        guard let settingsUI = manifest.settingsUI, !settingsUI.isEmpty else {
            return []
        }

        let settingsURL = projectURL.appendingPathComponent(settingsUI)
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            throw BGIScriptRepositoryCatalogLoaderError.missingSettingsFile(settingsUI)
        }

        let settingsData = try Data(contentsOf: settingsURL)
        return try decoder.decode([BGIJSScriptSettingItem].self, from: settingsData)
    }

    private func normalizeRelativePath(_ path: String) throws -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty,
              !normalized.hasPrefix("/"),
              !parts.contains("."),
              !parts.contains("..") else {
            throw BGIJSScriptRuntimeError.unsafePath(path)
        }
        return parts.joined(separator: "/")
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

final class BGIJSScriptPackageDocumentLoader {
    private let projectURL: URL
    private let fileManager: FileManager

    init(projectURL: URL, fileManager: FileManager = .default) {
        self.projectURL = projectURL.standardizedFileURL
        self.fileManager = fileManager
    }

    func searchPathURLs(for manifest: BGIJSScriptManifest) throws -> [URL] {
        var libraries = manifest.library
        libraries.append(".")
        libraries.append("./packages")

        var seen = Set<String>()
        var urls: [URL] = []
        for library in libraries {
            let url = try normalizeScriptPath(library)
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    func loadModule(
        specifier: String,
        referrerPath: String,
        searchPathURLs: [URL]
    ) throws -> BGIJSScriptLoadedModule {
        guard let moduleURL = resolvePath(specifier: specifier, referrerPath: referrerPath, searchPathURLs: searchPathURLs) else {
            throw BGIJSScriptRuntimeError.moduleNotFound(specifier)
        }
        guard moduleURL.pathExtension.caseInsensitiveCompare("js") == .orderedSame else {
            throw BGIJSScriptRuntimeError.unsupportedModule(specifier)
        }

        let content = try String(contentsOf: moduleURL, encoding: .utf8)
        let rewrittenCode = try rewriteScriptCode(content, currentFileURL: moduleURL)
        let compiledCode = transformESModuleSyntax(rewrittenCode)
        return BGIJSScriptLoadedModule(filename: moduleURL.standardizedFileURL.path, code: compiledCode)
    }

    func loadMainModule(project: BGIJSScriptProject) throws -> BGIJSScriptLoadedModule {
        let code = try String(contentsOf: project.mainScriptURL, encoding: .utf8)
        guard !code.isEmpty else {
            throw BGIJSScriptRuntimeError.emptyMainScript(project.mainScriptURL)
        }

        let rewrittenCode = try rewriteScriptCode(code, currentFileURL: project.mainScriptURL)
        return BGIJSScriptLoadedModule(
            filename: project.mainScriptURL.standardizedFileURL.path,
            code: transformESModuleSyntax(rewrittenCode)
        )
    }

    func rewriteScriptCode(_ code: String, currentFileURL: URL) throws -> String {
        guard !code.isEmpty else { return code }

        var result = code.replacingOccurrences(of: "../../../packages", with: "packages")
        let regex = try NSRegularExpression(
            pattern: #"import\s+([\w\d_*$]+|[\s\S]*?)\s+from\s+(['"])([^'"\n]+)(['"])"#,
            options: []
        )
        let matches = regex.matches(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result)
        ).reversed()

        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: result),
                  let importRange = Range(match.range(at: 1), in: result),
                  let quoteRange = Range(match.range(at: 2), in: result),
                  let pathRange = Range(match.range(at: 3), in: result) else {
                continue
            }

            let importPart = result[importRange].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !importPart.hasPrefix("{") else { continue }

            let quote = String(result[quoteRange])
            let importPath = result[pathRange].replacingOccurrences(of: "../../../packages", with: "packages")
            guard let resourceURL = resolvePath(
                specifier: importPath,
                referrerPath: currentFileURL.path,
                searchPathURLs: []
            ),
                fileManager.fileExists(atPath: resourceURL.path),
                resourceURL.pathExtension.caseInsensitiveCompare("js") != .orderedSame else {
                continue
            }

            let normalizedPath = try relativePath(of: resourceURL, from: projectURL)
            let replacement: String
            if isImageFile(resourceURL) {
                replacement = "const \(importPart) = file.ReadImageMatSync(\(quote)\(normalizedPath)\(quote));"
            } else {
                replacement = "const \(importPart) = file.ReadTextSync(\(quote)\(normalizedPath)\(quote));"
            }
            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    func resolvePath(
        specifier: String,
        referrerPath: String,
        searchPathURLs: [URL]
    ) -> URL? {
        let normalizedSpecifier = specifier.replacingOccurrences(of: "\\", with: "/")
        if normalizedSpecifier.hasPrefix("packages/") {
            return probeFile(projectURL.appendingPathComponent(normalizedSpecifier))
        }

        if let packagesRange = normalizedSpecifier.range(
            of: #"^(?:\.\./)+(packages/.*)$"#,
            options: .regularExpression
        ) {
            let packagePath = String(normalizedSpecifier[packagesRange])
                .replacingOccurrences(
                    of: #"^(?:\.\./)+"#,
                    with: "",
                    options: .regularExpression
                )
            return probeFile(projectURL.appendingPathComponent(packagePath))
        }

        if normalizedSpecifier.hasPrefix(".") {
            let referrerURL = URL(fileURLWithPath: referrerPath)
            let candidate = referrerURL
                .deletingLastPathComponent()
                .appendingPathComponent(normalizedSpecifier)
                .standardizedFileURL
            if let found = probeFile(candidate) {
                return found
            }
        }

        for searchPathURL in searchPathURLs {
            if let found = probeFile(searchPathURL.appendingPathComponent(normalizedSpecifier)) {
                return found
            }
        }

        return probeFile(projectURL.appendingPathComponent(normalizedSpecifier))
    }

    func transformESModuleSyntax(_ code: String) -> String {
        var result = code
        var exportNames: [(local: String, exported: String)] = []

        result = replaceMatches(
            pattern: #"import\s+\*\s+as\s+([A-Za-z_$][\w$]*)\s+from\s+['"]([^'"\n]+)['"];?"#,
            in: result
        ) { match, source in
            let name = source[match.range(at: 1)]
            let specifier = source[match.range(at: 2)]
            return "const \(name) = __bgi_require__(\"\(escapeForJavaScript(specifier))\", __filename);"
        }

        result = replaceMatches(
            pattern: #"import\s+\{([^}]+)\}\s+from\s+['"]([^'"\n]+)['"];?"#,
            in: result
        ) { match, source in
            let importList = source[match.range(at: 1)]
            let specifier = source[match.range(at: 2)]
            return "const { \(rewriteImportList(importList)) } = __bgi_require__(\"\(escapeForJavaScript(specifier))\", __filename);"
        }

        result = replaceMatches(
            pattern: #"import\s+([A-Za-z_$][\w$]*)\s+from\s+['"]([^'"\n]+)['"];?"#,
            in: result
        ) { match, source in
            let name = source[match.range(at: 1)]
            let specifier = source[match.range(at: 2)]
            return "const \(name) = __bgi_require__(\"\(escapeForJavaScript(specifier))\", __filename).default;"
        }

        result = replaceMatches(
            pattern: #"import\s+['"]([^'"\n]+)['"];?"#,
            in: result
        ) { match, source in
            let specifier = source[match.range(at: 1)]
            return "__bgi_require__(\"\(escapeForJavaScript(specifier))\", __filename);"
        }

        result = replaceMatches(
            pattern: #"export\s+async\s+function\s+([A-Za-z_$][\w$]*)\s*\("#,
            in: result
        ) { match, source in
            let name = source[match.range(at: 1)]
            exportNames.append((name, name))
            return "async function \(name)("
        }

        result = replaceMatches(
            pattern: #"export\s+function\s+([A-Za-z_$][\w$]*)\s*\("#,
            in: result
        ) { match, source in
            let name = source[match.range(at: 1)]
            exportNames.append((name, name))
            return "function \(name)("
        }

        result = replaceMatches(
            pattern: #"export\s+(const|let|var)\s+([A-Za-z_$][\w$]*)\s*="#,
            in: result
        ) { match, source in
            let kind = source[match.range(at: 1)]
            let name = source[match.range(at: 2)]
            exportNames.append((name, name))
            return "\(kind) \(name) ="
        }

        result = replaceMatches(
            pattern: #"export\s+default\s+function\s+([A-Za-z_$][\w$]*)\s*\("#,
            in: result
        ) { match, source in
            let name = source[match.range(at: 1)]
            exportNames.append((name, "default"))
            return "function \(name)("
        }

        result = replaceMatches(
            pattern: #"export\s+default\s+"#,
            in: result
        ) { _, _ in
            "exports.default = "
        }

        result = replaceMatches(
            pattern: #"export\s+\{([^}]+)\};?"#,
            in: result
        ) { match, source in
            let exportList = source[match.range(at: 1)]
            return rewriteExportList(exportList)
        }

        if !exportNames.isEmpty {
            let appendedExports = exportNames
                .map { "exports.\($0.exported) = \($0.local);" }
                .joined(separator: "\n")
            result += "\n\(appendedExports)\n"
        }

        return result
    }

    private func normalizeScriptPath(_ path: String) throws -> URL {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let url = projectURL.appendingPathComponent(normalized).standardizedFileURL
        _ = try relativePath(of: url, from: projectURL)
        return url
    }

    private func probeFile(_ url: URL) -> URL? {
        let normalized = url.standardizedFileURL
        guard isInsideProject(normalized) else { return nil }
        if isFile(normalized) {
            return normalized
        }

        let jsURL = URL(fileURLWithPath: normalized.path + ".js").standardizedFileURL
        guard isInsideProject(jsURL) else { return nil }
        if isFile(jsURL) {
            return jsURL
        }
        return nil
    }

    private func relativePath(of url: URL, from baseURL: URL) throws -> String {
        let basePath = baseURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == basePath || path.hasPrefix(basePath + "/") else {
            throw BGIJSScriptRuntimeError.unsafePath(path)
        }
        if path == basePath { return "" }
        return String(path.dropFirst(basePath.count + 1)).replacingOccurrences(of: "\\", with: "/")
    }

    /// Safe path containment check — resolves symlinks before comparing.
    /// Symlinks pointing outside `projectURL` are rejected.
    private func isInsideProject(_ url: URL) -> Bool {
        let basePath = projectURL.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        return resolvedPath == basePath || resolvedPath.hasPrefix(basePath + "/")
    }

    private func isFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private func isImageFile(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "bmp", "tiff", "webp"].contains(url.pathExtension.lowercased())
    }

    private func replaceMatches(
        pattern: String,
        in source: String,
        replacement: (NSTextCheckingResult, String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return source }
        var result = source
        let matches = regex.matches(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result)
        ).reversed()
        for match in matches {
            guard let range = Range(match.range(at: 0), in: result) else { continue }
            result.replaceSubrange(range, with: replacement(match, result))
        }
        return result
    }

    private func rewriteImportList(_ importList: String) -> String {
        importList
            .split(separator: ",")
            .map { item in
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = trimmed.components(separatedBy: " as ")
                if parts.count == 2 {
                    return "\(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)): \(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))"
                }
                return trimmed
            }
            .joined(separator: ", ")
    }

    private func rewriteExportList(_ exportList: String) -> String {
        exportList
            .split(separator: ",")
            .map { item in
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = trimmed.components(separatedBy: " as ")
                if parts.count == 2 {
                    let local = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let exported = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    return "exports.\(exported) = \(local);"
                }
                return "exports.\(trimmed) = \(trimmed);"
            }
            .joined(separator: "\n")
    }

    private func escapeForJavaScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

struct BGIJSScriptLoadedModule: Equatable, Sendable {
    let filename: String
    let code: String
}

final class BGIJSScriptRunner {
    private let fileManager: FileManager
    private let hostEnvironment: BGIJSScriptHostEnvironment

    init(fileManager: FileManager = .default, versionString: String = "betterGI-mac") {
        self.fileManager = fileManager
        hostEnvironment = BGIRecordingJSScriptHostEnvironment(versionString: versionString)
    }

    init(fileManager: FileManager = .default, hostEnvironment: BGIJSScriptHostEnvironment) {
        self.fileManager = fileManager
        self.hostEnvironment = hostEnvironment
    }

    func execute(
        project: BGIJSScriptProject,
        settingsJSON: String = "{}"
    ) throws -> BGIJSScriptExecutionResult {
        let loader = BGIJSScriptPackageDocumentLoader(projectURL: project.projectURL, fileManager: fileManager)
        let searchPathURLs = try loader.searchPathURLs(for: project.manifest)
        let mainModule = try loader.loadMainModule(project: project)
        let recorder = BGIJSScriptExecutionRecorder(
            projectURL: project.projectURL,
            hostEnvironment: hostEnvironment
        )

        guard let context = JSContext() else {
            throw BGIJSScriptRuntimeError.scriptException("Unable to create JavaScriptCore context.")
        }
        var scriptException: String?
        context.exceptionHandler = { _, exception in
            scriptException = exception?.toString()
        }

        installRuntime(on: context)
        installHostObjects(on: context, recorder: recorder)
        installModuleLoader(on: context, loader: loader, searchPathURLs: searchPathURLs, recorder: recorder)

        let settingsScript = "var settings = \(settingsJSON.isEmpty ? "{}" : settingsJSON);"
        context.evaluateScript(settingsScript)
        if let scriptException {
            throw BGIJSScriptRuntimeError.scriptException(scriptException)
        }

        let escapedFilename = escapeForJavaScript(mainModule.filename)
        let escapedCode = escapeForJavaScript(mainModule.code)
        context.evaluateScript("__bgi_run_main(\"\(escapedFilename)\", \"\(escapedCode)\");")
        if let scriptException {
            throw BGIJSScriptRuntimeError.scriptException(scriptException)
        }
        if let hostError = recorder.hostError {
            throw BGIJSScriptRuntimeError.scriptException(hostError)
        }

        return BGIJSScriptExecutionResult(
            projectURL: project.projectURL,
            mainScriptURL: project.mainScriptURL,
            loadedModulePaths: recorder.loadedModulePaths,
            logs: recorder.logs,
            hostCalls: recorder.hostCalls,
            captureRegions: recorder.captureRegions,
            ocrResults: recorder.ocrResults,
            templateMatchRegions: recorder.templateMatchRegions,
            inputCommands: recorder.inputCommands,
            genshinCommands: recorder.genshinCommands
        )
    }

    private func installRuntime(on context: JSContext) {
        context.evaluateScript(
            """
            var __bgi_module_cache = Object.create(null);
            function __bgi_dirname(path) {
                var index = path.lastIndexOf('/');
                return index >= 0 ? path.slice(0, index) : '';
            }
            function __bgi_require__(specifier, referrer) {
                var record = __bgi_load_module(String(specifier), String(referrer || ""));
                if (record.error) {
                    throw new Error(record.error);
                }
                var filename = String(record.filename);
                if (__bgi_module_cache[filename]) {
                    return __bgi_module_cache[filename].exports;
                }
                var module = { exports: {} };
                __bgi_module_cache[filename] = module;
                var fn = new Function("exports", "module", "__filename", "__dirname", "__bgi_require__", record.code + "\\n//# sourceURL=" + filename);
                fn(module.exports, module, filename, __bgi_dirname(filename), function(childSpecifier) {
                    return __bgi_require__(childSpecifier, filename);
                });
                return module.exports;
            }
            function __bgi_run_main(filename, code) {
                var module = { exports: {} };
                var fn = new Function("exports", "module", "__filename", "__dirname", "__bgi_require__", code + "\\n//# sourceURL=" + filename);
                fn(module.exports, module, filename, __bgi_dirname(filename), function(childSpecifier) {
                    return __bgi_require__(childSpecifier, filename);
                });
                return module.exports;
            }
            """
        )
    }

    private func installModuleLoader(
        on context: JSContext,
        loader: BGIJSScriptPackageDocumentLoader,
        searchPathURLs: [URL],
        recorder: BGIJSScriptExecutionRecorder
    ) {
        let loadModule: @convention(block) (String, String) -> NSDictionary = { specifier, referrerPath in
            do {
                let module = try loader.loadModule(
                    specifier: specifier,
                    referrerPath: referrerPath,
                    searchPathURLs: searchPathURLs
                )
                recorder.loadedModulePaths.append(module.filename)
                return [
                    "filename": module.filename,
                    "code": module.code
                ]
            } catch {
                return [
                    "error": error.localizedDescription
                ]
            }
        }
        context.setObject(loadModule, forKeyedSubscript: "__bgi_load_module" as NSString)
    }

    private func installHostObjects(on context: JSContext, recorder: BGIJSScriptExecutionRecorder) {
        installLogging(on: context, recorder: recorder)
        installFileBridge(on: context, recorder: recorder)
        installGlobalMethods(on: context, recorder: recorder)
        installBgiVisionBridge(on: context)
        installGenshinBridge(on: context, recorder: recorder)
    }

    private func installLogging(on context: JSContext, recorder: BGIJSScriptExecutionRecorder) {
        let logObject = JSValue(newObjectIn: context)
        for level in ["debug", "info", "warn", "error"] {
            let block: @convention(block) (JSValue) -> Void = { value in
                recorder.logs.append("[\(level)] \(value.toString() ?? "")")
            }
            logObject?.setObject(block, forKeyedSubscript: level as NSString)
        }
        context.setObject(logObject, forKeyedSubscript: "log" as NSString)
    }

    private func installFileBridge(on context: JSContext, recorder: BGIJSScriptExecutionRecorder) {
        let fileObject = JSValue(newObjectIn: context)
        let readTextSync: @convention(block) (String) -> String = { path in
            recorder.record("file.ReadTextSync", [path])
            return (try? recorder.readText(path)) ?? ""
        }
        let writeTextSync: @convention(block) (String, String, Bool) -> Bool = { path, content, append in
            recorder.record("file.WriteTextSync", [path, append.description])
            return ((try? recorder.writeText(path, content: content, append: append)) != nil)
        }
        let isExists: @convention(block) (String) -> Bool = { path in
            recorder.record("file.IsExists", [path])
            return recorder.fileExists(path)
        }
        let isFile: @convention(block) (String) -> Bool = { path in
            recorder.record("file.IsFile", [path])
            return recorder.isFile(path)
        }
        let isFolder: @convention(block) (String) -> Bool = { path in
            recorder.record("file.IsFolder", [path])
            return recorder.isDirectory(path)
        }
        let createDirectory: @convention(block) (String) -> Bool = { path in
            recorder.record("file.CreateDirectory", [path])
            return ((try? recorder.createDirectory(path)) != nil)
        }
        let readPathSync: @convention(block) (String) -> [String] = { path in
            recorder.record("file.ReadPathSync", [path])
            return (try? recorder.readPath(path)) ?? []
        }
        let readImageMatSync: @convention(block) (String) -> String = { path in
            recorder.record("file.ReadImageMatSync", [path])
            return (try? recorder.readImageBase64(path)) ?? ""
        }

        for key in ["ReadTextSync", "readTextSync"] {
            fileObject?.setObject(readTextSync, forKeyedSubscript: key as NSString)
        }
        for key in ["WriteTextSync", "writeTextSync"] {
            fileObject?.setObject(writeTextSync, forKeyedSubscript: key as NSString)
        }
        for key in ["IsExists", "isExists"] {
            fileObject?.setObject(isExists, forKeyedSubscript: key as NSString)
        }
        for key in ["IsFile", "isFile"] {
            fileObject?.setObject(isFile, forKeyedSubscript: key as NSString)
        }
        for key in ["IsFolder", "isFolder"] {
            fileObject?.setObject(isFolder, forKeyedSubscript: key as NSString)
        }
        for key in ["CreateDirectory", "createDirectory"] {
            fileObject?.setObject(createDirectory, forKeyedSubscript: key as NSString)
        }
        for key in ["ReadPathSync", "readPathSync"] {
            fileObject?.setObject(readPathSync, forKeyedSubscript: key as NSString)
        }
        for key in ["ReadImageMatSync", "readImageMatSync"] {
            fileObject?.setObject(readImageMatSync, forKeyedSubscript: key as NSString)
        }
        context.setObject(fileObject, forKeyedSubscript: "file" as NSString)
    }

    private func installGlobalMethods(on context: JSContext, recorder: BGIJSScriptExecutionRecorder) {
        let sleep: @convention(block) (Int) -> Void = { milliseconds in
            recorder.record("sleep", [String(milliseconds)])
            recorder.sleep(milliseconds: milliseconds)
        }
        let getVersion: @convention(block) () -> String = {
            recorder.record("getVersion", [])
            return recorder.versionString
        }
        let keyDown: @convention(block) (String) -> Void = { key in recorder.performKeyInput(name: "keyDown", key: key) }
        let keyUp: @convention(block) (String) -> Void = { key in recorder.performKeyInput(name: "keyUp", key: key) }
        let keyPress: @convention(block) (String) -> Void = { key in recorder.performKeyInput(name: "keyPress", key: key) }
        let setGameMetrics: @convention(block) (Double, Double, Double) -> Void = { width, height, dpi in
            recorder.record("setGameMetrics", [String(width), String(height), String(dpi)])
            recorder.setGameMetrics(width: width, height: height, dpi: dpi)
        }
        let getGameMetrics: @convention(block) () -> [Double] = {
            recorder.record("getGameMetrics", [])
            return recorder.gameMetrics
        }
        let moveMouseBy: @convention(block) (Double, Double) -> Void = { x, y in
            recorder.performInputCommand(.mouseMoveBy(dx: x, dy: y), name: "moveMouseBy", arguments: [String(x), String(y)])
        }
        let moveMouseTo: @convention(block) (Double, Double) -> Void = { x, y in
            recorder.performInputCommand(.mouseMoveToGame(x: x, y: y), name: "moveMouseTo", arguments: [String(x), String(y)])
        }
        let click: @convention(block) (Double, Double) -> Void = { x, y in
            recorder.performInputCommand(.mouseClickGame(button: .left, x: x, y: y), name: "click", arguments: [String(x), String(y)])
        }
        let noArgMouse: (String) -> @convention(block) () -> Void = { name in
            {
                guard let command = BGIJSScriptInputCommand.mouseCommand(named: name) else {
                    recorder.record(name, [])
                    return
                }
                recorder.performInputCommand(command, name: name, arguments: [])
            }
        }
        let verticalScroll: @convention(block) (Int) -> Void = { amount in
            recorder.performInputCommand(.verticalScroll(amount), name: "verticalScroll", arguments: [String(amount)])
        }
        let captureGameRegion: @convention(block) () -> JSValue? = {
            recorder.record("captureGameRegion", [])
            let region = recorder.captureGameRegion()
            return self.captureRegionObject(region, on: context, recorder: recorder)
        }
        let getAvatars: @convention(block) () -> [String] = {
            recorder.record("getAvatars", [])
            return recorder.avatars
        }
        let inputText: @convention(block) (String) -> Void = { text in
            recorder.performInputCommand(.inputText(text), name: "inputText", arguments: [text])
        }
        let findTemplate: @convention(block) (String, JSValue?, Double, Bool) -> [NSDictionary] = { templateAssetName, roiValue, threshold, findAll in
            let region = recorder.captureGameRegion()
            let roi = self.ocrRegionOfInterest(from: [roiValue])
            let locator = BGIJSScriptTemplateLocator(
                templateAssetName: templateAssetName,
                roi: roi,
                threshold: threshold,
                findAll: findAll
            )
            var arguments = [String(region.id), templateAssetName, String(threshold), findAll.description]
            if let roi {
                arguments.append(self.roiDescription(roi))
            }
            recorder.record("BvLocator.FindAll.Template", arguments)
            return recorder.recognizeTemplate(in: region, locator: locator).map(self.visionRegionDictionary)
        }

        context.setObject(sleep, forKeyedSubscript: "sleep" as NSString)
        context.setObject(getVersion, forKeyedSubscript: "getVersion" as NSString)
        context.setObject(keyDown, forKeyedSubscript: "keyDown" as NSString)
        context.setObject(keyUp, forKeyedSubscript: "keyUp" as NSString)
        context.setObject(keyPress, forKeyedSubscript: "keyPress" as NSString)
        context.setObject(setGameMetrics, forKeyedSubscript: "setGameMetrics" as NSString)
        context.setObject(getGameMetrics, forKeyedSubscript: "getGameMetrics" as NSString)
        context.setObject(moveMouseBy, forKeyedSubscript: "moveMouseBy" as NSString)
        context.setObject(moveMouseTo, forKeyedSubscript: "moveMouseTo" as NSString)
        context.setObject(click, forKeyedSubscript: "click" as NSString)
        context.setObject(noArgMouse("leftButtonClick"), forKeyedSubscript: "leftButtonClick" as NSString)
        context.setObject(noArgMouse("leftButtonDown"), forKeyedSubscript: "leftButtonDown" as NSString)
        context.setObject(noArgMouse("leftButtonUp"), forKeyedSubscript: "leftButtonUp" as NSString)
        context.setObject(noArgMouse("rightButtonClick"), forKeyedSubscript: "rightButtonClick" as NSString)
        context.setObject(noArgMouse("rightButtonDown"), forKeyedSubscript: "rightButtonDown" as NSString)
        context.setObject(noArgMouse("rightButtonUp"), forKeyedSubscript: "rightButtonUp" as NSString)
        context.setObject(noArgMouse("middleButtonClick"), forKeyedSubscript: "middleButtonClick" as NSString)
        context.setObject(noArgMouse("middleButtonDown"), forKeyedSubscript: "middleButtonDown" as NSString)
        context.setObject(noArgMouse("middleButtonUp"), forKeyedSubscript: "middleButtonUp" as NSString)
        context.setObject(verticalScroll, forKeyedSubscript: "verticalScroll" as NSString)
        context.setObject(captureGameRegion, forKeyedSubscript: "captureGameRegion" as NSString)
        context.setObject(getAvatars, forKeyedSubscript: "getAvatars" as NSString)
        context.setObject(inputText, forKeyedSubscript: "inputText" as NSString)
        context.setObject(findTemplate, forKeyedSubscript: "__bgi_find_template" as NSString)
    }

    private func captureRegionObject(
        _ region: BGIJSScriptCaptureRegion,
        on context: JSContext,
        recorder: BGIJSScriptExecutionRecorder
    ) -> JSValue? {
        let object = JSValue(newObjectIn: context)
        object?.setObject(region.id, forKeyedSubscript: "id" as NSString)
        object?.setObject(region.id, forKeyedSubscript: "captureId" as NSString)
        object?.setObject(region.width, forKeyedSubscript: "width" as NSString)
        object?.setObject(region.height, forKeyedSubscript: "height" as NSString)
        object?.setObject(region.dpi, forKeyedSubscript: "dpi" as NSString)
        object?.setObject(region.backendName, forKeyedSubscript: "backendName" as NSString)
        if let frameIndex = region.frameIndex {
            object?.setObject(frameIndex, forKeyedSubscript: "frameIndex" as NSString)
        }
        if let timestamp = region.timestamp {
            object?.setObject(timestamp.timeIntervalSince1970, forKeyedSubscript: "timestamp" as NSString)
        }
        if let pixelFormatName = region.pixelFormatName {
            object?.setObject(pixelFormatName, forKeyedSubscript: "pixelFormat" as NSString)
            object?.setObject(pixelFormatName, forKeyedSubscript: "pixelFormatName" as NSString)
        }
        if let bytesPerRow = region.bytesPerRow {
            object?.setObject(bytesPerRow, forKeyedSubscript: "bytesPerRow" as NSString)
        }
        if let sourceWindowID = region.sourceWindowID {
            object?.setObject(sourceWindowID, forKeyedSubscript: "sourceWindowId" as NSString)
        }
        if let sourceWindowTitle = region.sourceWindowTitle {
            object?.setObject(sourceWindowTitle, forKeyedSubscript: "sourceWindowTitle" as NSString)
        }
        if let captureRect = region.captureRect {
            object?.setObject(rectDictionary(captureRect), forKeyedSubscript: "captureRect" as NSString)
        }

        let ocr: @convention(block) (JSValue?, JSValue?, JSValue?, JSValue?) -> JSValue? = { first, second, third, fourth in
            let roi = self.ocrRegionOfInterest(from: [first, second, third, fourth])
            var arguments = [String(region.id)]
            if let roi {
                arguments.append(self.roiDescription(roi))
            }
            recorder.record("captureGameRegion.Ocr", arguments)
            let result = recorder.recognizeText(in: region, roi: roi)
            return self.ocrResultObject(result, on: context)
        }
        object?.setObject(ocr, forKeyedSubscript: "Ocr" as NSString)
        object?.setObject(ocr, forKeyedSubscript: "ocr" as NSString)

        let findMulti: @convention(block) (JSValue?) -> [NSDictionary] = { recognitionObjectValue in
            self.findRegions(
                in: region,
                recognitionObjectValue: recognitionObjectValue,
                findAll: true,
                recorder: recorder
            )
        }
        let find: @convention(block) (JSValue?) -> NSDictionary = { recognitionObjectValue in
            let regions = self.findRegions(
                in: region,
                recognitionObjectValue: recognitionObjectValue,
                findAll: false,
                recorder: recorder
            )
            return regions.first ?? self.emptyRegionDictionary()
        }
        let isExist: @convention(block) () -> Bool = {
            true
        }
        let isEmpty: @convention(block) () -> Bool = {
            false
        }
        let clickRegion: @convention(block) () -> Void = {
            recorder.performInputCommand(
                .mouseClickGame(button: .left, x: region.width / 2, y: region.height / 2),
                name: "ImageRegion.Click",
                arguments: [String(region.width / 2), String(region.height / 2)]
            )
        }
        object?.setObject(find, forKeyedSubscript: "Find" as NSString)
        object?.setObject(find, forKeyedSubscript: "find" as NSString)
        object?.setObject(findMulti, forKeyedSubscript: "FindMulti" as NSString)
        object?.setObject(findMulti, forKeyedSubscript: "findMulti" as NSString)
        object?.setObject(isExist, forKeyedSubscript: "IsExist" as NSString)
        object?.setObject(isExist, forKeyedSubscript: "isExist" as NSString)
        object?.setObject(isEmpty, forKeyedSubscript: "IsEmpty" as NSString)
        object?.setObject(isEmpty, forKeyedSubscript: "isEmpty" as NSString)
        object?.setObject(clickRegion, forKeyedSubscript: "Click" as NSString)
        object?.setObject(clickRegion, forKeyedSubscript: "click" as NSString)
        return object
    }

    private func findRegions(
        in region: BGIJSScriptCaptureRegion,
        recognitionObjectValue: JSValue?,
        findAll: Bool,
        recorder: BGIJSScriptExecutionRecorder
    ) -> [NSDictionary] {
        guard let recognitionObjectValue,
              !recognitionObjectValue.isUndefined,
              !recognitionObjectValue.isNull else {
            recorder.record(findAll ? "ImageRegion.FindMulti" : "ImageRegion.Find", [String(region.id), "null"])
            return []
        }

        if let templateAsset = jsStringValue(recognitionObjectValue, keys: ["__bgiTemplateAsset", "templateAsset", "Name", "name"]),
           !templateAsset.isEmpty {
            let roi = ocrRegionOfInterest(from: [recognitionObjectValue.forProperty("rect")])
            let threshold = jsOptionalDoubleValue(recognitionObjectValue, keys: ["threshold", "Threshold"]) ?? 0.8
            let locator = BGIJSScriptTemplateLocator(
                templateAssetName: templateAsset,
                roi: roi,
                threshold: threshold,
                findAll: findAll
            )
            var arguments = [String(region.id), templateAsset, String(threshold), findAll.description]
            if let roi {
                arguments.append(roiDescription(roi))
            }
            recorder.record(findAll ? "ImageRegion.FindMulti.Template" : "ImageRegion.Find.Template", arguments)
            return recorder.recognizeTemplate(in: region, locator: locator).map {
                interactiveRegionDictionary($0, recorder: recorder)
            }
        }

        let recognitionType = jsStringValue(recognitionObjectValue, keys: ["RecognitionType", "recognitionType"]) ?? "Ocr"
        let roi = firstRegionOfInterest(from: [
            recognitionObjectValue.forProperty("rect"),
            recognitionObjectValue.forProperty("RegionOfInterest"),
            recognitionObjectValue.forProperty("regionOfInterest")
        ])
        if let object = recognitionObject(
            from: recognitionObjectValue,
            recognitionTypeName: recognitionType,
            roi: roi,
            region: region
        ) {
            let typeName = object.recognitionType.label
            guard supportsImageRegionFind(object.recognitionType, findAll: findAll) else {
                recorder.hostError = BGIJSScriptRuntimeError
                    .unsupportedImageRegionRecognitionType(typeName, findAll: findAll)
                    .localizedDescription
                return []
            }
            if object.recognitionType == .ocr || object.recognitionType == .ocrMatch {
                return findOCRRegions(
                    in: region,
                    recognitionObjectValue: recognitionObjectValue,
                    recognitionType: recognitionType,
                    roi: roi,
                    findAll: findAll,
                    recorder: recorder
                )
            }

            var arguments = [String(region.id), typeName]
            if let roi {
                arguments.append(roiDescription(roi))
            }
            recorder.record("ImageRegion.\(findAll ? "FindMulti" : "Find").\(typeName)", arguments)
            return recorder.recognizeObject(in: region, object: object, findAll: findAll).map {
                interactiveRegionDictionary($0, recorder: recorder)
            }
        }
        return findOCRRegions(
            in: region,
            recognitionObjectValue: recognitionObjectValue,
            recognitionType: recognitionType,
            roi: roi,
            findAll: findAll,
            recorder: recorder
        )
    }

    private func supportsImageRegionFind(_ recognitionType: RecognitionType, findAll: Bool) -> Bool {
        if findAll {
            return recognitionType == .templateMatch || recognitionType == .ocr
        }
        switch recognitionType {
        case .templateMatch, .ocrMatch, .ocr, .colorRangeAndOcr:
            return true
        case .none, .colorMatch, .detect:
            return false
        }
    }

    private func findOCRRegions(
        in region: BGIJSScriptCaptureRegion,
        recognitionObjectValue: JSValue,
        recognitionType: String,
        roi: CGRect?,
        findAll: Bool,
        recorder: BGIJSScriptExecutionRecorder
    ) -> [NSDictionary] {
        let text = jsStringValue(recognitionObjectValue, keys: ["Text", "text"]) ?? ""
        var arguments = [String(region.id), "ocr"]
        if !text.isEmpty {
            arguments.append(text)
        }
        if let roi {
            arguments.append(roiDescription(roi))
        }
        recorder.record(findAll ? "ImageRegion.FindMulti.Ocr" : "ImageRegion.Find.Ocr", arguments)
        let result = recorder.recognizeText(in: region, roi: roi)
        if recognitionType.caseInsensitiveCompare("OcrMatch") == .orderedSame {
            let normalizedText = normalizedOCRText(
                result.combinedText,
                replacements: jsReplacementDictionaryValue(
                    recognitionObjectValue,
                    keys: ["ReplaceDictionary", "replaceDictionary"]
                )
            )
            guard matchesOCRText(
                normalizedText,
                allContain: jsStringArrayValue(recognitionObjectValue, keys: ["AllContainMatchText", "allContainMatchText"]),
                oneContain: jsStringArrayValue(recognitionObjectValue, keys: ["OneContainMatchText", "oneContainMatchText"]),
                regexPatterns: jsStringArrayValue(recognitionObjectValue, keys: ["RegexMatchText", "regexMatchText"])
            ) else {
                return []
            }
            let matchRect = roi ?? CGRect(x: 0, y: 0, width: region.width, height: region.height)
            let matchRegion = BGIJSScriptVisionRegion(
                x: matchRect.minX,
                y: matchRect.minY,
                width: matchRect.width,
                height: matchRect.height,
                text: normalizedText,
                confidence: result.regions.map { Double($0.confidence) }.max() ?? 1,
                objectID: text.isEmpty ? "ocr-match" : text,
                objectName: text.isEmpty ? "OcrMatch" : text,
                recognitionType: .ocrMatch
            )
            return [interactiveRegionDictionary(matchRegion, recorder: recorder)]
        }
        let regions = result.regions
            .map { region in
                (
                    region: region,
                    text: replacedOCRText(
                        region.text,
                        replacements: jsReplacementDictionaryValue(
                            recognitionObjectValue,
                            keys: ["ReplaceDictionary", "replaceDictionary"]
                        )
                    )
                )
            }
        if findAll {
            return regions.map { item in
                interactiveRegionDictionary(BGIJSScriptVisionRegion(
                    x: item.region.x,
                    y: item.region.y,
                    width: item.region.width,
                    height: item.region.height,
                    text: item.text,
                    confidence: item.region.confidence,
                    objectID: text.isEmpty ? "ocr" : text,
                    objectName: text.isEmpty ? "OCR" : text,
                    recognitionType: .ocr
                ), recorder: recorder)
            }
        }

        let combinedText = result.combinedText.filter { !$0.isWhitespace }
        guard !combinedText.isEmpty else {
            return []
        }
        let matchRect = roi ?? CGRect(x: 0, y: 0, width: region.width, height: region.height)
        return [interactiveRegionDictionary(BGIJSScriptVisionRegion(
            x: matchRect.minX,
            y: matchRect.minY,
            width: matchRect.width,
            height: matchRect.height,
            text: combinedText,
            confidence: result.regions.map { Double($0.confidence) }.max() ?? 1,
            objectID: text.isEmpty ? "ocr" : text,
            objectName: text.isEmpty ? "OCR" : text,
            recognitionType: .ocr
        ), recorder: recorder)]
    }

    private func replacedOCRText(
        _ text: String,
        replacements: [String: [String]]
    ) -> String {
        var result = text
        for (target, candidates) in replacements {
            for candidate in candidates {
                result = result.replacingOccurrences(of: candidate, with: target)
            }
        }
        return result
    }

    private func recognitionObject(
        from value: JSValue,
        recognitionTypeName: String,
        roi: CGRect?,
        region: BGIJSScriptCaptureRegion
    ) -> RecognitionObject? {
        guard let recognitionType = recognitionType(from: recognitionTypeName) else {
            return nil
        }
        let regionOfInterest = roi.map { roi in
            RecognitionROI(
                x: roi.minX / max(1, region.width),
                y: roi.minY / max(1, region.height),
                width: roi.width / max(1, region.width),
                height: roi.height / max(1, region.height),
                coordinateSpace: .normalized
            )
        }
        return RecognitionObject(
            id: jsStringValue(value, keys: ["Name", "name"]) ?? "JS.\(recognitionType.rawValue)",
            recognitionType: recognitionType,
            regionOfInterest: regionOfInterest,
            name: jsStringValue(value, keys: ["Name", "name"]),
            threshold: jsOptionalDoubleValue(value, keys: ["Threshold", "threshold"]) ?? 0.8,
            colorConversionCode: jsOptionalIntValue(value, keys: ["ColorConversionCode", "colorConversionCode"]) ?? 4,
            lowerColor: colorScalarValue(value.forProperty("LowerColor")) ?? colorScalarValue(value.forProperty("lowerColor")),
            upperColor: colorScalarValue(value.forProperty("UpperColor")) ?? colorScalarValue(value.forProperty("upperColor")),
            matchCount: jsOptionalIntValue(value, keys: ["MatchCount", "matchCount"]) ?? 1,
            replaceDictionary: jsReplacementDictionaryValue(value, keys: ["ReplaceDictionary", "replaceDictionary"]),
            allContainMatchText: jsStringArrayValue(value, keys: ["AllContainMatchText", "allContainMatchText"]),
            oneContainMatchText: jsStringArrayValue(value, keys: ["OneContainMatchText", "oneContainMatchText"]),
            regexMatchText: jsStringArrayValue(value, keys: ["RegexMatchText", "regexMatchText"]),
            text: jsStringValue(value, keys: ["Text", "text"]) ?? ""
        )
    }

    private func recognitionType(from name: String) -> RecognitionType? {
        RecognitionType.allCases.first {
            $0.rawValue.caseInsensitiveCompare(name) == .orderedSame
                || $0.label.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func ocrResultObject(_ result: BGIJSScriptOCRResult, on context: JSContext) -> JSValue? {
        let object = JSValue(newObjectIn: context)
        object?.setObject(result.combinedText, forKeyedSubscript: "Text" as NSString)
        object?.setObject(result.combinedText, forKeyedSubscript: "text" as NSString)
        object?.setObject(result.combinedText, forKeyedSubscript: "combinedText" as NSString)
        if let sourceCaptureID = result.sourceCaptureID {
            object?.setObject(sourceCaptureID, forKeyedSubscript: "sourceCaptureId" as NSString)
        }
        if let frameIndex = result.frameIndex {
            object?.setObject(frameIndex, forKeyedSubscript: "frameIndex" as NSString)
        }
        if let timestamp = result.timestamp {
            object?.setObject(timestamp.timeIntervalSince1970, forKeyedSubscript: "timestamp" as NSString)
        }
        if let roi = result.roi {
            object?.setObject(rectDictionary(roi), forKeyedSubscript: "roi" as NSString)
        }
        let regions = result.regions.map(ocrRegionDictionary)
        object?.setObject(regions, forKeyedSubscript: "Regions" as NSString)
        object?.setObject(regions, forKeyedSubscript: "regions" as NSString)
        return object
    }

    private func installBgiVisionBridge(on context: JSContext) {
        context.evaluateScript(
            """
            (function(root) {
                function rectFromArguments(args) {
                    if (!args || args.length === 0 || args[0] === undefined || args[0] === null) {
                        return null;
                    }
                    if (typeof args[0] === "number") {
                        return {
                            x: Number(args[0]) || 0,
                            y: Number(args[1]) || 0,
                            width: Number(args[2]) || 0,
                            height: Number(args[3]) || 0
                        };
                    }
                    var rect = args[0];
                    return {
                        x: Number(rect.x !== undefined ? rect.x : (rect.X !== undefined ? rect.X : 0)) || 0,
                        y: Number(rect.y !== undefined ? rect.y : (rect.Y !== undefined ? rect.Y : 0)) || 0,
                        width: Number(rect.width !== undefined ? rect.width : (rect.Width !== undefined ? rect.Width : rect.w)) || 0,
                        height: Number(rect.height !== undefined ? rect.height : (rect.Height !== undefined ? rect.Height : rect.h)) || 0
                    };
                }
                function rectObject(x, y, width, height) {
                    var rect = {
                        x: Number(x) || 0,
                        y: Number(y) || 0,
                        width: Number(width) || 0,
                        height: Number(height) || 0
                    };
                    rect.X = rect.x;
                    rect.Y = rect.y;
                    rect.Width = rect.width;
                    rect.Height = rect.height;
                    rect.CutLeft = rect.cutLeft = function(ratio) {
                        ratio = Math.max(0, Math.min(1, Number(ratio) || 0));
                        return rectObject(this.x, this.y, this.width * ratio, this.height);
                    };
                    rect.CutRight = rect.cutRight = function(ratio) {
                        ratio = Math.max(0, Math.min(1, Number(ratio) || 0));
                        var width = this.width * ratio;
                        return rectObject(this.x + this.width - width, this.y, width, this.height);
                    };
                    rect.CutTop = rect.cutTop = function(ratio) {
                        ratio = Math.max(0, Math.min(1, Number(ratio) || 0));
                        return rectObject(this.x, this.y, this.width, this.height * ratio);
                    };
                    rect.CutBottom = rect.cutBottom = function(ratio) {
                        ratio = Math.max(0, Math.min(1, Number(ratio) || 0));
                        var height = this.height * ratio;
                        return rectObject(this.x, this.y + this.height - height, this.width, height);
                    };
                    rect.CutLeftTop = rect.cutLeftTop = function(widthRatio, heightRatio) {
                        return this.CutLeft(widthRatio).CutTop(heightRatio);
                    };
                    rect.CutRightTop = rect.cutRightTop = function(widthRatio, heightRatio) {
                        return this.CutRight(widthRatio).CutTop(heightRatio);
                    };
                    rect.CutLeftBottom = rect.cutLeftBottom = function(widthRatio, heightRatio) {
                        return this.CutLeft(widthRatio).CutBottom(heightRatio);
                    };
                    rect.CutRightBottom = rect.cutRightBottom = function(widthRatio, heightRatio) {
                        return this.CutRight(widthRatio).CutBottom(heightRatio);
                    };
                    return rect;
                }
                function cloneRect(rect) {
                    if (!rect) {
                        return null;
                    }
                    return rectObject(rect.x, rect.y, rect.width, rect.height);
                }
                function captureRect() {
                    var metrics = getGameMetrics();
                    return rectObject(0, 0, Number(metrics[0]) || 1920, Number(metrics[1]) || 1080);
                }
                function timeoutError(locator, timeout, disappeared) {
                    var target = locator.kind === "template" ? locator.templateAsset : locator.text;
                    var verb = disappeared ? "disappear" : "appear";
                    return new Error("BvLocator timed out waiting for " + verb + ": " + target + " after " + timeout + "ms");
                }
                function regionsFromOCR(result, text) {
                    var regions = Array.prototype.slice.call((result && (result.Regions || result.regions)) || []);
                    if (!text) {
                        return regions;
                    }
                    return regions.filter(function(region) {
                        var value = String(region.Text || region.text || "");
                        return value.indexOf(text) >= 0;
                    });
                }
                function BvLocator(text, rect) {
                    if (text && text.__bgiTemplateAsset) {
                        this.kind = "template";
                        this.templateAsset = text.__bgiTemplateAsset;
                        this.text = "";
                        this.rect = text.rect || null;
                        this.threshold = Number(text.threshold) || 0.8;
                    } else {
                        this.kind = "ocr";
                        this.text = text || "";
                        this.rect = rect || null;
                        this.threshold = 0.8;
                    }
                    this.timeout = null;
                    this.retryInterval = null;
                    this.retryAction = null;
                }
                function cloneLocatorForRecognition(locator) {
                    if (locator.kind === "template") {
                        return new BvLocator({
                            __bgiTemplateAsset: locator.templateAsset,
                            rect: locator.rect || null,
                            threshold: locator.threshold
                        });
                    }
                    return new BvLocator(locator.text || "", locator.rect || null);
                }
                BvLocator.DefaultTimeout = 10000;
                BvLocator.DefaultRetryInterval = 250;
                BvLocator.prototype._actualTimeout = function(timeout) {
                    var value = timeout === undefined || timeout === null ? (this.timeout || BvLocator.DefaultTimeout) : Number(timeout);
                    return Math.max(1, Math.floor(Number(value) || BvLocator.DefaultTimeout));
                };
                BvLocator.prototype._actualRetryInterval = function() {
                    return Math.max(1, Math.floor(Number(this.retryInterval || BvLocator.DefaultRetryInterval) || BvLocator.DefaultRetryInterval));
                };
                BvLocator.prototype._runRetryAction = function(results) {
                    if (typeof this.retryAction === "function") {
                        this.retryAction(results || []);
                    }
                };
                BvLocator.prototype.FindAll = function() {
                    if (this.kind === "template") {
                        return __bgi_find_template(this.templateAsset, this.rect || null, this.threshold, false);
                    }
                    var screen = captureGameRegion();
                    var result = this.rect ? screen.Ocr(this.rect) : screen.Ocr();
                    return regionsFromOCR(result, this.text);
                };
                BvLocator.prototype.findAll = BvLocator.prototype.FindAll;
                BvLocator.prototype.Find = function() {
                    var results = this.FindAll();
                    return results.length > 0 ? results[0] : null;
                };
                BvLocator.prototype.find = BvLocator.prototype.Find;
                BvLocator.prototype.IsExist = function() {
                    return this.FindAll().length > 0;
                };
                BvLocator.prototype.isExist = BvLocator.prototype.IsExist;
                BvLocator.prototype.WaitFor = function(timeout) {
                    var actualTimeout = this._actualTimeout(timeout);
                    var retryInterval = this._actualRetryInterval();
                    var retryCount = Math.max(1, Math.floor(actualTimeout / retryInterval));
                    var results = [];
                    for (var attempt = 0; attempt < retryCount; attempt += 1) {
                        results = this.FindAll();
                        if (results.length > 0) {
                            return results;
                        }
                        this._runRetryAction(results);
                        if (attempt + 1 < retryCount) {
                            sleep(retryInterval);
                        }
                    }
                    throw timeoutError(this, actualTimeout, false);
                };
                BvLocator.prototype.waitFor = BvLocator.prototype.WaitFor;
                BvLocator.prototype.TryWaitFor = function(timeout) {
                    try {
                        return this.WaitFor(timeout);
                    } catch (error) {
                        return [];
                    }
                };
                BvLocator.prototype.tryWaitFor = BvLocator.prototype.TryWaitFor;
                BvLocator.prototype.WaitForDisappear = function(timeout) {
                    var actualTimeout = this._actualTimeout(timeout);
                    var retryInterval = this._actualRetryInterval();
                    var retryCount = Math.max(1, Math.floor(actualTimeout / retryInterval));
                    var results = [];
                    for (var attempt = 0; attempt < retryCount; attempt += 1) {
                        results = this.FindAll();
                        if (results.length === 0) {
                            return this;
                        }
                        this._runRetryAction(results);
                        if (attempt + 1 < retryCount) {
                            sleep(retryInterval);
                        }
                    }
                    throw timeoutError(this, actualTimeout, true);
                };
                BvLocator.prototype.waitForDisappear = BvLocator.prototype.WaitForDisappear;
                BvLocator.prototype.TryWaitForDisappear = function(timeout) {
                    try {
                        this.WaitForDisappear(timeout);
                        return true;
                    } catch (error) {
                        return false;
                    }
                };
                BvLocator.prototype.tryWaitForDisappear = BvLocator.prototype.TryWaitForDisappear;
                BvLocator.prototype.Click = function(timeout) {
                    var region = this.WaitFor(timeout)[0];
                    if (!region) {
                        return null;
                    }
                    click(Number(region.x) + Number(region.width) / 2, Number(region.y) + Number(region.height) / 2);
                    return region;
                };
                BvLocator.prototype.click = BvLocator.prototype.Click;
                BvLocator.prototype.DoubleClick = function(timeout) {
                    var region = this.Click(timeout);
                    if (region) {
                        click(Number(region.x) + Number(region.width) / 2, Number(region.y) + Number(region.height) / 2);
                    }
                    return region;
                };
                BvLocator.prototype.doubleClick = BvLocator.prototype.DoubleClick;
                BvLocator.prototype.ClickUntilDisappears = function(timeout) {
                    var region = this.Click(timeout);
                    var waitLocator = cloneLocatorForRecognition(this);
                    waitLocator.WithRetryAction(function(results) {
                        if (results && results[0]) {
                            var item = results[0];
                            click(Number(item.x) + Number(item.width) / 2, Number(item.y) + Number(item.height) / 2);
                        }
                    });
                    waitLocator.WaitForDisappear();
                    return region;
                };
                BvLocator.prototype.clickUntilDisappears = BvLocator.prototype.ClickUntilDisappears;
                BvLocator.prototype.WithRoi = function(rectOrFunc) {
                    if (typeof rectOrFunc === "function") {
                        this.rect = rectFromArguments([rectOrFunc(captureRect())]);
                    } else {
                        this.rect = rectFromArguments([rectOrFunc]);
                    }
                    return this;
                };
                BvLocator.prototype.withRoi = BvLocator.prototype.WithRoi;
                BvLocator.prototype.WithTimeout = function(timeout) {
                    timeout = Math.floor(Number(timeout) || 0);
                    if (timeout <= 0) {
                        throw new Error("timeout must be greater than 0");
                    }
                    this.timeout = timeout;
                    return this;
                };
                BvLocator.prototype.withTimeout = BvLocator.prototype.WithTimeout;
                BvLocator.prototype.WithRetryInterval = function(retryInterval) {
                    retryInterval = Math.floor(Number(retryInterval) || 0);
                    if (retryInterval <= 0) {
                        throw new Error("retryInterval must be greater than 0");
                    }
                    this.retryInterval = retryInterval;
                    return this;
                };
                BvLocator.prototype.withRetryInterval = BvLocator.prototype.WithRetryInterval;
                BvLocator.prototype.WithRetryAction = function(action) {
                    this.retryAction = typeof action === "function" ? action : null;
                    return this;
                };
                BvLocator.prototype.withRetryAction = BvLocator.prototype.WithRetryAction;

                function BvImage(templateAsset, rect, threshold) {
                    this.__bgiTemplateAsset = String(templateAsset || "");
                    this.rect = cloneRect(rectFromArguments([rect]));
                    this.threshold = threshold === undefined || threshold === null ? 0.8 : Number(threshold);
                }
                BvImage.prototype.ToRecognitionObject = function() {
                    return this;
                };
                BvImage.prototype.toRecognitionObject = BvImage.prototype.ToRecognitionObject;

                function RecognitionObject() {
                    this.RecognitionType = "None";
                    this.recognitionType = "None";
                    this.RegionOfInterest = null;
                    this.regionOfInterest = null;
                    this.Name = "";
                    this.name = "";
                    this.Text = "";
                    this.text = "";
                    this.ReplaceDictionary = {};
                    this.replaceDictionary = this.ReplaceDictionary;
                    this.AllContainMatchText = [];
                    this.allContainMatchText = this.AllContainMatchText;
                    this.OneContainMatchText = [];
                    this.oneContainMatchText = this.OneContainMatchText;
                    this.RegexMatchText = [];
                    this.regexMatchText = this.RegexMatchText;
                    this.ColorConversionCode = 4;
                    this.colorConversionCode = 4;
                    this.LowerColor = null;
                    this.lowerColor = null;
                    this.UpperColor = null;
                    this.upperColor = null;
                    this.MatchCount = 1;
                    this.matchCount = 1;
                    this.Threshold = 0.8;
                    this.threshold = 0.8;
                }
                RecognitionObject.Ocr = function(x, y, width, height) {
                    var ro = new RecognitionObject();
                    ro.RecognitionType = ro.recognitionType = "Ocr";
                    ro.RegionOfInterest = ro.regionOfInterest = rectFromArguments(arguments);
                    return ro;
                };
                RecognitionObject.OcrMatch = function(x, y, width, height) {
                    var ro = RecognitionObject.Ocr(x, y, width, height);
                    ro.RecognitionType = ro.recognitionType = "OcrMatch";
                    ro.OneContainMatchText = ro.oneContainMatchText = Array.prototype.slice.call(arguments, 4).map(String);
                    return ro;
                };
                RecognitionObject.OcrThis = (function() {
                    var ro = new RecognitionObject();
                    ro.RecognitionType = ro.recognitionType = "Ocr";
                    return ro;
                })();
                RecognitionObject.ocrThis = RecognitionObject.OcrThis;
                RecognitionObject.ColorRangeAndOcr = function(x, y, width, height, lowerColor, upperColor, colorConversionCode) {
                    var ro = RecognitionObject.Ocr(x, y, width, height);
                    ro.RecognitionType = ro.recognitionType = "ColorRangeAndOcr";
                    ro.LowerColor = ro.lowerColor = lowerColor || null;
                    ro.UpperColor = ro.upperColor = upperColor || null;
                    if (colorConversionCode !== undefined && colorConversionCode !== null) {
                        ro.ColorConversionCode = ro.colorConversionCode = Number(colorConversionCode);
                    }
                    return ro;
                };
                RecognitionObject.colorRangeAndOcr = RecognitionObject.ColorRangeAndOcr;
                RecognitionObject.ColorMatch = function(x, y, width, height, lowerColor, upperColor, matchCount, colorConversionCode) {
                    var ro = new RecognitionObject();
                    ro.RecognitionType = ro.recognitionType = "ColorMatch";
                    ro.RegionOfInterest = ro.regionOfInterest = rectFromArguments(arguments);
                    ro.LowerColor = ro.lowerColor = lowerColor || null;
                    ro.UpperColor = ro.upperColor = upperColor || null;
                    if (matchCount !== undefined && matchCount !== null) {
                        ro.MatchCount = ro.matchCount = Math.trunc(Number(matchCount) || 1);
                    }
                    if (colorConversionCode !== undefined && colorConversionCode !== null) {
                        ro.ColorConversionCode = ro.colorConversionCode = Number(colorConversionCode);
                    }
                    return ro;
                };
                RecognitionObject.colorMatch = RecognitionObject.ColorMatch;
                RecognitionObject.Detect = function(x, y, width, height, name, threshold) {
                    var ro = new RecognitionObject();
                    ro.RecognitionType = ro.recognitionType = "Detect";
                    ro.RegionOfInterest = ro.regionOfInterest = rectFromArguments(arguments);
                    ro.Name = ro.name = name ? String(name) : "";
                    if (threshold !== undefined && threshold !== null) {
                        ro.Threshold = ro.threshold = Number(threshold);
                    }
                    return ro;
                };
                RecognitionObject.detect = RecognitionObject.Detect;

                function keyboardObject() {
                    return {
                        KeyDown: function(key) { keyDown(String(key || "")); return this; },
                        keyDown: function(key) { keyDown(String(key || "")); return this; },
                        KeyUp: function(key) { keyUp(String(key || "")); return this; },
                        keyUp: function(key) { keyUp(String(key || "")); return this; },
                        KeyPress: function(key) { keyPress(String(key || "")); return this; },
                        keyPress: function(key) { keyPress(String(key || "")); return this; }
                    };
                }
                function mouseObject() {
                    return {
                        MoveMouseBy: function(x, y) { moveMouseBy(Number(x) || 0, Number(y) || 0); return this; },
                        moveMouseBy: function(x, y) { moveMouseBy(Number(x) || 0, Number(y) || 0); return this; },
                        MoveMouseTo: function(x, y) { moveMouseTo(Number(x) || 0, Number(y) || 0); return this; },
                        moveMouseTo: function(x, y) { moveMouseTo(Number(x) || 0, Number(y) || 0); return this; },
                        LeftButtonClick: function() { leftButtonClick(); return this; },
                        leftButtonClick: function() { leftButtonClick(); return this; },
                        LeftButtonDown: function() { leftButtonDown(); return this; },
                        leftButtonDown: function() { leftButtonDown(); return this; },
                        LeftButtonUp: function() { leftButtonUp(); return this; },
                        leftButtonUp: function() { leftButtonUp(); return this; },
                        RightButtonClick: function() { rightButtonClick(); return this; },
                        rightButtonClick: function() { rightButtonClick(); return this; },
                        RightButtonDown: function() { rightButtonDown(); return this; },
                        rightButtonDown: function() { rightButtonDown(); return this; },
                        RightButtonUp: function() { rightButtonUp(); return this; },
                        rightButtonUp: function() { rightButtonUp(); return this; },
                        MiddleButtonClick: function() { middleButtonClick(); return this; },
                        middleButtonClick: function() { middleButtonClick(); return this; },
                        MiddleButtonDown: function() { middleButtonDown(); return this; },
                        middleButtonDown: function() { middleButtonDown(); return this; },
                        MiddleButtonUp: function() { middleButtonUp(); return this; },
                        middleButtonUp: function() { middleButtonUp(); return this; },
                        VerticalScroll: function(amount) { verticalScroll(Math.trunc(Number(amount) || 0)); return this; },
                        verticalScroll: function(amount) { verticalScroll(Math.trunc(Number(amount) || 0)); return this; }
                    };
                }
                function BvPage() {
                    this.Keyboard = keyboardObject();
                    this.keyboard = this.Keyboard;
                    this.Mouse = mouseObject();
                    this.mouse = this.Mouse;
                }
                BvPage.prototype.Screenshot = function() {
                    return captureGameRegion();
                };
                BvPage.prototype.screenshot = BvPage.prototype.Screenshot;
                BvPage.prototype.Wait = function(milliseconds) {
                    sleep(Number(milliseconds) || 0);
                    return this;
                };
                BvPage.prototype.wait = BvPage.prototype.Wait;
                BvPage.prototype.Locator = function(text, rect) {
                    if (text && text.__bgiTemplateAsset) {
                        return new BvLocator(text, null);
                    }
                    return new BvLocator(text || "", rectFromArguments([rect]));
                };
                BvPage.prototype.locator = BvPage.prototype.Locator;
                BvPage.prototype.GetByText = function(text, rect) {
                    return this.Locator(text || "", rect);
                };
                BvPage.prototype.getByText = BvPage.prototype.GetByText;
                BvPage.prototype.GetByImage = function(image) {
                    return this.Locator(image);
                };
                BvPage.prototype.getByImage = BvPage.prototype.GetByImage;
                BvPage.prototype.Ocr = function(rect) {
                    return this.Locator("", rectFromArguments(arguments)).FindAll();
                };
                BvPage.prototype.ocr = BvPage.prototype.Ocr;
                BvPage.prototype.Click = function(x, y) {
                    click(Number(x) || 0, Number(y) || 0);
                };
                BvPage.prototype.click = BvPage.prototype.Click;

                root.BvImage = BvImage;
                root.BvLocator = BvLocator;
                root.BvPage = BvPage;
                root.RecognitionObject = RecognitionObject;
            })(this);
            """
        )
    }

    private func installGenshinBridge(on context: JSContext, recorder: BGIJSScriptExecutionRecorder) {
        let genshinObject = JSValue(newObjectIn: context)
        let uid: @convention(block) () -> Int = {
            recorder.record("genshin.Uid", [])
            return recorder.performGenshinCommand(.uid).intValue
        }
        let tp: @convention(block) (JSValue?, JSValue?, JSValue?, JSValue?) -> Bool = { xValue, yValue, thirdValue, fourthValue in
            let x = xValue?.toDouble() ?? 0
            let y = yValue?.toDouble() ?? 0
            let third = self.optionalString(from: thirdValue)
            let fourth = self.optionalBool(from: fourthValue)
            let mapName: String?
            let force: Bool?
            if let bool = self.optionalBool(from: thirdValue), third == nil {
                mapName = nil
                force = bool
            } else {
                mapName = third
                force = fourth
            }
            var arguments = [String(x), String(y)]
            if let mapName {
                arguments.append(mapName)
            }
            if let force {
                arguments.append(String(force))
            }
            recorder.record("genshin.Tp", arguments)
            return recorder.performGenshinCommand(.teleport(x: x, y: y, mapName: mapName, force: force)).boolValue
        }
        let moveMapTo: @convention(block) (JSValue?, JSValue?, JSValue?) -> Bool = { xValue, yValue, forceCountryValue in
            let x = xValue?.toDouble() ?? 0
            let y = yValue?.toDouble() ?? 0
            let forceCountry = self.optionalString(from: forceCountryValue)
            var arguments = [String(x), String(y)]
            if let forceCountry {
                arguments.append(forceCountry)
            }
            recorder.record("genshin.MoveMapTo", arguments)
            return recorder.performGenshinCommand(.moveMapTo(x: x, y: y, forceCountry: forceCountry)).boolValue
        }
        let moveIndependentMapTo: @convention(block) (JSValue?, JSValue?, JSValue?, JSValue?) -> Bool = { xValue, yValue, mapNameValue, forceCountryValue in
            let x = Int(xValue?.toInt32() ?? 0)
            let y = Int(yValue?.toInt32() ?? 0)
            let mapName = self.optionalString(from: mapNameValue) ?? ""
            let forceCountry = self.optionalString(from: forceCountryValue)
            var arguments = [String(x), String(y), mapName]
            if let forceCountry {
                arguments.append(forceCountry)
            }
            recorder.record("genshin.MoveIndependentMapTo", arguments)
            return recorder.performGenshinCommand(.moveIndependentMapTo(x: x, y: y, mapName: mapName, forceCountry: forceCountry)).boolValue
        }
        let getBigMapZoomLevel: @convention(block) () -> Double = {
            recorder.record("genshin.GetBigMapZoomLevel", [])
            return recorder.performGenshinCommand(.getBigMapZoomLevel).doubleValue
        }
        let setBigMapZoomLevel: @convention(block) (Double) -> Bool = { zoomLevel in
            recorder.record("genshin.SetBigMapZoomLevel", [String(zoomLevel)])
            return recorder.performGenshinCommand(.setBigMapZoomLevel(zoomLevel)).boolValue
        }
        let getPositionFromBigMap: @convention(block) (JSValue?) -> NSDictionary = { mapNameValue in
            let mapName = self.optionalString(from: mapNameValue)
            var arguments: [String] = []
            if let mapName {
                arguments.append(mapName)
            }
            recorder.record("genshin.GetPositionFromBigMap", arguments)
            let result = recorder.performGenshinCommand(.getPositionFromBigMap(mapName: mapName))
            return self.pointDictionary(result.point)
        }
        let getPosition: @convention(block) (JSValue?, JSValue?, JSValue?, JSValue?, JSValue?) -> NSDictionary = { first, second, third, fourth, fifth in
            let mapName = self.optionalString(from: first)
            let matchingMethod = self.optionalString(from: second)
            let cacheTimeMs = self.optionalInt(from: third)
            let nearX = self.optionalDouble(from: fourth)
            let nearY = self.optionalDouble(from: fifth)
            var arguments: [String] = []
            if let mapName { arguments.append(mapName) }
            if let matchingMethod { arguments.append(matchingMethod) }
            if let cacheTimeMs { arguments.append(String(cacheTimeMs)) }
            if let nearX, let nearY {
                arguments.append(String(nearX))
                arguments.append(String(nearY))
            }
            recorder.record("genshin.GetPositionFromMap", arguments)
            let result = recorder.performGenshinCommand(.getPositionFromMap(
                mapName: mapName,
                matchingMethod: matchingMethod,
                cacheTimeMs: cacheTimeMs,
                nearX: nearX,
                nearY: nearY
            ))
            return self.pointDictionary(result.point)
        }
        let getPositionWithMatchingMethod: @convention(block) (JSValue?, JSValue?, JSValue?) -> NSDictionary = { first, second, third in
            let firstString = self.optionalString(from: first)
            let secondString = self.optionalString(from: second)
            let cacheTimeMs = self.optionalInt(from: third) ?? 900
            let mapName: String?
            let matchingMethod: String?
            if let secondString {
                mapName = firstString
                matchingMethod = secondString
            } else {
                mapName = nil
                matchingMethod = firstString
            }
            var arguments: [String] = []
            if let mapName { arguments.append(mapName) }
            if let matchingMethod { arguments.append(matchingMethod) }
            arguments.append(String(cacheTimeMs))
            recorder.record("genshin.GetPositionFromMapWithMatchingMethod", arguments)
            let result = recorder.performGenshinCommand(.getPositionFromMap(
                mapName: mapName,
                matchingMethod: matchingMethod,
                cacheTimeMs: cacheTimeMs,
                nearX: nil,
                nearY: nil
            ))
            return self.pointDictionary(result.point)
        }
        let getCameraOrientation: @convention(block) () -> Double = {
            recorder.record("genshin.GetCameraOrientation", [])
            return recorder.performGenshinCommand(.getCameraOrientation).doubleValue
        }
        let switchParty: @convention(block) (String) -> Bool = { name in
            recorder.record("genshin.SwitchParty", [name])
            return recorder.performGenshinCommand(.switchParty(name)).boolValue
        }
        let clearPartyCache: @convention(block) () -> Void = {
            recorder.record("genshin.ClearPartyCache", [])
            _ = recorder.performGenshinCommand(.clearPartyCache)
        }
        let returnMainUI: @convention(block) () -> Bool = {
            recorder.record("genshin.ReturnMainUi", [])
            return recorder.performGenshinCommand(.returnMainUI).boolValue
        }
        let teleportToStatueOfTheSeven: @convention(block) () -> Bool = {
            recorder.record("genshin.TpToStatueOfTheSeven", [])
            return recorder.performGenshinCommand(.teleportToStatueOfTheSeven).boolValue
        }
        let chooseTalkOption: @convention(block) (JSValue?, JSValue?, JSValue?) -> Bool = { optionValue, skipTimesValue, isOrangeValue in
            let option = optionValue?.toString() ?? ""
            let skipTimes = self.optionalInt(from: skipTimesValue) ?? 10
            let isOrange = self.optionalBool(from: isOrangeValue) ?? false
            recorder.record("genshin.ChooseTalkOption", [option, String(skipTimes), String(isOrange)])
            return recorder.performGenshinCommand(.chooseTalkOption(option: option, skipTimes: skipTimes, isOrange: isOrange)).boolValue
        }
        let autoFishing: @convention(block) (JSValue?) -> Bool = { fishingTimePolicyValue in
            let fishingTimePolicy = self.optionalInt(from: fishingTimePolicyValue)
            var arguments: [String] = []
            if let fishingTimePolicy {
                arguments.append(String(fishingTimePolicy))
            }
            recorder.record("genshin.AutoFishing", arguments)
            return recorder.performGenshinCommand(.autoFishing(fishingTimePolicy: fishingTimePolicy)).boolValue
        }
        let relogin: @convention(block) () -> Bool = {
            recorder.record("genshin.Relogin", [])
            return recorder.performGenshinCommand(.relogin).boolValue
        }
        let setTime: @convention(block) (JSValue?, JSValue?, JSValue?) -> Bool = { hourValue, minuteValue, skipValue in
            let hour = self.optionalInt(from: hourValue) ?? 0
            let minute = self.optionalInt(from: minuteValue) ?? 0
            let skip = self.optionalBool(from: skipValue) ?? false
            recorder.record("genshin.SetTime", [String(hour), String(minute), String(skip)])
            return recorder.performGenshinCommand(.setTime(hour: hour, minute: minute, skip: skip)).boolValue
        }

        setProperty(genshinObject, ["Width", "width"], recorder.gameMetrics[safe: 0] ?? 1920)
        setProperty(genshinObject, ["Height", "height"], recorder.gameMetrics[safe: 1] ?? 1080)
        setProperty(genshinObject, ["ScaleTo1080PRatio", "scaleTo1080PRatio"], (recorder.gameMetrics[safe: 1] ?? 1080) / 1080.0)
        setProperty(genshinObject, ["ScreenDpiScale", "screenDpiScale"], recorder.gameMetrics[safe: 2] ?? 1)
        set(genshinObject, ["Uid", "uid"], uid)
        set(genshinObject, ["Tp", "tp"], tp)
        set(genshinObject, ["MoveMapTo", "moveMapTo"], moveMapTo)
        set(genshinObject, ["MoveIndependentMapTo", "moveIndependentMapTo"], moveIndependentMapTo)
        set(genshinObject, ["GetBigMapZoomLevel", "getBigMapZoomLevel"], getBigMapZoomLevel)
        set(genshinObject, ["SetBigMapZoomLevel", "setBigMapZoomLevel"], setBigMapZoomLevel)
        set(genshinObject, ["GetPositionFromBigMap", "getPositionFromBigMap"], getPositionFromBigMap)
        set(genshinObject, ["GetPositionFromMap", "getPositionFromMap"], getPosition)
        set(genshinObject, ["GetPositionFromMapWithMatchingMethod", "getPositionFromMapWithMatchingMethod"], getPositionWithMatchingMethod)
        set(genshinObject, ["GetCameraOrientation", "getCameraOrientation"], getCameraOrientation)
        set(genshinObject, ["SwitchParty", "switchParty"], switchParty)
        set(genshinObject, ["ClearPartyCache", "clearPartyCache"], clearPartyCache)
        set(genshinObject, ["ReturnMainUi", "returnMainUi"], returnMainUI)
        set(genshinObject, ["TpToStatueOfTheSeven", "tpToStatueOfTheSeven"], teleportToStatueOfTheSeven)
        set(genshinObject, ["ChooseTalkOption", "chooseTalkOption"], chooseTalkOption)
        set(genshinObject, ["AutoFishing", "autoFishing"], autoFishing)
        set(genshinObject, ["Relogin", "relogin"], relogin)
        set(genshinObject, ["SetTime", "setTime"], setTime)
        context.setObject(genshinObject, forKeyedSubscript: "genshin" as NSString)
    }

    private func setProperty(_ object: JSValue?, _ keys: [String], _ value: Any) {
        for key in keys {
            object?.setObject(value, forKeyedSubscript: key as NSString)
        }
    }

    private func set(_ object: JSValue?, _ keys: [String], _ value: Any) {
        for key in keys {
            object?.setObject(value, forKeyedSubscript: key as NSString)
        }
    }

    private func optionalString(from value: JSValue?) -> String? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        if value.isString {
            let string = value.toString()
            return string?.isEmpty == false ? string : nil
        }
        return nil
    }

    private func optionalBool(from value: JSValue?) -> Bool? {
        guard let value, !value.isUndefined, !value.isNull, value.isBoolean else { return nil }
        return value.toBool()
    }

    private func optionalInt(from value: JSValue?) -> Int? {
        guard let value, !value.isUndefined, !value.isNull, value.isNumber else { return nil }
        return Int(value.toInt32())
    }

    private func optionalDouble(from value: JSValue?) -> Double? {
        guard let value, !value.isUndefined, !value.isNull, value.isNumber else { return nil }
        return value.toDouble()
    }

    private func pointDictionary(_ point: CGPoint) -> NSDictionary {
        [
            "x": Double(point.x),
            "y": Double(point.y),
            "X": Double(point.x),
            "Y": Double(point.y)
        ]
    }

    private func jsStringValue(_ value: JSValue, keys: [String]) -> String? {
        for key in keys {
            guard let field = value.forProperty(key), !field.isUndefined, !field.isNull else {
                continue
            }
            if let string = field.toString(), !string.isEmpty {
                return string
            }
        }
        return nil
    }

    private func jsOptionalDoubleValue(_ value: JSValue, keys: [String]) -> Double? {
        for key in keys {
            guard let field = value.forProperty(key), !field.isUndefined, !field.isNull, field.isNumber else {
                continue
            }
            return field.toDouble()
        }
        return nil
    }

    private func jsOptionalIntValue(_ value: JSValue, keys: [String]) -> Int? {
        for key in keys {
            guard let field = value.forProperty(key), !field.isUndefined, !field.isNull, field.isNumber else {
                continue
            }
            return Int(field.toInt32())
        }
        return nil
    }

    private func colorScalarValue(_ value: JSValue?) -> BGIColorScalar? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        if let array = value.toArray(), array.count >= 3 {
            return BGIColorScalar(
                b: doubleValue(array[safe: 0]) ?? 0,
                g: doubleValue(array[safe: 1]) ?? 0,
                r: doubleValue(array[safe: 2]) ?? 0,
                a: doubleValue(array[safe: 3]) ?? 255
            )
        }
        let b = jsOptionalDoubleValue(value, keys: ["b", "B", "blue", "Blue"]) ?? 0
        let g = jsOptionalDoubleValue(value, keys: ["g", "G", "green", "Green"]) ?? 0
        let r = jsOptionalDoubleValue(value, keys: ["r", "R", "red", "Red"]) ?? 0
        let a = jsOptionalDoubleValue(value, keys: ["a", "A", "alpha", "Alpha"]) ?? 255
        return BGIColorScalar(b: b, g: g, r: r, a: a)
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }

    private func jsStringArrayValue(_ value: JSValue, keys: [String]) -> [String] {
        for key in keys {
            guard let field = value.forProperty(key), !field.isUndefined, !field.isNull else {
                continue
            }
            if field.isString, let string = field.toString(), !string.isEmpty {
                return [string]
            }
            if let array = field.toArray() {
                return array.compactMap { item in
                    (item as? String) ?? (item as? CustomStringConvertible)?.description
                }.filter { !$0.isEmpty }
            }
        }
        return []
    }

    private func jsReplacementDictionaryValue(_ value: JSValue, keys: [String]) -> [String: [String]] {
        for key in keys {
            guard let field = value.forProperty(key), !field.isUndefined, !field.isNull else {
                continue
            }
            guard let dictionary = field.toDictionary() as? [String: Any] else {
                continue
            }
            var replacements: [String: [String]] = [:]
            for (target, rawCandidates) in dictionary {
                if let candidates = rawCandidates as? [String] {
                    replacements[target] = candidates
                } else if let candidates = rawCandidates as? [Any] {
                    replacements[target] = candidates.map { String(describing: $0) }
                } else if let candidate = rawCandidates as? String {
                    replacements[target] = [candidate]
                }
            }
            return replacements
        }
        return [:]
    }

    private func normalizedOCRText(_ text: String, replacements: [String: [String]]) -> String {
        var result = text.filter { !$0.isWhitespace }
        for (target, candidates) in replacements {
            for candidate in candidates {
                result = result.replacingOccurrences(of: candidate, with: target)
            }
        }
        return result
    }

    private func matchesOCRText(
        _ text: String,
        allContain: [String],
        oneContain: [String],
        regexPatterns: [String]
    ) -> Bool {
        guard !text.isEmpty else { return false }
        guard !allContain.isEmpty || !oneContain.isEmpty || !regexPatterns.isEmpty else { return false }
        let allMatched = allContain.allSatisfy { text.contains($0) }
        let oneMatched = oneContain.isEmpty || oneContain.contains { text.contains($0) }
        let regexMatched = regexPatterns.allSatisfy { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, range: range) != nil
        }
        return allMatched && oneMatched && regexMatched
    }

    private func rectDictionary(_ rect: CGRect) -> NSDictionary {
        [
            "x": Double(rect.minX),
            "y": Double(rect.minY),
            "width": Double(rect.width),
            "height": Double(rect.height)
        ]
    }

    private func ocrRegionDictionary(_ region: BGIJSScriptOCRRegion) -> NSDictionary {
        [
            "x": region.x,
            "y": region.y,
            "width": region.width,
            "height": region.height,
            "text": region.text,
            "Text": region.text,
            "confidence": region.confidence,
            "score": region.confidence,
            "Score": region.confidence,
            "rect": rectDictionary(CGRect(
                x: region.x,
                y: region.y,
                width: region.width,
                height: region.height
            ))
        ]
    }

    private func emptyRegionDictionary() -> NSDictionary {
        let isExist: @convention(block) () -> Bool = { false }
        let isEmpty: @convention(block) () -> Bool = { true }
        let noOp: @convention(block) () -> NSDictionary = {
            self.emptyRegionDictionary()
        }
        return [
            "x": 0,
            "y": 0,
            "width": 0,
            "height": 0,
            "text": "",
            "Text": "",
            "confidence": 0,
            "score": 0,
            "Score": 0,
            "isExist": isExist,
            "IsExist": isExist,
            "isEmpty": isEmpty,
            "IsEmpty": isEmpty,
            "click": noOp,
            "Click": noOp,
            "doubleClick": noOp,
            "DoubleClick": noOp,
            "rect": rectDictionary(.zero)
        ]
    }

    private func interactiveRegionDictionary(
        _ region: BGIJSScriptVisionRegion,
        recorder: BGIJSScriptExecutionRecorder
    ) -> NSDictionary {
        let x = region.x
        let y = region.y
        let width = region.width
        let height = region.height
        let centerX = x + width / 2
        let centerY = y + height / 2
        let isExist: @convention(block) () -> Bool = { true }
        let isEmpty: @convention(block) () -> Bool = { false }
        let click: @convention(block) () -> NSDictionary = {
            recorder.performInputCommand(
                .mouseClickGame(button: .left, x: centerX, y: centerY),
                name: "Region.Click",
                arguments: [String(centerX), String(centerY)]
            )
            return self.interactiveRegionDictionary(region, recorder: recorder)
        }
        let doubleClick: @convention(block) () -> NSDictionary = {
            recorder.performInputCommand(
                .mouseClickGame(button: .left, x: centerX, y: centerY),
                name: "Region.DoubleClick",
                arguments: [String(centerX), String(centerY)]
            )
            recorder.performInputCommand(.mouseClickGame(button: .left, x: centerX, y: centerY))
            return self.interactiveRegionDictionary(region, recorder: recorder)
        }
        let text = region.text ?? ""
        return [
            "x": x,
            "y": y,
            "width": width,
            "height": height,
            "left": x,
            "top": y,
            "right": x + width,
            "bottom": y + height,
            "Left": x,
            "Top": y,
            "Right": x + width,
            "Bottom": y + height,
            "text": text,
            "Text": text,
            "confidence": region.confidence,
            "score": region.confidence,
            "Score": region.confidence,
            "objectID": region.objectID,
            "objectId": region.objectID,
            "objectName": region.objectName,
            "recognitionType": region.recognitionType.rawValue,
            "isExist": isExist,
            "IsExist": isExist,
            "isEmpty": isEmpty,
            "IsEmpty": isEmpty,
            "click": click,
            "Click": click,
            "doubleClick": doubleClick,
            "DoubleClick": doubleClick,
            "rect": rectDictionary(CGRect(x: x, y: y, width: width, height: height))
        ]
    }

    private func visionRegionDictionary(_ region: BGIJSScriptVisionRegion) -> NSDictionary {
        let text = region.text ?? ""
        return [
            "x": region.x,
            "y": region.y,
            "width": region.width,
            "height": region.height,
            "text": text,
            "Text": text,
            "confidence": region.confidence,
            "score": region.confidence,
            "Score": region.confidence,
            "objectID": region.objectID,
            "objectId": region.objectID,
            "objectName": region.objectName,
            "recognitionType": region.recognitionType.rawValue,
            "rect": rectDictionary(CGRect(
                x: region.x,
                y: region.y,
                width: region.width,
                height: region.height
            ))
        ]
    }

    private func ocrRegionOfInterest(from values: [JSValue?]) -> CGRect? {
        guard let first = values.first ?? nil, !first.isUndefined, !first.isNull else {
            return nil
        }

        if first.isNumber {
            let numbers = values.map { value in
                value?.isNumber == true ? value?.toDouble() ?? 0 : 0
            }
            return nonEmptyRect(
                x: numbers[safe: 0] ?? 0,
                y: numbers[safe: 1] ?? 0,
                width: numbers[safe: 2] ?? 0,
                height: numbers[safe: 3] ?? 0
            )
        }

        let x = jsRectValue(first, keys: ["x", "X", "left", "Left"])
        let y = jsRectValue(first, keys: ["y", "Y", "top", "Top"])
        let width = jsRectValue(first, keys: ["width", "Width", "w", "W"])
        let height = jsRectValue(first, keys: ["height", "Height", "h", "H"])
        return nonEmptyRect(x: x, y: y, width: width, height: height)
    }

    private func firstRegionOfInterest(from values: [JSValue?]) -> CGRect? {
        for value in values {
            if let roi = ocrRegionOfInterest(from: [value]) {
                return roi
            }
        }
        return nil
    }

    private func jsRectValue(_ value: JSValue, keys: [String]) -> Double {
        for key in keys {
            guard let field = value.forProperty(key), !field.isUndefined, !field.isNull else {
                continue
            }
            return field.toDouble()
        }
        return 0
    }

    private func nonEmptyRect(x: Double, y: Double, width: Double, height: Double) -> CGRect? {
        guard width > 0, height > 0 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func roiDescription(_ roi: CGRect) -> String {
        "\(roi.minX),\(roi.minY),\(roi.width),\(roi.height)"
    }

    private func escapeForJavaScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

private final class BGIJSScriptExecutionRecorder {
    let projectURL: URL
    let hostEnvironment: BGIJSScriptHostEnvironment
    var logs: [String] = []
    var hostCalls: [BGIJSScriptHostCall] = []
    var loadedModulePaths: [String] = []
    var captureRegions: [BGIJSScriptCaptureRegion] = []
    var ocrResults: [BGIJSScriptOCRResult] = []
    var templateMatchRegions: [BGIJSScriptVisionRegion] = []
    var hostError: String?

    var versionString: String { hostEnvironment.versionString }
    var gameMetrics: [Double] { hostEnvironment.gameMetrics }
    var avatars: [String] { hostEnvironment.avatars }
    var inputCommands: [BGIJSScriptInputCommand] {
        (hostEnvironment as? BGIRecordingJSScriptHostEnvironment)?.inputCommands ?? []
    }
    var genshinCommands: [BGIJSScriptGenshinCommand] {
        (hostEnvironment as? BGIRecordingJSScriptHostEnvironment)?.genshinCommands ?? []
    }

    private let fileManager: FileManager

    init(
        projectURL: URL,
        hostEnvironment: BGIJSScriptHostEnvironment,
        fileManager: FileManager = .default
    ) {
        self.projectURL = projectURL.standardizedFileURL
        self.hostEnvironment = hostEnvironment
        self.fileManager = fileManager
    }

    func record(_ name: String, _ arguments: [String]) {
        hostCalls.append(BGIJSScriptHostCall(name: name, arguments: arguments))
    }

    func sleep(milliseconds: Int) {
        hostEnvironment.sleep(milliseconds: milliseconds)
    }

    func setGameMetrics(width: Double, height: Double, dpi: Double) {
        hostEnvironment.gameMetrics = [width, height, dpi]
    }

    func performKeyInput(name: String, key: String) {
        record(name, [key])
        guard let command = BGIJSScriptInputCommand.keyCommand(named: name, key: key) else {
            hostError = BGIJSScriptRuntimeError.unsupportedInputKey(key).localizedDescription
            return
        }
        performInputCommand(command)
    }

    func performInputCommand(
        _ command: BGIJSScriptInputCommand,
        name: String? = nil,
        arguments: [String] = []
    ) {
        if let name {
            record(name, arguments)
        }
        do {
            try hostEnvironment.performInputCommand(command)
        } catch {
            hostError = error.localizedDescription
        }
    }

    func captureGameRegion() -> BGIJSScriptCaptureRegion {
        do {
            let region = try hostEnvironment.captureGameRegion()
            captureRegions.append(region)
            return region
        } catch {
            hostError = error.localizedDescription
            let region = BGIJSScriptCaptureRegion(
                width: gameMetrics[safe: 0] ?? 1920,
                height: gameMetrics[safe: 1] ?? 1080,
                dpi: gameMetrics[safe: 2] ?? 1,
                backendName: "Error"
            )
            captureRegions.append(region)
            return region
        }
    }

    func recognizeText(in region: BGIJSScriptCaptureRegion, roi: CGRect?) -> BGIJSScriptOCRResult {
        do {
            let result = try hostEnvironment.recognizeText(in: region, roi: roi)
            ocrResults.append(result)
            return result
        } catch {
            hostError = error.localizedDescription
            var result = BGIJSScriptOCRResult.empty(for: region)
            if let roi {
                result = BGIJSScriptOCRResult(
                    sourceCaptureID: region.id,
                    frameIndex: region.frameIndex,
                    timestamp: region.timestamp,
                    roi: roi
                )
            }
            ocrResults.append(result)
            return result
        }
    }

    func recognizeTemplate(
        in region: BGIJSScriptCaptureRegion,
        locator: BGIJSScriptTemplateLocator
    ) -> [BGIJSScriptVisionRegion] {
        do {
            let regions = try hostEnvironment.recognizeTemplate(in: region, locator: locator)
            templateMatchRegions.append(contentsOf: regions)
            return regions
        } catch {
            hostError = error.localizedDescription
            return []
        }
    }

    func recognizeObject(
        in region: BGIJSScriptCaptureRegion,
        object: RecognitionObject,
        findAll: Bool
    ) -> [BGIJSScriptVisionRegion] {
        do {
            let regions = try hostEnvironment.recognizeObject(in: region, object: object, findAll: findAll)
            templateMatchRegions.append(contentsOf: regions)
            return regions
        } catch {
            hostError = error.localizedDescription
            return []
        }
    }

    func performGenshinCommand(_ command: BGIJSScriptGenshinCommand) -> BGIJSScriptGenshinResult {
        do {
            return try hostEnvironment.performGenshinCommand(command)
        } catch {
            hostError = error.localizedDescription
            return BGIJSScriptGenshinResult(boolValue: false)
        }
    }

    func readText(_ path: String) throws -> String {
        try String(contentsOf: resolve(path), encoding: .utf8)
    }

    func writeText(_ path: String, content: String, append: Bool) throws {
        let url = try resolve(path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if append, fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(content.utf8))
        } else {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func readImageBase64(_ path: String) throws -> String {
        try Data(contentsOf: resolve(path)).base64EncodedString()
    }

    func createDirectory(_ path: String) throws {
        try fileManager.createDirectory(at: resolve(path), withIntermediateDirectories: true)
    }

    func readPath(_ path: String) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: resolve(path).path).sorted()
    }

    func fileExists(_ path: String) -> Bool {
        guard let url = try? resolve(path) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    func isFile(_ path: String) -> Bool {
        guard let url = try? resolve(path) else { return false }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    func isDirectory(_ path: String) -> Bool {
        guard let url = try? resolve(path) else { return false }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func resolve(_ path: String) throws -> URL {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else {
            throw BGIJSScriptRuntimeError.unsafePath(path)
        }
        let candidateURL = projectURL.appendingPathComponent(normalized).standardizedFileURL
        let basePath = projectURL.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedPath = resolvedURL.path
        guard resolvedPath == basePath || resolvedPath.hasPrefix(basePath + "/") else {
            throw BGIJSScriptRuntimeError.unsafePath(path)
        }
        return resolvedURL
    }
}

private extension String {
    subscript(_ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: self) else { return "" }
        return String(self[swiftRange])
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension BGIJSScriptInputCommand {
    static func keyCommand(named name: String, key: String) -> BGIJSScriptInputCommand? {
        guard let keyCode = BGIJSScriptKeyMapper.keyCode(from: key) else {
            return mouseKeyCommand(named: name, key: key)
        }
        switch name {
        case "keyDown":
            return .keyDown(keyCode)
        case "keyUp":
            return .keyUp(keyCode)
        case "keyPress":
            return .keyPress(keyCode)
        default:
            return nil
        }
    }

    static func mouseCommand(named name: String) -> BGIJSScriptInputCommand? {
        switch name {
        case "leftButtonClick":
            return .mouseClick(.left)
        case "leftButtonDown":
            return .mouseButtonDown(.left)
        case "leftButtonUp":
            return .mouseButtonUp(.left)
        case "rightButtonClick":
            return .mouseClick(.right)
        case "rightButtonDown":
            return .mouseButtonDown(.right)
        case "rightButtonUp":
            return .mouseButtonUp(.right)
        case "middleButtonClick":
            return .mouseClick(.middle)
        case "middleButtonDown":
            return .mouseButtonDown(.middle)
        case "middleButtonUp":
            return .mouseButtonUp(.middle)
        default:
            return nil
        }
    }

    private static func mouseKeyCommand(named name: String, key: String) -> BGIJSScriptInputCommand? {
        guard let button = BGIJSScriptKeyMapper.mouseButton(from: key) else { return nil }
        switch name {
        case "keyDown":
            return .mouseButtonDown(button)
        case "keyUp":
            return .mouseButtonUp(button)
        case "keyPress":
            return .mouseClick(button)
        default:
            return nil
        }
    }
}

enum BGIJSScriptKeyMapper {
    static func keyCode(fromWindowsVirtualKey virtualKey: Int) -> KeyCode? {
        if (0x30...0x39).contains(virtualKey) {
            return KeyCode(rawValue: "digit\(virtualKey - 0x30)")
        }
        if (0x41...0x5A).contains(virtualKey),
           let scalar = UnicodeScalar(virtualKey) {
            return KeyCode(rawValue: String(Character(scalar)).lowercased())
        }
        if (0x70...0x7B).contains(virtualKey) {
            return KeyCode(rawValue: "f\(virtualKey - 0x6F)")
        }
        return switch virtualKey {
        case 0x08: .backspace; case 0x09: .tab; case 0x0D: .return
        case 0x10, 0xA0, 0xA1: .leftShift
        case 0x11, 0xA2, 0xA3: .leftControl
        case 0x12, 0xA4, 0xA5: .leftOption
        case 0x14: .capsLock; case 0x1B: .escape; case 0x20: .space
        case 0x21: .pageUp; case 0x22: .pageDown; case 0x23: .end; case 0x24: .home
        case 0x25: .leftArrow; case 0x26: .upArrow; case 0x27: .rightArrow; case 0x28: .downArrow
        case 0x2E: .delete
        case 0xBA: .semicolon; case 0xBB: .equal; case 0xBC: .comma; case 0xBD: .minus
        case 0xBE: .period; case 0xBF: .slash; case 0xC0: .grave
        case 0xDB: .leftBracket; case 0xDC: .backslash; case 0xDD: .rightBracket; case 0xDE: .apostrophe
        default: nil
        }
    }

    static func keyCode(from rawKey: String) -> KeyCode? {
        let key = normalizedKey(rawKey)
        if key.count == 1, let character = key.first {
            if character >= "A", character <= "Z" {
                return KeyCode(rawValue: character.lowercased())
            }
            if character >= "0", character <= "9" {
                return KeyCode(rawValue: "digit\(character)")
            }
        }

        if key.hasPrefix("F"),
           let number = Int(key.dropFirst()),
           (1...12).contains(number) {
            return KeyCode(rawValue: "f\(number)")
        }

        switch key {
        case "VK_ESCAPE", "ESCAPE", "ESC":
            return .escape
        case "VK_RETURN", "RETURN", "ENTER":
            return .return
        case "VK_SPACE", "SPACE":
            return .space
        case "VK_TAB", "TAB":
            return .tab
        case "VK_BACK", "BACKSPACE":
            return .backspace
        case "VK_DELETE", "DELETE", "DEL":
            return .delete
        case "VK_LEFT", "LEFT":
            return .leftArrow
        case "VK_RIGHT", "RIGHT":
            return .rightArrow
        case "VK_UP", "UP":
            return .upArrow
        case "VK_DOWN", "DOWN":
            return .downArrow
        case "VK_SHIFT", "VK_LSHIFT", "SHIFT", "LSHIFT":
            return .leftShift
        case "VK_CONTROL", "VK_LCONTROL", "VK_CTRL", "VK_LCTRL", "CONTROL", "CTRL":
            return .leftControl
        case "VK_MENU", "VK_LMENU", "VK_ALT", "ALT":
            return .leftOption
        case "VK_OEM_COMMA", "COMMA", ",":
            return .comma
        case "VK_OEM_MINUS", "MINUS", "-":
            return .minus
        case "VK_OEM_PLUS", "EQUAL", "=":
            return .equal
        case "VK_OEM_PERIOD", "PERIOD", ".":
            return .period
        case "VK_OEM_2", "SLASH", "/":
            return .slash
        case "VK_OEM_5", "BACKSLASH", "\\":
            return .backslash
        case "VK_OEM_1", "SEMICOLON", ";":
            return .semicolon
        case "VK_OEM_4", "LBRACKET", "[":
            return .leftBracket
        case "VK_OEM_6", "RBRACKET", "]":
            return .rightBracket
        case "VK_OEM_3", "GRAVE", "TILDE", "`":
            return .grave
        default:
            if key.hasPrefix("VK_") {
                return keyCode(from: String(key.dropFirst(3)))
            }
            return nil
        }
    }

    static func mouseButton(from rawKey: String) -> InputMouseButton? {
        switch normalizedKey(rawKey) {
        case "VK_LBUTTON", "LBUTTON", "MOUSELEFT", "MOUSE_LEFT":
            return .left
        case "VK_RBUTTON", "RBUTTON", "MOUSERIGHT", "MOUSE_RIGHT":
            return .right
        case "VK_MBUTTON", "MBUTTON", "MOUSEMIDDLE", "MOUSE_MIDDLE":
            return .middle
        default:
            return nil
        }
    }

    private static func normalizedKey(_ rawKey: String) -> String {
        rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .uppercased()
    }
}
