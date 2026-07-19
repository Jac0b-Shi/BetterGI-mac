import CoreGraphics
import CoreVideo
import Darwin
import Foundation

enum QuartzWindowImageFrameError: LocalizedError {
    case syntheticWindow
    case unavailableOnCurrentOS
    case emptyImage(CGWindowID)

    var errorDescription: String? {
        switch self {
        case .syntheticWindow:
            "Quartz window capture cannot capture a synthetic window sentinel"
        case .unavailableOnCurrentOS:
            "Quartz window capture is unavailable on this macOS version"
        case let .emptyImage(id):
            "Quartz window capture returned an empty image for window id \(id)"
        }
    }
}

/// Compatibility capture backend for the macOS port.
///
/// BetterGI exposes several Windows capture backends through `GameCaptureFactory`.
/// ScreenCaptureKit is the primary macOS backend, while this Quartz path is a
/// lightweight fallback matching the inventory item for `CGWindowListCreateImage`.
@MainActor
final class QuartzWindowImageFrameProvider {
    private var frameIndex: UInt64 = 0

    func captureWindow(_ window: WindowInfo) throws -> CaptureImageFrame {
        guard !window.isSynthetic else {
            throw QuartzWindowImageFrameError.syntheticWindow
        }

        let options: CGWindowImageOption = [.boundsIgnoreFraming, .nominalResolution]
        let createImage = try Self.loadCGWindowListCreateImage()
        guard let imageRef = createImage(
            .null,
            CGWindowListOption.optionIncludingWindow.rawValue,
            window.id,
            options.rawValue
        ) else {
            throw QuartzWindowImageFrameError.emptyImage(window.id)
        }

        let image = imageRef.takeRetainedValue()
        guard image.width > 0, image.height > 0 else {
            throw QuartzWindowImageFrameError.emptyImage(window.id)
        }

        frameIndex = (frameIndex + 1) % UInt64(CapturedFrame.maxFrameIndex(intervalMs: 50))
        let captureRect = window.captureRect
        let pointWidth = max(1, captureRect.width)
        let scale = max(1, CGFloat(image.width) / pointWidth)
        let metadata = CapturedFrame(
            frameIndex: frameIndex,
            timestamp: Date(),
            width: image.width,
            height: image.height,
            scaleFactor: scale,
            pixelFormat: kCVPixelFormatType_32BGRA,
            bytesPerRow: image.bytesPerRow,
            sourceWindow: window
        )
        return CaptureImageFrame(
            metadata: metadata,
            cgImage: image,
            backendName: "CGWindowListCreateImage"
        )
    }

    private typealias CGWindowListCreateImageFunction = @convention(c) (
        CGRect,
        UInt32,
        CGWindowID,
        UInt32
    ) -> Unmanaged<CGImage>?

    private static func loadCGWindowListCreateImage() throws -> CGWindowListCreateImageFunction {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else {
            throw QuartzWindowImageFrameError.unavailableOnCurrentOS
        }
        return unsafeBitCast(symbol, to: CGWindowListCreateImageFunction.self)
    }
}
