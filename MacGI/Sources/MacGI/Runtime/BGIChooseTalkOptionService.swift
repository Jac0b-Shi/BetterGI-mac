import CoreGraphics
import Foundation

struct BGIChooseTalkOptionConfig: Equatable, Sendable {
    var talkUIRetryTimes: Int = 10
    var talkUIRetryIntervalMs: UInt64 = 500
    var skipWaitMs: UInt64 = 500
    var firstTextStabilizeWaitMs: UInt64 = 1_000
    var clickWaitMs: UInt64 = 300
}

enum BGIChooseTalkOptionError: LocalizedError, Equatable {
    case captureUnavailable
    case ocrUnavailable
    case talkUIUnavailable
    case optionNotFound(String)
    case foundButNotOrange(String)
    case invalidClickTarget(CGRect)

    var errorDescription: String? {
        switch self {
        case .captureUnavailable:
            "ChooseTalkOption requires a capture provider"
        case .ocrUnavailable:
            "ChooseTalkOption requires an OCR provider"
        case .talkUIUnavailable:
            "Current UI is not a talk option UI"
        case let .optionNotFound(option):
            "Talk option not found: \(option)"
        case let .foundButNotOrange(option):
            "Talk option found but it is not orange: \(option)"
        case let .invalidClickTarget(rect):
            "Could not convert talk option OCR rect to screen point: \(rect)"
        }
    }
}

final class BGIChooseTalkOptionService: @unchecked Sendable {
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias RecognitionObjectProvider = @MainActor (CaptureImageFrame, RecognitionObject) async throws -> [RecognitionObservation]
    typealias OCRProvider = @MainActor (CaptureImageFrame, CGRect?) async throws -> OCRResult

    private let inputHandler: InputHandler
    private let captureFrameProvider: CaptureFrameProvider?
    private let recognitionObjectProvider: RecognitionObjectProvider?
    private let ocrProvider: OCRProvider?
    private let templateRecognitionEngine: TemplateMatchingRecognitionEngine
    private let config: BGIChooseTalkOptionConfig

    init(
        inputHandler: @escaping InputHandler,
        captureFrameProvider: CaptureFrameProvider? = nil,
        recognitionObjectProvider: RecognitionObjectProvider? = nil,
        ocrProvider: OCRProvider? = nil,
        templateRecognitionEngine: TemplateMatchingRecognitionEngine = TemplateMatchingRecognitionEngine(),
        config: BGIChooseTalkOptionConfig = BGIChooseTalkOptionConfig()
    ) {
        self.inputHandler = inputHandler
        self.captureFrameProvider = captureFrameProvider
        self.recognitionObjectProvider = recognitionObjectProvider
        self.ocrProvider = ocrProvider
        self.templateRecognitionEngine = templateRecognitionEngine
        self.config = config
    }

    func selectText(_ option: String, skipTimes: Int, isOrange: Bool) async throws {
        guard let captureFrameProvider else {
            throw BGIChooseTalkOptionError.captureUnavailable
        }
        guard let ocrProvider else {
            throw BGIChooseTalkOptionError.ocrUnavailable
        }
        guard try await waitForTalkUI(using: captureFrameProvider) else {
            throw BGIChooseTalkOptionError.talkUIUnavailable
        }

        var delayedForFirstOCR = false
        for _ in 0..<max(1, skipTimes) {
            let frame = try await captureFrameProvider()
            let optionIcons = try await optionIconObservations(in: frame)
            guard let lowestOptionIcon = optionIcons.sorted(by: lowestFirst).first else {
                await perform(.keyPress(key: .space))
                try await sleep(config.skipWaitMs)
                continue
            }

            if !delayedForFirstOCR {
                delayedForFirstOCR = true
                try await sleep(config.firstTextStabilizeWaitMs)
            }

            let ocrROI = textOCRRect(for: lowestOptionIcon, frame: frame)
            let ocrResult = try await ocrProvider(frame, ocrROI)
            let matchingRegions = ocrResult.regions
                .filter { !$0.text.isEmpty && $0.text.contains(option) }
                .sorted { $0.boundingBox.minY < $1.boundingBox.minY }
            guard let matchedRegion = matchingRegions.first else {
                continue
            }

            if isOrange, !isOrangeOption(frame: frame, rect: matchedRegion.boundingBox) {
                throw BGIChooseTalkOptionError.foundButNotOrange(option)
            }

            let normalized = normalizedRect(matchedRegion.boundingBox, frame: frame)
            guard let point = InputTargetResolver.screenPoint(for: normalized, in: frame.metadata) else {
                throw BGIChooseTalkOptionError.invalidClickTarget(matchedRegion.boundingBox)
            }
            await perform(.mouseClick(button: .left, at: point))
            try await sleep(config.clickWaitMs)
            return
        }

        throw BGIChooseTalkOptionError.optionNotFound(option)
    }

    private func optionIconObservations(in frame: CaptureImageFrame) async throws -> [RecognitionObservation] {
        try await observations(in: frame, object: optionIconRecognitionObject())
    }

    private func talkUIObservations(in frame: CaptureImageFrame) async throws -> [RecognitionObservation] {
        try await observations(in: frame, object: talkUIRecognitionObject())
    }

    private func observations(in frame: CaptureImageFrame, object: RecognitionObject) async throws -> [RecognitionObservation] {
        if let recognitionObjectProvider {
            return try await recognitionObjectProvider(frame, object)
        }
        return templateRecognitionEngine.recognize(
            imageFrame: frame,
            objects: [object]
        ).observations
    }

    private func optionIconRecognitionObject() throws -> RecognitionObject {
        guard let object = RecognitionObject.bgiAutoSkipObjects.first(where: { $0.id == "AutoSkip.OptionIconRo" }) else {
            throw BGIChooseTalkOptionError.optionNotFound("AutoSkip.OptionIconRo")
        }
        return object
    }

    private func talkUIRecognitionObject() throws -> RecognitionObject {
        guard let object = RecognitionObject.bgiAutoSkipObjects.first(where: { $0.id == "AutoSkip.DisabledUiButtonRo" }) else {
            throw BGIChooseTalkOptionError.talkUIUnavailable
        }
        return object
    }

    private func waitForTalkUI(using captureFrameProvider: CaptureFrameProvider) async throws -> Bool {
        for attempt in 0..<max(1, config.talkUIRetryTimes) {
            let frame = try await captureFrameProvider()
            let observations = try await talkUIObservations(in: frame)
            if !observations.isEmpty {
                return true
            }
            if attempt < max(1, config.talkUIRetryTimes) - 1 {
                try await sleep(config.talkUIRetryIntervalMs)
            }
        }
        return false
    }

    private func lowestFirst(lhs: RecognitionObservation, rhs: RecognitionObservation) -> Bool {
        if lhs.normalizedRect.minY != rhs.normalizedRect.minY {
            return lhs.normalizedRect.minY > rhs.normalizedRect.minY
        }
        return lhs.normalizedRect.minX < rhs.normalizedRect.minX
    }

    private func textOCRRect(for lowestOptionIcon: RecognitionObservation, frame: CaptureImageFrame) -> CGRect {
        let width = CGFloat(max(1, frame.metadata.width))
        let height = CGFloat(max(1, frame.metadata.height))
        let scale = width / 1_920.0
        let iconRect = CGRect(
            x: lowestOptionIcon.normalizedRect.minX * width,
            y: lowestOptionIcon.normalizedRect.minY * height,
            width: lowestOptionIcon.normalizedRect.width * width,
            height: lowestOptionIcon.normalizedRect.height * height
        )
        let rect = CGRect(
            x: iconRect.maxX + 8.0 * scale,
            y: height / 8.0,
            width: 535.0 * scale,
            height: iconRect.maxY + 30.0 * scale - height / 12.0
        )
        return rect.intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
    }

    private func normalizedRect(_ rect: CGRect, frame: CaptureImageFrame) -> CGRect {
        CGRect(
            x: rect.minX / CGFloat(max(1, frame.metadata.width)),
            y: rect.minY / CGFloat(max(1, frame.metadata.height)),
            width: rect.width / CGFloat(max(1, frame.metadata.width)),
            height: rect.height / CGFloat(max(1, frame.metadata.height))
        )
    }

    private func isOrangeOption(frame: CaptureImageFrame, rect: CGRect) -> Bool {
        let imageBounds = CGRect(x: 0, y: 0, width: frame.cgImage.width, height: frame.cgImage.height)
        let cropRect = rect.integral.intersection(imageBounds)
        guard !cropRect.isNull,
              !cropRect.isEmpty,
              let cropped = frame.cgImage.cropping(to: cropRect),
              let rgba = rgbaPixels(from: cropped) else {
            return false
        }

        var orangePixels = 0
        let totalPixels = max(1, cropped.width * cropped.height)
        for pixel in 0..<totalPixels {
            let offset = pixel * 4
            let hsv = rgbToHSV(
                red: Double(rgba[offset]),
                green: Double(rgba[offset + 1]),
                blue: Double(rgba[offset + 2])
            )
            if hsv.hue >= 10.0,
               hsv.hue <= 25.0,
               hsv.saturation >= 150.0,
               hsv.value >= 150.0 {
                orangePixels += 1
            }
        }
        return Double(orangePixels) / Double(totalPixels) > 0.1
    }

    private func rgbaPixels(from image: CGImage) -> [UInt8]? {
        let bytesPerRow = image.width * 4
        var rgba = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        guard let context = CGContext(
            data: &rgba,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return rgba
    }

    private func rgbToHSV(red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, value: Double) {
        let r = red / 255.0
        let g = green / 255.0
        let b = blue / 255.0
        let maxChannel = max(r, g, b)
        let minChannel = min(r, g, b)
        let delta = maxChannel - minChannel

        let hueDegrees: Double
        if delta == 0 {
            hueDegrees = 0
        } else if maxChannel == r {
            hueDegrees = 60.0 * ((g - b) / delta).truncatingRemainder(dividingBy: 6.0)
        } else if maxChannel == g {
            hueDegrees = 60.0 * (((b - r) / delta) + 2.0)
        } else {
            hueDegrees = 60.0 * (((r - g) / delta) + 4.0)
        }

        let hue = (hueDegrees < 0 ? hueDegrees + 360.0 : hueDegrees) / 2.0
        let saturation = maxChannel == 0 ? 0 : (delta / maxChannel) * 255.0
        return (hue: hue, saturation: saturation, value: maxChannel * 255.0)
    }

    private func perform(_ action: InputAction) async {
        _ = await inputHandler(action)
    }

    private func sleep(_ ms: UInt64) async throws {
        try await Task.sleep(nanoseconds: ms * 1_000_000)
    }
}
