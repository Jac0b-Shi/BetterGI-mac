import CoreGraphics
import Foundation

struct YOLOLabel: Identifiable, Equatable, Sendable {
    let index: Int
    let name: String

    var id: Int { index }
}

struct YOLORawDetection: Equatable, Sendable {
    let classIndex: Int
    let confidence: Float
    let inputRect: CGRect
}

struct YOLODetection: Identifiable, Equatable, Sendable {
    let label: YOLOLabel
    let confidence: Float
    let boundingBox: CGRect

    var id: String {
        "\(label.index)-\(boundingBox)-\(confidence)"
    }
}

struct YOLOInputGeometry: Equatable, Sendable {
    let originalSize: CGSize
    let inputSize: CGSize
    let scale: Double
    let padding: CGSize

    static func letterboxed(originalSize: CGSize, inputSize: CGSize) -> YOLOInputGeometry? {
        guard originalSize.isValidPixelSize,
              inputSize.isValidPixelSize else {
            return nil
        }

        let scale = min(
            Double(inputSize.width / originalSize.width),
            Double(inputSize.height / originalSize.height)
        )
        guard scale.isFinite, scale > 0 else { return nil }

        let resizedWidth = Double(originalSize.width) * scale
        let resizedHeight = Double(originalSize.height) * scale
        return YOLOInputGeometry(
            originalSize: originalSize,
            inputSize: inputSize,
            scale: scale,
            padding: CGSize(
                width: CGFloat((Double(inputSize.width) - resizedWidth) / 2.0),
                height: CGFloat((Double(inputSize.height) - resizedHeight) / 2.0)
            )
        )
    }

    func originalRect(from inputRect: CGRect) -> CGRect? {
        guard inputRect.isFiniteRect,
              inputRect.width > 0,
              inputRect.height > 0,
              scale.isFinite,
              scale > 0 else {
            return nil
        }

        let cgScale = CGFloat(scale)
        let rect = CGRect(
            x: (inputRect.minX - padding.width) / cgScale,
            y: (inputRect.minY - padding.height) / cgScale,
            width: inputRect.width / cgScale,
            height: inputRect.height / cgScale
        )
        let bounds = CGRect(origin: .zero, size: originalSize)
        let clipped = rect.intersection(bounds).integral
        guard clipped.isFiniteRect,
              !clipped.isNull,
              clipped.width > 0,
              clipped.height > 0 else {
            return nil
        }
        return clipped
    }
}

enum YOLODetectionPostProcessor {
    static func detections(
        from rawDetections: [YOLORawDetection],
        labels: [YOLOLabel],
        geometry: YOLOInputGeometry,
        confidenceThreshold: Float = 0.25,
        iouThreshold: Double = 0.45
    ) -> [YOLODetection] {
        let labelMap = Dictionary(uniqueKeysWithValues: labels.map { ($0.index, $0) })
        let candidates = rawDetections.compactMap { raw -> YOLODetection? in
            guard raw.confidence >= confidenceThreshold,
                  let label = labelMap[raw.classIndex],
                  let originalRect = geometry.originalRect(from: raw.inputRect) else {
                return nil
            }
            return YOLODetection(
                label: label,
                confidence: raw.confidence,
                boundingBox: originalRect
            )
        }

        return nonMaximumSuppression(candidates, iouThreshold: iouThreshold)
    }

    static func groupedRectsByLabel(_ detections: [YOLODetection]) -> [String: [CGRect]] {
        detections.reduce(into: [String: [CGRect]]()) { partial, detection in
            partial[detection.label.name, default: []].append(detection.boundingBox)
        }
    }

    static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        guard lhs.isFiniteRect,
              rhs.isFiniteRect,
              lhs.width > 0,
              lhs.height > 0,
              rhs.width > 0,
              rhs.height > 0 else {
            return 0
        }

        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull,
              intersection.width > 0,
              intersection.height > 0 else {
            return 0
        }

        let intersectionArea = Double(intersection.width * intersection.height)
        let unionArea = Double(lhs.width * lhs.height + rhs.width * rhs.height) - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private static func nonMaximumSuppression(
        _ detections: [YOLODetection],
        iouThreshold: Double
    ) -> [YOLODetection] {
        let sorted = detections.sorted {
            if $0.confidence == $1.confidence {
                return $0.label.index < $1.label.index
            }
            return $0.confidence > $1.confidence
        }
        var kept: [YOLODetection] = []

        for detection in sorted {
            let overlapsKeptSameClass = kept.contains { keptDetection in
                keptDetection.label.index == detection.label.index
                    && intersectionOverUnion(keptDetection.boundingBox, detection.boundingBox) > iouThreshold
            }
            if !overlapsKeptSameClass {
                kept.append(detection)
            }
        }

        return kept.sorted {
            if $0.label.name == $1.label.name {
                if abs($0.boundingBox.minY - $1.boundingBox.minY) < 1 {
                    return $0.boundingBox.minX < $1.boundingBox.minX
                }
                return $0.boundingBox.minY < $1.boundingBox.minY
            }
            return $0.label.name < $1.label.name
        }
    }
}

private extension CGSize {
    var isValidPixelSize: Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
    }
}

private extension CGRect {
    var isFiniteRect: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.width.isFinite
            && size.height.isFinite
    }
}
