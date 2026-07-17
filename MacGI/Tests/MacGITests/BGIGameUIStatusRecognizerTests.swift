import CoreGraphics
import Foundation
import ImageIO
@testable import MacGI
import Testing

@Suite("BGI game UI status recognizer")
struct BGIGameUIStatusRecognizerTests {
    @Test("QuickTeleport big-map status assets are bundled")
    func quickTeleportBigMapStatusAssetsAreBundled() {
        let coverage = BGIAssetResolver.coverage(
            for: RecognitionObject.bgiQuickTeleportBigMapStatusObjects
                + RecognitionObject.bgiCommonElementMainUIObjects
        )
        #expect(coverage.resolved == coverage.total)
    }

    @Test("Big-map scale fraction follows upstream 1080p Y mapping")
    func bigMapScaleFractionUses1080Y() throws {
        let now = Date()
        let scaleButton = RecognitionObservation(
            id: "scale",
            objectID: BGIGameUIStatusRecognizer.mapScaleObjectID,
            objectName: "MapScaleButton",
            recognitionType: .templateMatch,
            normalizedRect: CGRect(x: 30.0 / 1920.0, y: 500.0 / 1080.0, width: 10.0 / 1920.0, height: 16.0 / 1080.0),
            confidence: 0.99,
            text: nil,
            frameIndex: 1,
            timestamp: now
        )
        let value = try #require(BGIGameUIStatusRecognizer().bigMapScaleFraction(from: scaleButton))
        let expected = (612.0 - 508.0) / (612.0 - 468.0)
        #expect(abs(value - expected) < 0.0001)
    }

    @Test("Main UI status follows upstream Paimon menu template")
    func mainUIStatusUsesPaimonMenuTemplate() throws {
        let template = try BGIAssetResolver.cgImage(for: BGIMiniMapConstants.paimonTemplateAssetName)
        let image = try makeSyntheticFrame(
            template: template,
            at: CGPoint(x: 24, y: 15),
            size: CGSize(width: 1920, height: 1080)
        )
        let frame = makeSyntheticImageFrame(image, width: 1920, height: 1080)

        let status = BGIGameUIStatusRecognizer().recognize(frame)

        #expect(status.isInMainUI)
        #expect(!status.isInBigMapUI)
        #expect(status.paimonMenuObservation != nil)
    }

    @Test("Capturing JS host returns big-map zoom level from current frame")
    func capturingJSHostReturnsBigMapZoomLevelFromCurrentFrame() throws {
        let templateAsset = "GameTask/QuickTeleport/Assets/1920x1080/MapScaleButton.png"
        let template = try BGIAssetResolver.cgImage(for: templateAsset)
        let targetPoint = CGPoint(x: 35, y: 500)
        let image = try makeSyntheticFrame(
            template: template,
            at: targetPoint,
            size: CGSize(width: 1920, height: 1080)
        )
        let frame = makeSyntheticImageFrame(image, width: 1920, height: 1080)
        let host = BGICapturingJSScriptHostEnvironment(captureFrameProvider: { frame })

        let result = try host.performGenshinCommand(.getBigMapZoomLevel)

        let expectedCenterY = targetPoint.y + CGFloat(template.height) / 2
        let scale = (612.0 - Double(expectedCenterY)) / (612.0 - 468.0)
        let expected = (-5.0 * scale) + 6.0
        #expect(abs(result.doubleValue - expected) < 0.0001)
        #expect(host.genshinCommands == [.getBigMapZoomLevel])
    }
}

private func makeSyntheticImageFrame(_ image: CGImage, width: Int, height: Int) -> CaptureImageFrame {
    let window = WindowInfo(
        id: 7001,
        ownerPID: 1,
        ownerName: "MacGITests",
        title: "Synthetic BigMap",
        frame: CGRect(x: 0, y: 0, width: width, height: height),
        layer: 0,
        isOnScreen: true,
        scaleFactor: 1
    )
    return CaptureImageFrame(
        metadata: CapturedFrame(
            frameIndex: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            width: width,
            height: height,
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: width * 4,
            sourceWindow: window
        ),
        cgImage: image,
        backendName: "Synthetic"
    )
}

private func makeSyntheticFrame(template: CGImage, at point: CGPoint, size: CGSize) throws -> CGImage {
    let width = Int(size.width)
    let height = Int(size.height)
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let templatePixels = try rgbaPixels(from: template)
    let templateBytesPerRow = template.width * bytesPerPixel

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
            pixels[destinationIndex..<(destinationIndex + bytesPerPixel)] =
                templatePixels[sourceIndex..<(sourceIndex + bytesPerPixel)]
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
