import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI mini map preprocessor")
struct BGIMiniMapPreprocessorTests {
    @Test("Preprocessor emits BetterGI-sized masks")
    func preprocessorEmitsBetterGISizedMasks() throws {
        let image = try makeMiniMapImage(iconRect: CGRect(x: 68, y: 70, width: 20, height: 18))
        let result = try BGIMiniMapPreprocessor().preprocess(image)

        #expect(result.sourceImage.width == BGIMiniMapConstants.originalSize)
        #expect(result.sourceImage.height == BGIMiniMapConstants.originalSize)
        #expect(result.iconMaskImage.width == BGIMiniMapConstants.originalSize)
        #expect(result.usableMaskImage.height == BGIMiniMapConstants.originalSize)
        #expect(result.iconMask.count == BGIMiniMapConstants.originalSize * BGIMiniMapConstants.originalSize)
        #expect(result.usableMask.count == BGIMiniMapConstants.originalSize * BGIMiniMapConstants.originalSize)
    }

    @Test("CreateIconMask mirrors upstream mid-gray icon masking")
    func createIconMaskMasksMidGrayIcons() throws {
        let iconRect = CGRect(x: 68, y: 70, width: 20, height: 18)
        let image = try makeMiniMapImage(iconRect: iconRect)
        let result = try BGIMiniMapPreprocessor().preprocess(image)

        let centerIndex = 79 * BGIMiniMapConstants.originalSize + 78
        let backgroundIndex = 34 * BGIMiniMapConstants.originalSize + 34
        #expect(result.iconMask[centerIndex] == 255)
        #expect(result.usableMask[centerIndex] == 0)
        #expect(result.iconMask[backgroundIndex] == 0)
        #expect(result.usableMask[backgroundIndex] == 255)
        #expect(result.statistics.iconMaskedPixels >= Int(iconRect.width * iconRect.height))
        #expect(result.statistics.usablePixels < result.statistics.circlePixels)
    }

    @Test("Orientation estimator returns finite degree and confidence")
    func orientationEstimatorReturnsFiniteValues() throws {
        let image = try makeMiniMapImage(iconRect: CGRect(x: 68, y: 70, width: 20, height: 18))
        let preprocess = try BGIMiniMapPreprocessor().preprocess(image)

        let estimate = try BGIMiniMapOrientationEstimator().estimate(preprocess)

        #expect(estimate.degrees >= 0)
        #expect(estimate.degrees < 360)
        #expect(estimate.confidence.isFinite)
        #expect(estimate.confidence >= 0)
    }

    @Test("Process2 baseline emits processed image and final mask")
    func process2BaselineEmitsMatchInput() throws {
        let image = try makeMiniMapImage(iconRect: CGRect(x: 68, y: 70, width: 20, height: 18))
        let preprocess = try BGIMiniMapPreprocessor().preprocess(image)
        let orientation = try BGIMiniMapOrientationEstimator().estimate(preprocess)

        let matchInput = try BGIMiniMapPreprocessor().makeMatchInput(
            from: preprocess,
            orientation: orientation
        )

        #expect(matchInput.processedImage.width == BGIMiniMapConstants.originalSize)
        #expect(matchInput.processedImage.height == BGIMiniMapConstants.originalSize)
        #expect(matchInput.finalMaskImage.width == BGIMiniMapConstants.originalSize)
        #expect(matchInput.finalMask.count == BGIMiniMapConstants.originalSize * BGIMiniMapConstants.originalSize)
        #expect(matchInput.statistics.finalMaskPixels > 0)
        #expect(matchInput.finalMask[79 * BGIMiniMapConstants.originalSize + 78] == 0)
        #expect(matchInput.finalMask[34 * BGIMiniMapConstants.originalSize + 34] == 255)
    }

    private func makeMiniMapImage(iconRect: CGRect) throws -> CGImage {
        let width = BGIMiniMapConstants.originalSize
        let height = BGIMiniMapConstants.originalSize
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                if iconRect.contains(CGPoint(x: x, y: y)) {
                    rgba[offset] = 92
                    rgba[offset + 1] = 92
                    rgba[offset + 2] = 92
                } else {
                    rgba[offset] = UInt8(90 + (x % 40))
                    rgba[offset + 1] = UInt8(130 + (y % 60))
                    rgba[offset + 2] = UInt8(70 + ((x + y) % 50))
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
