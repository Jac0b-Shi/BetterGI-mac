import CoreGraphics
import Foundation
import ImageIO
@testable import MacGI
import Testing

@Suite("RustCoreBridge template matching")
struct RustCoreBridgeTemplateMatchTests {
    @MainActor
    @Test("RustCoreBridge calls macgi_core_match_template for multi-template observations")
    func rustCoreBridgeTemplateMatchReturnsMultipleObservations() throws {
        let dylibPath = localRustDylibPath()
        guard FileManager.default.fileExists(atPath: dylibPath) else {
            return
        }

        let bridge = try RustCoreBridge(libraryPath: dylibPath)
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

        let report = try #require(bridge.recognizeTemplates(imageFrame: imageFrame, objects: [object]))

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

    @Test("RustCoreBridge calls macgi_core_match_pixels for mini-map pixel matching")
    func rustCoreBridgePixelMatchFindsEmbeddedTemplate() throws {
        let dylibPath = localRustDylibPath()
        guard FileManager.default.fileExists(atPath: dylibPath) else {
            return
        }

        let bridge = try RustPixelMatchBridge(libraryPath: dylibPath)
        let template = makePattern(width: 5, height: 4, channels: 3)
        let source = embed(template, inWidth: 18, height: 16, atX: 7, y: 6)
        let mask = [Double](repeating: 1, count: template.width * template.height)
        let result = try #require(bridge.matchPixels(
            source: source,
            template: template,
            mask: mask,
            worstSqDiff: worstSqDiff(template: template, mask: mask),
            searchX: 2,
            searchY: 3,
            searchWidth: 14,
            searchHeight: 11
        ))

        #expect(result.sourcePoint == CGPoint(x: 7, y: 6))
        #expect(result.sqDiff == 0)
        #expect(result.confidence > 0.999)
    }

    @Test("RustPixelMatchBridge default loader finds local macgi-core dylib")
    func rustPixelMatchDefaultLoaderFindsLocalDylib() throws {
        let dylibPath = localRustDylibPath()
        guard FileManager.default.fileExists(atPath: dylibPath) else {
            return
        }

        _ = try #require(RustPixelMatchBridge.loadDefault())
    }

    private func localRustDylibPath() -> String {
        if let path = ProcessInfo.processInfo.environment["MACGI_CORE_DYLIB"], !path.isEmpty {
            return path
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot
            .appendingPathComponent("macgi-core/target/debug/libmacgi_core.dylib")
            .path
    }

    private func loadTemplate(_ assetName: String) throws -> CGImage {
        let url = try #require(BGIAssetResolver.url(for: assetName))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func loadScaledTemplate(_ assetName: String, frameWidth: Int) throws -> CGImage {
        try BGIAssetResolver.scaledTemplateImage(for: assetName, frameWidth: frameWidth)
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
}
