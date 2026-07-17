import CoreGraphics
import Foundation
import ImageIO
@testable import MacGI
import Testing
import UniformTypeIdentifiers

@Suite("Real Genshin big map verification",
       .enabled(if: ProcessInfo.processInfo.environment["MACGI_RUN_REAL_BIGMAP_TESTS"] == "1"))
struct RealGenshinBigMapVerificationTests {
    @MainActor
    @Test("Capture current Genshin window and recognize big-map UI status")
    func captureCurrentWindowAndRecognizeBigMapUIStatus() throws {
        let windows = QuartzWindowEnumerator.enumerateApplicationWindows()
        let window = try #require(QuartzWindowEnumerator.bestGameWindow(from: windows))
        #expect(window.isLikelyGameWindow)

        let frame = try QuartzWindowImageFrameProvider().captureWindow(window)
        let status = BGIGameUIStatusRecognizer().recognize(frame)
        let outputBase = outputBaseURL()
        try savePNG(frame.cgImage, to: outputBase.appendingPathExtension("full.png"))

        print(
            """
            Real Genshin big map verification:
              window: \(window.displayName) id=\(window.id) frame=\(window.frame) captureRect=\(window.captureRect)
              capture: \(frame.backendName) \(frame.metadata.sizeDescription) scale=\(String(format: "%.2f", frame.metadata.scaleFactor))
              isInBigMapUI: \(status.isInBigMapUI)
              isUnderground: \(status.isBigMapUnderground)
              bigMapScaleFraction: \(status.bigMapScaleFraction.map { String(format: "%.3f", $0) } ?? "nil")
              backend: \(status.report.backendName) objects=\(status.report.objectCount) matched=\(status.report.matchedCount) costMs=\(String(format: "%.2f", status.report.costMs))
              observations: \(status.observations.map { "\($0.objectID):\(String(format: "%.3f", $0.confidence))@\($0.normalizedRect)" }.joined(separator: "; "))
              savedFull: \(outputBase.appendingPathExtension("full.png").path)
            """
        )

        #expect(status.isInBigMapUI)
        #expect(status.report.objectCount == RecognitionObject.bgiQuickTeleportBigMapStatusObjects.count + RecognitionObject.bgiCommonElementMainUIObjects.count)
        #expect(status.report.matchedCount > 0)
    }

    @MainActor
    @Test("OpenBigMap skips map hotkey when real window is already in big-map UI")
    func openBigMapSkipsMapHotkeyWhenRealWindowAlreadyInBigMapUI() async throws {
        let windows = QuartzWindowEnumerator.enumerateApplicationWindows()
        let window = try #require(QuartzWindowEnumerator.bestGameWindow(from: windows))
        var actions: [InputAction] = []
        let provider = QuartzWindowImageFrameProvider()
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: {
                try provider.captureWindow(window)
            },
            config: BGIBigMapConfig.forWindow(
                window,
                base: BGIBigMapConfig(openMapPrepareMs: 0, openMapWaitMs: 0, openMapRetryWaitMs: 0)
            )
        )

        try await service.openBigMap()

        print(
            """
            Real Genshin big map open verification:
              window: \(window.displayName) id=\(window.id) frame=\(window.frame) captureRect=\(window.captureRect)
              actions: \(actions)
            """
        )
        #expect(actions.isEmpty)
    }

    @MainActor
    @Test("Teleport dry-run: compute click point for nearest teleport and save annotated screenshot")
    func teleportDryRunClickVerification() async throws {
        let windows = QuartzWindowEnumerator.enumerateApplicationWindows()
        let window = try #require(QuartzWindowEnumerator.bestGameWindow(from: windows))
        var actions: [InputAction] = []
        let provider = QuartzWindowImageFrameProvider()

        // Use a known teleport point visible in Mondstadt area
        let goddessPoints = BGIWorldSceneAssets.nearestGoddess(toX: 1500, y: 500)
        guard let goddess = goddessPoints else {
            print("No goddess point found")
            return
        }
        print("Target: goddess id=\(goddess.id) at (\(goddess.x), \(goddess.y))")

        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: {
                try provider.captureWindow(window)
            },
            config: BGIBigMapConfig.forWindow(
                window,
                base: BGIBigMapConfig(openMapPrepareMs: 0, openMapWaitMs: 0, openMapRetryWaitMs: 0,
                                      teleportConfirmDelayMs: 0, teleportLoadWaitMs: 0)
            ),
            sceneConverter: .teyvat
        )

        // Open big map
        try await service.openBigMap()
        let frame = try provider.captureWindow(window)

        // Compute click position (public coordinate converter)
        let converter = BGISceneMapCoordinateConverter.teyvat
        guard let imagePoint = converter.genshinToImage(CGPoint(x: goddess.x, y: goddess.y)) else {
            print("Coordinate conversion failed")
            return
        }

        // Estimate map rect from capture rect with margins
        let captureRect = window.captureRect
        let margin = max(30.0, captureRect.width * 0.06)
        let bottomMargin = max(30.0, captureRect.height * 0.08)
        let mapRect = CGRect(
            x: captureRect.minX + margin,
            y: captureRect.minY,
            width: captureRect.width - margin * 2,
            height: captureRect.height - bottomMargin
        )
        let clickX = mapRect.minX + (imagePoint.x / converter.imageSize.width) * mapRect.width
        let clickY = mapRect.minY + (imagePoint.y / converter.imageSize.height) * mapRect.height

        print("""
        Teleport dry-run:
          target: (\(goddess.x), \(goddess.y))
          imagePoint: (\(imagePoint.x), \(imagePoint.y))
          mapRect: (\(Int(mapRect.minX)), \(Int(mapRect.minY)), \(Int(mapRect.width)), \(Int(mapRect.height)))
          clickPoint: (\(Int(clickX)), \(Int(clickY)))
          window: \(window.frame) captureRect=\(window.captureRect)
        """)

        // Save annotated frame with click point marked
        // Save annotated frame
        let dir = URL(fileURLWithPath: "/tmp/bettergi-mac-teleport-dry-run")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let outputFile = dir.appendingPathComponent("annotated.png")
        let annotated = try annotateFrame(frame.cgImage, withClickAt: CGPoint(x: clickX, y: clickY))
        try savePNG(annotated, to: outputFile)
        try savePNG(frame.cgImage, to: dir.appendingPathComponent("original.png"))
        print("Saved annotated: \(outputFile.path)")
    }

    private func annotateFrame(_ image: CGImage, withClickAt point: CGPoint) throws -> CGImage {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
        ) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: point.x - 15, y: point.y))
        ctx.addLine(to: CGPoint(x: point.x + 15, y: point.y))
        ctx.move(to: CGPoint(x: point.x, y: point.y - 15))
        ctx.addLine(to: CGPoint(x: point.x, y: point.y + 15))
        ctx.strokePath()
        ctx.setLineWidth(3)
        ctx.addEllipse(in: CGRect(x: point.x - 20, y: point.y - 20, width: 40, height: 40))
        ctx.strokePath()
        return try #require(ctx.makeImage())
    }

    private func outputBaseURL() -> URL {
        if let configuredPath = ProcessInfo.processInfo.environment["MACGI_REAL_BIGMAP_OUTPUT"], !configuredPath.isEmpty {
            return URL(fileURLWithPath: configuredPath)
        }
        return URL(fileURLWithPath: "/tmp/bettergi-mac-real-genshin-bigmap")
    }

    private func savePNG(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
