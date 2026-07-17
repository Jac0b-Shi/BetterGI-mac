import CoreGraphics
import Foundation

struct BGIMiniMapLayerDescriptor: Codable, Equatable, Sendable {
    var layerGroupId: String?
    var layerId: String
    var name: String?
    var scale: Double
    var floor: Int?
    var top: Double
    var left: Double
    var isOverSize: Bool?

    enum CodingKeys: String, CodingKey {
        case layerGroupId = "LayerGroupId"
        case layerId = "LayerId"
        case name = "Name"
        case scale = "Scale"
        case floor = "Floor"
        case top = "Top"
        case left = "Left"
        case isOverSize = "IsOverSize"
    }

    static func decodeList(from data: Data) throws -> [BGIMiniMapLayerDescriptor] {
        try JSONDecoder().decode([BGIMiniMapLayerDescriptor].self, from: data)
    }
}

struct BGIMiniMapPreparedTemplate: Sendable {
    let roughColor: PixelImage
    let roughMask: [Double]
    let exactGray: PixelImage
    let exactMask: [Double]
    let roughWorstSqDiff: Double
    let exactWorstSqDiff: Double
}

struct BGIMiniMapMatchResult: Equatable, Sendable {
    let sourcePoint: CGPoint
    let confidence: Double
    let sqDiff: Double
}

struct BGIMiniMapCoarseTemplateLayer: Sendable {
    let descriptor: BGIMiniMapLayerDescriptor
    let coarseColorMap: PixelImage

    func roughMatch(_ template: BGIMiniMapPreparedTemplate) -> BGIMiniMapMatchResult? {
        BGIMiniMapPixelMatcher.match(
            source: coarseColorMap,
            template: template.roughColor,
            mask: template.roughMask,
            worstSqDiff: template.roughWorstSqDiff
        )
    }

    func roughMatch(_ template: BGIMiniMapPreparedTemplate, near worldPoint: CGPoint) -> BGIMiniMapMatchResult? {
        let mapPoint = worldToMap(worldPoint, zoom: Double(BGIMiniMapConstants.roughZoom))
        let scaledHalfSide = Int((Double(BGIMiniMapConstants.roughSearchRadius) * descriptor.scale).rounded())
        let rect = searchRect(
            centeredAt: mapPoint,
            halfSide: scaledHalfSide,
            templateSize: BGIMiniMapConstants.roughMatchSize,
            source: coarseColorMap
        )
        guard rect.width >= BGIMiniMapConstants.roughMatchSize,
              rect.height >= BGIMiniMapConstants.roughMatchSize else {
            return nil
        }
        return BGIMiniMapPixelMatcher.match(
            source: coarseColorMap,
            template: template.roughColor,
            mask: template.roughMask,
            worstSqDiff: template.roughWorstSqDiff,
            searchRect: rect
        )
    }

    func mapToWorld(_ point: CGPoint, zoom: Double, miniMapSize: Int) -> CGPoint {
        CGPoint(
            x: descriptor.left - (point.x + Double(miniMapSize) / 2.0) * zoom / descriptor.scale,
            y: descriptor.top - (point.y + Double(miniMapSize) / 2.0) * zoom / descriptor.scale
        )
    }

    func worldToMap(_ point: CGPoint, zoom: Double) -> CGPoint {
        CGPoint(
            x: ((descriptor.left - point.x) * descriptor.scale / zoom).rounded(),
            y: ((descriptor.top - point.y) * descriptor.scale / zoom).rounded()
        )
    }
}

struct BGIMiniMapTemplateLayer: Sendable {
    let descriptor: BGIMiniMapLayerDescriptor
    let coarseColorMap: PixelImage
    let fineGrayMap: PixelImage

    func roughMatch(_ template: BGIMiniMapPreparedTemplate) -> BGIMiniMapMatchResult? {
        BGIMiniMapPixelMatcher.match(
            source: coarseColorMap,
            template: template.roughColor,
            mask: template.roughMask,
            worstSqDiff: template.roughWorstSqDiff
        )
    }

    /// Upstream local rough match: restricts the search to a rectangle centered at `near`
    /// with half‑side `RoughSearchRadius * Scale` (upstream `RoughMatch` with `preLoc`).
    func roughMatch(_ template: BGIMiniMapPreparedTemplate, near worldPoint: CGPoint) -> BGIMiniMapMatchResult? {
        let mapPoint = worldToMap(worldPoint, zoom: Double(BGIMiniMapConstants.roughZoom))
        let scaledHalfSide = Int((Double(BGIMiniMapConstants.roughSearchRadius) * descriptor.scale).rounded())
        let rect = searchRect(
            centeredAt: mapPoint,
            halfSide: scaledHalfSide,
            templateSize: BGIMiniMapConstants.roughMatchSize,
            source: coarseColorMap
        )
        guard rect.width >= BGIMiniMapConstants.roughMatchSize,
              rect.height >= BGIMiniMapConstants.roughMatchSize,
              let local = BGIMiniMapPixelMatcher.match(
                source: coarseColorMap,
                template: template.roughColor,
                mask: template.roughMask,
                worstSqDiff: template.roughWorstSqDiff,
                searchRect: rect
              ) else {
            return nil
        }
        return BGIMiniMapMatchResult(
            sourcePoint: local.sourcePoint,
            confidence: local.confidence,
            sqDiff: local.sqDiff
        )
    }

    func exactMatch(_ template: BGIMiniMapPreparedTemplate, near worldPoint: CGPoint) -> BGIMiniMapMatchResult? {
        let mapPoint = worldToMap(worldPoint, zoom: Double(BGIMiniMapConstants.exactZoom))
        let rect = searchRect(
            centeredAt: mapPoint,
            halfSide: BGIMiniMapConstants.exactSearchRadius,
            templateSize: BGIMiniMapConstants.exactMatchSize,
            source: fineGrayMap
        )
        guard rect.width >= BGIMiniMapConstants.exactMatchSize,
              rect.height >= BGIMiniMapConstants.exactMatchSize,
              let local = BGIMiniMapPixelMatcher.match(
                source: fineGrayMap,
                template: template.exactGray,
                mask: template.exactMask,
                worstSqDiff: template.exactWorstSqDiff,
                searchRect: rect
              ) else {
            return nil
        }
        return BGIMiniMapMatchResult(
            sourcePoint: local.sourcePoint,
            confidence: local.confidence,
            sqDiff: local.sqDiff
        )
    }

    func mapToWorld(_ point: CGPoint, zoom: Double, miniMapSize: Int) -> CGPoint {
        CGPoint(
            x: descriptor.left - (point.x + Double(miniMapSize) / 2.0) * zoom / descriptor.scale,
            y: descriptor.top - (point.y + Double(miniMapSize) / 2.0) * zoom / descriptor.scale
        )
    }

    func worldToMap(_ point: CGPoint, zoom: Double) -> CGPoint {
        CGPoint(
            x: ((descriptor.left - point.x) * descriptor.scale / zoom).rounded(),
            y: ((descriptor.top - point.y) * descriptor.scale / zoom).rounded()
        )
    }
}

private func searchRect(centeredAt point: CGPoint, halfSide: Int, templateSize: Int, source: PixelImage) -> MatchSearchRect {
    let minX = Int(point.x.rounded()) - halfSide - templateSize / 2
    let minY = Int(point.y.rounded()) - halfSide - templateSize / 2
    return MatchSearchRect(
        minX: max(0, minX),
        minY: max(0, minY),
        width: min(source.width - max(0, minX), halfSide * 2 + templateSize),
        height: min(source.height - max(0, minY), halfSide * 2 + templateSize)
    )
}

private enum BGIMiniMapPixelMatcher {
    static func match(
        source: PixelImage,
        template: PixelImage,
        mask: [Double],
        worstSqDiff: Double,
        searchRect: MatchSearchRect? = nil
    ) -> BGIMiniMapMatchResult? {
        guard source.channelCount == template.channelCount,
              template.width <= source.width,
              template.height <= source.height,
              mask.count == template.width * template.height,
              worstSqDiff > 0 else {
            return nil
        }

        let rect = searchRect ?? MatchSearchRect(minX: 0, minY: 0, width: source.width, height: source.height)
        let maxX = min(source.width - template.width, rect.minX + rect.width - template.width)
        let maxY = min(source.height - template.height, rect.minY + rect.height - template.height)
        guard maxX >= rect.minX, maxY >= rect.minY else { return nil }

        if let accelerated = BGIMiniMapRustPixelMatcher.shared?.matchPixels(
            source: source,
            template: template,
            mask: mask,
            worstSqDiff: worstSqDiff,
            searchX: rect.minX,
            searchY: rect.minY,
            searchWidth: maxX - rect.minX + template.width,
            searchHeight: maxY - rect.minY + template.height
        ) {
            return accelerated
        }

        var bestPoint = CGPoint.zero
        var bestValue = Double.greatestFiniteMagnitude
        for y in rect.minY...maxY {
            for x in rect.minX...maxX {
                let value = weightedSqDiff(
                    source: source,
                    template: template,
                    mask: mask,
                    originX: x,
                    originY: y,
                    cutoff: bestValue
                )
                if value < bestValue {
                    bestValue = value
                    bestPoint = CGPoint(x: x, y: y)
                }
            }
        }

        return BGIMiniMapMatchResult(
            sourcePoint: bestPoint,
            confidence: max(0, min(1, 1.0 - bestValue / worstSqDiff)),
            sqDiff: bestValue
        )
    }

    private static func weightedSqDiff(
        source: PixelImage,
        template: PixelImage,
        mask: [Double],
        originX: Int,
        originY: Int,
        cutoff: Double
    ) -> Double {
        var sum = 0.0
        for ty in 0..<template.height {
            for tx in 0..<template.width {
                let weight = mask[ty * template.width + tx]
                guard weight > 0 else { continue }
                for channel in 0..<template.channelCount {
                    let sourceValue = source.value(x: originX + tx, y: originY + ty, channel: channel)
                    let templateValue = template.value(x: tx, y: ty, channel: channel)
                    let diff = sourceValue - templateValue
                    sum += diff * diff * weight
                    if sum >= cutoff {
                        return sum
                    }
                }
            }
        }
        return sum
    }
}

enum BGIMiniMapMatchContext {
    static func prepare(_ input: BGIMiniMapMatchInput) throws -> BGIMiniMapPreparedTemplate {
        let roughImage = try PixelImage(cgImage: input.processedImage, mode: .rgb)
            .resized(width: BGIMiniMapConstants.roughMatchSize, height: BGIMiniMapConstants.roughMatchSize, mode: .rgb)
        let roughMask = try resizeMask(
            input.finalMask,
            sourceSize: BGIMiniMapConstants.originalSize,
            targetSize: BGIMiniMapConstants.roughMatchSize,
            interpolation: .none
        )
        let exactImage = try PixelImage(cgImage: input.processedImage, mode: .grayscale)
            .resized(width: BGIMiniMapConstants.exactMatchSize, height: BGIMiniMapConstants.exactMatchSize, mode: .grayscale)
        let exactMask = try resizeMask(
            input.finalMask,
            sourceSize: BGIMiniMapConstants.originalSize,
            targetSize: BGIMiniMapConstants.exactMatchSize,
            interpolation: .none
        )

        return BGIMiniMapPreparedTemplate(
            roughColor: roughImage,
            roughMask: roughMask,
            exactGray: exactImage,
            exactMask: exactMask,
            roughWorstSqDiff: worstSqDiff(template: roughImage, mask: roughMask),
            exactWorstSqDiff: worstSqDiff(template: exactImage, mask: exactMask)
        )
    }

    private static func worstSqDiff(template: PixelImage, mask: [Double]) -> Double {
        var sum = 0.0
        for y in 0..<template.height {
            for x in 0..<template.width {
                let weight = mask[y * template.width + x]
                guard weight > 0 else { continue }
                for channel in 0..<template.channelCount {
                    let value = template.value(x: x, y: y, channel: channel)
                    let inverted = max(value, 255.0 - value)
                    sum += inverted * inverted * weight
                }
            }
        }
        return sum
    }

    private static func resizeMask(
        _ mask: [UInt8],
        sourceSize: Int,
        targetSize: Int,
        interpolation: CGInterpolationQuality
    ) throws -> [Double] {
        let bytesPerPixel = 4
        let sourceBytesPerRow = sourceSize * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: sourceSize * sourceBytesPerRow)
        for index in 0..<(sourceSize * sourceSize) {
            let value = mask[index]
            let offset = index * bytesPerPixel
            rgba[offset] = value
            rgba[offset + 1] = value
            rgba[offset + 2] = value
            rgba[offset + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(
                width: sourceSize,
                height: sourceSize,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: sourceBytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: interpolation != .none,
                intent: .defaultIntent
              ) else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }

        let resized = try PixelImage(cgImage: image, mode: .grayscale)
            .resized(width: targetSize, height: targetSize, mode: .grayscale, interpolation: interpolation)
        return resized.values.map { $0 >= 128 ? 1.0 : 0.0 }
    }
}

private struct MatchSearchRect {
    let minX: Int
    let minY: Int
    let width: Int
    let height: Int
}

private enum BGIMiniMapRustPixelMatcher {
    static let shared = RustPixelMatchBridge.loadDefault()
}

struct PixelImage: Sendable {
    enum Mode: Equatable, Sendable {
        case rgb
        case grayscale
    }

    let width: Int
    let height: Int
    let channelCount: Int
    let values: [Double]
    let byteValues: [UInt8]

    init(width: Int, height: Int, channelCount: Int, values: [Double]) {
        self.width = width
        self.height = height
        self.channelCount = channelCount
        self.values = values
        self.byteValues = values.map { UInt8(max(0, min(255, $0.rounded()))) }
    }

    init(cgImage: CGImage, mode: Mode) throws {
        width = cgImage.width
        height = cgImage.height
        channelCount = mode == .rgb ? 3 : 1
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var byteValues: [UInt8] = []
        byteValues.reserveCapacity(width * height * channelCount)
        var values: [Double] = []
        values.reserveCapacity(width * height * channelCount)
        for pixel in 0..<(width * height) {
            let offset = pixel * bytesPerPixel
            let redByte = rgba[offset]
            let greenByte = rgba[offset + 1]
            let blueByte = rgba[offset + 2]
            let red = Double(redByte)
            let green = Double(greenByte)
            let blue = Double(blueByte)
            switch mode {
            case .rgb:
                byteValues.append(redByte)
                byteValues.append(greenByte)
                byteValues.append(blueByte)
                values.append(red)
                values.append(green)
                values.append(blue)
            case .grayscale:
                let gray = 0.299 * red + 0.587 * green + 0.114 * blue
                byteValues.append(UInt8(max(0, min(255, gray.rounded()))))
                values.append(gray)
            }
        }
        self.byteValues = byteValues
        self.values = values
    }

    func value(x: Int, y: Int, channel: Int) -> Double {
        values[(y * width + x) * channelCount + channel]
    }

    func resized(
        width targetWidth: Int,
        height targetHeight: Int,
        mode: Mode,
        interpolation: CGInterpolationQuality = .high
    ) throws -> PixelImage {
        let image = try cgImage(mode: mode)
        let bytesPerPixel = 4
        let bytesPerRow = targetWidth * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: targetHeight * bytesPerRow)
        guard let context = CGContext(
            data: &rgba,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        context.interpolationQuality = interpolation
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let resizedImage = context.makeImage() else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        return try PixelImage(cgImage: resizedImage, mode: mode)
    }

    func cgImage(mode: Mode) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                switch mode {
                case .rgb:
                    let pixel = (y * width + x) * channelCount
                    rgba[offset] = byteValues[pixel]
                    rgba[offset + 1] = byteValues[pixel + min(1, channelCount - 1)]
                    rgba[offset + 2] = byteValues[pixel + min(2, channelCount - 1)]
                case .grayscale:
                    let gray = byteValues[(y * width + x) * channelCount]
                    rgba[offset] = gray
                    rgba[offset + 1] = gray
                    rgba[offset + 2] = gray
                }
                rgba[offset + 3] = 255
            }
        }
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        return image
    }
}
