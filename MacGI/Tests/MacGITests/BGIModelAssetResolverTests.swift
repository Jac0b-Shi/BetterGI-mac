import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI OCR model resources")
struct BGIModelAssetResolverTests {
    @Test("P0 PaddleOCR model resources resolve by full upstream path")
    func p0PaddleOCRModelsResolve() throws {
        let coverage = BGIModelAssetResolver.coverage(for: BGIOnnxModel.p0PaddleOCR)

        #expect(coverage.total == 3)
        #expect(coverage.resolved == 3)
        #expect(coverage.missing.isEmpty)

        let modelURLs = coverage.resolutions.compactMap(\.modelURL)
        #expect(Set(modelURLs.map(\.path)).count == 3)

        for url in modelURLs {
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
            #expect((size?.intValue ?? 0) > 1_000_000)
        }
    }

    @Test("PaddleOCR recognition labels are read from inference.yml")
    func paddleOCRRecognitionLabelsResolve() throws {
        let zhConfigURL = try #require(BGIModelAssetResolver.inferenceConfigURL(for: .paddleOcrRecV4))
        #expect(zhConfigURL.path.contains("PP-OCRv4_mobile_rec_infer"))

        let zhLabels = try BGIModelAssetResolver.paddleCharacterDictionary(for: .paddleOcrRecV4)
        let enLabels = try BGIModelAssetResolver.paddleCharacterDictionary(for: .paddleOcrRecV4En)

        #expect(zhLabels.count > 1_000)
        #expect(zhLabels.contains("原"))
        #expect(zhLabels.contains("神") || zhLabels.contains("委"))

        #expect(enLabels.contains("0"))
        #expect(enLabels.contains("A"))
        #expect(enLabels.contains("z"))
    }

    @Test("Upstream BetterGI ONNX model registry mirrors BgiOnnxModel asset paths")
    func upstreamModelRegistryMirrorsBgiOnnxModelPaths() {
        let models = BGIOnnxModel.upstreamRegisteredModels

        #expect(models.count == 16)
        #expect(Set(models.map(\.name)).count == models.count)
        #expect(models.contains(.bgiFish))
        #expect(models.contains(.bgiTree))
        #expect(models.contains(.bgiWorld))
        #expect(models.contains(.bgiMine))
        #expect(models.contains(.bgiAvatarSide))
        #expect(models.contains(.bgiQClassify))
        #expect(models.contains(.sileroVad))

        #expect(BGIOnnxModel.bgiFish.assetPath == "Assets/Model/Fish/bgi_fish.onnx")
        #expect(BGIOnnxModel.bgiTree.assetPath == "Assets/Model/Domain/bgi_tree.onnx")
        #expect(BGIOnnxModel.bgiWorld.assetPath == "Assets/Model/World/bgi_world.onnx")
        #expect(BGIOnnxModel.bgiMine.assetPath == "Assets/Model/Mine/bgi_mine.onnx")
        #expect(BGIOnnxModel.bgiAvatarSide.assetPath == "Assets/Model/Common/avatar_side_classify_sim.onnx")
        #expect(BGIOnnxModel.bgiQClassify.assetPath == "Assets/Model/Common/q_classify_sim.onnx")
        #expect(BGIOnnxModel.sileroVad.assetPath == "Assets/Model/Vad/silero_vad.onnx")

        #expect(BGIOnnxModel.yoloModels.count == 6)
        #expect(BGIOnnxModel.yoloModels.allSatisfy {
            $0.kind == .yoloDetection || $0.kind == .yoloClassification
        })
    }

    @Test("Runtime resource root can provide first-launch downloaded ONNX assets")
    func runtimeResourceRootProvidesDownloadedOnnxAssets() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-resource-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let modelURL = tempRoot.appendingPathComponent(BGIOnnxModel.bgiFish.assetPath)
        try FileManager.default.createDirectory(
            at: modelURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0, 1, 2, 3]).write(to: modelURL)

        let resolved = BGIModelAssetResolver.url(
            for: .bgiFish,
            runtimeResourceRoots: [tempRoot],
            includeBundle: false
        )
        #expect(resolved == modelURL)

        let coverage = BGIModelAssetResolver.coverage(
            for: [.bgiFish],
            runtimeResourceRoots: [tempRoot],
            includeBundle: false
        )
        #expect(coverage.total == 1)
        #expect(coverage.resolved == 1)
        #expect(coverage.missing.isEmpty)
    }
}
