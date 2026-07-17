import CoreGraphics
import Foundation
import ImageIO
@testable import MacGI
import Testing

@Suite("BetterGI template resources")
struct TemplateMatchingRecognitionEngineTests {
    @Test("P0 template resources resolve from bundle")
    func p0TemplateResourcesResolve() throws {
        let coverage = BGIAssetResolver.coverage(for: RecognitionObject.bgiP0Defaults)
        let templateCount = Set(RecognitionObject.bgiP0Defaults.compactMap(\.templateAssetName)).count
        #expect(coverage.total == templateCount)
        #expect(coverage.resolved == templateCount)
        #expect(coverage.missing.isEmpty)
    }

    @Test("Template assets scale with BetterGI 1080P AssetScale")
    func templateAssetsScaleWithBetterGIAssetScale() throws {
        let assetName = "GameTask/AutoSkip/Assets/1920x1080/icon_option.png"
        let rawTemplate = try loadTemplate(assetName)
        let scaledTemplate = try BGIAssetResolver.scaledTemplateImage(for: assetName, frameWidth: 960)

        #expect(abs(BGIAssetResolver.assetScale(forFrameWidth: 960) - 0.5) < 0.0001)
        #expect(BGIAssetResolver.assetScale(forFrameWidth: 2560) == 1)
        #expect(scaledTemplate.width == max(1, Int((Double(rawTemplate.width) * 0.5).rounded())))
        #expect(scaledTemplate.height == max(1, Int((Double(rawTemplate.height) * 0.5).rounded())))
    }

    @Test("Template assets resolve upstream feature asset aliases")
    func templateAssetsResolveUpstreamFeatureAssetAliases() throws {
        let directAssetName = "GameTask/AutoSkip/Assets/1920x1080/icon_option.png"
        let aliasAssetName = "AutoSkip:icon_option.png"
        let backslashDirectAssetName = #"GameTask\AutoSkip\Assets\1920x1080\icon_option.png"#

        #expect(BGIAssetResolver.resolvedAssetName(for: aliasAssetName) == directAssetName)
        #expect(BGIAssetResolver.url(for: aliasAssetName) == BGIAssetResolver.url(for: directAssetName))
        #expect(BGIAssetResolver.url(for: backslashDirectAssetName) == BGIAssetResolver.url(for: directAssetName))
        let aliasTemplate = try BGIAssetResolver.scaledTemplateImage(for: aliasAssetName, frameWidth: 960)
        let directTemplate = try BGIAssetResolver.scaledTemplateImage(for: directAssetName, frameWidth: 960)
        #expect(aliasTemplate.width == directTemplate.width)
        #expect(aliasTemplate.height == directTemplate.height)
    }

    @Test("Template matcher finds an exact F icon in a synthetic frame")
    func templateMatcherFindsExactFIcon() throws {
        let frameWidth = 960
        let frameHeight = 540
        let template = try loadScaledTemplate("GameTask/AutoPick/Assets/1920x1080/F.png", frameWidth: frameWidth)
        let targetPoint = CGPoint(x: 220, y: 180)
        let image = try makeSyntheticFrame(template: template, at: targetPoint, size: CGSize(width: frameWidth, height: frameHeight))
        let window = WindowInfo(
            id: 7,
            ownerPID: 1,
            ownerName: "MacGITests",
            title: "Synthetic",
            frame: CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1
        )
        let metadata = CapturedFrame(
            frameIndex: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            width: frameWidth,
            height: frameHeight,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: frameWidth * 4,
            sourceWindow: window
        )
        let imageFrame = CaptureImageFrame(metadata: metadata, cgImage: image, backendName: "Synthetic")
        let object = RecognitionObject(
            id: "AutoPick.FRo",
            recognitionType: .templateMatch,
            regionOfInterest: RecognitionROI(x: 0.20, y: 0.30, width: 0.08, height: 0.10, coordinateSpace: .normalized),
            name: "F",
            templateAssetName: "GameTask/AutoPick/Assets/1920x1080/F.png",
            threshold: 0.95
        )

        let report = TemplateMatchingRecognitionEngine().recognize(
            imageFrame: imageFrame,
            objects: [object]
        )

        #expect(report.objectCount == 1)
        #expect(report.matchedCount == 1)
        let observation = try #require(report.observations.first)
        #expect(observation.confidence >= 0.99)
        let observedRect = CGRect(
            x: observation.normalizedRect.minX * CGFloat(frameWidth),
            y: observation.normalizedRect.minY * CGFloat(frameHeight),
            width: observation.normalizedRect.width * CGFloat(frameWidth),
            height: observation.normalizedRect.height * CGFloat(frameHeight)
        )
        let expectedRect = CGRect(
            x: targetPoint.x,
            y: targetPoint.y,
            width: CGFloat(template.width),
            height: CGFloat(template.height)
        )
        #expect(observedRect.intersects(expectedRect))
    }

    @Test("Template matcher emits multiple option icon observations when requested")
    func templateMatcherEmitsMultipleOptionIcons() throws {
        let assetName = "GameTask/AutoSkip/Assets/1920x1080/icon_option.png"
        let frameWidth = 960
        let frameHeight = 540
        let template = try loadScaledTemplate(assetName, frameWidth: frameWidth)
        let targetPoints = [
            CGPoint(x: 250, y: 160),
            CGPoint(x: 252, y: 210)
        ]
        let image = try makeSyntheticFrame(
            template: template,
            at: targetPoints,
            size: CGSize(width: frameWidth, height: frameHeight)
        )
        let imageFrame = makeSyntheticImageFrame(image, width: frameWidth, height: frameHeight)
        let object = RecognitionObject(
            id: "AutoSkip.OptionIconRo",
            recognitionType: .templateMatch,
            regionOfInterest: RecognitionROI(x: 0.24, y: 0.28, width: 0.08, height: 0.16, coordinateSpace: .normalized),
            name: "OptionIcon",
            templateAssetName: assetName,
            threshold: 0.999,
            maxMatchCount: 8
        )

        let report = TemplateMatchingRecognitionEngine().recognize(
            imageFrame: imageFrame,
            objects: [object]
        )

        #expect(report.objectCount == 1)
        #expect(report.matchedCount == 2)
        #expect(Set(report.observations.map(\.id)).count == 2)

        let observedRects = report.observations.map { observation in
            CGRect(
                x: observation.normalizedRect.minX * CGFloat(frameWidth),
                y: observation.normalizedRect.minY * CGFloat(frameHeight),
                width: observation.normalizedRect.width * CGFloat(frameWidth),
                height: observation.normalizedRect.height * CGFloat(frameHeight)
            )
        }
        for point in targetPoints {
            let expectedRect = CGRect(
                x: point.x,
                y: point.y,
                width: CGFloat(template.width),
                height: CGFloat(template.height)
            )
            #expect(observedRects.contains { $0.intersects(expectedRect) })
        }
    }

    @Test("P0 AutoSkip option icon requests multi-match observations")
    func p0OptionIconRequestsMultiMatch() throws {
        let optionIcon = try #require(RecognitionObject.bgiP0Defaults.first {
            $0.id == "AutoSkip.OptionIconRo"
        })

        #expect(optionIcon.maxMatchCount == 8)
    }

    private func loadTemplate(_ assetName: String) throws -> CGImage {
        let url = try #require(BGIAssetResolver.url(for: assetName))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func loadScaledTemplate(_ assetName: String, frameWidth: Int) throws -> CGImage {
        try BGIAssetResolver.scaledTemplateImage(for: assetName, frameWidth: frameWidth)
    }

    private func makeSyntheticFrame(template: CGImage, at point: CGPoint, size: CGSize) throws -> CGImage {
        try makeSyntheticFrame(template: template, at: [point], size: size)
    }

    private func makeSyntheticFrame(template: CGImage, at points: [CGPoint], size: CGSize) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let templatePixels = try rgbaPixels(from: template)
        let templateBytesPerRow = template.width * bytesPerPixel

        for point in points {
            let originX = Int(point.x.rounded())
            let originY = Int(point.y.rounded())
            for templateY in 0..<template.height {
                let destinationY = originY + templateY
                guard destinationY >= 0, destinationY < height else { continue }
                for templateX in 0..<template.width {
                    let destinationX = originX + templateX
                    guard destinationX >= 0, destinationX < width else { continue }
                    let sourceIndex = templateY * templateBytesPerRow + templateX * bytesPerPixel
                    let destinationIndex = destinationY * bytesPerRow + destinationX * bytesPerPixel
                    pixels[destinationIndex..<(destinationIndex + bytesPerPixel)] = templatePixels[sourceIndex..<(sourceIndex + bytesPerPixel)]
                }
            }
        }

        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
        ))
        return try #require(context.makeImage())
    }

    private func rgbaPixels(from image: CGImage) throws -> [UInt8] {
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    private func makeSyntheticImageFrame(_ image: CGImage, width: Int, height: Int) -> CaptureImageFrame {
        let window = WindowInfo(
            id: 7,
            ownerPID: 1,
            ownerName: "MacGITests",
            title: "Synthetic",
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1
        )
        let metadata = CapturedFrame(
            frameIndex: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            width: width,
            height: height,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: width * 4,
            sourceWindow: window
        )
        return CaptureImageFrame(metadata: metadata, cgImage: image, backendName: "Synthetic")
    }
}
