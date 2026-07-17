import CoreGraphics
import Foundation

// MARK: - Preprocessor

/// YOLO image preprocessing: letterbox + normalize + HWC→CHW.
/// Produces the float tensor expected by BGIYOLOOonnxSession.
struct BGIYOLOPreprocessor {
    let inputSize: CGSize

    init(inputSize: CGSize = CGSize(width: 640, height: 640)) {
        self.inputSize = inputSize
    }

    /// Preprocess a CGImage into a YOLO-compatible float tensor [1, 3, H, W].
    func preprocess(_ image: CGImage) -> [Float]? {
        let w = inputSize.width
        let h = inputSize.height
        let size = Int(w) * Int(h)
        guard size > 0 else { return nil }

        // 1. Create a bitmap context at the target size (letterboxed)
        guard let ctx = CGContext(
            data: nil,
            width: Int(w),
            height: Int(h),
            bitsPerComponent: 8,
            bytesPerRow: Int(w) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
        ) else { return nil }

        // Letterbox: compute scale and offset to center the image
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let scale = min(w / imgW, h / imgH)
        let scaledW = imgW * scale
        let scaledH = imgH * scale
        let offsetX = (w - scaledW) / 2
        let offsetY = (h - scaledH) / 2

        ctx.setFillColor(CGColor(gray: 0.447, alpha: 1)) // 114/255 — YOLO default padding
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: offsetX, y: offsetY, width: scaledW, height: scaledH))

        guard let resized = ctx.makeImage() else { return nil }
        guard let data = resized.dataProvider?.data,
              let pixels = CFDataGetBytePtr(data) else { return nil }

        // 2. Extract RGB channels, normalize to [0,1], HWC→CHW
        let channels = 3
        let totalPixels = Int(w) * Int(h)
        var tensor = [Float](repeating: 0, count: channels * totalPixels)
        for i in 0..<totalPixels {
            let srcOff = i * 4 // BGRA or RGBA
            let r = Float(pixels[srcOff]) / 255.0
            let g = Float(pixels[srcOff + 1]) / 255.0
            let b = Float(pixels[srcOff + 2]) / 255.0
            tensor[i] = r
            tensor[totalPixels + i] = g
            tensor[2 * totalPixels + i] = b
        }
        return tensor
    }
}

// MARK: - Detection Pipeline

struct BGIYOLODetectionResult: Sendable {
    let detections: [YOLODetection]
    let costMs: Double
}

/// Convenience wrapper: preprocess → ONNX inference → post-process.
final class BGIYOLODetectionPipeline {
    private let session: BGIYOLOOonnxSession
    let labels: [YOLOLabel]

    init(session: BGIYOLOOonnxSession, labels: [YOLOLabel]) {
        self.session = session
        self.labels = labels
    }

    func detect(image: CGImage) throws -> BGIYOLODetectionResult {
        let preprocessor = BGIYOLOPreprocessor(inputSize: session.inputSize)
        guard let tensor = preprocessor.preprocess(image) else {
            throw BGIYOLOError.inferenceFailed("preprocessing failed")
        }
        let start = Date()
        let rawOutput = try session.detect(tensor: tensor, shape: [1, 3, Int(session.inputSize.height), Int(session.inputSize.width)])
        let costMs = Date().timeIntervalSince(start) * 1000

        // Parse raw output into detections
        // YOLO output format: [1, N, 85] or [1, 25200, N] depending on model
        // For BgiFish (YOLOv8): flat array, each detection is class_count + 4 bbox coords + 1 confidence
        let classCount = labels.count
        let raw = YOLORawDecoder.decode(rawOutput, classCount: classCount, inputSize: session.inputSize)
        let geometry = YOLOInputGeometry.letterboxed(
            originalSize: CGSize(width: image.width, height: image.height),
            inputSize: session.inputSize
        )
        if let geo = geometry {
            let detections = YOLODetectionPostProcessor.detections(
                from: raw,
                labels: labels,
                geometry: geo,
                confidenceThreshold: 0.25
            )
            return BGIYOLODetectionResult(detections: detections, costMs: costMs)
        }
        return BGIYOLODetectionResult(detections: [], costMs: costMs)
    }
}

/// Decode raw float output into YOLORawDetection candidates.
enum YOLORawDecoder {
    /// YOLOv8/v5 flat output: each row = [cx, cy, w, h, obj_conf, class_probs...]
    static func decode(_ output: [Float], classCount: Int, inputSize: CGSize) -> [YOLORawDetection] {
        let step = 4 + 1 + classCount // cx, cy, w, h, obj_conf, class_probs
        guard step > 0, output.count >= step else { return [] }
        let count = output.count / step
        var detections: [YOLORawDetection] = []
        let w = Float(inputSize.width)
        let h = Float(inputSize.height)
        for i in 0..<count {
            let base = i * step
            let objConf = output[base + 4]
            guard objConf > 0.25 else { continue }
            var maxClassConf: Float = 0
            var maxClassIdx = 0
            for c in 0..<classCount {
                let conf = output[base + 5 + c]
                if conf > maxClassConf {
                    maxClassConf = conf
                    maxClassIdx = c
                }
            }
            let score = objConf * maxClassConf
            guard score > 0.25 else { continue }
            let cx = output[base] / w
            let cy = output[base + 1] / h
            let bw = output[base + 2] / w
            let bh = output[base + 3] / h
            let rect = CGRect(
                x: CGFloat(cx - bw / 2),
                y: CGFloat(cy - bh / 2),
                width: CGFloat(bw),
                height: CGFloat(bh)
            )
            detections.append(YOLORawDetection(
                classIndex: maxClassIdx,
                confidence: score,
                inputRect: rect
            ))
        }
        return detections
    }
}

// MARK: - YOLO Model Labels

extension BGIOnnxModel {
    /// Default YOLO labels matching upstream BGI model classes.
    var defaultYOLOLabels: [YOLOLabel] {
        switch name {
        case "BgiFish":
            return [
                YOLOLabel(index: 0, name: "fish"),
            ]
        case "BgiTree":
            return [
                YOLOLabel(index: 0, name: "tree"),
            ]
        case "BgiMine":
            return [
                YOLOLabel(index: 0, name: "mine"),
            ]
        case "BgiWorld":
            return [
                YOLOLabel(index: 0, name: "monster"),
            ]
        default:
            return []
        }
    }
}
