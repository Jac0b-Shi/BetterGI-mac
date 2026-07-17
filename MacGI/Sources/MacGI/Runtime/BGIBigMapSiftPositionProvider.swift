import CoreGraphics
import Foundation

// MARK: - Observation

/// Complete big-map observation — retains the full SIFT rect for viewport click math.
struct BGIBigMapObservation: Sendable {
    /// SIFT-returned visible area in 256-scale full-map texture coordinates.
    let visibleRect256: CGRect
    /// visibleRect256 center converted to Genshin world coordinates.
    let centerWorld: CGPoint
    /// SIFT match quality metrics.
    let queryKeypoints: UInt32
    let goodMatches: UInt32
    let inliers: UInt32
    let meanReprojectionError: Double
}

// MARK: - Error

enum BGIBigMapSiftPositionProviderError: LocalizedError, Equatable {
    case unsupportedMap(String)
    case missingAsset(String)
    case invalidFrame
    case noMatch(queryKeypoints: UInt32, goodMatches: UInt32)
    case mapNotRegistered(String)
    case invalidInput
    case internalError
    case coordinateConversionFailed

    var errorDescription: String? {
        switch self {
        case let .unsupportedMap(mapName):
            "Big-map SIFT assets are not available for \(mapName)"
        case let .missingAsset(path):
            "Missing big-map SIFT asset: \(path)"
        case .invalidFrame:
            "Could not convert big-map capture to grayscale pixels"
        case let .noMatch(queryKeypoints, goodMatches):
            "Big-map SIFT match failed: queryKeypoints=\(queryKeypoints), goodMatches=\(goodMatches)"
        case let .mapNotRegistered(mapID):
            "Big-map SIFT matcher is not registered for \(mapID)"
        case .invalidInput:
            "Big-map SIFT matcher rejected the input frame"
        case .internalError:
            "Big-map SIFT matcher returned an internal error"
        case .coordinateConversionFailed:
            "Could not convert big-map SIFT match to Genshin coordinates"
        }
    }
}

@MainActor
final class BGIBigMapSiftPositionProvider {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame

    private struct AssetDescriptor {
        let mapName: String
        let mapID: String
        let keypointURL: URL
        let descriptorURL: URL
        let mapWidth256: Int32
        let mapHeight256: Int32
        let converter: BGISceneMapCoordinateConverter
    }

    private let captureFrameProvider: CaptureFrameProvider
    private let matcher: BGIBigMapSiftMatching
    private let store: BGIRuntimeResourceStore
    private var registeredMapIDs = Set<String>()

    init(
        captureFrameProvider: @escaping CaptureFrameProvider,
        matcher: BGIBigMapSiftMatching,
        store: BGIRuntimeResourceStore = .defaultStore()
    ) {
        self.captureFrameProvider = captureFrameProvider
        self.matcher = matcher
        self.store = store
    }

    func getBigMapCenter(mapName: String) async throws -> CGPoint {
        let obs = try await getBigMapObservation(mapName: mapName)
        return obs.centerWorld
    }

    func getBigMapObservation(mapName: String) async throws -> BGIBigMapObservation {
        let descriptor = try assetDescriptor(for: mapName)
        try ensureRegistered(descriptor)

        let frame = try await captureFrameProvider()
        let image = frame.cgImage
        let grayscale = BGIBigMapSiftBridge.grayscaleData(from: image)
        guard !grayscale.isEmpty else {
            throw BGIBigMapSiftPositionProviderError.invalidFrame
        }

        let outcome = try matcher.match(
            mapID: descriptor.mapID,
            grayscaleData: grayscale,
            width: Int32(clamping: image.width),
            height: Int32(clamping: image.height),
            stride: image.width
        )

        switch outcome {
        case let .matched(match):
            let rect256 = match.rect256
            let center256 = CGPoint(x: rect256.midX, y: rect256.midY)
            let center2048 = CGPoint(x: center256.x * 8.0, y: center256.y * 8.0)
            guard let worldPoint = descriptor.converter.imageToGenshin(center2048) else {
                throw BGIBigMapSiftPositionProviderError.coordinateConversionFailed
            }
            return BGIBigMapObservation(
                visibleRect256: rect256,
                centerWorld: worldPoint,
                queryKeypoints: match.queryKeypoints,
                goodMatches: match.goodMatches,
                inliers: match.inliers,
                meanReprojectionError: match.meanReprojectionError
            )
        case let .noMatch(quality):
            throw BGIBigMapSiftPositionProviderError.noMatch(
                queryKeypoints: quality.queryKeypoints,
                goodMatches: quality.goodMatches
            )
        case .notRegistered:
            registeredMapIDs.remove(descriptor.mapID)
            throw BGIBigMapSiftPositionProviderError.mapNotRegistered(descriptor.mapID)
        case .invalidInput:
            throw BGIBigMapSiftPositionProviderError.invalidInput
        case .internalError:
            throw BGIBigMapSiftPositionProviderError.internalError
        }
    }

    private func ensureRegistered(_ descriptor: AssetDescriptor) throws {
        guard !registeredMapIDs.contains(descriptor.mapID) else { return }
        let keypointData = try requiredData(at: descriptor.keypointURL)
        let descriptorData = try requiredData(at: descriptor.descriptorURL)
        try matcher.registerAssets(
            mapID: descriptor.mapID,
            keypointData: keypointData,
            descriptorPNGData: descriptorData,
            mapWidth256: descriptor.mapWidth256,
            mapHeight256: descriptor.mapHeight256
        )
        registeredMapIDs.insert(descriptor.mapID)
    }

    private func requiredData(at url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BGIBigMapSiftPositionProviderError.missingAsset(url.path)
        }
        return try Data(contentsOf: url)
    }

    private func assetDescriptor(for mapName: String) throws -> AssetDescriptor {
        switch mapName.lowercased() {
        case "teyvat":
            let converter = BGISceneMapCoordinateConverter.teyvat
            let mapDir = store.mapsURL.appendingPathComponent("Teyvat", isDirectory: true)
            return AssetDescriptor(
                mapName: "Teyvat",
                mapID: "Teyvat",
                keypointURL: mapDir.appendingPathComponent("Teyvat_0_256_SIFT.kp.bin"),
                descriptorURL: mapDir.appendingPathComponent("Teyvat_0_256_SIFT.mat.png"),
                mapWidth256: Int32(converter.imageSize.width / 8.0),
                mapHeight256: Int32(converter.imageSize.height / 8.0),
                converter: converter
            )
        default:
            throw BGIBigMapSiftPositionProviderError.unsupportedMap(mapName)
        }
    }
}
