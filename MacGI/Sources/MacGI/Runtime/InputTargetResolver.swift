import CoreGraphics
import Foundation

enum InputTargetResolver {
    static func screenPoint(for normalizedRect: CGRect, in frame: CapturedFrame) -> CGPoint? {
        guard normalizedRect.isFinite,
              normalizedRect.width > 0,
              normalizedRect.height > 0 else {
            return nil
        }

        let visibleRect = normalizedRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard visibleRect.isFinite,
              !visibleRect.isNull,
              !visibleRect.isEmpty else {
            return nil
        }

        let captureRect = frame.sourceWindow.captureRect
        guard captureRect.isFinite,
              captureRect.width > 0,
              captureRect.height > 0 else {
            return nil
        }

        return CGPoint(
            x: captureRect.minX + visibleRect.midX * captureRect.width,
            y: captureRect.minY + visibleRect.midY * captureRect.height
        )
    }
}

private extension CGRect {
    var isFinite: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.width.isFinite
            && size.height.isFinite
    }
}
