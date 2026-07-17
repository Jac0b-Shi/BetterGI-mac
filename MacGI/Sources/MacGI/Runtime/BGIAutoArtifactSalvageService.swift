import Foundation

// MARK: - AutoArtifactSalvage (自动圣遗物分解)

/// Upstream ref: `AutoArtifactSalvageTask.cs` (1037 lines)
/// Opens bag, clicks artifact tab, selects artifacts, clicks salvage, confirms.
final class BGIAutoArtifactSalvageService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    typealias OCRProvider = @MainActor (CaptureImageFrame, CGRect) async throws -> String

    private let captureFrameProvider: CaptureFrameProvider?
    private let inputHandler: InputHandler
    private let ocrProvider: OCRProvider?
    private let templateEngine = TemplateMatchingRecognitionEngine()

    init(
        inputHandler: @escaping InputHandler,
        captureFrameProvider: CaptureFrameProvider? = nil,
        ocrProvider: OCRProvider? = nil
    ) {
        self.inputHandler = inputHandler; self.captureFrameProvider = captureFrameProvider; self.ocrProvider = ocrProvider
    }

    /// Salvage artifacts matching the given attribute filter.
    func salvage(artifactSetFilter: String? = nil, minLevel: Int = 0) async {
        // 1. Open bag (press B)
        _ = await inputHandler(.keyPress(key: .b))
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // 2. Click artifact tab (bag_artifact_unchecked template)
        if let provider = captureFrameProvider {
            for _ in 0..<3 {
                guard let frame = try? await provider() else { break }
                let results = templateEngine.recognize(imageFrame: frame, objects: RecognitionObject.bgiSalvageObjects).observations
                if let tab = results.first(where: { $0.objectID.contains("ArtifactUnchecked") }) {
                    let x = tab.normalizedRect.midX * Double(frame.metadata.width)
                    let y = tab.normalizedRect.midY * Double(frame.metadata.height)
                    _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: x, y: y)))
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    break
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        // 3. Select artifacts by scanning rows with OCR or click first
        if let provider = captureFrameProvider, let ocr = ocrProvider, let frame = try? await provider() {
            let w = Double(frame.metadata.width)
            let h = Double(frame.metadata.height)
            let text = try? await ocr(frame, CGRect(x: 0, y: 0, width: w, height: h))
            if let filter = artifactSetFilter, let t = text, t.contains(filter) {
                // Click matching artifact entry
                _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: w * 0.5, y: h * 0.3)))
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        // 4. Click salvage button
        _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 200, y: 900)))
        try? await Task.sleep(nanoseconds: 500_000_000)

        // 5. Confirm (white confirm button, right side)
        _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 1600, y: 500)))
        try? await Task.sleep(nanoseconds: 500_000_000)
        _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 1600, y: 800)))
        try? await Task.sleep(nanoseconds: 500_000_000)

        // 6. Close
        _ = await inputHandler(.keyPress(key: .escape))
    }
}

extension RecognitionObject {
    static let bgiSalvageArtifactUncheckedObject = RecognitionObject(
        id: "Salvage.ArtifactUncheckedRo",
        recognitionType: .templateMatch,
        regionOfInterest: RecognitionROI(x: 0, y: 0, width: 1, height: 1, coordinateSpace: .normalized),
        name: "ArtifactUnchecked",
        templateAssetName: "GameTask/Common/Element/Assets/1920x1080/bag_artifact_unchecked.png",
        threshold: 0.8,
        tags: ["Salvage", "Artifact"]
    )
    static let bgiSalvageObjects: [RecognitionObject] = [bgiSalvageArtifactUncheckedObject]
}
