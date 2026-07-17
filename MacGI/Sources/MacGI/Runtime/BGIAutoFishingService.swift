import CoreGraphics
import Foundation

struct BGIAutoFishingConfig: Sendable {
    var enterFishingTimeoutMs: Int = 10000
    var biteWaitTimeoutMs: Int = 30000
    var fishingTickMs: Int = 50
    var overallTimeoutSeconds: Int = 600
    var tensionHoldMs: Int = 200
    var tensionReleaseMs: Int = 200
    static let `default` = BGIAutoFishingConfig()
}

/// First functional layer of upstream `AutoFishingTask` (3367 lines).
///
/// Implements the core fishing loop:
///   YOLO fish detection → enter fishing mode (F) → wait for bite (template+OCR)
///   → raise rod (click) → tension bar tracking (hold/release loop)
///   → repeat until fish depleted or timeout.
///
/// Upstream behaviour tree nodes referenced:
///   FishBite.cs (723) — template match lift_rod + OCR "上钩" → click
///   Fishing.cs (881) — tension bar rectangle color tracking → hold/release mouse
///   EnterFishingMode — press F, wait for exit_fishing to appear
final class BGIAutoFishingService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    typealias OCRProvider = @MainActor (CaptureImageFrame, CGRect) async throws -> String

    private let captureFrameProvider: CaptureFrameProvider
    private let inputHandler: InputHandler
    private let ocrProvider: OCRProvider?
    private let config: BGIAutoFishingConfig
    private let templateEngine = TemplateMatchingRecognitionEngine()
    private let fishPipeline: BGIYOLODetectionPipeline?

    init(
        inputHandler: @escaping InputHandler,
        captureFrameProvider: @escaping CaptureFrameProvider,
        ocrProvider: OCRProvider? = nil,
        config: BGIAutoFishingConfig = .default
    ) {
        self.inputHandler = inputHandler
        self.captureFrameProvider = captureFrameProvider
        self.ocrProvider = ocrProvider
        self.config = config
        self.fishPipeline = {
            guard let runtime = try? BGIYOLORuntime(),
                  let session = try? runtime.makeSession(model: .bgiFish) else { return nil }
            return BGIYOLODetectionPipeline(session: session, labels: BGIOnnxModel.bgiFish.defaultYOLOLabels)
        }()
    }

    /// Main fishing loop — run until timeout or fish depleted.
    func startFishing() async {
        let overallStart = Date()
        var fishCaught = 0

        while !Task.isCancelled,
              Date().timeIntervalSince(overallStart) < Double(config.overallTimeoutSeconds) {
            do {
                let frame = try await captureFrameProvider()

                // 1. Check if already in fishing UI (exit button visible)
                let exitResults = templateEngine.recognize(
                    imageFrame: frame,
                    objects: RecognitionObject.bgiFishingExitButtonObjects
                ).observations
                let isInFishingUI = !exitResults.isEmpty

                if !isInFishingUI {
                    // Detect fish via YOLO, if none found → done
                    var hasFish = false
                    if let pipeline = fishPipeline,
                       let result = try? pipeline.detect(image: frame.cgImage) {
                        hasFish = !result.detections.isEmpty
                    }
                    if !hasFish {
                        // Try casting again (press F near water)
                        _ = await inputHandler(.keyPress(key: .f))
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    }
                }

                // 2. Wait for bite — check lift rod template
                let biteStart = Date()
                var bit = false
                while !Task.isCancelled,
                      Date().timeIntervalSince(biteStart) * 1000 < Double(config.biteWaitTimeoutMs) {
                    let checkFrame = try await captureFrameProvider()
                    let biteResults = templateEngine.recognize(
                        imageFrame: checkFrame,
                        objects: RecognitionObject.bgiFishingBiteObjects
                    ).observations

                    if !biteResults.isEmpty {
                        // Bite detected → click to raise rod
                        _ = await inputHandler(.mouseClick(button: .left, at: nil))
                        bit = true
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        break
                    }

                    // Also check OCR for "上钩" text
                    if let ocr = ocrProvider {
                        let midRect = CGRect(
                            x: Double(checkFrame.metadata.width) / 3,
                            y: 0,
                            width: Double(checkFrame.metadata.width) / 3,
                            height: Double(checkFrame.metadata.height) / 2
                        )
                        if let text = try? await ocr(checkFrame, midRect),
                           text.range(of: "上钩") != nil || text.range(of: "咬钩") != nil {
                            _ = await inputHandler(.mouseClick(button: .left, at: nil))
                            bit = true
                            break
                        }
                    }
                    try? await Task.sleep(nanoseconds: UInt64(config.fishingTickMs) * 1_000_000)
                }
                guard bit else { continue }

                // 3. Tension bar tracking — alternate hold/release to keep cursor in zone
                let tensionStart = Date()
                while !Task.isCancelled,
                      Date().timeIntervalSince(tensionStart) < 30 { // max 30s per fish
                    let tFrame = try await captureFrameProvider()

                    // Check if fishing UI still active
                    let stillFishing = templateEngine.recognize(
                        imageFrame: tFrame,
                        objects: RecognitionObject.bgiFishingExitButtonObjects
                    ).observations
                    if stillFishing.isEmpty {
                        // Fishing complete (UI gone)
                        fishCaught += 1
                        break
                    }

                    // Simple alternating tension: hold → release → hold...
                    _ = await inputHandler(.mouseButtonDown(button: .left, at: nil))
                    try? await Task.sleep(nanoseconds: UInt64(config.tensionHoldMs) * 1_000_000)
                    _ = await inputHandler(.mouseButtonUp(button: .left, at: nil))
                    try? await Task.sleep(nanoseconds: UInt64(config.tensionReleaseMs) * 1_000_000)
                }

                // 4. After catch, short delay before next cast
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                _ = await inputHandler(.keyPress(key: .escape)) // exit any remaining dialogs
            } catch {
                break
            }
        }

        // Final exit
        _ = await inputHandler(.keyPress(key: .escape))
    }
}

// MARK: - Bite detection objects

extension RecognitionObject {
    static let bgiFishingBiteObject = RecognitionObject(
        id: "AutoFishing.LiftRodButtonRo",
        recognitionType: .templateMatch,
        regionOfInterest: RecognitionROI(x: 0, y: 0, width: 1, height: 0.7, coordinateSpace: .normalized),
        name: "LiftRod",
        templateAssetName: "GameTask/AutoFishing/Assets/1920x1080/lift_rod.png",
        threshold: 0.8,
        tags: ["AutoFishing", "Bite"]
    )

    static let bgiFishingBiteObjects: [RecognitionObject] = [bgiFishingBiteObject]
}
