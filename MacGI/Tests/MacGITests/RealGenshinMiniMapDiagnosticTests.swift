import CoreGraphics
import Foundation
@testable import MacGI
import Testing

/// Real-world mini-map diagnostic test.
///
/// Requires a live Genshin Impact window.  Gate with:
///   BETTERGI_RUN_REAL_GENSHIN_TESTS=1 swift test --filter "RealGenshinMiniMapDiagnostics"
@Suite("Real Genshin mini-map diagnostics", .enabled(if: ProcessInfo.processInfo.environment["BETTERGI_RUN_REAL_GENSHIN_TESTS"] == "1"))
struct RealGenshinMiniMapDiagnosticTests {

    /// Change this to your preferred output directory, or leave as a temp dir.
    static let outputBase = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("bettergi-minimap-diag", isDirectory: true)

    // MARK: - Part 1: Window capture verification

    @Test("Capture 3 frames and verify window metadata", arguments: [3])
    func verifyWindowCapture(frameCount: Int) async throws {
        let provider = ScreenCaptureKitFrameProvider()
        // Choose the first real Genshin window.
        let windows = QuartzWindowEnumerator.enumerateApplicationWindows()
            .filter { !$0.isMock && !$0.title.isEmpty }
        let window = try #require(windows.first(where: { $0.ownerName.contains("YAAGL") || $0.ownerName.contains("wine") || $0.title.contains("原神") }),
                                 "No Genshin window found")

        var frames: [CapturedFrame] = []
        for _ in 0..<frameCount {
            let imageFrame = try await provider.captureWindow(window)
            let frame = imageFrame.metadata
            #expect(frame.width > 0)
            #expect(frame.height > 0)
            #expect(frame.sourceWindow.id == window.id)
            frames.append(frame)
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        // Verify frame index changes
        let indices = Set(frames.map(\.frameIndex))
        #expect(indices.count == frameCount, "Frame index must increment")

        // Print window info
        let f = frames[0]
        print("""
        === Window Info ===
        Owner: \(f.sourceWindow.ownerName)
        Title: \(f.sourceWindow.title)
        WindowID: \(f.sourceWindow.id)
        Frame: \(f.sourceWindow.frame)
        CaptureRect: \(f.sourceWindow.captureRect)
        ScaleFactor: \(f.scaleFactor)
        ImageSize: \(f.width)x\(f.height)
        PixelFormat: \(f.pixelFormatName)
        ===================
        """)
    }

    // MARK: - Part 2-6: Full diagnostic pipeline

    @Test("Run full diagnostic pipeline against live Genshin window", arguments: [1])
    func fullDiagnosticPipeline(frames: Int) async throws {
        let provider = ScreenCaptureKitFrameProvider()
        let windows = QuartzWindowEnumerator.enumerateApplicationWindows()
            .filter { !$0.isMock && !$0.title.isEmpty }
        let window = try #require(windows.first(where: { $0.ownerName.contains("YAAGL") || $0.ownerName.contains("wine") || $0.title.contains("原神") }),
                                 "No Genshin window found")

        let frame = try await provider.captureWindow(window)
        let outputDir = Self.outputBase.appendingPathComponent("pipeline-\(ISO8601DateFormatter().string(from: Date()))")
        let result = try BGIRealWorldMiniMapDiagnostics.run(frame: frame, outputDir: outputDir)

        print("""
        === Diagnostic Pipeline Result ===
        Used Paimon: \(result.usedPaimonLocator)
        Used Fallback: \(result.usedFallback)
        Paimon Confidence: \(result.paimonConfidence ?? -1)
        Layer: \(result.layerId) (\(result.layerName ?? "?"))
        Orientation: \(result.orientationDegrees)° (conf: \(result.orientationConfidence))
        Rough: (\(result.roughPoint[0]), \(result.roughPoint[1])) conf=\(result.roughConfidence)
        Exact: (\(result.exactPoint[0]), \(result.exactPoint[1])) conf=\(result.exactConfidence)
        World: (\(result.worldPoint[0]), \(result.worldPoint[1]))
        Timing: total=\(result.timingsMs.totalMs)ms paimon=\(result.timingsMs.paimonMs) extract=\(result.timingsMs.extractMs) preprocess=\(result.timingsMs.preprocessMs) orient=\(result.timingsMs.orientMs) layer=\(result.timingsMs.layerMs) rough=\(result.timingsMs.roughMs) exact=\(result.timingsMs.exactMs)
        Output: \(outputDir.path)
        ===============================
        """)
    }

    // MARK: - Part 7: Continuous stability

    @Test("Run 10-frame stability test", arguments: [10])
    func stabilityTest(frameCount: Int) async throws {
        let provider = ScreenCaptureKitFrameProvider()
        let windows = QuartzWindowEnumerator.enumerateApplicationWindows()
            .filter { !$0.isMock && !$0.title.isEmpty }
        let window = try #require(windows.first(where: { $0.ownerName.contains("YAAGL") || $0.ownerName.contains("wine") || $0.title.contains("原神") }),
                                 "No Genshin window found")

        let store = LatestFrameStore()
        // Feed frames continuously
        let feedTask = Task {
            for _ in 0..<(frameCount + 5) {
                if Task.isCancelled { break }
                if let f = try? await provider.captureWindow(window) {
                    store.update(f)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        try await Task.sleep(nanoseconds: 500_000_000)

        let outputDir = Self.outputBase.appendingPathComponent("stability-\(ISO8601DateFormatter().string(from: Date()))")
        let results = try BGIRealWorldMiniMapDiagnostics.runSequence(
            count: frameCount, intervalMs: 150,
            frameStore: store, outputDir: outputDir
        )
        feedTask.cancel()

        // Statistics
        let xs = results.map { $0.worldPoint[0] }
        let ys = results.map { $0.worldPoint[1] }
        let os = results.map { $0.orientationDegrees }
        let ids = results.map { $0.layerId }
        let times = results.map { $0.timingsMs.totalMs }
        let successes = results.count

        let avgX = xs.reduce(0,+) / Double(successes)
        let avgY = ys.reduce(0,+) / Double(successes)
        let stdX = sqrt(xs.map { pow($0 - avgX, 2) }.reduce(0,+) / Double(successes))
        let stdY = sqrt(ys.map { pow($0 - avgY, 2) }.reduce(0,+) / Double(successes))
        let stdO = sqrt(os.map { pow($0 - os.reduce(0,+)/Double(successes), 2) }.reduce(0,+) / Double(successes))

        print("""
        === Stability Results (\(successes)/\(frameCount) ===
        World X: min=\(String(format:"%.2f", xs.min()!)) max=\(String(format:"%.2f", xs.max()!)) std=\(String(format:"%.2f", stdX))
        World Y: min=\(String(format:"%.2f", ys.min()!)) max=\(String(format:"%.2f", ys.max()!)) std=\(String(format:"%.2f", stdY))
        Orientation: min=\(String(format:"%.1f", os.min()!)) max=\(String(format:"%.1f", os.max()!)) std=\(String(format:"%.1f", stdO))
        Layer switches: \(Set(ids).count) unique layers (\(ids))
        Avg time: \(String(format:"%.0f", times.reduce(0,+)/Double(successes)))ms
        P95 time: \(String(format:"%.0f", times.sorted()[Int(Double(successes)*0.95)]))ms
        Output: \(outputDir.path)
        =======================================
        """)
    }
}
