import CoreGraphics
@testable import MacGI
import Testing

@Suite("HUD overlay geometry")
struct HUDOverlayGeometryTests {
    @Test("Directions preserve the upstream 1920x1080 grid")
    func directionGrid() {
        #expect(HUDOverlayGeometry.directionFrame(in: CGSize(width: 1920, height: 1080)) ==
            CGRect(x: 43, y: 0, width: 250, height: 250))
        let frame = HUDOverlayGeometry.directionFrame(in: CGSize(width: 2560, height: 1440))
        #expect(abs(frame.minX - 57.333333333333336) < 0.000_001)
        #expect(abs(frame.width - 333.3333333333333) < 0.000_001)
        #expect(frame.minY == 0)
        #expect(abs(frame.height - 333.3333333333333) < 0.000_001)
    }

    @Test("UID cover preserves the upstream right-bottom rectangle")
    func uidCoverGrid() {
        #expect(HUDOverlayGeometry.uidCoverRect(in: CGSize(width: 1920, height: 1080)) ==
            CGRect(x: 1685, y: 1053, width: 178, height: 22))
        #expect(HUDOverlayGeometry.uidCoverRect(in: CGSize(width: 2560, height: 1440)) ==
            CGRect(
                x: 2246.6666666666665,
                y: 1404,
                width: 237.33333333333331,
                height: 29.333333333333332
            ))
    }

    @Test("Core pixel geometry maps to the HUD point grid")
    func coreGeometryScaling() {
        let source = CGRect(x: 1280, y: 720, width: 256, height: 144)
        #expect(HUDOverlayGeometry.displayRect(
            source, capturePixelSize: CGSize(width: 2560, height: 1440),
            in: CGSize(width: 1280, height: 720)) == CGRect(x: 640, y: 360, width: 128, height: 72))
        #expect(HUDOverlayGeometry.displayRect(
            CGRect(x: 960, y: 540, width: 192, height: 108),
            capturePixelSize: CGSize(width: 1920, height: 1080),
            in: CGSize(width: 1920, height: 1080)) == CGRect(x: 960, y: 540, width: 192, height: 108))
    }

    @Test("Mini-map overlay follows the upstream capture grid")
    func miniMapGrid() {
        #expect(HUDOverlayGeometry.miniMapFrame(in: CGSize(width: 1920, height: 1080)) ==
            CGRect(x: 62, y: 19, width: 212, height: 212))
        #expect(HUDOverlayGeometry.miniMapFrame(in: CGSize(width: 2560, height: 1440)) ==
            CGRect(
                x: 82.66666666666667,
                y: 25.333333333333332,
                width: 282.6666666666667,
                height: 282.6666666666667))
    }
}
