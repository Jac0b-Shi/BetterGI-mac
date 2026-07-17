import CoreGraphics
import Foundation

struct PaddleOCRImageShape: Equatable, Sendable {
    let channels: Int
    let width: Int
    let height: Int

    static let ppOcrV4Recognition = PaddleOCRImageShape(channels: 3, width: 320, height: 48)
}

struct PaddleOCRDetectionConfig: Equatable, Sendable {
    let maxLongSide: Int?
    let scale: Float
    let mean: [Float]
    let standardDeviation: [Float]

    static let ppOcrV4 = PaddleOCRDetectionConfig(
        maxLongSide: 960,
        scale: 1.0 / 255.0,
        mean: [0.485, 0.456, 0.406],
        standardDeviation: [0.229, 0.224, 0.225]
    )
}

struct PaddleOCRTensor: Equatable, Sendable {
    let shape: [Int]
    let values: [Float]
}

struct PaddleOCRRecognitionInput: Equatable, Sendable {
    let tensor: PaddleOCRTensor
    let originalSize: CGSize
    let resizedSize: CGSize

    var widthRatio: Double {
        guard originalSize.width > 0 else { return 1 }
        return Double(resizedSize.width / originalSize.width)
    }
}

struct PaddleOCRDetectionInput: Equatable, Sendable {
    let tensor: PaddleOCRTensor
    let originalSize: CGSize
    let resizedSize: CGSize
    let paddedSize: CGSize

    var resizedToOriginalScale: Double {
        guard resizedSize.width > 0 else { return 1 }
        return Double(originalSize.width / resizedSize.width)
    }
}

enum PaddleOCRPreprocessorError: LocalizedError {
    case invalidImageSize(width: Int, height: Int)
    case invalidShape(PaddleOCRImageShape)
    case invalidDetectionConfig
    case bitmapContextCreationFailed

    var errorDescription: String? {
        switch self {
        case let .invalidImageSize(width, height):
            "Invalid OCR image size: \(width)x\(height)"
        case let .invalidShape(shape):
            "Invalid PaddleOCR image shape: channels=\(shape.channels), width=\(shape.width), height=\(shape.height)"
        case .invalidDetectionConfig:
            "Invalid PaddleOCR detection normalization config"
        case .bitmapContextCreationFailed:
            "Failed to create OCR bitmap context"
        }
    }
}

enum PaddleOCRPreprocessor {
    static func recognitionInput(
        from image: CGImage,
        shape: PaddleOCRImageShape = .ppOcrV4Recognition,
        maxWidth: Int? = nil
    ) throws -> PaddleOCRRecognitionInput {
        try validate(image: image)
        guard shape.channels == 3, shape.width > 0, shape.height > 0 else {
            throw PaddleOCRPreprocessorError.invalidShape(shape)
        }

        let ratio = Double(image.width) / Double(image.height)
        let unclampedWidth = max(1, Int(ceil(Double(shape.height) * ratio)))
        let resizedWidth = max(1, min(unclampedWidth, maxWidth ?? unclampedWidth))
        let rgba = try rasterize(image, width: resizedWidth, height: shape.height)
        let pixelCount = resizedWidth * shape.height
        let tensor = PaddleOCRTensor(
            shape: [1, shape.channels, shape.height, resizedWidth],
            values: normalizedBGRRecognitionValues(rgba: rgba, pixelCount: pixelCount)
        )

        return PaddleOCRRecognitionInput(
            tensor: tensor,
            originalSize: CGSize(width: CGFloat(image.width), height: CGFloat(image.height)),
            resizedSize: CGSize(width: CGFloat(resizedWidth), height: CGFloat(shape.height))
        )
    }

    static func detectionInput(
        from image: CGImage,
        config: PaddleOCRDetectionConfig = .ppOcrV4
    ) throws -> PaddleOCRDetectionInput {
        try validate(image: image)
        guard config.scale > 0,
              config.mean.count == 3,
              config.standardDeviation.count == 3,
              config.standardDeviation.allSatisfy({ $0 > 0 }) else {
            throw PaddleOCRPreprocessorError.invalidDetectionConfig
        }

        let originalWidth = image.width
        let originalHeight = image.height
        let longEdge = max(originalWidth, originalHeight)
        let resizeScale: Double
        if let maxLongSide = config.maxLongSide, maxLongSide > 0, longEdge > maxLongSide {
            resizeScale = Double(maxLongSide) / Double(longEdge)
        } else {
            resizeScale = 1.0
        }
        let resizedWidth = max(1, Int(round(Double(originalWidth) * resizeScale)))
        let resizedHeight = max(1, Int(round(Double(originalHeight) * resizeScale)))
        let paddedWidth = ceilToMultiple(resizedWidth, multiple: 32)
        let paddedHeight = ceilToMultiple(resizedHeight, multiple: 32)

        let rgba = try rasterize(image, width: resizedWidth, height: resizedHeight)
        let values = normalizedBGRDetectionValues(
            rgba: rgba,
            resizedWidth: resizedWidth,
            resizedHeight: resizedHeight,
            paddedWidth: paddedWidth,
            paddedHeight: paddedHeight,
            config: config
        )

        return PaddleOCRDetectionInput(
            tensor: PaddleOCRTensor(shape: [1, 3, paddedHeight, paddedWidth], values: values),
            originalSize: CGSize(width: CGFloat(originalWidth), height: CGFloat(originalHeight)),
            resizedSize: CGSize(width: CGFloat(resizedWidth), height: CGFloat(resizedHeight)),
            paddedSize: CGSize(width: CGFloat(paddedWidth), height: CGFloat(paddedHeight))
        )
    }

    private static func validate(image: CGImage) throws {
        guard image.width > 0, image.height > 0 else {
            throw PaddleOCRPreprocessorError.invalidImageSize(width: image.width, height: image.height)
        }
    }

    private static func rasterize(_ image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        guard width > 0, height > 0 else {
            throw PaddleOCRPreprocessorError.invalidImageSize(width: width, height: height)
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &rgba,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
              ) else {
            throw PaddleOCRPreprocessorError.bitmapContextCreationFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return rgba
    }

    private static func normalizedBGRRecognitionValues(rgba: [UInt8], pixelCount: Int) -> [Float] {
        var values = [Float](repeating: 0, count: 3 * pixelCount)
        for pixelIndex in 0..<pixelCount {
            let rgbaIndex = pixelIndex * 4
            let red = Float(rgba[rgbaIndex])
            let green = Float(rgba[rgbaIndex + 1])
            let blue = Float(rgba[rgbaIndex + 2])
            values[pixelIndex] = (blue - 127.5) * 2.0 / 255.0
            values[pixelCount + pixelIndex] = (green - 127.5) * 2.0 / 255.0
            values[2 * pixelCount + pixelIndex] = (red - 127.5) * 2.0 / 255.0
        }
        return values
    }

    private static func normalizedBGRDetectionValues(
        rgba: [UInt8],
        resizedWidth: Int,
        resizedHeight: Int,
        paddedWidth: Int,
        paddedHeight: Int,
        config: PaddleOCRDetectionConfig
    ) -> [Float] {
        let planeSize = paddedWidth * paddedHeight
        var values = [Float](repeating: 0, count: 3 * planeSize)
        for channel in 0..<3 {
            let black = normalizedDetectionValue(0, channel: channel, config: config)
            values.replaceSubrange((channel * planeSize)..<((channel + 1) * planeSize), with: repeatElement(black, count: planeSize))
        }

        for y in 0..<resizedHeight {
            for x in 0..<resizedWidth {
                let sourceIndex = (y * resizedWidth + x) * 4
                let targetIndex = y * paddedWidth + x
                let red = rgba[sourceIndex]
                let green = rgba[sourceIndex + 1]
                let blue = rgba[sourceIndex + 2]
                values[targetIndex] = normalizedDetectionValue(blue, channel: 0, config: config)
                values[planeSize + targetIndex] = normalizedDetectionValue(green, channel: 1, config: config)
                values[2 * planeSize + targetIndex] = normalizedDetectionValue(red, channel: 2, config: config)
            }
        }
        return values
    }

    private static func normalizedDetectionValue(
        _ byte: UInt8,
        channel: Int,
        config: PaddleOCRDetectionConfig
    ) -> Float {
        (Float(byte) * config.scale - config.mean[channel]) / config.standardDeviation[channel]
    }

    private static func ceilToMultiple(_ value: Int, multiple: Int) -> Int {
        guard multiple > 0 else { return value }
        return ((value + multiple - 1) / multiple) * multiple
    }
}

struct PaddleOCRRecognizedLine: Equatable, Sendable {
    let text: String
    let confidence: Float
}

enum PaddleOCRCTCDecoderError: LocalizedError {
    case invalidShape(batch: Int, timeSteps: Int, classCount: Int)
    case invalidLogitCount(expected: Int, actual: Int)
    case labelIndexOutOfRange(index: Int, labelCount: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidShape(batch, timeSteps, classCount):
            "Invalid CTC logits shape: batch=\(batch), timeSteps=\(timeSteps), classCount=\(classCount)"
        case let .invalidLogitCount(expected, actual):
            "Invalid CTC logits count: expected \(expected), actual \(actual)"
        case let .labelIndexOutOfRange(index, labelCount):
            "CTC label index \(index) is out of range for \(labelCount) labels"
        }
    }
}

enum PaddleOCRCTCDecoder {
    static func decode(
        logits: [Float],
        timeSteps: Int,
        classCount: Int,
        labels: [String]
    ) throws -> PaddleOCRRecognizedLine {
        try decodeBatch(
            logits: logits,
            batchSize: 1,
            timeSteps: timeSteps,
            classCount: classCount,
            labels: labels
        )[0]
    }

    static func decodeBatch(
        logits: [Float],
        batchSize: Int,
        timeSteps: Int,
        classCount: Int,
        labels: [String]
    ) throws -> [PaddleOCRRecognizedLine] {
        guard batchSize > 0, timeSteps > 0, classCount > 0 else {
            throw PaddleOCRCTCDecoderError.invalidShape(batch: batchSize, timeSteps: timeSteps, classCount: classCount)
        }

        let expected = batchSize * timeSteps * classCount
        guard logits.count == expected else {
            throw PaddleOCRCTCDecoderError.invalidLogitCount(expected: expected, actual: logits.count)
        }

        return try (0..<batchSize).map { batchIndex in
            try decodeOne(
                logits: logits,
                batchOffset: batchIndex * timeSteps * classCount,
                timeSteps: timeSteps,
                classCount: classCount,
                labels: labels
            )
        }
    }

    private static func decodeOne(
        logits: [Float],
        batchOffset: Int,
        timeSteps: Int,
        classCount: Int,
        labels: [String]
    ) throws -> PaddleOCRRecognizedLine {
        var text = ""
        var lastIndex = 0
        var confidenceSum: Float = 0
        var acceptedCount = 0

        for step in 0..<timeSteps {
            let rowOffset = batchOffset + step * classCount
            var maxValue = -Float.infinity
            var maxIndex = 0
            for classIndex in 0..<classCount {
                let value = logits[rowOffset + classIndex]
                if value > maxValue {
                    maxValue = value
                    maxIndex = classIndex
                }
            }

            if maxIndex > 0, !(step > 0 && maxIndex == lastIndex) {
                text += try label(forCTCIndex: maxIndex, labels: labels)
                confidenceSum += maxValue
                acceptedCount += 1
            }
            lastIndex = maxIndex
        }

        return PaddleOCRRecognizedLine(
            text: text,
            confidence: acceptedCount > 0 ? confidenceSum / Float(acceptedCount) : 0
        )
    }

    private static func label(forCTCIndex index: Int, labels: [String]) throws -> String {
        if index > 0, index <= labels.count {
            return labels[index - 1]
        }
        if index == labels.count + 1 {
            return " "
        }
        throw PaddleOCRCTCDecoderError.labelIndexOutOfRange(index: index, labelCount: labels.count)
    }
}
