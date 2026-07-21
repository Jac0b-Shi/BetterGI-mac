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
}
