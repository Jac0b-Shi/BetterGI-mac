import CoreGraphics
import Foundation

// MARK: - AutoMusicGame (千音雅集)

/// Upstream ref: `AutoMusicGameTask.cs` (251 lines)
/// Detects falling music notes by pixel color at fixed lane positions (1080p),
/// presses corresponding key when white note reaches target Y.
///
/// Lane positions (1080p):
///   A: (417,921)  S: (628,921)  D: (844,921)
///   J: (1061,921) K: (1277,921) L: (1493,921)
///
/// macOS equivalent: uses CGImage pixel sampling from captured frames
/// instead of upstream Win32 GetPixel.
final class BGIAutoMusicGameService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult

    private let captureFrameProvider: CaptureFrameProvider
    private let inputHandler: InputHandler

    /// 1080p lane positions → macOS key binding
    private static let lanes: [(x: Int, y: Int, key: KeyCode)] = [
        (417, 921, .a), (628, 921, .s), (844, 921, .d),
        (1061, 921, .j), (1277, 921, .k), (1493, 921, .l),
    ]

    init(inputHandler: @escaping InputHandler, captureFrameProvider: @escaping CaptureFrameProvider) {
        self.inputHandler = inputHandler
        self.captureFrameProvider = captureFrameProvider
    }

    /// Run auto music game — monitors lanes and presses keys when notes reach target.
    func start() async throws {
        while !Task.isCancelled {
            let frame = try await captureFrameProvider()
            let scale = Double(frame.metadata.width) / 1920.0

            for lane in Self.lanes {
                let px = Int(Double(lane.x) * scale)
                let py = Int(Double(lane.y) * scale)
                let color = pixelColor(frame.cgImage, atX: px, y: py)

                // Upstream: B < 220 means note is present (white/light pixel)
                if color.b < 220 {
                    await keyDown(lane.key)
                    // Wait for note to pass (B >= 220 or note edge)
                    for _ in 0..<100 { // 100 retries = 500ms max
                        try await Task.sleep(nanoseconds: 5_000_000)
                        let checkFrame = try await captureFrameProvider()
                        let cx = Int(Double(lane.x) * scale)
                        let cy = Int(Double(lane.y) * scale)
                        let cc = pixelColor(checkFrame.cgImage, atX: cx, y: cy)
                        if cc.b >= 220 { break }
                    }
                    await keyUp(lane.key)
                }
            }
            try await Task.sleep(nanoseconds: 5_000_000) // 5ms tick
        }
    }

    private func keyDown(_ key: KeyCode) async { _ = await inputHandler(.keyDown(key: key)) }
    private func keyUp(_ key: KeyCode) async { _ = await inputHandler(.keyUp(key: key)) }
}

// MARK: - AutoWood (自动伐木)

/// Upstream ref: `AutoWoodTask.cs` (564 lines)
/// Uses YOLO BgiTree detection to find trees, moves toward them, chops (attacks),
/// OCRs wood count to track progress.
final class BGIAutoWoodService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult

    private let captureFrameProvider: CaptureFrameProvider
    private let inputHandler: InputHandler
    private let keyBindings: KeyBindingsConfig
    private let treePipeline: BGIYOLODetectionPipeline?

    init(
        inputHandler: @escaping InputHandler,
        captureFrameProvider: @escaping CaptureFrameProvider,
        keyBindings: KeyBindingsConfig = .bgiDefault
    ) {
        self.inputHandler = inputHandler
        self.captureFrameProvider = captureFrameProvider
        self.keyBindings = keyBindings
        self.treePipeline = {
            guard let runtime = try? BGIYOLORuntime(),
                  let session = try? runtime.makeSession(model: .bgiTree) else { return nil }
            return BGIYOLODetectionPipeline(session: session, labels: BGIOnnxModel.bgiTree.defaultYOLOLabels)
        }()
    }

    /// Main wood harvesting loop — detect trees, move to nearest, chop.
    func harvest(maxCycles: Int = 50) async {
        for _ in 0..<maxCycles {
            guard !Task.isCancelled else { break }
            do {
                let frame = try await captureFrameProvider()

                // Detect trees via YOLO
                var detectedTrees: [YOLODetection] = []
                if let pipeline = treePipeline,
                   let result = try? pipeline.detect(image: frame.cgImage) {
                    detectedTrees = result.detections
                }

                if detectedTrees.isEmpty {
                    // No trees visible → rotate camera to find more
                    await rotateCamera()
                    continue
                }

                // Find nearest tree (biggest bounding box)
                guard let nearest = detectedTrees.max(by: {
                    $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
                }) else { continue }

                // Click tree center to target
                let cx = nearest.boundingBox.midX
                let cy = nearest.boundingBox.midY
                let w = Double(frame.metadata.width)
                let h = Double(frame.metadata.height)
                _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: cx * w, y: cy * h)))
                try? await Task.sleep(nanoseconds: 500_000_000)

                // Walk toward tree
                await holdForward(seconds: 2.0)

                // Chop (attack) until tree disappears
                for _ in 0..<10 {
                    await attack()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    let checkFrame = try? await captureFrameProvider()
                    if let cf = checkFrame, let pipe = treePipeline,
                       let result = try? pipe.detect(image: cf.cgImage),
                       result.detections.isEmpty { break }
                }
            } catch { break }
        }
    }

    private func attack() async {
        guard let ia = keyBindings.inputAction(for: .normalAttack, type: .keyPress) else { return }
        _ = await inputHandler(ia)
    }

    private func holdForward(seconds: Double) async {
        guard let down = keyBindings.inputAction(for: .moveForward, type: .keyDown) else { return }
        _ = await inputHandler(down)
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        if let up = keyBindings.inputAction(for: .moveForward, type: .keyUp) { _ = await inputHandler(up) }
    }

    private func rotateCamera() async {
        // Rotate camera 90° right to look for trees in new direction
        _ = await inputHandler(.mouseButtonDown(button: .right, at: CGPoint(x: 500, y: 500)))
        try? await Task.sleep(nanoseconds: 300_000_000)
        _ = await inputHandler(.mouseButtonUp(button: .right, at: CGPoint(x: 700, y: 500)))
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}

// MARK: - Pixel Helper

private func pixelColor(_ image: CGImage, atX x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
    guard x >= 0, y >= 0, x < image.width, y < image.height else { return (0,0,0) }
    guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return (0,0,0) }
    let bpp = image.bitsPerPixel / 8
    let offset = (y * image.bytesPerRow) + (x * bpp)
    return (Int(ptr[offset]), Int(ptr[offset+1]), Int(ptr[offset+2]))
}
