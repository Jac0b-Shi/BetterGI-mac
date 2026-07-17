import CoreGraphics
import Foundation
import ImageIO

// MARK: - Result types

struct BGIRealWorldDiagnosticResult: Encodable {
    struct Window: Encodable {
        let ownerName: String; let title: String; let windowID: String
        let frame: String; let captureRect: String; let scaleFactor: String
        let imageWidth: Int; let imageHeight: Int
    }
    struct Timing: Encodable {
        var paimonMs: Double=0; var extractMs: Double=0; var preprocessMs: Double=0
        var orientMs: Double=0; var layerMs: Double=0; var roughMs: Double=0
        var exactMs: Double=0; var totalMs: Double=0
    }
    var frameIndex: UInt64 = 0
    var captureTimestamp: String = ""
    var window: Window
    var usedPaimonLocator = false
    var usedFallback = false
    var paimonRect: String?
    var paimonConfidence: Double?
    var titleBarInset: String?
    var uiScale: String?
    var orientationDegrees: Double = 0
    var orientationConfidence: Double = 0
    var iconMaskRatio: Double = 0
    var usablePixelCount: Int = 0
    var layerId: String = ""
    var layerName: String?
    var layerCount: Int = 0
    var roughPoint: [Double] = [0,0]
    var roughConfidence: Double = 0
    var exactPoint: [Double] = [0,0]
    var exactConfidence: Double = 0
    var worldPoint: [Double] = [0,0]
    var timingsMs = Timing()
}

// MARK: - Diagnostic runner

enum BGIRealWorldMiniMapDiagnostics {

    /// Run the full pipeline and save all images to `dir`.
    static func run(
        frame: CaptureImageFrame,
        outputDir: URL,
        mapName: String? = nil,
        extractor: BGIMiniMapExtractor = BGIMiniMapExtractor(),
        preprocessor: BGIMiniMapPreprocessor = BGIMiniMapPreprocessor(),
        orientationEstimator: BGIMiniMapOrientationEstimator = BGIMiniMapOrientationEstimator(),
        localizationService: BGIMiniMapLocalizationService = BGIMiniMapLocalizationService()
    ) throws -> BGIRealWorldDiagnosticResult {
        let fm = FileManager.default
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let t0 = Date()

        let meta = frame.metadata
        let sw = meta.sourceWindow
        var r = BGIRealWorldDiagnosticResult(
            frameIndex: meta.frameIndex,
            captureTimestamp: ISO8601DateFormatter().string(from: meta.timestamp),
            window: .init(
                ownerName: sw.ownerName, title: sw.title,
                windowID: "\(sw.id)", frame: "\(sw.frame)",
                captureRect: "\(sw.captureRect)", scaleFactor: "\(sw.scaleFactor)",
                imageWidth: frame.cgImage.width, imageHeight: frame.cgImage.height
            )
        )

        // 01
        try save(frame.cgImage, to: outputDir.appendingPathComponent("01-full-frame.png"))

        // --- Paimon location ---
        let tPa = Date()
        let locator = BGIMiniMapPaimonLocator()
        let paimon = locator.locate(in: frame)
        r.timingsMs.paimonMs = Date().timeIntervalSince(tPa) * 1000

        if let p = paimon {
            r.usedPaimonLocator = true
            r.paimonConfidence = p.confidence
            r.paimonRect = "\(p.rect)"
            // 03-05
            try saveCropped(frame.cgImage, rect: p.rect, to: outputDir.appendingPathComponent("03-paimon-template.png"))
            let roi = BGIMiniMapConstants.paimonSearchROI(for: frame.cgImage)
            try saveCropped(frame.cgImage, rect: roi, to: outputDir.appendingPathComponent("04-paimon-search-roi.png"))
            try saveOverlay(frame.cgImage, rect: p.rect, to: outputDir.appendingPathComponent("05-paimon-match-overlay.png"))
        } else {
            r.usedFallback = true
        }

        // --- Game content (02) ---
        let inset = detectTitleBar(frame.cgImage)
        r.titleBarInset = "\(inset)"
        if inset > 0 {
            let gameRect = CGRect(x: 0, y: inset,
                                  width: CGFloat(frame.cgImage.width),
                                  height: CGFloat(frame.cgImage.height) - inset)
            if let cropped = frame.cgImage.cropping(to: gameRect.integral) {
                try save(cropped, to: outputDir.appendingPathComponent("02-game-content.png"))
            }
        }

        // --- Extraction ---
        let tEx = Date()
        let paimonTL = paimon?.topLeft
        let extraction = try extractor.extract(from: frame, paimonTopLeft: paimonTL)
        r.timingsMs.extractMs = Date().timeIntervalSince(tEx) * 1000
        let scale = max(0.1, Double(frame.metadata.height) / BGIMiniMapConstants.upstreamReferenceHeight)
        r.uiScale = "\(scale)"

        try save(extraction.viewportImage, to: outputDir.appendingPathComponent("06-minimap-viewport-210.png"))
        try save(extraction.originalImage, to: outputDir.appendingPathComponent("07-minimap-original-156.png"))

        // --- Preprocess ---
        let tPr = Date()
        let prep = try preprocessor.preprocess(extraction.originalImage)
        r.timingsMs.preprocessMs = Date().timeIntervalSince(tPr) * 1000
        r.iconMaskRatio = prep.statistics.iconMaskRatio
        r.usablePixelCount = prep.statistics.usablePixels

        try save(prep.iconMaskImage, to: outputDir.appendingPathComponent("08-icon-mask.png"))
        // 09 circle mask: save usableMaskImage
        try save(prep.usableMaskImage, to: outputDir.appendingPathComponent("09-circle-mask.png"))
        try save(prep.sourceImage, to: outputDir.appendingPathComponent("10-process1.png"))

        // --- Orientation ---
        let tOr = Date()
        let orient = try orientationEstimator.estimate(prep)
        r.timingsMs.orientMs = Date().timeIntervalSince(tOr) * 1000
        r.orientationDegrees = orient.degrees
        r.orientationConfidence = orient.confidence

        // Process2
        let mi = try preprocessor.makeMatchInput(from: prep, orientation: orient)
        try save(mi.processedImage, to: outputDir.appendingPathComponent("11-process2-visualized.png"))
        try save(mi.finalMaskImage, to: outputDir.appendingPathComponent("12-final-mask.png"))
        try save(mi.processedImage, to: outputDir.appendingPathComponent("13-rotated-minimap.png"))

        // --- Layer loading ---
        let tLa = Date()
        let descriptors = try localizationService.loadLayerDescriptorsForDiagnostics(mapName: mapName)
        r.timingsMs.layerMs = Date().timeIntervalSince(tLa) * 1000
        r.layerCount = descriptors.count

        // --- Matching ---
        let tpl = try BGIMiniMapMatchContext.prepare(mi)
        try save(try tpl.roughColor.cgImage(mode: .rgb), to: outputDir.appendingPathComponent("15-rough-template.png"))
        try save(try tpl.exactGray.cgImage(mode: .grayscale), to: outputDir.appendingPathComponent("18-exact-template.png"))

        // Rough
        let tRo = Date()
        let bestR = try localizationService.globalRoughMatch(template: tpl, mapName: mapName, earlyConfidence: 0.95)
        r.timingsMs.roughMs = Date().timeIntervalSince(tRo) * 1000
        guard let best = bestR else {
            throw BGIMiniMapLocalizationError.noLayerMatched
        }
        r.roughPoint = [best.result.sourcePoint.x, best.result.sourcePoint.y]
        r.roughConfidence = best.result.confidence
        r.layerId = best.layer.descriptor.layerId
        r.layerName = best.layer.descriptor.name

        // Exact
        let tEx2 = Date()
        let rw = best.layer.mapToWorld(best.result.sourcePoint,
                                        zoom: Double(BGIMiniMapConstants.roughZoom),
                                        miniMapSize: BGIMiniMapConstants.roughMatchSize)
        let exactLayer = try localizationService.loadLayerForDiagnostics(mapName: mapName, descriptor: best.layer.descriptor)
        guard let exact = exactLayer.exactMatch(tpl, near: rw) else {
            throw BGIMiniMapLocalizationError.noMatchInLayer
        }
        r.timingsMs.exactMs = Date().timeIntervalSince(tEx2) * 1000
        r.exactPoint = [exact.sourcePoint.x, exact.sourcePoint.y]
        r.exactConfidence = exact.confidence
        let world = best.layer.mapToWorld(exact.sourcePoint,
                                           zoom: Double(BGIMiniMapConstants.exactZoom),
                                           miniMapSize: BGIMiniMapConstants.exactMatchSize)
        r.worldPoint = [world.x, world.y]

        r.timingsMs.totalMs = Date().timeIntervalSince(t0) * 1000

        // JSON
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(r).write(to: outputDir.appendingPathComponent("21-final-result.json"))

        return r
    }

    // MARK: - Sequence

    static func runSequence(
        count: Int, intervalMs: UInt64,
        frameStore: LatestFrameStore,
        outputDir: URL
    ) throws -> [BGIRealWorldDiagnosticResult] {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        var results = [BGIRealWorldDiagnosticResult]()
        for i in 0..<count {
            let d = outputDir.appendingPathComponent("frame-\(String(format: "%04d", i))", isDirectory: true)
            let start = Date()
            var frame: CaptureImageFrame?
            while frame == nil, Date().timeIntervalSince(start) < 5 {
                frame = frameStore.snapshotAny()
                if frame == nil { Thread.sleep(forTimeInterval: 0.01) }
            }
            guard let f = frame else {
                throw NSError(domain: "Diag", code: 1, userInfo: [NSLocalizedDescriptionKey: "No fresh frame"])
            }
            let r = try run(frame: f, outputDir: d)
            results.append(r)
            if i < count - 1 { Thread.sleep(forTimeInterval: Double(intervalMs) / 1000) }
        }

        // Summary CSV
        var csv = "frameIndex,timestamp,layerId,worldX,worldY,orient,roughConf,exactConf,ms\n"
        for r in results {
            csv += "\(r.frameIndex),\(r.captureTimestamp),\(r.layerId),"
            csv += "\(r.worldPoint[0]),\(r.worldPoint[1]),"
            csv += "\(r.orientationDegrees),\(r.roughConfidence),\(r.exactConfidence),\(r.timingsMs.totalMs)\n"
        }
        try csv.write(to: outputDir.appendingPathComponent("sequence-summary.csv"), atomically: true, encoding: .utf8)
        return results
    }

    // MARK: - Helpers

    private static func save(_ image: CGImage, to url: URL) throws {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw NSError(domain: "Diag", code: 2) }
        CGImageDestinationAddImage(d, image, nil)
        guard CGImageDestinationFinalize(d) else { throw NSError(domain: "Diag", code: 3) }
    }

    private static func saveCropped(_ image: CGImage, rect: CGRect, to url: URL) throws {
        guard let c = image.cropping(to: rect.integral) else { throw NSError(domain: "Diag", code: 4) }
        try save(c, to: url)
    }

    private static func saveOverlay(_ image: CGImage, rect: CGRect, to url: URL) throws {
        let w = image.width, h = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.setLineWidth(2)
        ctx.stroke(rect.integral)
        guard let out = ctx.makeImage() else { return }
        try save(out, to: url)
    }

    private static func detectTitleBar(_ image: CGImage) -> CGFloat {
        let h = min(96, image.height)
        guard h > 0, let top = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: h)),
              let data = top.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return 0 }
        let bpr = top.bytesPerRow
        var last = 0
        for y in 0..<h {
            let row = ptr.advanced(by: y * bpr)
            let r0 = Int(row[0]), g0 = Int(row[1]), b0 = Int(row[2])
            var uniform = true
            let step = max(1, image.width / 10)
            for x in stride(from: 0, to: image.width, by: step) {
                let p = row.advanced(by: x * 4)
                if abs(Int(p[0]) - r0) > 30 || abs(Int(p[1]) - g0) > 30 || abs(Int(p[2]) - b0) > 30 {
                    uniform = false; break
                }
            }
            if uniform { last = y + 1 } else { break }
        }
        return CGFloat(last)
    }
}

// MARK: - Missing constant

private extension BGIMiniMapConstants {
    /// Search ROI for Paimon icon (top-left 25% of the frame).
    static func paimonSearchROI(for image: CGImage) -> CGRect {
        CGRect(x: 0, y: 0, width: image.width / 4, height: image.height / 4)
    }
}

// MARK: - Public layer access for diagnostics

extension BGIMiniMapLocalizationService {
    func loadLayersForDiagnostics(mapName: String?) throws -> [BGIMiniMapTemplateLayer] {
        try loadLayers(mapName: mapName)
    }

    func loadLayerDescriptorsForDiagnostics(mapName: String?) throws -> [BGIMiniMapLayerDescriptor] {
        try loadLayerDescriptors(mapName: mapName)
    }

    func loadLayerForDiagnostics(
        mapName: String?,
        descriptor: BGIMiniMapLayerDescriptor
    ) throws -> BGIMiniMapTemplateLayer {
        try loadLayer(mapName: mapName, descriptor: descriptor)
    }
}
