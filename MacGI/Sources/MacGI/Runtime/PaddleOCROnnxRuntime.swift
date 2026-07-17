import CoreGraphics
import Foundation

#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#endif

enum PaddleOCROnnxRuntimeError: LocalizedError {
    case runtimeUnavailable
    case missingModelAsset(String)
    case missingInputName(String)
    case missingOutputName(String)
    case emptyTensor
    case invalidOutputShape([Int])
    case tensorDataUnavailable
    case unsupportedModelKind(BGIOnnxModel.ModelKind)
    case imageCropFailed(CGRect)

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            "ONNX Runtime Swift bindings are not available"
        case let .missingModelAsset(path):
            "BetterGI ONNX model asset is missing: \(path)"
        case let .missingInputName(name):
            "ONNX model has no input name for \(name)"
        case let .missingOutputName(name):
            "ONNX model has no output name for \(name)"
        case .emptyTensor:
            "Cannot run ONNX inference with an empty tensor"
        case let .invalidOutputShape(shape):
            "Unexpected PaddleOCR output tensor shape: \(shape)"
        case .tensorDataUnavailable:
            "ONNX Runtime returned no tensor data"
        case let .unsupportedModelKind(kind):
            "Unsupported PaddleOCR model kind for this operation: \(kind.rawValue)"
        case let .imageCropFailed(rect):
            "Failed to crop OCR detection region: \(rect)"
        }
    }
}

struct PaddleOCRDetectionPostProcessorConfig: Equatable, Sendable {
    let boxThreshold: Float?
    let boxScoreThreshold: Float?
    let dilatedSize: Int?
    let minSize: Int
    let unclipRatio: Double

    static let bgiDefault = PaddleOCRDetectionPostProcessorConfig(
        boxThreshold: 0.3,
        boxScoreThreshold: 0.7,
        dilatedSize: 2,
        minSize: 3,
        unclipRatio: 2.0
    )
}

struct PaddleOCRDetectedRegion: Identifiable, Equatable, Sendable {
    let boundingBox: CGRect
    let score: Float

    var id: String { "\(boundingBox)-\(score)" }
}

struct PaddleOCRDetectionOutput: Equatable, Sendable {
    let regions: [PaddleOCRDetectedRegion]
    let rawTensor: PaddleOCRTensor
    let input: PaddleOCRDetectionInput
    let model: BGIOnnxModel
}

struct PaddleOCRRecognitionOutput: Equatable, Sendable {
    let line: PaddleOCRRecognizedLine
    let rawTensor: PaddleOCRTensor
    let model: BGIOnnxModel
}

#if canImport(OnnxRuntimeBindings)
final class PaddleOCROnnxSession {
    private let session: ORTSession
    private let inputName: String
    private let outputName: String
    let model: BGIOnnxModel
    /// Captured during session creation so callers can inspect what EP was used.
    let epAssignment: BGIEpAssignment

    init(
        model: BGIOnnxModel,
        env: ORTEnv,
        computePreference: BGIComputePreference = .automatic,
        policy: BGIModelExecutionPolicy = .default
    ) throws {
        guard let modelURL = BGIModelAssetResolver.url(for: model) else {
            throw PaddleOCROnnxRuntimeError.missingModelAsset(model.assetPath)
        }

        let coreMLRequested = BGIInferenceSessionFactory.shouldRegisterCoreML(
            preference: computePreference,
            policy: policy,
            model: model
        )
        let resolved: BGIResolvedCoreMLOptions? = coreMLRequested
            ? BGIInferenceSessionFactory.resolveCoreMLOptions(
                preference: computePreference,
                policy: policy
              )
            : nil
        let cacheKey: String? = {
            guard let r = resolved else { return nil }
            return BGIInferenceSessionFactory.prepareCoreMLCacheDirectory(
                forModelAt: modelURL,
                resolvedOptions: r
            )?.path
        }()

        let (ortSession, assignment) = try BGIInferenceSessionFactory.makeResilientSession(
            env: env,
            modelPath: modelURL.path,
            preference: computePreference,
            policy: policy,
            model: model,
            modelCacheKey: cacheKey
        )
        session = ortSession
        epAssignment = assignment
        self.model = model

        let inputNames = try session.inputNames()
        guard let firstInput = inputNames.first else {
            throw PaddleOCROnnxRuntimeError.missingInputName(model.name)
        }
        inputName = firstInput

        let outputNames = try session.outputNames()
        guard let firstOutput = outputNames.first else {
            throw PaddleOCROnnxRuntimeError.missingOutputName(model.name)
        }
        outputName = firstOutput
    }

    func run(_ tensor: PaddleOCRTensor) throws -> PaddleOCRTensor {
        guard !tensor.values.isEmpty else {
            throw PaddleOCROnnxRuntimeError.emptyTensor
        }

        let inputValue = try ORTValue(
            tensorData: tensor.mutableData(),
            elementType: .float,
            shape: tensor.shape.map { NSNumber(value: $0) }
        )
        let outputs = try session.run(
            withInputs: [inputName: inputValue],
            outputNames: Set([outputName]),
            runOptions: nil
        )
        guard let output = outputs[outputName] else {
            throw PaddleOCROnnxRuntimeError.tensorDataUnavailable
        }
        let info = try output.tensorTypeAndShapeInfo()
        let data = try output.tensorData()
        let outputShape = info.shape.map(\.intValue)
        return PaddleOCRTensor(shape: outputShape, values: data.floatArray())
    }
}

final class PaddleOCRRuntime {
    private let env: ORTEnv
    let computePreference: BGIComputePreference
    let modelExecutionPolicy: BGIModelExecutionPolicy

    init(
        loggingLevel: ORTLoggingLevel = .warning,
        computePreference: BGIComputePreference = .automatic,
        modelExecutionPolicy: BGIModelExecutionPolicy = .default
    ) throws {
        env = try ORTEnv(loggingLevel: loggingLevel)
        self.computePreference = computePreference
        self.modelExecutionPolicy = modelExecutionPolicy
    }

    func makeSession(model: BGIOnnxModel) throws -> PaddleOCROnnxSession {
        try PaddleOCROnnxSession(
            model: model,
            env: env,
            computePreference: computePreference,
            policy: modelExecutionPolicy
        )
    }
}

final class PaddleOCRRecognitionService {
    private let session: PaddleOCROnnxSession
    private let labels: [String]

    init(model: BGIOnnxModel = .paddleOcrRecV4, runtime: PaddleOCRRuntime) throws {
        guard model.kind == .paddleOcrRecognition else {
            throw PaddleOCROnnxRuntimeError.unsupportedModelKind(model.kind)
        }
        session = try runtime.makeSession(model: model)
        labels = try BGIModelAssetResolver.paddleCharacterDictionary(for: model)
    }

    func recognizeWithoutDetector(_ image: CGImage) throws -> PaddleOCRRecognitionOutput {
        let input = try PaddleOCRPreprocessor.recognitionInput(from: image)
        let output = try session.run(input.tensor)
        guard output.shape.count == 3 else {
            throw PaddleOCROnnxRuntimeError.invalidOutputShape(output.shape)
        }
        let line = try PaddleOCRCTCDecoder.decode(
            logits: output.values,
            timeSteps: output.shape[1],
            classCount: output.shape[2],
            labels: labels
        )
        return PaddleOCRRecognitionOutput(line: line, rawTensor: output, model: session.model)
    }
}

final class PaddleOCRDetectionService {
    private let session: PaddleOCROnnxSession
    private let postProcessorConfig: PaddleOCRDetectionPostProcessorConfig

    init(
        model: BGIOnnxModel = .paddleOcrDetV4,
        runtime: PaddleOCRRuntime,
        postProcessorConfig: PaddleOCRDetectionPostProcessorConfig = .bgiDefault
    ) throws {
        guard model.kind == .paddleOcrDetection else {
            throw PaddleOCROnnxRuntimeError.unsupportedModelKind(model.kind)
        }
        session = try runtime.makeSession(model: model)
        self.postProcessorConfig = postProcessorConfig
    }

    func detect(_ image: CGImage) throws -> PaddleOCRDetectionOutput {
        let input = try PaddleOCRPreprocessor.detectionInput(from: image)
        let output = try session.run(input.tensor)
        let regions = try PaddleOCRDetectionPostProcessor.regions(
            from: output,
            input: input,
            config: postProcessorConfig
        )
        return PaddleOCRDetectionOutput(regions: regions, rawTensor: output, input: input, model: session.model)
    }
}

final class PaddleOCRService {
    private let detector: PaddleOCRDetectionService
    private let recognizer: PaddleOCRRecognitionService

    init(
        detectionModel: BGIOnnxModel = .paddleOcrDetV4,
        recognitionModel: BGIOnnxModel = .paddleOcrRecV4,
        runtime: PaddleOCRRuntime
    ) throws {
        detector = try PaddleOCRDetectionService(model: detectionModel, runtime: runtime)
        recognizer = try PaddleOCRRecognitionService(model: recognitionModel, runtime: runtime)
    }

    func recognize(
        _ image: CGImage,
        sourceROI: NormalizedROI? = nil,
        frameIndex: UInt64 = 0,
        timestamp: Date = Date()
    ) throws -> OCRResult {
        let detection = try detector.detect(image)
        let regions = try detection.regions.map { region -> OCRResult.Region in
            let cropRect = region.boundingBox.integral
            guard let cropped = image.cropping(to: cropRect) else {
                throw PaddleOCROnnxRuntimeError.imageCropFailed(cropRect)
            }
            let recognized = try recognizer.recognizeWithoutDetector(cropped)
            return OCRResult.Region(
                boundingBox: cropRect,
                text: recognized.line.text,
                confidence: recognized.line.confidence
            )
        }
        return OCRResult(
            regions: regions,
            sourceROI: sourceROI,
            frameIndex: frameIndex,
            timestamp: timestamp
        )
    }
}

enum PaddleOCRDetectionPostProcessor {
    static func regions(
        from tensor: PaddleOCRTensor,
        input: PaddleOCRDetectionInput,
        config: PaddleOCRDetectionPostProcessorConfig = .bgiDefault
    ) throws -> [PaddleOCRDetectedRegion] {
        guard tensor.shape.count == 4,
              tensor.shape[0] == 1,
              tensor.shape[1] == 1 else {
            throw PaddleOCROnnxRuntimeError.invalidOutputShape(tensor.shape)
        }

        let outputHeight = tensor.shape[2]
        let outputWidth = tensor.shape[3]
        let resizedWidth = min(Int(input.resizedSize.width), outputWidth)
        let resizedHeight = min(Int(input.resizedSize.height), outputHeight)
        guard tensor.values.count >= outputWidth * outputHeight,
              resizedWidth > 0,
              resizedHeight > 0 else {
            throw PaddleOCROnnxRuntimeError.invalidOutputShape(tensor.shape)
        }

        let binary = makeBinaryMask(
            values: tensor.values,
            width: outputWidth,
            height: outputHeight,
            activeWidth: resizedWidth,
            activeHeight: resizedHeight,
            threshold: config.boxThreshold
        )
        let dilated = dilate(
            binary,
            width: resizedWidth,
            height: resizedHeight,
            kernelSize: config.dilatedSize
        )
        let components = connectedComponents(binary: dilated, width: resizedWidth, height: resizedHeight)
        let scale = input.resizedToOriginalScale
        let originalBounds = CGRect(origin: .zero, size: input.originalSize)

        return components
            .compactMap { component -> PaddleOCRDetectedRegion? in
                guard component.width > config.minSize, component.height > config.minSize else { return nil }
                let score = meanScore(component: component, values: tensor.values, width: outputWidth)
                if let threshold = config.boxScoreThreshold, score <= threshold {
                    return nil
                }

                let rect = unclippedRect(
                    component: component,
                    scale: scale,
                    unclipRatio: config.unclipRatio
                ).intersection(originalBounds).integral
                guard rect.width > 0, rect.height > 0 else { return nil }
                return PaddleOCRDetectedRegion(boundingBox: rect, score: score)
            }
            .sorted { lhs, rhs in
                if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) < 8 {
                    return lhs.boundingBox.midX < rhs.boundingBox.midX
                }
                return lhs.boundingBox.midY < rhs.boundingBox.midY
            }
    }

    private static func makeBinaryMask(
        values: [Float],
        width: Int,
        height: Int,
        activeWidth: Int,
        activeHeight: Int,
        threshold: Float?
    ) -> [Bool] {
        var binary = [Bool](repeating: false, count: activeWidth * activeHeight)
        for y in 0..<activeHeight {
            for x in 0..<activeWidth {
                let value = values[y * width + x]
                binary[y * activeWidth + x] = threshold.map { value > $0 } ?? (value > 0)
            }
        }
        return binary
    }

    private static func dilate(
        _ binary: [Bool],
        width: Int,
        height: Int,
        kernelSize: Int?
    ) -> [Bool] {
        guard let kernelSize, kernelSize > 1 else { return binary }

        var dilated = [Bool](repeating: false, count: binary.count)
        let radius = max(1, kernelSize - 1)
        for y in 0..<height where y * width < binary.count {
            for x in 0..<width where binary[y * width + x] {
                for dy in 0...radius {
                    for dx in 0...radius {
                        let nx = min(width - 1, x + dx)
                        let ny = min(height - 1, y + dy)
                        dilated[ny * width + nx] = true
                    }
                }
            }
        }
        return dilated
    }

    private static func connectedComponents(
        binary: [Bool],
        width: Int,
        height: Int
    ) -> [DetectionComponent] {
        var visited = [Bool](repeating: false, count: binary.count)
        var components: [DetectionComponent] = []
        let neighbors = [
            (-1, -1), (0, -1), (1, -1),
            (-1, 0),           (1, 0),
            (-1, 1),  (0, 1),  (1, 1)
        ]

        for y in 0..<height {
            for x in 0..<width {
                let start = y * width + x
                guard binary[start], !visited[start] else { continue }

                var queue = [(x: x, y: y)]
                var head = 0
                var minX = x
                var maxX = x
                var minY = y
                var maxY = y
                var pixels: [Int] = []
                visited[start] = true

                while head < queue.count {
                    let point = queue[head]
                    head += 1
                    pixels.append(point.y * width + point.x)
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)

                    for neighbor in neighbors {
                        let nx = point.x + neighbor.0
                        let ny = point.y + neighbor.1
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let index = ny * width + nx
                        guard binary[index], !visited[index] else { continue }
                        visited[index] = true
                        queue.append((x: nx, y: ny))
                    }
                }

                components.append(
                    DetectionComponent(
                        minX: minX,
                        minY: minY,
                        maxX: maxX,
                        maxY: maxY,
                        pixels: pixels,
                        maskWidth: width
                    )
                )
            }
        }
        return components
    }

    private static func meanScore(component: DetectionComponent, values: [Float], width: Int) -> Float {
        guard !component.pixels.isEmpty else { return 0 }
        let total = component.pixels.reduce(Float(0)) { partial, compactIndex in
            let x = compactIndex % component.maskWidth
            let y = compactIndex / component.maskWidth
            return partial + values[y * width + x]
        }
        return total / Float(component.pixels.count)
    }

    private static func unclippedRect(
        component: DetectionComponent,
        scale: Double,
        unclipRatio: Double
    ) -> CGRect {
        let width = Double(component.width)
        let height = Double(component.height)
        let minEdge = min(width, height)
        let expandedWidth = width + unclipRatio * minEdge
        let expandedHeight = height + unclipRatio * minEdge
        let centerX = Double(component.minX + component.maxX + 1) / 2.0
        let centerY = Double(component.minY + component.maxY + 1) / 2.0
        return CGRect(
            x: (centerX - expandedWidth / 2.0) * scale,
            y: (centerY - expandedHeight / 2.0) * scale,
            width: expandedWidth * scale,
            height: expandedHeight * scale
        )
    }
}

private struct DetectionComponent {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int
    let pixels: [Int]
    let maskWidth: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
}
#else
final class PaddleOCRRuntime {
    init() throws {
        throw PaddleOCROnnxRuntimeError.runtimeUnavailable
    }
}

final class PaddleOCRRecognitionService {
    init(model: BGIOnnxModel = .paddleOcrRecV4, runtime: PaddleOCRRuntime) throws {
        throw PaddleOCROnnxRuntimeError.runtimeUnavailable
    }

    func recognizeWithoutDetector(_ image: CGImage) throws -> PaddleOCRRecognitionOutput {
        throw PaddleOCROnnxRuntimeError.runtimeUnavailable
    }
}

final class PaddleOCRDetectionService {
    init(
        model: BGIOnnxModel = .paddleOcrDetV4,
        runtime: PaddleOCRRuntime,
        postProcessorConfig: PaddleOCRDetectionPostProcessorConfig = .bgiDefault
    ) throws {
        throw PaddleOCROnnxRuntimeError.runtimeUnavailable
    }

    func detect(_ image: CGImage) throws -> PaddleOCRDetectionOutput {
        throw PaddleOCROnnxRuntimeError.runtimeUnavailable
    }
}

final class PaddleOCRService {
    init(
        detectionModel: BGIOnnxModel = .paddleOcrDetV4,
        recognitionModel: BGIOnnxModel = .paddleOcrRecV4,
        runtime: PaddleOCRRuntime
    ) throws {
        throw PaddleOCROnnxRuntimeError.runtimeUnavailable
    }

    func recognize(
        _ image: CGImage,
        sourceROI: NormalizedROI? = nil,
        frameIndex: UInt64 = 0,
        timestamp: Date = Date()
    ) throws -> OCRResult {
        throw PaddleOCROnnxRuntimeError.runtimeUnavailable
    }
}
#endif

private extension PaddleOCRTensor {
    func mutableData() -> NSMutableData {
        values.withUnsafeBufferPointer { buffer in
            NSMutableData(
                bytes: buffer.baseAddress,
                length: buffer.count * MemoryLayout<Float>.stride
            )
        }
    }
}

private extension NSMutableData {
    func floatArray() -> [Float] {
        let count = length / MemoryLayout<Float>.stride
        var result = [Float](repeating: 0, count: count)
        result.withUnsafeMutableBufferPointer { outputBuffer in
            guard let outputBase = outputBuffer.baseAddress else { return }
            memcpy(outputBase, bytes, count * MemoryLayout<Float>.stride)
        }
        return result
    }
}
