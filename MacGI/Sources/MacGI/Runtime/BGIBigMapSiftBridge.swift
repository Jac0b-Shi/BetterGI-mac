import CoreGraphics
import Foundation

// MARK: - Public Swift types

struct BGIBigMapMatch {
    let rect256: CGRect
    let queryKeypoints: UInt32
    let goodMatches: UInt32
    let inliers: UInt32
    let meanReprojectionError: Double
}

struct BGIBigMapMatchQuality {
    let queryKeypoints: UInt32
    let goodMatches: UInt32
}

enum BGIBigMapMatchOutcome {
    case matched(BGIBigMapMatch)
    case noMatch(BGIBigMapMatchQuality)
    case notRegistered
    case invalidInput
    case internalError
}

protocol BGIBigMapSiftMatching: AnyObject, Sendable {
    func registerAssets(
        mapID: String,
        keypointData: Data,
        descriptorPNGData: Data,
        mapWidth256: Int32,
        mapHeight256: Int32
    ) throws
    func unregisterAssets(mapID: String) throws
    func match(
        mapID: String,
        grayscaleData: Data,
        width: Int32,
        height: Int32,
        stride: Int
    ) throws -> BGIBigMapMatchOutcome
}

// MARK: - Private C ABI POD

private struct MacGIBigMapMatchResultABI {
    var status: Int32 = 0
    var rectX256: Double = 0
    var rectY256: Double = 0
    var rectWidth256: Double = 0
    var rectHeight256: Double = 0
    var queryKeypoints: UInt32 = 0
    var goodMatches: UInt32 = 0
    var inliers: UInt32 = 0
    var meanReprojectionError: Double = 0
}

// MARK: - Bridge

final class BGIBigMapSiftBridge: @unchecked Sendable {
    typealias RegisterFn = @convention(c) (
        UnsafeMutableRawPointer?, UnsafePointer<CChar>?,
        UnsafePointer<UInt8>?, Int, UnsafePointer<UInt8>?, Int,
        Int32, Int32
    ) -> Int32

    typealias UnregisterFn = @convention(c) (
        UnsafeMutableRawPointer?, UnsafePointer<CChar>?
    ) -> Int32

    typealias MatchFn = @convention(c) (
        UnsafeMutableRawPointer?, UnsafePointer<CChar>?,
        UnsafePointer<UInt8>?, Int, Int32, Int32, Int,
        UnsafeMutableRawPointer?
    ) -> Int32

    private let coreHandle: UnsafeMutableRawPointer
    private let registerFn: RegisterFn
    private let unregisterFn: UnregisterFn
    private let matchFn: MatchFn

    init(coreHandle: UnsafeMutableRawPointer, dylibHandle: UnsafeMutableRawPointer) throws {
        self.coreHandle = coreHandle
        guard let reg = dlsym(dylibHandle, "macgi_core_big_map_register"),
              let unreg = dlsym(dylibHandle, "macgi_core_big_map_unregister"),
              let match = dlsym(dylibHandle, "macgi_core_big_map_match") else {
            throw BGIBigMapSiftBridgeError.symbolNotFound
        }
        registerFn = unsafeBitCast(reg, to: RegisterFn.self)
        unregisterFn = unsafeBitCast(unreg, to: UnregisterFn.self)
        matchFn = unsafeBitCast(match, to: MatchFn.self)
    }

    func registerAssets(mapID: String, keypointData: Data, descriptorPNGData: Data, mapWidth256: Int32, mapHeight256: Int32) throws {
        let rc = keypointData.withUnsafeBytes { kpBuf in
            descriptorPNGData.withUnsafeBytes { descBuf in
                mapID.withCString { idPtr in
                    registerFn(coreHandle, idPtr,
                        kpBuf.bindMemory(to: UInt8.self).baseAddress, kpBuf.count,
                        descBuf.bindMemory(to: UInt8.self).baseAddress, descBuf.count,
                        mapWidth256, mapHeight256)
                }
            }
        }
        guard rc == 0 else { throw BGIBigMapSiftBridgeError.abiCallFailed(rc) }
    }

    func unregisterAssets(mapID: String) throws {
        let rc = mapID.withCString { idPtr in unregisterFn(coreHandle, idPtr) }
        guard rc == 0 else { throw BGIBigMapSiftBridgeError.abiCallFailed(rc) }
    }

    func match(mapID: String, grayscaleData: Data, width: Int32, height: Int32, stride: Int = 0) throws -> BGIBigMapMatchOutcome {
        var result = MacGIBigMapMatchResultABI()
        let rc = grayscaleData.withUnsafeBytes { buf in
            mapID.withCString { idPtr in
                withUnsafeMutablePointer(to: &result) { rPtr in
                    matchFn(coreHandle, idPtr,
                        buf.bindMemory(to: UInt8.self).baseAddress, buf.count,
                        width, height, stride,
                        UnsafeMutableRawPointer(rPtr))
                }
            }
        }
        guard rc == 0 else { throw BGIBigMapSiftBridgeError.abiCallFailed(rc) }

        switch result.status {
        case 0:
            return .matched(BGIBigMapMatch(
                rect256: CGRect(x: result.rectX256, y: result.rectY256, width: result.rectWidth256, height: result.rectHeight256),
                queryKeypoints: result.queryKeypoints, goodMatches: result.goodMatches,
                inliers: result.inliers, meanReprojectionError: result.meanReprojectionError
            ))
        case 1:
            return .noMatch(BGIBigMapMatchQuality(queryKeypoints: result.queryKeypoints, goodMatches: result.goodMatches))
        case 2: return .notRegistered
        case 3: return .invalidInput
        default: return .internalError
        }
    }

    static func grayscaleData(from image: CGImage) -> Data {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return Data() }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Data(pixels)
    }
}

extension BGIBigMapSiftBridge: BGIBigMapSiftMatching {}

enum BGIBigMapSiftBridgeError: LocalizedError {
    case symbolNotFound
    case abiCallFailed(Int32)
    var errorDescription: String? {
        switch self {
        case .symbolNotFound: "SIFT bridge symbols not found in dylib"
        case .abiCallFailed(let c): "SIFT ABI call failed with code \(c)"
        }
    }
}
