import Foundation
import OnnxRuntimeBindings

enum BGIYOLOError: LocalizedError {
    case missingModel
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingModel: "YOLO 模型文件缺失"
        case let .inferenceFailed(msg): "YOLO 推理失败: \(msg)"
        }
    }
}

/// First-layer YOLO ONNX inference session.
/// Reuses the same ORTEnv/ORTSession infrastructure already wired for PaddleOCR.
final class BGIYOLOOonnxSession {
    private let session: ORTSession
    private let inputName: String
    private let outputName: String
    let inputSize: CGSize

    init(model: BGIOnnxModel, env: ORTEnv, inputWidth: Int = 640, inputHeight: Int = 640) throws {
        guard let modelURL = BGIModelAssetResolver.url(for: model) else {
            throw BGIYOLOError.missingModel
        }
        let sessionOptions = try ORTSessionOptions()
        try sessionOptions.setIntraOpNumThreads(1)
        self.session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: sessionOptions)
        inputSize = CGSize(width: inputWidth, height: inputHeight)

        let inputNames = try session.inputNames()
        guard let firstInput = inputNames.first else {
            throw BGIYOLOError.inferenceFailed("missing input name")
        }
        inputName = firstInput

        let outputNames = try session.outputNames()
        guard let firstOutput = outputNames.first else {
            throw BGIYOLOError.inferenceFailed("missing output name")
        }
        outputName = firstOutput
    }

    func detect(tensor: [Float], shape: [Int]) throws -> [Float] {
        guard !tensor.isEmpty else {
            throw BGIYOLOError.inferenceFailed("empty input tensor")
        }
        let data = tensor.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress!, length: tensor.count * MemoryLayout<Float>.stride) }
        let inputValue = try ORTValue(
            tensorData: data,
            elementType: .float,
            shape: shape.map { NSNumber(value: $0) }
        )
        let outputs = try session.run(
            withInputs: [inputName: inputValue],
            outputNames: Set([outputName]),
            runOptions: nil
        )
        guard let output = outputs[outputName] else {
            throw BGIYOLOError.inferenceFailed("output tensor unavailable")
        }
        let outputData = try output.tensorData()
        return outputData.toFloatArray()
    }
}

extension NSMutableData {
    fileprivate func toFloatArray() -> [Float] {
        let count = length / MemoryLayout<Float>.stride
        var result = [Float](repeating: 0, count: count)
        result.withUnsafeMutableBufferPointer { out in
            memcpy(out.baseAddress!, bytes, count * MemoryLayout<Float>.stride)
        }
        return result
    }
}

final class BGIYOLORuntime {
    private let env: ORTEnv

    init(loggingLevel: ORTLoggingLevel = .warning) throws {
        env = try ORTEnv(loggingLevel: loggingLevel)
    }

    func makeSession(model: BGIOnnxModel) throws -> BGIYOLOOonnxSession {
        try BGIYOLOOonnxSession(model: model, env: env)
    }
}
