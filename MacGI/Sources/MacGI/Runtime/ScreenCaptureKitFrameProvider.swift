import CoreGraphics
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

enum ScreenCaptureKitFrameError: LocalizedError {
    case mockWindow
    case windowNotFound(CGWindowID)
    case emptyImage(CGWindowID)
    case allBackendsFailed(primary: String, fallback: String)

    var errorDescription: String? {
        switch self {
        case .mockWindow:
            "ScreenCaptureKit cannot capture a mock window"
        case let .windowNotFound(id):
            "ScreenCaptureKit did not expose window id \(id)"
        case let .emptyImage(id):
            "ScreenCaptureKit returned an empty image for window id \(id)"
        case let .allBackendsFailed(primary, fallback):
            "All capture backends failed. ScreenCaptureKit: \(primary). Quartz: \(fallback)"
        }
    }
}

/// One-shot capture facade for the P0 capture path.
///
/// BetterGI's Windows dispatcher calls `GameCapture.Capture()` on every tick.
/// The macOS port starts with a one-frame API, using ScreenCaptureKit first and
/// falling back to Quartz window capture when SCK cannot expose the window.
@MainActor
final class ScreenCaptureKitFrameProvider {
    private var frameIndex: UInt64 = 0
    private let quartzFallback = QuartzWindowImageFrameProvider()

    func captureWindow(_ window: WindowInfo) async throws -> CaptureImageFrame {
        guard !window.isMock else {
            throw ScreenCaptureKitFrameError.mockWindow
        }

        do {
            return try await captureWindowWithScreenCaptureKit(window)
        } catch {
            do {
                return try quartzFallback.captureWindow(window)
            } catch let fallbackError {
                throw ScreenCaptureKitFrameError.allBackendsFailed(
                    primary: error.localizedDescription,
                    fallback: fallbackError.localizedDescription
                )
            }
        }
    }

    private func captureWindowWithScreenCaptureKit(_ window: WindowInfo) async throws -> CaptureImageFrame {
        let shareableContent = try await SCShareableContent.current
        guard let scWindow = shareableContent.windows.first(where: { $0.windowID == window.id }) else {
            throw ScreenCaptureKitFrameError.windowNotFound(window.id)
        }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let configuration = makeConfiguration(filter: filter, fallbackWindow: window)
        let image = try await captureImage(contentFilter: filter, configuration: configuration)

        guard image.width > 0, image.height > 0 else {
            throw ScreenCaptureKitFrameError.emptyImage(window.id)
        }

        frameIndex = (frameIndex + 1) % UInt64(CapturedFrame.maxFrameIndex(intervalMs: 50))
        let metadata = CapturedFrame(
            frameIndex: frameIndex,
            timestamp: Date(),
            width: image.width,
            height: image.height,
            scaleFactor: CGFloat(filter.pointPixelScale),
            pixelFormat: kCVPixelFormatType_32BGRA,
            bytesPerRow: image.bytesPerRow,
            sourceWindow: window
        )
        return CaptureImageFrame(
            metadata: metadata,
            cgImage: image,
            backendName: "ScreenCaptureKit"
        )
    }

    private func makeConfiguration(filter: SCContentFilter, fallbackWindow: WindowInfo) -> SCStreamConfiguration {
        let scale = CGFloat(filter.pointPixelScale > 0 ? filter.pointPixelScale : Float(fallbackWindow.scaleFactor))
        let contentRect = fallbackWindow.captureRect.isEmpty ? filter.contentRect : fallbackWindow.captureRect
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((contentRect.width * scale).rounded()))
        configuration.height = max(1, Int((contentRect.height * scale).rounded()))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.preservesAspectRatio = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.queueDepth = 1
        return configuration
    }

    private func captureImage(contentFilter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: ScreenCaptureKitFrameError.emptyImage(0))
                }
            }
        }
    }
}
