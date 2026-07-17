import CoreGraphics
import Foundation
import ImageIO
@testable import MacGI
import Testing
import UniformTypeIdentifiers

@Suite("BetterGI mini map localization service")
struct BGIMiniMapLocalizationServiceTests {

    // MARK: - Self-contained tests (no external resources)

    @Test("Service reports missing map root for unknown region")
    func missingMapRootError() throws {
        let store = BGIRuntimeResourceStore(rootURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-test-missing-map-root", isDirectory: true))
        let service = BGIMiniMapLocalizationService(store: store)
        let frame = try makeFrame(color: .black)

        do {
            _ = try service.getPosition(from: frame, mapName: "UnknownRegion")
            Issue.record("Expected missingMapRoot error, got success")
        } catch let error as BGIMiniMapLocalizationError {
            #expect(error == .missingMapRoot(store.mapsURL.appendingPathComponent("UnknownRegion", isDirectory: true)))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Service with fixture reaches matching stage and fails with noLayerMatched or noMatchInLayer")
    func localizationReachesMatchingStage() throws {
        let fixture = try makeTeyvatFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = BGIMiniMapLocalizationService(store: fixture.store)
        let frame = try makeFrame(color: .black)

        do {
            _ = try service.getPosition(from: frame, mapName: "Teyvat")
            Issue.record("Expected localization to fail on synthetic tile, got success")
        } catch let error as BGIMiniMapLocalizationError {
            switch error {
            case .noLayerMatched, .noMatchInLayer, .tooManyIconPixels,
                 .orientationNotConfident, .miniMapExtractionFailed:
                // These are all post-loading errors — the service successfully
                // loaded the map root, parsed city_info, and loaded the tile
                // images.  Which specific error we hit depends on the synthetic
                // frame content; all are acceptable proofs that loading worked.
                break
            default:
                Issue.record("Hit pre-matching error, loading may have failed: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("getCameraOrientation with fixture returns finite estimate")
    func cameraOrientationFixture() throws {
        let fixture = try makeTeyvatFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = BGIMiniMapLocalizationService(store: fixture.store)
        let frame = try makeFrame(color: .black)

        let orientation = try service.getCameraOrientation(from: frame)
        #expect(orientation.degrees.isFinite)
        #expect(orientation.confidence.isFinite)
    }

    @Test("Layer cache returns equivalent layer descriptors on subsequent loads")
    func layerCacheEquivalence() throws {
        let fixture = try makeTeyvatFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = BGIMiniMapLocalizationService(store: fixture.store)

        let layersA = try service.loadLayers(mapName: "Teyvat")
        let layersB = try service.loadLayers(mapName: "Teyvat")

        #expect(layersA.count == layersB.count)
        #expect(layersA.count == 2)
        for (a, b) in zip(layersA, layersB) {
            #expect(a.descriptor.layerId == b.descriptor.layerId)
            #expect(a.descriptor.name == b.descriptor.name)
            #expect(a.descriptor.scale == b.descriptor.scale)
            #expect(a.coarseColorMap.width == b.coarseColorMap.width)
            #expect(a.coarseColorMap.height == b.coarseColorMap.height)
            #expect(a.fineGrayMap.width == b.fineGrayMap.width)
            #expect(a.fineGrayMap.height == b.fineGrayMap.height)
        }
    }

    @Test("Global rough match lazily loads layers until early confidence")
    func globalRoughMatchLazilyLoadsUntilEarlyConfidence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-test-lazy-layer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let assetsDir = root.appendingPathComponent("Assets/Map/Teyvat", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let descriptors: [[String: Any]] = [
            [
                "LayerId": "MapBack_1",
                "Name": "Main",
                "Scale": 1.0,
                "Top": 0.0,
                "Left": 0.0,
                "IsOverSize": false
            ],
            [
                "LayerId": "LayeredMap_missing",
                "Name": "Missing",
                "Scale": 1.0,
                "Top": 0.0,
                "Left": 0.0,
                "IsOverSize": false
            ]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: descriptors, options: [.sortedKeys])
        try jsonData.write(to: assetsDir.appendingPathComponent("city_info.json"))

        let rough = makePattern(width: 52, height: 52, channels: 3)
        let exact = makePattern(width: 260, height: 260, channels: 1)
        let coarse = embed(rough, inWidth: 64, height: 64, atX: 6, y: 7)
        try writeCGImage(try coarse.cgImage(mode: .rgb), to: assetsDir.appendingPathComponent("MapBack_1_color.webp"))
        try writeCGImage(try exact.cgImage(mode: .grayscale), to: assetsDir.appendingPathComponent("MapBack_1_gray.webp"))

        let service = BGIMiniMapLocalizationService(store: BGIRuntimeResourceStore(rootURL: root))
        let maybeMatch = try service.globalRoughMatch(
            template: makePreparedTemplate(rough: rough, exact: exact),
            mapName: "Teyvat",
            earlyConfidence: 0.95
        )
        let match = try #require(maybeMatch)

        #expect(match.layer.descriptor.layerId == "MapBack_1")
        #expect(match.result.sourcePoint == CGPoint(x: 6, y: 7))
        #expect(match.result.confidence > 0.999)

        do {
            _ = try service.loadLayers(mapName: "Teyvat")
            Issue.record("Eager loading should fail on the intentionally missing second layer")
        } catch let error as BGIMiniMapLocalizationError {
            guard case .missingLayerTile = error else {
                Issue.record("Expected missingLayerTile, got \(error)")
                return
            }
        }
    }

    @Test("Local match refines exact search from rough match result")
    func localMatchRefinesExactSearchFromRoughResult() throws {
        let fixture = try makeTeyvatFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = BGIMiniMapLocalizationService(store: fixture.store)
        let setup = makeLocalMatchSetup(layerId: "current-layer")
        let staleNear = setup.layer.mapToWorld(
            CGPoint(x: 70, y: 80),
            zoom: Double(BGIMiniMapConstants.roughZoom),
            miniMapSize: BGIMiniMapConstants.roughMatchSize
        )

        let result = try #require(service.localMatch(
            template: setup.template,
            layers: [setup.layer],
            near: staleNear,
            preferredLayerId: "current-layer",
            orientation: BGIMiniMapOrientationEstimate(degrees: 45, confidence: 1),
            roughThreshold: 0.99,
            exactThreshold: 0.99
        ))

        #expect(result.layerId == "current-layer")
        #expect(result.worldPoint == setup.expectedWorld)
    }

    @Test("Local match tries other layers when preferred layer misses")
    func localMatchTriesOtherLayersWhenPreferredLayerMisses() throws {
        let fixture = try makeTeyvatFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = BGIMiniMapLocalizationService(store: fixture.store)
        let match = makeLocalMatchSetup(layerId: "matching-layer")
        let miss = makeNonMatchingLayer(layerId: "previous-layer")
        let staleNear = match.layer.mapToWorld(
            CGPoint(x: 70, y: 80),
            zoom: Double(BGIMiniMapConstants.roughZoom),
            miniMapSize: BGIMiniMapConstants.roughMatchSize
        )

        let result = try #require(service.localMatch(
            template: match.template,
            layers: [miss, match.layer],
            near: staleNear,
            preferredLayerId: "previous-layer",
            orientation: BGIMiniMapOrientationEstimate(degrees: 45, confidence: 1),
            roughThreshold: 0.99,
            exactThreshold: 0.99
        ))

        #expect(result.layerId == "matching-layer")
        #expect(result.worldPoint == match.expectedWorld)
    }

    // MARK: - Fixture helpers

    /// A minimal Teyvat map fixture that the service can load without external resources.
    private struct TeyvatFixture {
        let root: URL
        let store: BGIRuntimeResourceStore
    }

    private func makeTeyvatFixture() throws -> TeyvatFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-test-teyvat-fixture-\(UUID().uuidString)", isDirectory: true)
        let assetsDir = root.appendingPathComponent("Assets/Map/Teyvat", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        // Write multiple upstream-style layer JSON files.  BetterGI loads all
        // `*.json` files recursively, not only `city_info.json`.
        let layerId = "test-layer"
        let extraLayerId = "extra-layer"
        let cityInfo: [[String: Any]] = [[
            "LayerId": layerId,
            "Name": "TestLayer",
            "Scale": 1.0,
            "Top": 0.0,
            "Left": 0.0,
            "IsOverSize": false
        ]]
        let jsonData = try JSONSerialization.data(withJSONObject: cityInfo, options: [.sortedKeys])
        try jsonData.write(to: assetsDir.appendingPathComponent("city_info.json"))

        let layerInfo: [[String: Any]] = [[
            "LayerId": extraLayerId,
            "Name": "ExtraLayer",
            "Scale": 1.0,
            "Top": 0.0,
            "Left": 0.0,
            "IsOverSize": false
        ]]
        let layerInfoData = try JSONSerialization.data(withJSONObject: layerInfo, options: [.sortedKeys])
        try layerInfoData.write(to: assetsDir.appendingPathComponent("layer_map_info.json"))

        // Write small but valid tile images (52×52 minimum for rough match).
        let side = 52
        let rgbImage = try makeSolidImage(width: side, height: side, color: .gray)
        let grayImage = try makeGrayImage(width: side, height: side)

        try writeCGImage(rgbImage, to: assetsDir.appendingPathComponent("\(layerId)_color.webp"))
        try writeCGImage(grayImage, to: assetsDir.appendingPathComponent("\(layerId)_gray.webp"))
        try writeCGImage(rgbImage, to: assetsDir.appendingPathComponent("\(extraLayerId)_color.webp"))
        try writeCGImage(grayImage, to: assetsDir.appendingPathComponent("\(extraLayerId)_gray.webp"))

        return TeyvatFixture(
            root: root,
            store: BGIRuntimeResourceStore(rootURL: root)
        )
    }

    private func makeFrame(color: Color) throws -> CaptureImageFrame {
        let image = try makeSolidImage(width: 1920, height: 1080, color: color)
        return CaptureImageFrame(
            metadata: makeMetadata(width: 1920, height: 1080),
            cgImage: image,
            backendName: "Synthetic"
        )
    }

    private func makeMetadata(width: Int, height: Int) -> CapturedFrame {
        CapturedFrame.mock(window: .mock(), frameIndex: 0)
    }

    private func makeSolidImage(width: Int, height: Int, color: Color) throws -> CGImage {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in 0..<(width * height) {
            let offset = pixel * 4
            switch color {
            case .black: break // all zeros
            case .white:
                rgba[offset] = 255; rgba[offset + 1] = 255; rgba[offset + 2] = 255
            case .gray:
                rgba[offset] = 128; rgba[offset + 1] = 128; rgba[offset + 2] = 128
            }
            rgba[offset + 3] = 255
        }
        return try cgImage(from: &rgba, width: width, height: height)
    }

    private func makeGrayImage(width: Int, height: Int) throws -> CGImage {
        var gray = [UInt8](repeating: 128, count: width * height)
        guard let context = CGContext(
            data: &gray,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let image = context.makeImage() else {
            throw NSError(domain: "BGIMiniMapLocalizationServiceTests", code: 2)
        }
        return image
    }

    private func cgImage(from rgba: inout [UInt8], width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw NSError(domain: "BGIMiniMapLocalizationServiceTests", code: 1)
        }
        return image
    }

    private func writeCGImage(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "BGIMiniMapLocalizationServiceTests", code: 3)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "BGIMiniMapLocalizationServiceTests", code: 4)
        }
    }

    private struct LocalMatchSetup {
        let layer: BGIMiniMapTemplateLayer
        let template: BGIMiniMapPreparedTemplate
        let expectedWorld: CGPoint
    }

    private func makeLocalMatchSetup(layerId: String) -> LocalMatchSetup {
        let rough = makePattern(width: 52, height: 52, channels: 3)
        let exact = makePattern(width: 260, height: 260, channels: 1)
        let roughPoint = CGPoint(x: 80, y: 80)
        let exactPoint = CGPoint(x: 380, y: 380)
        let layer = makeLayer(
            layerId: layerId,
            coarse: embed(rough, inWidth: 160, height: 160, atX: Int(roughPoint.x), y: Int(roughPoint.y)),
            fine: embed(exact, inWidth: 700, height: 700, atX: Int(exactPoint.x), y: Int(exactPoint.y))
        )
        return LocalMatchSetup(
            layer: layer,
            template: makePreparedTemplate(rough: rough, exact: exact),
            expectedWorld: layer.mapToWorld(
                exactPoint,
                zoom: Double(BGIMiniMapConstants.exactZoom),
                miniMapSize: BGIMiniMapConstants.exactMatchSize
            )
        )
    }

    private func makeNonMatchingLayer(layerId: String) -> BGIMiniMapTemplateLayer {
        makeLayer(
            layerId: layerId,
            coarse: PixelImage(width: 160, height: 160, channelCount: 3, values: [Double](repeating: 1, count: 160 * 160 * 3)),
            fine: PixelImage(width: 700, height: 700, channelCount: 1, values: [Double](repeating: 1, count: 700 * 700))
        )
    }

    private func makeLayer(layerId: String, coarse: PixelImage, fine: PixelImage) -> BGIMiniMapTemplateLayer {
        BGIMiniMapTemplateLayer(
            descriptor: BGIMiniMapLayerDescriptor(
                layerGroupId: nil,
                layerId: layerId,
                name: layerId,
                scale: 1,
                floor: 0,
                top: 1000,
                left: 1000,
                isOverSize: false
            ),
            coarseColorMap: coarse,
            fineGrayMap: fine
        )
    }

    private func makePreparedTemplate(rough: PixelImage, exact: PixelImage) -> BGIMiniMapPreparedTemplate {
        let roughMask = [Double](repeating: 1, count: rough.width * rough.height)
        let exactMask = [Double](repeating: 1, count: exact.width * exact.height)
        return BGIMiniMapPreparedTemplate(
            roughColor: rough,
            roughMask: roughMask,
            exactGray: exact,
            exactMask: exactMask,
            roughWorstSqDiff: worstSqDiff(template: rough, mask: roughMask),
            exactWorstSqDiff: worstSqDiff(template: exact, mask: exactMask)
        )
    }

    private func makePattern(width: Int, height: Int, channels: Int) -> PixelImage {
        var values: [Double] = []
        values.reserveCapacity(width * height * channels)
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<channels {
                    values.append(Double((x * 13 + y * 29 + x * y * 3 + channel * 71) % 251 + 2))
                }
            }
        }
        return PixelImage(width: width, height: height, channelCount: channels, values: values)
    }

    private func embed(_ template: PixelImage, inWidth width: Int, height: Int, atX originX: Int, y originY: Int) -> PixelImage {
        var values = [Double](repeating: 1, count: width * height * template.channelCount)
        for y in 0..<template.height {
            for x in 0..<template.width {
                for channel in 0..<template.channelCount {
                    let sourceIndex = ((originY + y) * width + (originX + x)) * template.channelCount + channel
                    values[sourceIndex] = template.value(x: x, y: y, channel: channel)
                }
            }
        }
        return PixelImage(width: width, height: height, channelCount: template.channelCount, values: values)
    }

    private func worstSqDiff(template: PixelImage, mask: [Double]) -> Double {
        var sum = 0.0
        for y in 0..<template.height {
            for x in 0..<template.width {
                for channel in 0..<template.channelCount {
                    let value = template.value(x: x, y: y, channel: channel)
                    let inverted = max(value, 255.0 - value)
                    sum += inverted * inverted * mask[y * template.width + x]
                }
            }
        }
        return sum
    }

    private enum Color {
        case black, white, gray
    }
}
