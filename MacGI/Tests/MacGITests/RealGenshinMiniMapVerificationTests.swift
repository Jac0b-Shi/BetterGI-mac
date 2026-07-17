import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import MacGI
import Testing

@Suite("Real Genshin mini map verification",
       .enabled(if: ProcessInfo.processInfo.environment["MACGI_RUN_REAL_WINDOW_TESTS"] == "1"))
struct RealGenshinMiniMapVerificationTests {
    @MainActor
    @Test("Capture current Genshin window and extract mini map diagnostics")
    func captureCurrentWindowAndExtractMiniMapDiagnostics() throws {
        let windows = QuartzWindowEnumerator.enumerateApplicationWindows()
        let window = try #require(QuartzWindowEnumerator.bestGameWindow(from: windows))
        #expect(window.isLikelyGameWindow)

        let imageFrame = try QuartzWindowImageFrameProvider().captureWindow(window)
        let paimonMatch = BGIMiniMapPaimonLocator().locate(in: imageFrame)
        let extraction = try BGIMiniMapExtractor().extract(
            from: imageFrame,
            paimonTopLeft: paimonMatch?.topLeft
        )
        let preprocess = try BGIMiniMapPreprocessor().preprocess(extraction.originalImage)
        let orientation = try BGIMiniMapOrientationEstimator().estimate(preprocess)
        let matchInput = try BGIMiniMapPreprocessor().makeMatchInput(
            from: preprocess,
            orientation: orientation
        )
        let outputBase = outputBaseURL()
        try savePNG(imageFrame.cgImage, to: outputBase.appendingPathExtension("full.png"))
        try savePNG(extraction.viewportImage, to: outputBase.appendingPathExtension("viewport.png"))
        try savePNG(extraction.originalImage, to: outputBase.appendingPathExtension("original156.png"))
        try savePNG(preprocess.iconMaskImage, to: outputBase.appendingPathExtension("icon-mask.png"))
        try savePNG(preprocess.usableMaskImage, to: outputBase.appendingPathExtension("usable-mask.png"))
        try savePNG(matchInput.processedImage, to: outputBase.appendingPathExtension("processed.png"))
        try savePNG(matchInput.backgroundMaskImage, to: outputBase.appendingPathExtension("background-mask.png"))
        try savePNG(matchInput.finalMaskImage, to: outputBase.appendingPathExtension("final-mask.png"))

        print(
            """
            Real Genshin mini map verification:
              window: \(window.displayName) id=\(window.id) frame=\(window.frame)
              capture: \(imageFrame.backendName) \(imageFrame.metadata.sizeDescription) scale=\(String(format: "%.2f", imageFrame.metadata.scaleFactor))
              paimon: \(paimonMatch.map { "rect=\($0.rect) confidence=\(String(format: "%.3f", $0.confidence))" } ?? "not found; fallback ROI used")
              viewportRect: \(extraction.viewportRect)
              originalRect: \(extraction.originalRect)
              diagnostics: \(extraction.diagnostics.summary)
              preprocess: \(preprocess.statistics.summary)
              orientation: \(orientation.summary)
              matchInput: \(matchInput.statistics.summary)
              savedFull: \(outputBase.appendingPathExtension("full.png").path)
              savedViewport: \(outputBase.appendingPathExtension("viewport.png").path)
              savedOriginal156: \(outputBase.appendingPathExtension("original156.png").path)
              savedIconMask: \(outputBase.appendingPathExtension("icon-mask.png").path)
              savedUsableMask: \(outputBase.appendingPathExtension("usable-mask.png").path)
              savedProcessed: \(outputBase.appendingPathExtension("processed.png").path)
              savedBackgroundMask: \(outputBase.appendingPathExtension("background-mask.png").path)
              savedFinalMask: \(outputBase.appendingPathExtension("final-mask.png").path)
            """
        )

        #expect(paimonMatch != nil)
        #expect(extraction.viewportImage.width >= BGIMiniMapConstants.viewportSize)
        #expect(extraction.originalImage.width >= BGIMiniMapConstants.originalSize)
        #expect(extraction.diagnostics.circularSampleCount > 0)
        #expect(extraction.diagnostics.meanLuma > 5)
        #expect(extraction.diagnostics.lumaStandardDeviation > 1)
        #expect(preprocess.statistics.circlePixels > 18_000)
        #expect(preprocess.statistics.usablePixels > 8_000)
        #expect(orientation.degrees >= 0)
        #expect(orientation.degrees < 360)
        #expect(orientation.confidence >= 0)
        #expect(matchInput.statistics.finalMaskPixels > 8_000)
    }

    private func outputBaseURL() -> URL {
        if let configuredPath = ProcessInfo.processInfo.environment["MACGI_REAL_MINIMAP_OUTPUT"], !configuredPath.isEmpty {
            return URL(fileURLWithPath: configuredPath)
        }
        return URL(fileURLWithPath: "/tmp/bettergi-mac-real-genshin-minimap")
    }

    private func savePNG(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
