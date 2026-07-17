import CoreGraphics
import Foundation

/// Single captured frame — metadata only (not owning pixel bytes).
///
/// The pixel buffer is managed by the capture session (`CMSampleBuffer` / `IOSurface`).
/// `CapturedFrame` carries enough metadata for:
/// - ROI coordinate scaling (`width`, `height`, `scaleFactor`)
/// - OCR pixel-format selection (`pixelFormat`)
/// - Performance metrics (`timestamp`, `frameIndex`)
/// - HUD / overlay coordinate mapping (`sourceWindow.captureRect`)
///
/// Equivalent to upstream `CaptureContent` without the `ImageRegion` (Mat).
struct CapturedFrame: Identifiable, Sendable {

    /// Monotonically increasing frame counter.
    let frameIndex: UInt64

    /// Wall-clock capture time.
    let timestamp: Date

    // MARK: Dimensions

    let width: Int
    let height: Int
    let scaleFactor: CGFloat

    // MARK: Pixel format

    /// `OSType` four-char code, e.g. `kCVPixelFormatType_32BGRA`.
    let pixelFormat: OSType

    /// Bytes-per-row (stride). May be wider than `width * bytesPerPixel`.
    let bytesPerRow: Int

    // MARK: Source

    /// The window that produced this frame (snapshot at capture time).
    let sourceWindow: WindowInfo

    // MARK: Derived

    var sizeDescription: String { "\(width)×\(height)" }

    var pixelFormatName: String {
        switch pixelFormat {
        case 0x42475241: return "BGRA8888"   // kCVPixelFormatType_32BGRA
        case 0x34324142: return "ARGB8888"   // kCVPixelFormatType_32ARGB
        case 0x52323136: return "RGBA16"     // kCVPixelFormatType_64RGBAHalf
        default: return String(format: "0x%08X", pixelFormat)
        }
    }

    var id: UInt64 { frameIndex }
}

extension CapturedFrame {
    /// Maximum frame index before wrapping (mirrors upstream MaxFrameIndexSecond).
    static func maxFrameIndex(intervalMs: Int) -> UInt64 {
        UInt64(60 * 1000 / max(1, intervalMs))
    }

    /// Mock frame for UI / testing with no real capture session.
    static func mock(window: WindowInfo = .mock(), frameIndex: UInt64 = 0) -> CapturedFrame {
        CapturedFrame(
            frameIndex: frameIndex,
            timestamp: Date(),
            width: 2560,
            height: 1400,
            scaleFactor: window.scaleFactor,
            pixelFormat: 0x42475241,
            bytesPerRow: 2560 * 4,
            sourceWindow: window
        )
    }
}

// MARK: - CaptureImageFrame

/// A captured frame that carries actual pixel data — the input type for OCR.
///
/// `CapturedFrame` is metadata-only (safe to pass around cheaply).
/// `CaptureImageFrame` wraps metadata + pixel buffer for Vision / OCR processing.
///
/// In real ScreenCaptureKit usage the pixel buffer comes from `CMSampleBuffer`
/// or `IOSurface`. The concrete buffer type (`CGImage` / `CVPixelBuffer` / `Data`)
/// depends on the capture backend and is chosen at integration time.
struct CaptureImageFrame: @unchecked Sendable {

    /// Frame metadata (dimensions, format, timestamp, source window).
    let metadata: CapturedFrame

    /// Pixel data as a `CGImage`. Most OCR / Vision APIs accept CGImage natively.
    let cgImage: CGImage

    /// Name of the capture backend that produced this frame.
    let backendName: String

    init(metadata: CapturedFrame, cgImage: CGImage, backendName: String = "Unknown") {
        self.metadata = metadata
        self.cgImage = cgImage
        self.backendName = backendName
    }

    /// Convenience: normalized ROI → cropped CGImage sub-region.
    func cropped(to roi: NormalizedROI) -> CGImage? {
        let rect = roi.clampedPixelRect(for: metadata)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return cgImage.cropping(to: rect)
    }
}
