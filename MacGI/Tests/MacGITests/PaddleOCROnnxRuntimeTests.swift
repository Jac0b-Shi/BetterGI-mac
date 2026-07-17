import CoreGraphics
import Foundation
import ImageIO
@testable import MacGI
import Testing

@Suite("BetterGI PaddleOCR ONNX Runtime")
struct PaddleOCROnnxRuntimeTests {
    @Test("English V4 recognizer runs the upstream number preheat image")
    func englishV4RecognizerRunsNumberPreheatImage() throws {
        let image = try loadImage("Assets/Model/PaddleOCR/test_pp_ocr_number.png")
        let runtime = try PaddleOCRRuntime()
        let recognizer = try PaddleOCRRecognitionService(model: .paddleOcrRecV4En, runtime: runtime)

        let output = try recognizer.recognizeWithoutDetector(image)

        #expect(output.model == .paddleOcrRecV4En)
        #expect(output.rawTensor.shape.count == 3)
        #expect(output.rawTensor.shape[0] == 1)
        #expect(output.line.text == "7686")
        #expect(output.line.confidence > 0.8)
    }

    @Test("Detection model finds text boxes in the upstream PaddleOCR preheat image")
    func detectionModelFindsTextBoxesInPreheatImage() throws {
        let image = try loadImage("Assets/Model/PaddleOCR/test_pp_ocr.png")
        let runtime = try PaddleOCRRuntime()
        let detector = try PaddleOCRDetectionService(runtime: runtime)

        let output = try detector.detect(image)

        #expect(output.model == .paddleOcrDetV4)
        #expect(output.rawTensor.shape == [1, 1, 352, 288])
        #expect(output.regions.count >= 4)
        #expect(output.regions.allSatisfy { $0.score > 0.7 })
    }

    @Test("Full OCR pipeline recognizes text in the upstream PaddleOCR preheat image")
    func fullOCRPipelineRecognizesPreheatImage() throws {
        let image = try loadImage("Assets/Model/PaddleOCR/test_pp_ocr.png")
        let runtime = try PaddleOCRRuntime()
        let service = try PaddleOCRService(runtime: runtime)

        let result = try service.recognize(
            image,
            frameIndex: 42,
            timestamp: Date(timeIntervalSince1970: 1)
        )

        #expect(result.frameIndex == 42)
        #expect(result.regions.count >= 4)
        #expect(result.combinedText.contains("领取"))
        #expect(result.combinedText.contains("奖励"))
        #expect(result.combinedText.contains("探索派遣"))
        #expect(result.combinedText.contains("凯瑟琳"))
    }

    @Test("OCR engine emits RecognitionObservation for matching OCR objects")
    func ocrEngineEmitsRecognitionObservation() throws {
        let image = try loadImage("Assets/Model/PaddleOCR/test_pp_ocr.png")
        let frame = makeImageFrame(image)
        let runtime = try PaddleOCRRuntime()
        let engine = try PaddleOCRRecognitionEngine(runtime: runtime)
        let object = RecognitionObject(
            id: "Test.OcrMatch",
            recognitionType: .ocrMatch,
            name: "PreheatText",
            oneContainMatchText: ["领取"],
            featureID: "auto-dialog"
        )

        let report = engine.recognize(imageFrame: frame, objects: [object])

        #expect(report.objectCount == 1)
        #expect(report.matchedCount == 1)
        #expect(report.errors.isEmpty)
        let observation = try #require(report.observations.first)
        #expect(observation.objectID == "Test.OcrMatch")
        #expect(observation.recognitionType == .ocrMatch)
        #expect(observation.text?.contains("领取") == true)
        #expect(observation.frameIndex == 101)
    }

    @Test("OCR engine suppresses non-matching OCRMatch objects")
    func ocrEngineSuppressesNonMatchingOCRMatch() throws {
        let image = try loadImage("Assets/Model/PaddleOCR/test_pp_ocr.png")
        let frame = makeImageFrame(image)
        let runtime = try PaddleOCRRuntime()
        let engine = try PaddleOCRRecognitionEngine(runtime: runtime)
        let object = RecognitionObject(
            id: "Test.OcrMiss",
            recognitionType: .ocrMatch,
            name: "MissingText",
            oneContainMatchText: ["不存在的文本"],
            featureID: "auto-dialog"
        )

        let report = engine.recognize(imageFrame: frame, objects: [object])

        #expect(report.objectCount == 1)
        #expect(report.matchedCount == 0)
        #expect(report.observations.isEmpty)
        #expect(report.errors.isEmpty)
    }

    @Test("ColorRangeAndOcr applies a BetterGI-style white text mask before OCR")
    func colorRangeAndOCRAppliesWhiteTextMask() throws {
        let image = try loadImage("Assets/Model/PaddleOCR/test_pp_ocr.png")
        let frame = makeImageFrame(image)
        let runtime = try PaddleOCRRuntime()
        let engine = try PaddleOCRRecognitionEngine(runtime: runtime)
        let object = RecognitionObject(
            id: "Test.ColorRangeOcr.White",
            recognitionType: .colorRangeAndOcr,
            name: "MaskedPreheatText",
            lowerColor: BGIColorScalar(b: 180, g: 180, r: 180, a: 0),
            upperColor: BGIColorScalar(b: 255, g: 255, r: 255, a: 255),
            featureID: "quick-teleport"
        )

        let report = engine.recognize(imageFrame: frame, objects: [object])

        #expect(report.objectCount == 1)
        #expect(report.matchedCount == 1)
        #expect(report.errors.isEmpty)
        let observation = try #require(report.observations.first)
        #expect(observation.objectID == "Test.ColorRangeOcr.White")
        #expect(observation.recognitionType == .colorRangeAndOcr)
        #expect(observation.text?.contains("领取") == true)
    }

    @Test("ColorRangeAndOcr suppresses OCR when the mask selects no text")
    func colorRangeAndOCRSuppressesWhenMaskSelectsNoText() throws {
        let image = try loadImage("Assets/Model/PaddleOCR/test_pp_ocr.png")
        let frame = makeImageFrame(image)
        let runtime = try PaddleOCRRuntime()
        let engine = try PaddleOCRRecognitionEngine(runtime: runtime)
        let object = RecognitionObject(
            id: "Test.ColorRangeOcr.EmptyMask",
            recognitionType: .colorRangeAndOcr,
            name: "NoGreenText",
            lowerColor: BGIColorScalar(b: 0, g: 255, r: 0, a: 0),
            upperColor: BGIColorScalar(b: 0, g: 255, r: 0, a: 255),
            featureID: "quick-teleport"
        )

        let report = engine.recognize(imageFrame: frame, objects: [object])

        #expect(report.objectCount == 1)
        #expect(report.matchedCount == 0)
        #expect(report.observations.isEmpty)
        #expect(report.errors.isEmpty)
    }

    private func loadImage(_ assetPath: String) throws -> CGImage {
        let url = try #require(BGIModelAssetResolver.url(for: assetPath))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func makeImageFrame(_ image: CGImage) -> CaptureImageFrame {
        let window = WindowInfo(
            id: 101,
            ownerPID: 1,
            ownerName: "MacGITests",
            title: "OCR Preheat",
            frame: CGRect(x: 0, y: 0, width: image.width, height: image.height),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1
        )
        let metadata = CapturedFrame(
            frameIndex: 101,
            timestamp: Date(timeIntervalSince1970: 1),
            width: image.width,
            height: image.height,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: image.width * 4,
            sourceWindow: window
        )
        return CaptureImageFrame(metadata: metadata, cgImage: image, backendName: "Synthetic")
    }
}
