import CoreGraphics
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

enum ScreenCaptureKitFrameError: LocalizedError {
    case syntheticWindow
    case windowNotFound(CGWindowID)
    case emptyImage(CGWindowID)
    case allBackendsFailed(primary: String, fallback: String)

    var errorDescription: String? {
        switch self {
        case .syntheticWindow:
            "ScreenCaptureKit cannot capture a synthetic window sentinel"
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
        guard !window.isSynthetic else {
            throw ScreenCaptureKitFrameError.syntheticWindow
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
        let fullImage = try await captureImage(contentFilter: filter, configuration: configuration)
        let image = try cropToGameClient(fullImage, window: window)

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
        let frame = fallbackWindow.frame.isEmpty ? filter.contentRect : fallbackWindow.frame
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((frame.width * scale).rounded()))
        configuration.height = max(1, Int((frame.height * scale).rounded()))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.preservesAspectRatio = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.queueDepth = 1
        return configuration
    }

    private func cropToGameClient(_ image: CGImage, window: WindowInfo) throws -> CGImage {
        let topInsetPoints = window.captureRect.minY - window.frame.minY
        guard topInsetPoints > 0 else { return image }
        let expectedWidth = Int(window.capturePixelSize.width.rounded())
        let expectedHeight = Int(window.capturePixelSize.height.rounded())
        guard abs(image.width - expectedWidth) <= 2,
              image.height >= expectedHeight,
              image.height - expectedHeight > 0 else {
            return image
        }
        let topInsetPixels = min(
            image.height - expectedHeight,
            Int((topInsetPoints * window.scaleFactor).rounded())
        )
        guard let cropped = image.cropping(to: CGRect(
            x: 0, y: topInsetPixels, width: expectedWidth, height: expectedHeight
        )) else {
            throw ScreenCaptureKitFrameError.emptyImage(window.id)
        }
        return cropped
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
