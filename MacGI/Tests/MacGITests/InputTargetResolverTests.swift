import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("Input target resolver")
struct InputTargetResolverTests {
    @Test("Recognition rect center maps into target window screen coordinates")
    func recognitionRectCenterMapsIntoTargetWindowScreenCoordinates() throws {
        let frame = makeFrame(windowFrame: CGRect(x: 100, y: 200, width: 960, height: 540))
        let point = try #require(InputTargetResolver.screenPoint(
            for: CGRect(x: 0.10, y: 0.20, width: 0.05, height: 0.10),
            in: frame
        ))

        #expect(abs(point.x - 220) < 0.001)
        #expect(abs(point.y - 335) < 0.001)
    }

    @Test("Partially visible recognition rect is clamped before resolving")
    func partiallyVisibleRecognitionRectIsClampedBeforeResolving() throws {
        let frame = makeFrame(windowFrame: CGRect(x: 100, y: 200, width: 960, height: 540))
        let point = try #require(InputTargetResolver.screenPoint(
            for: CGRect(x: -0.10, y: 0.90, width: 0.20, height: 0.30),
            in: frame
        ))

        #expect(abs(point.x - 148) < 0.001)
        #expect(abs(point.y - 713) < 0.001)
    }

    @Test("Invalid recognition rect does not produce a click point")
    func invalidRecognitionRectDoesNotProduceClickPoint() {
        let frame = makeFrame(windowFrame: CGRect(x: 100, y: 200, width: 960, height: 540))

        #expect(InputTargetResolver.screenPoint(for: .zero, in: frame) == nil)
        #expect(InputTargetResolver.screenPoint(
            for: CGRect(x: 1.2, y: 0.2, width: 0.1, height: 0.1),
            in: frame
        ) == nil)
        #expect(InputTargetResolver.screenPoint(
            for: CGRect(x: .nan, y: 0.2, width: 0.1, height: 0.1),
            in: frame
        ) == nil)
    }

    private func makeFrame(windowFrame: CGRect) -> CapturedFrame {
        let window = WindowInfo(
            id: 42,
            ownerPID: 10,
            ownerName: "wine",
            title: "原神",
            frame: windowFrame,
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1
        )
        return CapturedFrame(
            frameIndex: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            width: Int(windowFrame.width),
            height: Int(windowFrame.height),
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: Int(windowFrame.width) * 4,
            sourceWindow: window
        )
    }
}
