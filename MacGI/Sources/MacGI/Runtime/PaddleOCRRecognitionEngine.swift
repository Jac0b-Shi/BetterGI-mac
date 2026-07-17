import CoreGraphics
import Foundation

enum PaddleOCRRecognitionEngineError: LocalizedError {
    case missingColorRange(String)
    case unsupportedColorConversionCode(Int)
    case bitmapContextCreationFailed
    case cgImageCreationFailed

    var errorDescription: String? {
        switch self {
        case let .missingColorRange(id):
            "ColorRangeAndOcr object \(id) is missing lowerColor or upperColor"
        case let .unsupportedColorConversionCode(code):
            "Unsupported ColorRangeAndOcr color conversion code: \(code)"
        case .bitmapContextCreationFailed:
            "Failed to create ColorRangeAndOcr bitmap context"
        case .cgImageCreationFailed:
            "Failed to create ColorRangeAndOcr mask image"
        }
    }
}

struct PaddleOCRRecognitionReport: Equatable, Sendable {
    let observations: [RecognitionObservation]
    let objectCount: Int
    let matchedCount: Int
    let errors: [String]
    let costMs: Double
}

final class PaddleOCRRecognitionEngine {
    private let service: PaddleOCRService

    init(service: PaddleOCRService) {
        self.service = service
    }

    convenience init() throws {
        let runtime = try PaddleOCRRuntime()
        try self.init(runtime: runtime)
    }

    convenience init(runtime: PaddleOCRRuntime) throws {
        try self.init(service: PaddleOCRService(runtime: runtime))
    }

    func recognize(
        imageFrame: CaptureImageFrame,
        objects: [RecognitionObject]
    ) -> PaddleOCRRecognitionReport {
        let startedAt = Date()
        let ocrObjects = objects.filter(\.isOCRRecognitionType)
        var observations: [RecognitionObservation] = []
        var errors: [String] = []

        for object in ocrObjects {
            do {
                guard let observation = try observation(for: object, imageFrame: imageFrame) else {
                    continue
                }
                observations.append(observation)
            } catch {
                errors.append("\(object.id): \(error.localizedDescription)")
            }
        }

        return PaddleOCRRecognitionReport(
            observations: observations,
            objectCount: ocrObjects.count,
            matchedCount: observations.count,
            errors: errors,
            costMs: Date().timeIntervalSince(startedAt) * 1000
        )
    }

    private func observation(
        for object: RecognitionObject,
        imageFrame: CaptureImageFrame
    ) throws -> RecognitionObservation? {
        let cropRect = cropRect(for: object, image: imageFrame.cgImage)
        guard let croppedImage = imageFrame.cgImage.cropping(to: cropRect) else {
            throw PaddleOCROnnxRuntimeError.imageCropFailed(cropRect)
        }
        let ocrImage = try colorRangeMaskedImageIfNeeded(croppedImage, object: object)

        let result = try service.recognize(
            ocrImage,
            frameIndex: imageFrame.metadata.frameIndex,
            timestamp: imageFrame.metadata.timestamp
        )
        let rawText = result.combinedText
        let normalizedText = normalizedOCRText(rawText, replacements: object.replaceDictionary)
        guard shouldEmitObservation(for: object, normalizedText: normalizedText) else {
            return nil
        }

        let normalizedRect = CGRect(
            x: cropRect.minX / CGFloat(imageFrame.cgImage.width),
            y: cropRect.minY / CGFloat(imageFrame.cgImage.height),
            width: cropRect.width / CGFloat(imageFrame.cgImage.width),
            height: cropRect.height / CGFloat(imageFrame.cgImage.height)
        )
        let confidence = result.regions.map(\.confidence).max() ?? 0
        return RecognitionObservation(
            id: "\(object.id)-\(imageFrame.metadata.frameIndex)",
            objectID: object.id,
            objectName: object.name ?? object.id,
            recognitionType: object.recognitionType,
            normalizedRect: normalizedRect,
            confidence: Double(confidence),
            text: normalizedText,
            frameIndex: imageFrame.metadata.frameIndex,
            timestamp: imageFrame.metadata.timestamp
        )
    }

    private func cropRect(for object: RecognitionObject, image: CGImage) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let roi = object.regionOfInterest else { return full }

        let normalized = roi.normalizedRect()
        let raw = CGRect(
            x: normalized.minX * CGFloat(image.width),
            y: normalized.minY * CGFloat(image.height),
            width: normalized.width * CGFloat(image.width),
            height: normalized.height * CGFloat(image.height)
        )
        let clamped = raw.intersection(full).integral
        return clamped.isEmpty ? full : clamped
    }

    private func colorRangeMaskedImageIfNeeded(
        _ image: CGImage,
        object: RecognitionObject
    ) throws -> CGImage {
        guard object.recognitionType == .colorRangeAndOcr else { return image }
        guard let lowerColor = object.lowerColor,
              let upperColor = object.upperColor else {
            throw PaddleOCRRecognitionEngineError.missingColorRange(object.id)
        }

        let width = image.width
        let height = image.height
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
            throw PaddleOCRRecognitionEngineError.bitmapContextCreationFailed
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var maskRGBA = [UInt8](repeating: 0, count: rgba.count)
        for pixelIndex in 0..<(width * height) {
            let offset = pixelIndex * bytesPerPixel
            let red = Double(rgba[offset])
            let green = Double(rgba[offset + 1])
            let blue = Double(rgba[offset + 2])
            let channels = try convertedChannels(
                red: red,
                green: green,
                blue: blue,
                colorConversionCode: object.colorConversionCode
            )
            let value: UInt8 = matchesColorRange(channels, lower: lowerColor, upper: upperColor) ? 255 : 0
            maskRGBA[offset] = value
            maskRGBA[offset + 1] = value
            maskRGBA[offset + 2] = value
            maskRGBA[offset + 3] = 255
        }

        guard let provider = CGDataProvider(data: Data(maskRGBA) as CFData),
              let maskImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGImageByteOrderInfo.order32Big.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw PaddleOCRRecognitionEngineError.cgImageCreationFailed
        }
        return maskImage
    }

    private func convertedChannels(
        red: Double,
        green: Double,
        blue: Double,
        colorConversionCode: Int
    ) throws -> [Double] {
        switch colorConversionCode {
        case OpenCVColorConversionCode.bgra2BGR:
            return [blue, green, red]
        case OpenCVColorConversionCode.bgr2RGB:
            return [red, green, blue]
        case OpenCVColorConversionCode.bgr2GRAY:
            let gray = 0.114 * blue + 0.587 * green + 0.299 * red
            return [gray]
        case OpenCVColorConversionCode.bgr2HSV:
            let hsv = bgrToHSV(blue: blue, green: green, red: red)
            return [hsv.hue, hsv.saturation, hsv.value]
        default:
            throw PaddleOCRRecognitionEngineError.unsupportedColorConversionCode(colorConversionCode)
        }
    }

    private func bgrToHSV(blue: Double, green: Double, red: Double) -> (hue: Double, saturation: Double, value: Double) {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue

        let hueDegrees: Double
        if delta == 0 {
            hueDegrees = 0
        } else if maxValue == red {
            hueDegrees = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxValue == green {
            hueDegrees = 60 * ((blue - red) / delta + 2)
        } else {
            hueDegrees = 60 * ((red - green) / delta + 4)
        }

        let normalizedHue = hueDegrees < 0 ? hueDegrees + 360 : hueDegrees
        let saturation = maxValue == 0 ? 0 : delta / maxValue * 255
        return (normalizedHue / 2, saturation, maxValue)
    }

    private func matchesColorRange(
        _ channels: [Double],
        lower: BGIColorScalar,
        upper: BGIColorScalar
    ) -> Bool {
        let lowerValues = [lower.b, lower.g, lower.r, lower.a]
        let upperValues = [upper.b, upper.g, upper.r, upper.a]
        for index in channels.indices {
            guard channels[index] >= lowerValues[index], channels[index] <= upperValues[index] else {
                return false
            }
        }
        return true
    }

    private func normalizedOCRText(
        _ text: String,
        replacements: [String: [String]]
    ) -> String {
        var result = text.filter { !$0.isWhitespace }
        for (target, candidates) in replacements {
            for candidate in candidates {
                result = result.replacingOccurrences(of: candidate, with: target)
            }
        }
        return result
    }

    private func shouldEmitObservation(
        for object: RecognitionObject,
        normalizedText: String
    ) -> Bool {
        guard !normalizedText.isEmpty else { return false }

        switch object.recognitionType {
        case .ocr, .colorRangeAndOcr:
            return true
        case .ocrMatch:
            guard !object.allContainMatchText.isEmpty
                    || !object.oneContainMatchText.isEmpty
                    || !object.regexMatchText.isEmpty else {
                return false
            }
            let allContain = object.allContainMatchText.allSatisfy { normalizedText.contains($0) }
            let oneContain = object.oneContainMatchText.isEmpty
                || object.oneContainMatchText.contains { normalizedText.contains($0) }
            let allRegex = object.regexMatchText.allSatisfy { pattern in
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
                let range = NSRange(normalizedText.startIndex..., in: normalizedText)
                return regex.firstMatch(in: normalizedText, range: range) != nil
            }
            return allContain && oneContain && allRegex
        default:
            return false
        }
    }
}

private enum OpenCVColorConversionCode {
    static let bgra2BGR = 1
    static let bgr2RGB = 4
    static let bgr2GRAY = 6
    static let bgr2HSV = 40
}

private extension RecognitionObject {
    var isOCRRecognitionType: Bool {
        switch recognitionType {
        case .ocr, .ocrMatch, .colorRangeAndOcr:
            true
        default:
            false
        }
    }
}
