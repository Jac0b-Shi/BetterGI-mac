import CoreGraphics
import Foundation

/// Explicit cloud video geometry; browser chrome and page letterboxing never enter OCR.
enum CloudGameGeometry {
    static func fittedWindowSize(_ requested: CGSize, visibleSize: CGSize) -> CGSize {
        let width = min(requested.width, visibleSize.width * 0.9, visibleSize.height * 0.9 * 16 / 9)
        return CGSize(width: max(320, width), height: max(180, width * 9 / 16))
    }

    static func videoRect(_ values: [String: Any], in window: CGRect) -> CGRect? {
        guard let x = values["x"] as? Double, let y = values["y"] as? Double,
              let width = values["width"] as? Double, let height = values["height"] as? Double,
              [x, y, width, height].allSatisfy(\.isFinite), width >= 320, height >= 180 else { return nil }
        let local = CGRect(x: x, y: y, width: width, height: height)
        let content = CGRect(origin: .zero, size: window.size)
        guard content.contains(local) else { return nil }
        return local.offsetBy(dx: window.minX, dy: window.minY)
    }

    static func cropRect(imageSize: CGSize, window: WindowInfo) -> CGRect? {
        guard window.frame.width > 0, window.frame.height > 0,
              window.frame.contains(window.captureRect), !window.captureRect.isEmpty else { return nil }
        let scale = imageSize.width / window.frame.width
        guard abs(imageSize.height - window.frame.height * scale) <= 3 else { return nil }
        let rect = CGRect(x: (window.captureRect.minX - window.frame.minX) * scale,
                          y: (window.captureRect.minY - window.frame.minY) * scale,
                          width: window.captureRect.width * scale, height: window.captureRect.height * scale).integral
        return rect.intersection(CGRect(origin: .zero, size: imageSize))
    }

    static func normalizedPoint(_ point: CGPoint, in viewport: CGRect) throws -> CGPoint {
        guard point.x.isFinite, point.y.isFinite, !viewport.isEmpty,
              viewport.contains(point) else { throw CloudWebInputError.invalidCoordinates }
        return CGPoint(x: (point.x - viewport.minX) / viewport.width,
                       y: (point.y - viewport.minY) / viewport.height)
    }
}
