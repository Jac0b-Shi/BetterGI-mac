import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit
import VideoToolbox

enum ScreenCaptureKitFrameError: LocalizedError {
    case permissionRequired
    case syntheticWindow
    case windowNotFound(CGWindowID)
    case emptyImage(CGWindowID)
    case firstFrameTimedOut(CGWindowID)
    case staleStreamFrame(CGWindowID)
    case allBackendsFailed(primary: String, fallback: String)

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            "Screen Recording permission is required; grant it and reopen BetterGI"
        case .syntheticWindow:
            "ScreenCaptureKit cannot capture a synthetic window sentinel"
        case let .windowNotFound(id):
            "ScreenCaptureKit did not expose window id \(id)"
        case let .emptyImage(id):
            "ScreenCaptureKit returned an empty image for window id \(id)"
        case let .firstFrameTimedOut(id):
            "ScreenCaptureKit stream did not produce a frame for window id \(id)"
        case let .staleStreamFrame(id):
            "ScreenCaptureKit stream stopped updating window id \(id)"
        case let .allBackendsFailed(primary, fallback):
            "All capture backends failed. ScreenCaptureKit: \(primary). Quartz: \(fallback)"
        }
    }
}

private struct ScreenCaptureStreamFrame: @unchecked Sendable {
    let image: CGImage
    let timestamp: Date
    let frameIndex: UInt64
}

private final class ScreenCaptureStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var latestFrame: ScreenCaptureStreamFrame?
    private var frameIndex: UInt64 = 0

    func snapshot() -> ScreenCaptureStreamFrame? {
        lock.withLock { latestFrame }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer
        else {
            return
        }

        var image: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(
            pixelBuffer,
            options: nil,
            imageOut: &image
        ) == noErr, let image else {
            return
        }

        lock.withLock {
            frameIndex = (frameIndex + 1)
                % UInt64(CapturedFrame.maxFrameIndex(intervalMs: 16))
            latestFrame = ScreenCaptureStreamFrame(
                image: image,
                timestamp: Date(),
                frameIndex: frameIndex
            )
        }
    }
}

private final class ScreenCaptureStreamSession: @unchecked Sendable {
    let window: WindowInfo
    let stream: SCStream
    let output: ScreenCaptureStreamOutput

    init(window: WindowInfo, stream: SCStream, output: ScreenCaptureStreamOutput) {
        self.window = window
        self.stream = stream
        self.output = output
    }

    func stop() async {
        try? await stream.stopCapture()
    }
}

/// Reuses one ScreenCaptureKit stream and serves its latest frame to Core capture requests.
///
/// BetterGI asks for frames frequently. Recreating `SCShareableContent` and taking a one-shot
/// screenshot for every request adds enough latency to miss music notes and slows all realtime
/// triggers. The stream remains window-scoped and is replaced when the selected window or its
/// capture geometry changes.
@MainActor
final class ScreenCaptureKitFrameProvider {
    private var session: ScreenCaptureStreamSession?
    private let quartzFallback = QuartzWindowImageFrameProvider()
    private let sampleQueue = DispatchQueue(
        label: "bettergi.capture.frames",
        qos: .userInteractive
    )

    func stopCapture() async {
        guard let session else { return }
        self.session = nil
        await session.stop()
    }

    func captureWindow(_ window: WindowInfo) async throws -> CaptureImageFrame {
        guard !window.isSynthetic else {
            throw ScreenCaptureKitFrameError.syntheticWindow
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenCaptureKitFrameError.permissionRequired
        }

        do {
            let session = try await streamSession(for: window)
            let frame = try await latestFrame(from: session)
            let image = try cropToGameClient(frame.image, window: window)
            guard image.width > 0, image.height > 0 else {
                throw ScreenCaptureKitFrameError.emptyImage(window.id)
            }
            let metadata = CapturedFrame(
                frameIndex: frame.frameIndex,
                timestamp: frame.timestamp,
                width: image.width,
                height: image.height,
                scaleFactor: window.scaleFactor,
                pixelFormat: kCVPixelFormatType_32BGRA,
                bytesPerRow: image.bytesPerRow,
                sourceWindow: window
            )
            return CaptureImageFrame(
                metadata: metadata,
                cgImage: image,
                backendName: "ScreenCaptureKit Stream"
            )
        } catch {
            await stopCapture()
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

    private func streamSession(for window: WindowInfo) async throws
        -> ScreenCaptureStreamSession
    {
        if let session,
           session.window.id == window.id,
           session.window.capturePixelSize == window.capturePixelSize {
            return session
        }

        await stopCapture()

        let shareableContent = try await SCShareableContent.current
        guard let scWindow = shareableContent.windows.first(where: {
            $0.windowID == window.id
        }) else {
            throw ScreenCaptureKitFrameError.windowNotFound(window.id)
        }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let configuration = makeConfiguration(
            filter: filter,
            fallbackWindow: window
        )
        let output = ScreenCaptureStreamOutput()
        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: nil
        )
        try stream.addStreamOutput(
            output,
            type: .screen,
            sampleHandlerQueue: sampleQueue
        )
        try await stream.startCapture()
        let created = ScreenCaptureStreamSession(
            window: window,
            stream: stream,
            output: output
        )
        session = created
        return created
    }

    private func latestFrame(from session: ScreenCaptureStreamSession) async throws
        -> ScreenCaptureStreamFrame
    {
        for _ in 0..<200 {
            if let frame = session.output.snapshot() {
                guard Date().timeIntervalSince(frame.timestamp) < 0.5 else {
                    throw ScreenCaptureKitFrameError.staleStreamFrame(
                        session.window.id
                    )
                }
                return frame
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ScreenCaptureKitFrameError.firstFrameTimedOut(session.window.id)
    }

    private func makeConfiguration(
        filter: SCContentFilter,
        fallbackWindow: WindowInfo
    ) -> SCStreamConfiguration {
        let scale = CGFloat(
            filter.pointPixelScale > 0
                ? filter.pointPixelScale
                : Float(fallbackWindow.scaleFactor)
        )
        let frame = fallbackWindow.frame.isEmpty
            ? filter.contentRect
            : fallbackWindow.frame
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((frame.width * scale).rounded()))
        configuration.height = max(1, Int((frame.height * scale).rounded()))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.preservesAspectRatio = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.queueDepth = 3
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        return configuration
    }

    private func cropToGameClient(
        _ image: CGImage,
        window: WindowInfo
    ) throws -> CGImage {
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
            x: 0,
            y: topInsetPixels,
            width: expectedWidth,
            height: expectedHeight
        )) else {
            throw ScreenCaptureKitFrameError.emptyImage(window.id)
        }
        return cropped
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
