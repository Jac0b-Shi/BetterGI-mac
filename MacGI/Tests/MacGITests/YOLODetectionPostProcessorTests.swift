import CoreGraphics
@testable import MacGI
import Testing

@Suite("BetterGI YOLO post-processing")
struct YOLODetectionPostProcessorTests {
    @Test("Letterbox geometry maps model input boxes back to original frame coordinates")
    func letterboxGeometryMapsInputBoxesBackToOriginalFrameCoordinates() throws {
        let geometry = try #require(YOLOInputGeometry.letterboxed(
            originalSize: CGSize(width: 1920, height: 1080),
            inputSize: CGSize(width: 640, height: 640)
        ))

        #expect(abs(geometry.scale - (1.0 / 3.0)) < 0.0001)
        #expect(geometry.padding.width == 0)
        #expect(geometry.padding.height == 140)

        let rect = try #require(geometry.originalRect(from: CGRect(x: 320, y: 320, width: 64, height: 32)))
        #expect(rect == CGRect(x: 960, y: 540, width: 192, height: 96))
    }

    @Test("NMS suppresses overlapping boxes only within the same label")
    func nmsSuppressesOverlappingBoxesOnlyWithinSameLabel() throws {
        let geometry = try #require(YOLOInputGeometry.letterboxed(
            originalSize: CGSize(width: 640, height: 640),
            inputSize: CGSize(width: 640, height: 640)
        ))
        let labels = [
            YOLOLabel(index: 0, name: "fish"),
            YOLOLabel(index: 1, name: "target")
        ]
        let detections = YOLODetectionPostProcessor.detections(
            from: [
                YOLORawDetection(classIndex: 0, confidence: 0.95, inputRect: CGRect(x: 100, y: 100, width: 100, height: 100)),
                YOLORawDetection(classIndex: 0, confidence: 0.90, inputRect: CGRect(x: 110, y: 110, width: 100, height: 100)),
                YOLORawDetection(classIndex: 1, confidence: 0.85, inputRect: CGRect(x: 115, y: 115, width: 100, height: 100)),
                YOLORawDetection(classIndex: 0, confidence: 0.10, inputRect: CGRect(x: 300, y: 300, width: 50, height: 50))
            ],
            labels: labels,
            geometry: geometry,
            confidenceThreshold: 0.25,
            iouThreshold: 0.45
        )

        #expect(detections.count == 2)
        #expect(detections.map(\.label.name).sorted() == ["fish", "target"])
        #expect(detections.first { $0.label.name == "fish" }?.confidence == 0.95)
        #expect(detections.first { $0.label.name == "target" }?.confidence == 0.85)
    }

    @Test("Detections are grouped like upstream BgiYoloPredictor Detect output")
    func detectionsAreGroupedLikeUpstreamBgiYoloPredictorDetectOutput() throws {
        let geometry = try #require(YOLOInputGeometry.letterboxed(
            originalSize: CGSize(width: 640, height: 640),
            inputSize: CGSize(width: 640, height: 640)
        ))
        let detections = YOLODetectionPostProcessor.detections(
            from: [
                YOLORawDetection(classIndex: 0, confidence: 0.8, inputRect: CGRect(x: 10, y: 20, width: 30, height: 40)),
                YOLORawDetection(classIndex: 0, confidence: 0.7, inputRect: CGRect(x: 100, y: 120, width: 30, height: 40)),
                YOLORawDetection(classIndex: 1, confidence: 0.9, inputRect: CGRect(x: 200, y: 220, width: 30, height: 40))
            ],
            labels: [
                YOLOLabel(index: 0, name: "item"),
                YOLOLabel(index: 1, name: "enemy")
            ],
            geometry: geometry
        )

        let grouped = YOLODetectionPostProcessor.groupedRectsByLabel(detections)
        #expect(grouped["item"]?.count == 2)
        #expect(grouped["enemy"] == [CGRect(x: 200, y: 220, width: 30, height: 40)])
    }

    @Test("Out-of-bounds detections are clamped to the original image")
    func outOfBoundsDetectionsAreClampedToOriginalImage() throws {
        let geometry = try #require(YOLOInputGeometry.letterboxed(
            originalSize: CGSize(width: 320, height: 240),
            inputSize: CGSize(width: 320, height: 320)
        ))
        let rect = try #require(geometry.originalRect(from: CGRect(x: 300, y: 250, width: 80, height: 80)))

        #expect(rect == CGRect(x: 300, y: 210, width: 20, height: 30))
    }
}
