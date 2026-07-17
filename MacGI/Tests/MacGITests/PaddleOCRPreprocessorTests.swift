import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI PaddleOCR preprocessing")
struct PaddleOCRPreprocessorTests {
    @Test("Recognition preprocessing matches BGI BGR CHW normalization")
    func recognitionPreprocessingUsesBGRCHWNormalization() throws {
        let image = try makeImage(
            width: 2,
            height: 1,
            pixels: [
                RGBA(red: 255, green: 0, blue: 0),
                RGBA(red: 0, green: 255, blue: 0)
            ]
        )
        let shape = PaddleOCRImageShape(channels: 3, width: 2, height: 1)

        let input = try PaddleOCRPreprocessor.recognitionInput(from: image, shape: shape)

        #expect(input.tensor.shape == [1, 3, 1, 2])
        #expect(input.resizedSize == CGSize(width: 2, height: 1))
        #expect(abs(input.tensor.values[0] - -1.0) < 0.001)
        #expect(abs(input.tensor.values[1] - -1.0) < 0.001)
        #expect(abs(input.tensor.values[2] - -1.0) < 0.001)
        #expect(abs(input.tensor.values[3] - 1.0) < 0.001)
        #expect(abs(input.tensor.values[4] - 1.0) < 0.001)
        #expect(abs(input.tensor.values[5] - -1.0) < 0.001)
    }

    @Test("Detection preprocessing resizes and pads to multiples of 32")
    func detectionPreprocessingPadsToMultipleOf32() throws {
        let image = try makeImage(
            width: 65,
            height: 33,
            pixels: Array(repeating: RGBA(red: 255, green: 0, blue: 0), count: 65 * 33)
        )
        let config = PaddleOCRDetectionConfig(
            maxLongSide: nil,
            scale: 1.0 / 255.0,
            mean: [0.485, 0.456, 0.406],
            standardDeviation: [0.229, 0.224, 0.225]
        )

        let input = try PaddleOCRPreprocessor.detectionInput(from: image, config: config)

        #expect(input.tensor.shape == [1, 3, 64, 96])
        #expect(input.resizedSize == CGSize(width: 65, height: 33))
        #expect(input.paddedSize == CGSize(width: 96, height: 64))

        let planeSize = 64 * 96
        let redPlaneFirstPixel = input.tensor.values[2 * planeSize]
        let paddedBluePixel = input.tensor.values[63 * 96 + 95]
        #expect(abs(redPlaneFirstPixel - Float((1.0 - 0.406) / 0.225)) < 0.001)
        #expect(abs(paddedBluePixel - Float((0.0 - 0.485) / 0.229)) < 0.001)
    }

    @Test("CTC decoder follows BGI blank and duplicate skipping")
    func ctcDecoderSkipsBlankAndContinuousDuplicate() throws {
        let labels = ["A", "B", "C"]
        let classCount = labels.count + 2
        let logits = makeLogits(
            winningIndexes: [0, 1, 1, 0, 2, 4],
            scores: [0.6, 0.9, 0.85, 0.7, 0.8, 0.7],
            classCount: classCount
        )

        let line = try PaddleOCRCTCDecoder.decode(
            logits: logits,
            timeSteps: 6,
            classCount: classCount,
            labels: labels
        )

        #expect(line.text == "AB ")
        #expect(abs(line.confidence - Float(0.8)) < 0.001)
    }

    @Test("CTC decoder maps bundled Paddle labels with one-based CTC indexes")
    func ctcDecoderMapsBundledPaddleLabels() throws {
        let labels = try BGIModelAssetResolver.paddleCharacterDictionary(for: .paddleOcrRecV4)
        let yuanIndex = try #require(labels.firstIndex(of: "原")).advanced(by: 1)
        let logits = makeLogits(winningIndexes: [yuanIndex], scores: [0.99], classCount: labels.count + 2)

        let line = try PaddleOCRCTCDecoder.decode(
            logits: logits,
            timeSteps: 1,
            classCount: labels.count + 2,
            labels: labels
        )

        #expect(line.text == "原")
        #expect(abs(line.confidence - Float(0.99)) < 0.001)
    }

    private func makeLogits(winningIndexes: [Int], scores: [Float], classCount: Int) -> [Float] {
        var logits: [Float] = []
        for (index, winner) in winningIndexes.enumerated() {
            var row = [Float](repeating: 0, count: classCount)
            row[winner] = scores[index]
            logits.append(contentsOf: row)
        }
        return logits
    }

    private func makeImage(width: Int, height: Int, pixels: [RGBA]) throws -> CGImage {
        #expect(pixels.count == width * height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes: [UInt8] = []
        bytes.reserveCapacity(pixels.count * bytesPerPixel)
        for pixel in pixels {
            bytes.append(pixel.red)
            bytes.append(pixel.green)
            bytes.append(pixel.blue)
            bytes.append(pixel.alpha)
        }
        let data = Data(bytes)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }
}

private struct RGBA {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}
