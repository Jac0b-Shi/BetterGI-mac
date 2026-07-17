import Foundation

struct BGIOnnxModel: Identifiable, Equatable, Sendable {
    enum ModelKind: String, Sendable {
        case yapRecognition
        case paddleOcrDetection
        case paddleOcrRecognition
        case yoloDetection
        case yoloClassification
        case voiceActivityDetection
    }

    let name: String
    let assetPath: String
    let kind: ModelKind

    var id: String { name }

    var directoryPath: String {
        (assetPath as NSString).deletingLastPathComponent
    }

    var inferenceConfigPath: String? {
        switch kind {
        case .paddleOcrDetection, .paddleOcrRecognition:
            "\(directoryPath)/inference.yml"
        case .yapRecognition, .yoloDetection, .yoloClassification, .voiceActivityDetection:
            nil
        }
    }

    static let yapModelTraining = BGIOnnxModel(
        name: "YapModelTraining",
        assetPath: "Assets/Model/Yap/model_training.onnx",
        kind: .yapRecognition
    )

    static let bgiFish = BGIOnnxModel(
        name: "BgiFish",
        assetPath: "Assets/Model/Fish/bgi_fish.onnx",
        kind: .yoloDetection
    )

    static let bgiTree = BGIOnnxModel(
        name: "BgiTree",
        assetPath: "Assets/Model/Domain/bgi_tree.onnx",
        kind: .yoloDetection
    )

    static let bgiWorld = BGIOnnxModel(
        name: "BgiWorld",
        assetPath: "Assets/Model/World/bgi_world.onnx",
        kind: .yoloDetection
    )

    static let bgiMine = BGIOnnxModel(
        name: "BgiMine",
        assetPath: "Assets/Model/Mine/bgi_mine.onnx",
        kind: .yoloDetection
    )

    static let bgiAvatarSide = BGIOnnxModel(
        name: "BgiAvatarSide",
        assetPath: "Assets/Model/Common/avatar_side_classify_sim.onnx",
        kind: .yoloClassification
    )

    static let bgiQClassify = BGIOnnxModel(
        name: "BgiQClassify",
        assetPath: "Assets/Model/Common/q_classify_sim.onnx",
        kind: .yoloClassification
    )

    static let sileroVad = BGIOnnxModel(
        name: "SileroVad",
        assetPath: "Assets/Model/Vad/silero_vad.onnx",
        kind: .voiceActivityDetection
    )

    static let paddleOcrDetV4 = BGIOnnxModel(
        name: "PpOcrDetV4",
        assetPath: "Assets/Model/PaddleOCR/Det/V4/PP-OCRv4_mobile_det_infer/slim.onnx",
        kind: .paddleOcrDetection
    )

    static let paddleOcrDetV5 = BGIOnnxModel(
        name: "PpOcrDetV5",
        assetPath: "Assets/Model/PaddleOCR/Det/V5/PP-OCRv5_mobile_det_infer/slim.onnx",
        kind: .paddleOcrDetection
    )

    static let paddleOcrRecV4 = BGIOnnxModel(
        name: "PpOcrRecV4",
        assetPath: "Assets/Model/PaddleOCR/Rec/V4/PP-OCRv4_mobile_rec_infer/slim.onnx",
        kind: .paddleOcrRecognition
    )

    static let paddleOcrRecV4En = BGIOnnxModel(
        name: "PpOcrRecV4En",
        assetPath: "Assets/Model/PaddleOCR/Rec/V4/en_PP-OCRv4_mobile_rec_infer/slim.onnx",
        kind: .paddleOcrRecognition
    )

    static let paddleOcrRecV5 = BGIOnnxModel(
        name: "PpOcrRecV5",
        assetPath: "Assets/Model/PaddleOCR/Rec/V5/PP-OCRv5_mobile_rec_infer/slim.onnx",
        kind: .paddleOcrRecognition
    )

    static let paddleOcrRecV5Latin = BGIOnnxModel(
        name: "PpOcrRecV5Latin",
        assetPath: "Assets/Model/PaddleOCR/Rec/V5/latin_PP-OCRv5_mobile_rec_infer/slim.onnx",
        kind: .paddleOcrRecognition
    )

    static let paddleOcrRecV5Eslav = BGIOnnxModel(
        name: "PpOcrRecV5Eslav",
        assetPath: "Assets/Model/PaddleOCR/Rec/V5/eslav_PP-OCRv5_mobile_rec_infer/slim.onnx",
        kind: .paddleOcrRecognition
    )

    static let paddleOcrRecV5Korean = BGIOnnxModel(
        name: "PpOcrRecV5Korean",
        assetPath: "Assets/Model/PaddleOCR/Rec/V5/korean_PP-OCRv5_mobile_rec_infer/slim.onnx",
        kind: .paddleOcrRecognition
    )

    static let p0PaddleOCR: [BGIOnnxModel] = [
        .paddleOcrDetV4,
        .paddleOcrRecV4,
        .paddleOcrRecV4En
    ]

    static let upstreamRegisteredModels: [BGIOnnxModel] = [
        .yapModelTraining,
        .bgiFish,
        .bgiTree,
        .bgiWorld,
        .bgiMine,
        .bgiAvatarSide,
        .bgiQClassify,
        .sileroVad,
        .paddleOcrDetV4,
        .paddleOcrDetV5,
        .paddleOcrRecV4,
        .paddleOcrRecV4En,
        .paddleOcrRecV5,
        .paddleOcrRecV5Latin,
        .paddleOcrRecV5Eslav,
        .paddleOcrRecV5Korean
    ]

    static let yoloModels: [BGIOnnxModel] = [
        .bgiFish,
        .bgiTree,
        .bgiWorld,
        .bgiMine,
        .bgiAvatarSide,
        .bgiQClassify
    ]

    static let runtimeDownloadCandidates: [BGIOnnxModel] = upstreamRegisteredModels.filter {
        !p0PaddleOCR.contains($0)
    }
}

struct BGIModelAssetResolution: Identifiable, Equatable, Sendable {
    let model: BGIOnnxModel
    let modelURL: URL?
    let inferenceConfigURL: URL?

    var id: String { model.id }
    var isResolved: Bool {
        modelURL != nil && (model.inferenceConfigPath == nil || inferenceConfigURL != nil)
    }
}

struct BGIModelAssetCoverage: Equatable, Sendable {
    let resolutions: [BGIModelAssetResolution]

    var total: Int { resolutions.count }
    var resolved: Int { resolutions.filter(\.isResolved).count }
    var missing: [String] {
        resolutions.flatMap { resolution -> [String] in
            var result: [String] = []
            if resolution.modelURL == nil { result.append(resolution.model.assetPath) }
            if let inferenceConfigPath = resolution.model.inferenceConfigPath,
               resolution.inferenceConfigURL == nil {
                result.append(inferenceConfigPath)
            }
            return result
        }
    }

    var summary: String {
        "\(resolved)/\(total) models"
    }
}

enum BGIModelAssetResolver {
    static func url(
        for path: String,
        runtimeResourceRoots: [URL] = BGIRuntimeResourceStore.defaultSearchRoots(),
        includeBundle: Bool = true
    ) -> URL? {
        let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalized.isEmpty else { return nil }

        for root in runtimeResourceRoots {
            for candidate in runtimeCandidates(for: normalized, root: root) {
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        guard includeBundle else { return nil }

        let nsPath = normalized as NSString
        let subdirectory = nsPath.deletingLastPathComponent
        let fileName = nsPath.lastPathComponent as NSString
        let resourceName = fileName.deletingPathExtension
        let fileExtension = fileName.pathExtension.isEmpty ? nil : fileName.pathExtension

        let baseURLs = [
            Bundle.module.resourceURL,
            Bundle.module.bundleURL
        ].compactMap { $0 }

        for baseURL in baseURLs {
            for candidate in [
                baseURL.appendingPathComponent("Resources").appendingPathComponent(normalized),
                baseURL.appendingPathComponent(normalized)
            ] {
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        if let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: fileExtension,
            subdirectory: subdirectory.isEmpty ? nil : subdirectory
        ) {
            return url
        }

        return Bundle.module.url(forResource: normalized, withExtension: nil)
    }

    static func url(
        for model: BGIOnnxModel,
        runtimeResourceRoots: [URL] = BGIRuntimeResourceStore.defaultSearchRoots(),
        includeBundle: Bool = true
    ) -> URL? {
        url(for: model.assetPath, runtimeResourceRoots: runtimeResourceRoots, includeBundle: includeBundle)
    }

    static func inferenceConfigURL(
        for model: BGIOnnxModel,
        runtimeResourceRoots: [URL] = BGIRuntimeResourceStore.defaultSearchRoots(),
        includeBundle: Bool = true
    ) -> URL? {
        guard let inferenceConfigPath = model.inferenceConfigPath else { return nil }
        return url(for: inferenceConfigPath, runtimeResourceRoots: runtimeResourceRoots, includeBundle: includeBundle)
    }

    static func coverage(
        for models: [BGIOnnxModel],
        runtimeResourceRoots: [URL] = BGIRuntimeResourceStore.defaultSearchRoots(),
        includeBundle: Bool = true
    ) -> BGIModelAssetCoverage {
        BGIModelAssetCoverage(
            resolutions: models.map { model in
                BGIModelAssetResolution(
                    model: model,
                    modelURL: url(for: model, runtimeResourceRoots: runtimeResourceRoots, includeBundle: includeBundle),
                    inferenceConfigURL: inferenceConfigURL(
                        for: model,
                        runtimeResourceRoots: runtimeResourceRoots,
                        includeBundle: includeBundle
                    )
                )
            }
        )
    }

    static func paddleCharacterDictionary(for model: BGIOnnxModel) throws -> [String] {
        guard model.kind == .paddleOcrRecognition else {
            throw BGIModelAssetResolverError.notRecognitionModel(model.name)
        }
        guard let configURL = inferenceConfigURL(for: model) else {
            throw BGIModelAssetResolverError.missingAsset(model.inferenceConfigPath ?? "\(model.name)/inference.yml")
        }
        let text = try String(contentsOf: configURL, encoding: .utf8)
        return try parsePaddleCharacterDictionary(from: text)
    }

    static func parsePaddleCharacterDictionary(from yamlText: String) throws -> [String] {
        let lines = yamlText.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "character_dict:" }) else {
            throw BGIModelAssetResolverError.missingCharacterDictionary
        }

        var result: [String] = []
        for rawLine in lines.dropFirst(start + 1) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("- ") else {
                if !trimmed.isEmpty && !rawLine.hasPrefix(" ") {
                    break
                }
                continue
            }
            let value = String(trimmed.dropFirst(2))
            result.append(unquoteYAMLScalar(value))
        }

        guard !result.isEmpty else {
            throw BGIModelAssetResolverError.missingCharacterDictionary
        }
        return result
    }

    private static func unquoteYAMLScalar(_ value: String) -> String {
        if value == "''" { return "" }
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            let inner = value.dropFirst().dropLast()
            return inner.replacingOccurrences(of: "''", with: "'")
        }
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func runtimeCandidates(for normalizedPath: String, root: URL) -> [URL] {
        [
            root.appendingPathComponent(normalizedPath),
            root.appendingPathComponent("Resources").appendingPathComponent(normalizedPath),
            root.appendingPathComponent("Cache").appendingPathComponent(normalizedPath)
        ]
    }
}

enum BGIModelAssetResolverError: LocalizedError {
    case missingAsset(String)
    case notRecognitionModel(String)
    case missingCharacterDictionary

    var errorDescription: String? {
        switch self {
        case let .missingAsset(path):
            "BetterGI model asset not found in bundle: \(path)"
        case let .notRecognitionModel(name):
            "Paddle character dictionary is only available for recognition models: \(name)"
        case .missingCharacterDictionary:
            "PaddleOCR inference.yml is missing PostProcess.character_dict"
        }
    }
}
