import CoreGraphics
import CoreVideo
import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI mini map extractor")
struct BGIMiniMapExtractorTests {
    @Test("MiniMap constants mirror upstream template-match sizes")
    func constantsMirrorUpstream() {
        #expect(BGIMiniMapConstants.paimonTemplateSize == CGSize(width: 38, height: 40))
        #expect(BGIMiniMapConstants.viewportOffsetFromPaimonTopLeft == CGPoint(x: 24, y: -15))
        #expect(BGIMiniMapConstants.viewportSize == 210)
        #expect(BGIMiniMapConstants.originalSize == 156)
        #expect(BGIMiniMapConstants.roughMatchSize == 52)
        #expect(BGIMiniMapConstants.exactMatchSize == 260)
    }

    @Test("Paimon menu template resolves from upstream Common Element assets")
    func paimonMenuTemplateResolves() throws {
        let url = try #require(BGIAssetResolver.url(for: BGIMiniMapConstants.paimonTemplateAssetName))
        #expect(url.lastPathComponent == "paimon_menu.png")
        let image = try BGIAssetResolver.cgImage(for: BGIMiniMapConstants.paimonTemplateAssetName)
        #expect(image.width == Int(BGIMiniMapConstants.paimonTemplateSize.width))
        #expect(image.height == Int(BGIMiniMapConstants.paimonTemplateSize.height))
    }

    @Test("Paimon locator finds template top-left in top-left capture quadrant")
    func paimonLocatorFindsTemplateTopLeft() throws {
        let width = 960
        let height = 540
        let template = try BGIAssetResolver.scaledTemplateImage(
            for: BGIMiniMapConstants.paimonTemplateAssetName,
            frameWidth: width
        )
        let expectedTopLeft = CGPoint(x: 18, y: 34)
        let image = try makeSyntheticImage(
            width: width,
            height: height,
            template: template,
            templateTopLeft: expectedTopLeft
        )
        let frame = CaptureImageFrame(
            metadata: makeMetadata(width: width, height: height),
            cgImage: image,
            backendName: "Synthetic"
        )

        let match = try #require(BGIMiniMapPaimonLocator().locate(in: frame))

        #expect(match.confidence >= 0.99)
        #expect(abs(match.topLeft.x - expectedTopLeft.x) <= 1)
        #expect(abs(match.topLeft.y - expectedTopLeft.y) <= 1)
        #expect(match.rect.width == CGFloat(template.width))
        #expect(match.rect.height == CGFloat(template.height))
    }

    @Test("Fallback viewport follows upstream Paimon-relative crop at 1080p")
    func fallbackViewportUsesUpstreamOffsets() throws {
        let frame = makeMetadata(width: 1920, height: 1080)
        let rect = try BGIMiniMapExtractor().miniMapViewportRect(frame: frame)

        #expect(rect == CGRect(x: 48, y: 0, width: 210, height: 210))
    }

    @Test("Explicit Paimon top-left scales offsets with capture height")
    func explicitPaimonTopLeftScalesOffsets() throws {
        let frame = makeMetadata(width: 960, height: 540)
        let rect = try BGIMiniMapExtractor().miniMapViewportRect(
            frame: frame,
            paimonTopLeft: CGPoint(x: 12, y: 8)
        )

        #expect(rect == CGRect(x: 24, y: 0, width: 105, height: 105))
    }

    @Test("Extractor returns viewport and original-size centered crop")
    func extractorReturnsViewportAndOriginalCrop() throws {
        let image = try makeSyntheticImage(width: 1920, height: 1080)
        let frame = CaptureImageFrame(
            metadata: makeMetadata(width: 1920, height: 1080),
            cgImage: image,
            backendName: "Synthetic"
        )

        let extraction = try BGIMiniMapExtractor().extract(from: frame)

        #expect(extraction.viewportRect == CGRect(x: 48, y: 0, width: 210, height: 210))
        #expect(extraction.originalRect == CGRect(x: 75, y: 27, width: 156, height: 156))
        #expect(extraction.viewportImage.width == 210)
        #expect(extraction.viewportImage.height == 210)
        #expect(extraction.originalImage.width == 156)
        #expect(extraction.originalImage.height == 156)
        #expect(extraction.diagnostics.circularSampleCount > 18_000)
        #expect(extraction.diagnostics.meanLuma > 10)
        #expect(extraction.diagnostics.lumaStandardDeviation > 1)
    }

    @Test("Extractor detects window title bar only when fallback crop needs it")
    func extractorDetectsWindowChromeTopInset() throws {
        let image = try makeSyntheticImage(width: 1920, height: 1080, chromeHeight: 36)
        let frame = CaptureImageFrame(
            metadata: makeMetadata(width: 1920, height: 1080),
            cgImage: image,
            backendName: "Synthetic"
        )

        let extraction = try BGIMiniMapExtractor().extract(from: frame)
        let explicitPaimonExtraction = try BGIMiniMapExtractor().extract(
            from: frame,
            paimonTopLeft: CGPoint(x: 24, y: 15)
        )

        #expect(extraction.viewportRect == CGRect(x: 48, y: 36, width: 210, height: 210))
        #expect(extraction.originalRect == CGRect(x: 75, y: 63, width: 156, height: 156))
        #expect(explicitPaimonExtraction.viewportRect == CGRect(x: 48, y: 0, width: 210, height: 210))
    }

    private func makeMetadata(width: Int, height: Int) -> CapturedFrame {
        CapturedFrame(
            frameIndex: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            width: width,
            height: height,
            scaleFactor: 1,
            pixelFormat: kCVPixelFormatType_32BGRA,
            bytesPerRow: width * 4,
            sourceWindow: WindowInfo.mock()
        )
    }

    private func makeSyntheticImage(
        width: Int,
        height: Int,
        chromeHeight: Int = 0,
        template: CGImage? = nil,
        templateTopLeft: CGPoint = .zero
    ) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                if y < chromeHeight {
                    rgba[offset] = 238
                    rgba[offset + 1] = 238
                    rgba[offset + 2] = 238
                } else {
                    rgba[offset] = UInt8((x / 8) % 255)
                    rgba[offset + 1] = UInt8((y / 8) % 255)
                    rgba[offset + 2] = 80
                }
                rgba[offset + 3] = 255
            }
        }
        if let template {
            try blend(template, into: &rgba, width: width, height: height, at: templateTopLeft)
        }

        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Could not create synthetic image context")
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        return try #require(context.makeImage())
    }

    private func blend(_ template: CGImage, into rgba: inout [UInt8], width: Int, height: Int, at topLeft: CGPoint) throws {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let templateBytesPerRow = template.width * bytesPerPixel
        var templateRGBA = [UInt8](repeating: 0, count: template.height * templateBytesPerRow)
        guard let context = CGContext(
            data: &templateRGBA,
            width: template.width,
            height: template.height,
            bitsPerComponent: 8,
            bytesPerRow: templateBytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Could not create template image context")
            throw BGIMiniMapExtractionError.unableToReadPixels
        }
        context.draw(template, in: CGRect(x: 0, y: 0, width: template.width, height: template.height))

        let originX = Int(topLeft.x.rounded())
        let originY = Int(topLeft.y.rounded())
        for y in 0..<template.height {
            let destY = originY + y
            guard destY >= 0, destY < height else { continue }
            for x in 0..<template.width {
                let destX = originX + x
                guard destX >= 0, destX < width else { continue }

                let sourceOffset = y * templateBytesPerRow + x * bytesPerPixel
                let alpha = Double(templateRGBA[sourceOffset + 3]) / 255.0
                guard alpha > 0 else { continue }

                let destOffset = destY * bytesPerRow + destX * bytesPerPixel
                for channel in 0..<3 {
                    let source = Double(templateRGBA[sourceOffset + channel])
                    let dest = Double(rgba[destOffset + channel])
                    rgba[destOffset + channel] = UInt8(max(0, min(255, source + dest * (1 - alpha))))
                }
                rgba[destOffset + 3] = 255
            }
        }
    }
}
