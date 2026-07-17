import CoreGraphics
import Foundation

enum BGIMiniMapExtractionError: LocalizedError {
    case invalidViewport(CGRect)
    case invalidOriginalRect(CGRect)
    case unableToReadPixels

    var errorDescription: String? {
        switch self {
        case let .invalidViewport(rect):
            "MiniMap viewport is outside the captured frame: \(rect)"
        case let .invalidOriginalRect(rect):
            "MiniMap original-size rect is outside the captured frame: \(rect)"
        case .unableToReadPixels:
            "MiniMap diagnostic pixel read failed"
        }
    }
}

struct BGIMiniMapDiagnostics: Equatable, Sendable {
    let meanLuma: Double
    let meanSaturation: Double
    let lumaStandardDeviation: Double
    let circularSampleCount: Int

    var summary: String {
        "luma=\(String(format: "%.2f", meanLuma)) saturation=\(String(format: "%.3f", meanSaturation)) std=\(String(format: "%.2f", lumaStandardDeviation)) samples=\(circularSampleCount)"
    }
}

struct BGIMiniMapExtraction: Sendable {
    /// Source-frame viewport rect before normalizing to BetterGI's 210 px size.
    let viewportRect: CGRect
    /// Source-frame original mini map rect before normalizing to 156 px.
    let originalRect: CGRect
    /// BetterGI-compatible 210x210 viewport image.
    let viewportImage: CGImage
    /// BetterGI-compatible 156x156 center mini map image.
    let originalImage: CGImage
    let diagnostics: BGIMiniMapDiagnostics
}

struct BGIMiniMapPaimonMatch: Equatable, Sendable {
    let topLeft: CGPoint
    let rect: CGRect
    let confidence: Double
}

/// First native input stage for BetterGI map recognition.
///
/// Upstream `AutoTrackPathTask.GetMiniMapMat` finds the Paimon menu template and
/// crops `Rect(paimon.X + 24, paimon.Y - 15, 210, 210)`.  The map preprocessor
/// then center-crops the original 156 px mini map from that 210 px viewport.
/// Keep those constants here so the future Rust/OpenCV matcher receives the
/// same image shape as BetterGI.
enum BGIMiniMapConstants {
    static let upstreamReferenceWidth = 1920.0
    static let upstreamReferenceHeight = 1080.0
    static let paimonTemplateSize = CGSize(width: 38, height: 40)
    static let viewportOffsetFromPaimonTopLeft = CGPoint(x: 24, y: -15)
    static let fallbackPaimonTopLeft = CGPoint(x: 24, y: 15)
    static let viewportSize = 210
    static let originalSize = 156
    static let roughMatchSize = 52
    static let exactMatchSize = 260
    static let roughZoom = 5
    static let exactZoom = 1
    static let roughSearchRadius = 50
    static let exactSearchRadius = 20
    static let paimonTemplateAssetName = "GameTask/Common/Element/Assets/1920x1080/paimon_menu.png"
}

struct BGIMiniMapPaimonLocator {
    private let templateEngine = TemplateMatchingRecognitionEngine()

    func locate(in imageFrame: CaptureImageFrame) -> BGIMiniMapPaimonMatch? {
        let report = templateEngine.recognize(
            imageFrame: imageFrame,
            objects: [Self.paimonRecognitionObject]
        )
        guard let observation = report.observations.max(by: { $0.confidence < $1.confidence }) else {
            return nil
        }

        let rect = CGRect(
            x: observation.normalizedRect.minX * CGFloat(imageFrame.metadata.width),
            y: observation.normalizedRect.minY * CGFloat(imageFrame.metadata.height),
            width: observation.normalizedRect.width * CGFloat(imageFrame.metadata.width),
            height: observation.normalizedRect.height * CGFloat(imageFrame.metadata.height)
        ).integral
        return BGIMiniMapPaimonMatch(
            topLeft: rect.origin,
            rect: rect,
            confidence: observation.confidence
        )
    }

    static let paimonRecognitionObject = RecognitionObject.bgiCommonElementPaimonMenuObject
}

struct BGIMiniMapExtractor: Sendable {
    func extract(
        from imageFrame: CaptureImageFrame,
        paimonTopLeft: CGPoint? = nil
    ) throws -> BGIMiniMapExtraction {
        let contentTopInset = paimonTopLeft == nil
            ? detectWindowChromeTopInset(in: imageFrame.cgImage)
            : 0
        let viewportRect = try miniMapViewportRect(
            frame: imageFrame.metadata,
            paimonTopLeft: paimonTopLeft,
            contentTopInset: contentTopInset
        )
        guard let sourceViewportImage = imageFrame.cgImage.cropping(to: viewportRect) else {
            throw BGIMiniMapExtractionError.invalidViewport(viewportRect)
        }

        let originalRectInSourceViewport = centeredSourceOriginalRect(in: sourceViewportImage)
        let normalizedViewportImage = try normalized(
            sourceViewportImage,
            side: BGIMiniMapConstants.viewportSize
        )
        let originalRectInViewport = centeredOriginalRect(in: normalizedViewportImage)
        guard let originalImage = normalizedViewportImage.cropping(to: originalRectInViewport) else {
            throw BGIMiniMapExtractionError.invalidOriginalRect(originalRectInViewport)
        }

        let originalRect = originalRectInSourceViewport.offsetBy(
            dx: viewportRect.minX,
            dy: viewportRect.minY
        )
        let diagnostics = try BGIMiniMapDiagnostics.make(from: originalImage)
        return BGIMiniMapExtraction(
            viewportRect: viewportRect,
            originalRect: originalRect,
            viewportImage: normalizedViewportImage,
            originalImage: originalImage,
            diagnostics: diagnostics
        )
    }

    func miniMapViewportRect(
        frame: CapturedFrame,
        paimonTopLeft: CGPoint? = nil,
        contentTopInset: CGFloat = 0
    ) throws -> CGRect {
        let scale = uiScale(for: frame)
        let paimon = paimonTopLeft ?? CGPoint(
            x: BGIMiniMapConstants.fallbackPaimonTopLeft.x * scale,
            y: BGIMiniMapConstants.fallbackPaimonTopLeft.y * scale + contentTopInset
        )
        let raw = pixelAligned(CGRect(
            x: paimon.x + BGIMiniMapConstants.viewportOffsetFromPaimonTopLeft.x * scale,
            y: paimon.y + BGIMiniMapConstants.viewportOffsetFromPaimonTopLeft.y * scale,
            width: Double(BGIMiniMapConstants.viewportSize) * scale,
            height: Double(BGIMiniMapConstants.viewportSize) * scale
        ))
        let bounds = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        let rect = raw.intersection(bounds).integral
        guard rect.width >= 1, rect.height >= 1 else {
            throw BGIMiniMapExtractionError.invalidViewport(raw)
        }
        return rect
    }

    private func centeredOriginalRect(in image: CGImage) -> CGRect {
        let side = min(image.width, image.height, BGIMiniMapConstants.originalSize)
        return CGRect(
            x: (image.width - side) / 2,
            y: (image.height - side) / 2,
            width: side,
            height: side
        ).integral
    }

    private func centeredSourceOriginalRect(in image: CGImage) -> CGRect {
        let side = min(
            image.width,
            image.height,
            Int((Double(BGIMiniMapConstants.originalSize) * Double(image.height) / Double(BGIMiniMapConstants.viewportSize)).rounded())
        )
        return CGRect(
            x: (image.width - side) / 2,
            y: (image.height - side) / 2,
            width: side,
            height: side
        ).integral
    }

    private func uiScale(for frame: CapturedFrame) -> Double {
        guard frame.height > 0 else { return 1 }
        return max(0.1, Double(frame.height) / BGIMiniMapConstants.upstreamReferenceHeight)
    }

    private func detectWindowChromeTopInset(in image: CGImage) -> CGFloat {
        let width = image.width
        let height = min(96, image.height)
        guard width > 0, height > 0 else { return 0 }
        guard let topImage = image.cropping(to: CGRect(x: 0, y: 0, width: width, height: height)) else {
            return 0
        }

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
            return 0
        }
        context.draw(topImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let sampleWidth = min(width, 360)
        var lastChromeRow = -1
        for y in 0..<height {
            var chromeLikePixels = 0
            for x in 0..<sampleWidth {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Double(rgba[offset])
                let g = Double(rgba[offset + 1])
                let b = Double(rgba[offset + 2])
                let maxChannel = max(r, g, b)
                let minChannel = min(r, g, b)
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let saturation = maxChannel <= 0 ? 0 : (maxChannel - minChannel) / maxChannel
                if luma > 215, saturation < 0.18 {
                    chromeLikePixels += 1
                }
            }

            let chromeRatio = Double(chromeLikePixels) / Double(sampleWidth)
            if chromeRatio > 0.72 {
                lastChromeRow = y
            } else if y > 12, lastChromeRow >= 0 {
                break
            }
        }

        return lastChromeRow >= 12 ? CGFloat(lastChromeRow + 1) : 0
    }

    private func pixelAligned(_ rect: CGRect) -> CGRect {
        CGRect(
            x: floor(rect.minX),
            y: floor(rect.minY),
            width: max(1, rect.width.rounded()),
            height: max(1, rect.height.rounded())
        )
    }

    private func normalized(_ image: CGImage, side: Int) throws -> CGImage {
        guard image.width != side || image.height != side else {
            return image
        }
        let bytesPerPixel = 4
        let bytesPerRow = side * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: side * bytesPerRow)
        guard let context = CGContext(
            data: &rgba,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let resized = context.makeImage() else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        return resized
    }
}

private extension BGIMiniMapDiagnostics {
    static func make(from image: CGImage) throws -> BGIMiniMapDiagnostics {
        let width = image.width
        let height = image.height
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
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let centerX = Double(width - 1) / 2.0
        let centerY = Double(height - 1) / 2.0
        let radius = Double(min(width, height)) / 2.0
        let radiusSquared = radius * radius
        var lumaSum = 0.0
        var lumaSquaredSum = 0.0
        var saturationSum = 0.0
        var count = 0

        for y in 0..<height {
            for x in 0..<width {
                let dx = Double(x) - centerX
                let dy = Double(y) - centerY
                guard dx * dx + dy * dy <= radiusSquared else { continue }

                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Double(rgba[offset])
                let g = Double(rgba[offset + 1])
                let b = Double(rgba[offset + 2])
                let maxChannel = max(r, g, b)
                let minChannel = min(r, g, b)
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                lumaSum += luma
                lumaSquaredSum += luma * luma
                saturationSum += maxChannel <= 0 ? 0 : (maxChannel - minChannel) / maxChannel
                count += 1
            }
        }

        guard count > 0 else {
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        let mean = lumaSum / Double(count)
        let variance = max(0, lumaSquaredSum / Double(count) - mean * mean)
        return BGIMiniMapDiagnostics(
            meanLuma: mean,
            meanSaturation: saturationSum / Double(count),
            lumaStandardDeviation: sqrt(variance),
            circularSampleCount: count
        )
    }
}
