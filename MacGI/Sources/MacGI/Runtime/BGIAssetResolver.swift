import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct BGIAssetResolution: Identifiable, Equatable, Sendable {
    let assetName: String
    let url: URL?

    var id: String { assetName }
    var isResolved: Bool { url != nil }
}

struct BGIAssetCoverage: Equatable, Sendable {
    let resolutions: [BGIAssetResolution]

    var total: Int { resolutions.count }
    var resolved: Int { resolutions.filter(\.isResolved).count }
    var missing: [String] { resolutions.filter { !$0.isResolved }.map(\.assetName) }

    var summary: String {
        "\(resolved)/\(total) templates"
    }
}

enum BGIAssetResolver {
    private static let baseAssetWidth: CGFloat = 1920

    static func url(for assetName: String) -> URL? {
        let normalized = normalizedAssetName(assetName)
        guard !normalized.isEmpty else { return nil }

        for candidateName in lookupAssetNames(for: normalized) {
            if let url = bundledURL(for: candidateName) {
                return url
            }
        }

        return nil
    }

    static func upstreamAssetName(featureName: String, assetName: String) -> String? {
        let feature = normalizedAssetName(featureName)
        let asset = normalizedAssetName(assetName)
        guard !feature.isEmpty, !asset.isEmpty else { return nil }
        return "GameTask/\(feature)/Assets/1920x1080/\(asset)"
    }

    static func resolvedAssetName(for assetName: String) -> String {
        let normalized = normalizedAssetName(assetName)
        for candidateName in lookupAssetNames(for: normalized) where bundledURL(for: candidateName) != nil {
            return candidateName
        }
        return normalized
    }

    private static func normalizedAssetName(_ assetName: String) -> String {
        assetName
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func lookupAssetNames(for normalized: String) -> [String] {
        var candidates = [normalized]
        if let alias = upstreamAliasAssetName(for: normalized) {
            candidates.append(alias)
        }
        return candidates.uniquedPreservingOrder()
    }

    private static func upstreamAliasAssetName(for normalized: String) -> String? {
        let parts = normalized.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return upstreamAssetName(featureName: String(parts[0]), assetName: String(parts[1]))
    }

    private static func bundledURL(for normalized: String) -> URL? {
        // 1 — External runtime resource store (first-launch downloaded assets)
        for root in BGIRuntimeResourceStore.defaultSearchRoots() {
            let externalURL = root.appendingPathComponent(normalized)
            if FileManager.default.fileExists(atPath: externalURL.path) {
                return externalURL
            }
        }

        // 2 — App bundle resources (embedded for P0 templates)
        let path = normalized as NSString
        let subdirectory = path.deletingLastPathComponent
        let fileName = path.lastPathComponent as NSString
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

        // SwiftPM `.process("Resources")` may flatten copied PNGs into the
        // resource bundle root. Keep upstream paths in the model, but allow
        // lookup by basename until a custom resource layout is needed.
        if let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: fileExtension
        ) {
            return url
        }

        return Bundle.module.url(
            forResource: normalized,
            withExtension: nil
        )
    }

    static func data(for assetName: String) throws -> Data {
        guard let url = url(for: assetName) else {
            throw BGIAssetResolverError.missingAsset(assetName)
        }
        return try Data(contentsOf: url)
    }

    static func data(for object: RecognitionObject) throws -> Data? {
        guard let assetName = object.templateAssetName else { return nil }
        return try data(for: assetName)
    }

    static func cgImage(for assetName: String) throws -> CGImage {
        guard let url = url(for: assetName) else {
            throw BGIAssetResolverError.missingAsset(assetName)
        }
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw BGIAssetResolverError.invalidImage(assetName)
        }
        return image
    }

    /// Compute the template scaling factor relative to the 1920 baseline asset width.
    ///
    /// - 1920 is the baseline asset width (matching BetterGI's 1920×1080 reference).
    /// - MacGI only **downscales** 1920×1080 templates for sub-1920 game windows
    ///   (typical in YAAGL/windowed captures).
    /// - For frame widths ≥ 1920, scale stays at 1 to preserve upstream 1920 baseline
    ///   assets — templates are never upscaled for 2K/4K windows.
    /// - This is intentional for the current macOS/YAAGL windowed validation path;
    ///   2K/4K behavior should be validated separately.
    static func assetScale(forFrameWidth frameWidth: Int) -> CGFloat {
        guard frameWidth > 0 else { return 1 }
        return min(1, CGFloat(frameWidth) / baseAssetWidth)
    }

    static func scaledTemplateImage(for assetName: String, frameWidth: Int) throws -> CGImage {
        let image = try cgImage(for: assetName)
        let scale = assetScale(forFrameWidth: frameWidth)
        guard abs(scale - 1) > 0.00001 else { return image }
        return try resized(image, by: scale, assetName: assetName)
    }

    static func scaledTemplateImage(for object: RecognitionObject, frameWidth: Int) throws -> CGImage? {
        guard let assetName = object.templateAssetName else { return nil }
        return try scaledTemplateImage(for: assetName, frameWidth: frameWidth)
    }

    static func scaledTemplatePNGData(for object: RecognitionObject, frameWidth: Int) throws -> Data? {
        guard let assetName = object.templateAssetName else { return nil }
        let image = try scaledTemplateImage(for: assetName, frameWidth: frameWidth)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw BGIAssetResolverError.imageEncodingFailed(assetName)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw BGIAssetResolverError.imageEncodingFailed(assetName)
        }
        return data as Data
    }

    static func coverage(for objects: [RecognitionObject]) -> BGIAssetCoverage {
        let assetNames = objects
            .compactMap(\.templateAssetName)
            .uniquedPreservingOrder()
        let resolutions = assetNames.map { assetName in
            BGIAssetResolution(assetName: assetName, url: url(for: assetName))
        }
        return BGIAssetCoverage(resolutions: resolutions)
    }

    private static func resized(_ image: CGImage, by scale: CGFloat, assetName: String) throws -> CGImage {
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
              ) else {
            throw BGIAssetResolverError.invalidImage(assetName)
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaledImage = context.makeImage() else {
            throw BGIAssetResolverError.invalidImage(assetName)
        }
        return scaledImage
    }
}

enum BGIAssetResolverError: LocalizedError {
    case missingAsset(String)
    case invalidImage(String)
    case imageEncodingFailed(String)

    var errorDescription: String? {
        switch self {
        case let .missingAsset(assetName):
            "BetterGI asset not found in bundle: \(assetName)"
        case let .invalidImage(assetName):
            "BetterGI asset cannot be decoded or resized: \(assetName)"
        case let .imageEncodingFailed(assetName):
            "BetterGI asset cannot be encoded as PNG: \(assetName)"
        }
    }
}

private extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
