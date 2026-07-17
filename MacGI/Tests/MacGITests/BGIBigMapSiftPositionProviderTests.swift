import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI big-map SIFT position provider")
struct BGIBigMapSiftPositionProviderTests {
    @MainActor
    @Test("Registers 256-scale Teyvat SIFT assets and converts matched center to Genshin coordinates")
    func registersAssetsAndConvertsMatchedCenter() async throws {
        let root = try makeTemporaryStoreRoot()
        let store = BGIRuntimeResourceStore(rootURL: root)
        try writeSiftAssets(in: store)
        let matcher = FakeBigMapSiftMatcher(
            outcome: .matched(BGIBigMapMatch(
                rect256: CGRect(x: 1_024, y: 512, width: 100, height: 50),
                queryKeypoints: 20,
                goodMatches: 12,
                inliers: 9,
                meanReprojectionError: 1.2
            ))
        )
        let provider = BGIBigMapSiftPositionProvider(
            captureFrameProvider: { try makeFrame(width: 320, height: 180) },
            matcher: matcher,
            store: store
        )

        let point = try await provider.getBigMapCenter(mapName: "Teyvat")

        #expect(matcher.registerCalls.count == 1)
        #expect(matcher.registerCalls.first?.mapID == "Teyvat")
        #expect(matcher.registerCalls.first?.mapWidth256 == 5_632)
        #expect(matcher.registerCalls.first?.mapHeight256 == 3_840)
        #expect(matcher.matchCalls.count == 1)
        #expect(abs(point.x - 12_088) < 0.001)
        #expect(abs(point.y - 6_044) < 0.001)
    }

    @MainActor
    @Test("Does not re-register assets after first successful registration")
    func doesNotReregisterAssets() async throws {
        let root = try makeTemporaryStoreRoot()
        let store = BGIRuntimeResourceStore(rootURL: root)
        try writeSiftAssets(in: store)
        let matcher = FakeBigMapSiftMatcher(outcome: .matched(BGIBigMapMatch(
            rect256: CGRect(x: 1_024, y: 512, width: 100, height: 50),
            queryKeypoints: 20,
            goodMatches: 12,
            inliers: 9,
            meanReprojectionError: 1.2
        )))
        let provider = BGIBigMapSiftPositionProvider(
            captureFrameProvider: { try makeFrame(width: 320, height: 180) },
            matcher: matcher,
            store: store
        )

        _ = try await provider.getBigMapCenter(mapName: "Teyvat")
        _ = try await provider.getBigMapCenter(mapName: "Teyvat")

        #expect(matcher.registerCalls.count == 1)
        #expect(matcher.matchCalls.count == 2)
    }

    @MainActor
    @Test("Surfaces no-match quality metrics")
    func surfacesNoMatchQualityMetrics() async throws {
        let root = try makeTemporaryStoreRoot()
        let store = BGIRuntimeResourceStore(rootURL: root)
        try writeSiftAssets(in: store)
        let matcher = FakeBigMapSiftMatcher(outcome: .noMatch(BGIBigMapMatchQuality(
            queryKeypoints: 5,
            goodMatches: 2
        )))
        let provider = BGIBigMapSiftPositionProvider(
            captureFrameProvider: { try makeFrame(width: 320, height: 180) },
            matcher: matcher,
            store: store
        )

        await #expect(throws: BGIBigMapSiftPositionProviderError.noMatch(queryKeypoints: 5, goodMatches: 2)) {
            _ = try await provider.getBigMapCenter(mapName: "Teyvat")
        }
    }

    @MainActor
    @Test("Rejects maps without SIFT asset descriptors")
    func rejectsUnsupportedMaps() async throws {
        let store = BGIRuntimeResourceStore(rootURL: try makeTemporaryStoreRoot())
        let provider = BGIBigMapSiftPositionProvider(
            captureFrameProvider: { try makeFrame(width: 320, height: 180) },
            matcher: FakeBigMapSiftMatcher(outcome: .internalError),
            store: store
        )

        await #expect(throws: BGIBigMapSiftPositionProviderError.unsupportedMap("Enkanomiya")) {
            _ = try await provider.getBigMapCenter(mapName: "Enkanomiya")
        }
    }

    private func makeTemporaryStoreRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-bigmap-sift-provider-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeSiftAssets(in store: BGIRuntimeResourceStore) throws {
        let mapDir = store.mapsURL.appendingPathComponent("Teyvat", isDirectory: true)
        try FileManager.default.createDirectory(at: mapDir, withIntermediateDirectories: true)
        try Data([0x01, 0x02]).write(to: mapDir.appendingPathComponent("Teyvat_0_256_SIFT.kp.bin"))
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: mapDir.appendingPathComponent("Teyvat_0_256_SIFT.mat.png"))
    }
}

private final class FakeBigMapSiftMatcher: BGIBigMapSiftMatching, @unchecked Sendable {
    struct RegisterCall: Equatable {
        let mapID: String
        let mapWidth256: Int32
        let mapHeight256: Int32
    }

    struct MatchCall: Equatable {
        let mapID: String
        let width: Int32
        let height: Int32
        let stride: Int
        let dataCount: Int
    }

    private let outcome: BGIBigMapMatchOutcome
    private(set) var registerCalls: [RegisterCall] = []
    private(set) var matchCalls: [MatchCall] = []

    init(outcome: BGIBigMapMatchOutcome) {
        self.outcome = outcome
    }

    func registerAssets(
        mapID: String,
        keypointData: Data,
        descriptorPNGData: Data,
        mapWidth256: Int32,
        mapHeight256: Int32
    ) throws {
        registerCalls.append(RegisterCall(
            mapID: mapID,
            mapWidth256: mapWidth256,
            mapHeight256: mapHeight256
        ))
    }

    func unregisterAssets(mapID: String) throws {}

    func match(
        mapID: String,
        grayscaleData: Data,
        width: Int32,
        height: Int32,
        stride: Int
    ) throws -> BGIBigMapMatchOutcome {
        matchCalls.append(MatchCall(
            mapID: mapID,
            width: width,
            height: height,
            stride: stride,
            dataCount: grayscaleData.count
        ))
        return outcome
    }
}

private func makeFrame(width: Int, height: Int) throws -> CaptureImageFrame {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0xff, count: height * bytesPerRow)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
    ), let image = context.makeImage() else {
        throw NSError(domain: "BGIBigMapSiftPositionProviderTests", code: 1)
    }
    return CaptureImageFrame(
        metadata: CapturedFrame(
            frameIndex: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            width: width,
            height: height,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: bytesPerRow,
            sourceWindow: WindowInfo(
                id: 42,
                ownerPID: 100,
                ownerName: "wine64-preloader",
                title: "原神",
                frame: CGRect(x: 0, y: 0, width: width, height: height),
                layer: 0,
                isOnScreen: true,
                scaleFactor: 1
            )
        ),
        cgImage: image,
        backendName: "Synthetic"
    )
}
