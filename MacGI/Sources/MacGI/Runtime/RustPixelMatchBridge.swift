import CoreGraphics
import Darwin
import Foundation

final class RustPixelMatchBridge: @unchecked Sendable {
    private let libraryHandleRaw: UInt
    private let matchPixelsFn: MatchPixelsFn
    private let matchU8PixelsFn: MatchU8PixelsFn?

    static func loadDefault() -> RustPixelMatchBridge? {
        for path in candidateLibraryPaths() where FileManager.default.fileExists(atPath: path) {
            if let bridge = try? RustPixelMatchBridge(libraryPath: path) {
                return bridge
            }
        }
        return nil
    }

    init(libraryPath: String) throws {
        guard let libraryHandle = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else {
            throw RustPixelMatchBridgeError.loadFailed(String(cString: dlerror()))
        }
        guard let pointer = dlsym(libraryHandle, "macgi_core_match_pixels") else {
            dlclose(libraryHandle)
            throw RustPixelMatchBridgeError.missingSymbol("macgi_core_match_pixels")
        }
        libraryHandleRaw = UInt(bitPattern: libraryHandle)
        matchPixelsFn = unsafeBitCast(pointer, to: MatchPixelsFn.self)
        if let u8Pointer = dlsym(libraryHandle, "macgi_core_match_u8_pixels") {
            matchU8PixelsFn = unsafeBitCast(u8Pointer, to: MatchU8PixelsFn.self)
        } else {
            matchU8PixelsFn = nil
        }
    }

    deinit {
        dlclose(UnsafeMutableRawPointer(bitPattern: libraryHandleRaw))
    }

    func matchPixels(
        source: PixelImage,
        template: PixelImage,
        mask: [Double],
        worstSqDiff: Double,
        searchX: Int,
        searchY: Int,
        searchWidth: Int,
        searchHeight: Int
    ) -> BGIMiniMapMatchResult? {
        guard source.channelCount == template.channelCount,
              mask.count == template.width * template.height,
              worstSqDiff > 0,
              searchX >= 0,
              searchY >= 0,
              searchWidth >= template.width,
              searchHeight >= template.height,
              searchX + searchWidth <= source.width,
              searchY + searchHeight <= source.height else {
            return nil
        }

        if let matchU8PixelsFn,
           let result = matchU8Pixels(
            source: source,
            template: template,
            mask: mask,
            worstSqDiff: worstSqDiff,
            searchX: searchX,
            searchY: searchY,
            searchWidth: searchWidth,
            searchHeight: searchHeight,
            function: matchU8PixelsFn
           ) {
            return result
        }

        var result = FFIPixelMatchResult()
        let status = source.values.withUnsafeBufferPointer { sourceBuffer in
            template.values.withUnsafeBufferPointer { templateBuffer in
                mask.withUnsafeBufferPointer { maskBuffer in
                    guard let sourceBase = sourceBuffer.baseAddress,
                          let templateBase = templateBuffer.baseAddress,
                          let maskBase = maskBuffer.baseAddress else {
                        return Int32(-3)
                    }
                    var request = FFIPixelMatchRequest(
                        sourceData: sourceBase,
                        sourceLen: UInt(source.values.count),
                        sourceWidth: UInt32(source.width),
                        sourceHeight: UInt32(source.height),
                        sourceChannels: UInt32(source.channelCount),
                        templateData: templateBase,
                        templateLen: UInt(template.values.count),
                        templateWidth: UInt32(template.width),
                        templateHeight: UInt32(template.height),
                        templateChannels: UInt32(template.channelCount),
                        maskData: maskBase,
                        maskLen: UInt(mask.count),
                        worstSqDiff: worstSqDiff,
                        searchX: UInt32(searchX),
                        searchY: UInt32(searchY),
                        searchWidth: UInt32(searchWidth),
                        searchHeight: UInt32(searchHeight)
                    )
                    return withUnsafePointer(to: &request) { requestPointer in
                        withUnsafeMutablePointer(to: &result) { resultPointer in
                            matchPixelsFn(UnsafeRawPointer(requestPointer), UnsafeMutableRawPointer(resultPointer))
                        }
                    }
                }
            }
        }
        guard status == 0 else { return nil }
        return BGIMiniMapMatchResult(
            sourcePoint: CGPoint(x: Int(result.sourceX), y: Int(result.sourceY)),
            confidence: result.confidence,
            sqDiff: result.sqDiff
        )
    }

    private func matchU8Pixels(
        source: PixelImage,
        template: PixelImage,
        mask: [Double],
        worstSqDiff: Double,
        searchX: Int,
        searchY: Int,
        searchWidth: Int,
        searchHeight: Int,
        function: MatchU8PixelsFn
    ) -> BGIMiniMapMatchResult? {
        var result = FFIPixelMatchResult()
        let status = source.byteValues.withUnsafeBufferPointer { sourceBuffer in
            template.byteValues.withUnsafeBufferPointer { templateBuffer in
                mask.withUnsafeBufferPointer { maskBuffer in
                    guard let sourceBase = sourceBuffer.baseAddress,
                          let templateBase = templateBuffer.baseAddress,
                          let maskBase = maskBuffer.baseAddress else {
                        return Int32(-3)
                    }
                    var request = FFIU8PixelMatchRequest(
                        sourceData: sourceBase,
                        sourceLen: UInt(source.byteValues.count),
                        sourceWidth: UInt32(source.width),
                        sourceHeight: UInt32(source.height),
                        sourceChannels: UInt32(source.channelCount),
                        templateData: templateBase,
                        templateLen: UInt(template.byteValues.count),
                        templateWidth: UInt32(template.width),
                        templateHeight: UInt32(template.height),
                        templateChannels: UInt32(template.channelCount),
                        maskData: maskBase,
                        maskLen: UInt(mask.count),
                        worstSqDiff: worstSqDiff,
                        searchX: UInt32(searchX),
                        searchY: UInt32(searchY),
                        searchWidth: UInt32(searchWidth),
                        searchHeight: UInt32(searchHeight)
                    )
                    return withUnsafePointer(to: &request) { requestPointer in
                        withUnsafeMutablePointer(to: &result) { resultPointer in
                            function(UnsafeRawPointer(requestPointer), UnsafeMutableRawPointer(resultPointer))
                        }
                    }
                }
            }
        }
        guard status == 0 else { return nil }
        return BGIMiniMapMatchResult(
            sourcePoint: CGPoint(x: Int(result.sourceX), y: Int(result.sourceY)),
            confidence: result.confidence,
            sqDiff: result.sqDiff
        )
    }

    private static func candidateLibraryPaths() -> [String] {
        let env = ProcessInfo.processInfo.environment["MACGI_CORE_DYLIB"].map { [$0] } ?? []
        let cwd = FileManager.default.currentDirectoryPath
        let sourceRepoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let executableDir = Bundle.main.executableURL?.deletingLastPathComponent().path
        let resourceDir = Bundle.main.resourceURL?.path
        let local = [
            "\(cwd)/macgi-core/target/debug/libmacgi_core.dylib",
            "\(cwd)/macgi-core/target/release/libmacgi_core.dylib",
            "\(sourceRepoRoot)/macgi-core/target/debug/libmacgi_core.dylib",
            "\(sourceRepoRoot)/macgi-core/target/release/libmacgi_core.dylib"
        ]
        let bundle = [executableDir, resourceDir]
            .compactMap { $0 }
            .flatMap { dir in
                [
                    "\(dir)/libmacgi_core.dylib",
                    "\(dir)/Frameworks/libmacgi_core.dylib",
                    "\(dir)/../Frameworks/libmacgi_core.dylib"
                ]
            }
        return Array(NSOrderedSet(array: env + local + bundle)) as? [String] ?? env + local + bundle
    }
}

private enum RustPixelMatchBridgeError: LocalizedError {
    case loadFailed(String)
    case missingSymbol(String)

    var errorDescription: String? {
        switch self {
        case let .loadFailed(message):
            "Failed to load macgi-core dylib: \(message)"
        case let .missingSymbol(name):
            "Missing macgi-core symbol: \(name)"
        }
    }
}

private typealias MatchPixelsFn = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Int32
private typealias MatchU8PixelsFn = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Int32

private struct FFIPixelMatchRequest {
    var sourceData: UnsafePointer<Double>?
    var sourceLen: UInt
    var sourceWidth: UInt32
    var sourceHeight: UInt32
    var sourceChannels: UInt32
    var templateData: UnsafePointer<Double>?
    var templateLen: UInt
    var templateWidth: UInt32
    var templateHeight: UInt32
    var templateChannels: UInt32
    var maskData: UnsafePointer<Double>?
    var maskLen: UInt
    var worstSqDiff: Double
    var searchX: UInt32
    var searchY: UInt32
    var searchWidth: UInt32
    var searchHeight: UInt32
}

private struct FFIPixelMatchResult {
    var sourceX: UInt32 = 0
    var sourceY: UInt32 = 0
    var confidence: Double = 0
    var sqDiff: Double = 0
}

private struct FFIU8PixelMatchRequest {
    var sourceData: UnsafePointer<UInt8>?
    var sourceLen: UInt
    var sourceWidth: UInt32
    var sourceHeight: UInt32
    var sourceChannels: UInt32
    var templateData: UnsafePointer<UInt8>?
    var templateLen: UInt
    var templateWidth: UInt32
    var templateHeight: UInt32
    var templateChannels: UInt32
    var maskData: UnsafePointer<Double>?
    var maskLen: UInt
    var worstSqDiff: Double
    var searchX: UInt32
    var searchY: UInt32
    var searchWidth: UInt32
    var searchHeight: UInt32
}
