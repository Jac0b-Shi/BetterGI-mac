import CoreGraphics
import Foundation
import ImageIO

// MARK: - Errors / Status

enum BGIMiniMapLocalizationError: LocalizedError, Equatable {
    case missingMapRoot(URL)
    case missingCityInfo(String)
    case invalidCityInfo(String)
    case missingLayerTile(String)
    case cannotDecodeTile(String)
    case miniMapExtractionFailed(String)
    case noLayerMatched
    case noMatchInLayer
    case tooManyIconPixels(ratio: Double)
    case orientationNotConfident(confidence: Double)

    var errorDescription: String? {
        switch self {
        case let .missingMapRoot(url):
            "BetterGI map assets missing at \(url.path)"
        case let .missingCityInfo(path):
            "BetterGI map city info missing: \(path)"
        case let .invalidCityInfo(path):
            "BetterGI map city info cannot be decoded: \(path)"
        case let .missingLayerTile(path):
            "BetterGI map tile missing: \(path)"
        case let .cannotDecodeTile(path):
            "BetterGI map tile cannot be decoded: \(path)"
        case let .miniMapExtractionFailed(message):
            "BetterGI mini map extraction failed: \(message)"
        case .noLayerMatched:
            "BetterGI mini map did not match any known layer"
        case .noMatchInLayer:
            "BetterGI mini map matched a layer but failed exact refinement"
        case let .tooManyIconPixels(ratio):
            "BetterGI mini map has too many icon pixels (ratio \(String(format: "%.2f", ratio))); unsafe to match"
        case let .orientationNotConfident(confidence):
            "BetterGI mini map orientation confidence too low (\(String(format: "%.3f", confidence)))"
        }
    }
}

struct BGIMiniMapLocalizationResult: Equatable, Sendable {
    let worldPoint: CGPoint
    let layerId: String
    let layerName: String?
    let orientation: BGIMiniMapOrientationEstimate
    let confidence: Double
}

// MARK: - Localization session

/// Persists the upstream localization state across successive `getPosition`
/// calls so the matcher can benefit from temporal coherence.
struct BGIMiniMapLocalizationSession {
    var prevPosition: CGPoint?
    var prevLayerId: String?
    var prevCaptureTime: Date = .distantPast

    /// Upstream `GetPositionStableByCache` cache window (900 ms).
    static let cacheWindowMs: Int = 900
}

// MARK: - Service

/// Unified entry point for BetterGI-style mini map localization.
///
/// The service mirrors upstream `Navigation.GetPosition` / `GetPositionStable`: when
/// a previous position is available it uses local rough+exact matching with a strict
/// 0.99 threshold; otherwise it falls back to global rough (0.95 gate) → exact.
///
/// Pipeline: capture -> `BGIMiniMapExtractor` -> `BGIMiniMapPreprocessor` ->
/// `BGIMiniMapOrientationEstimator` -> `BGIMiniMapMatcher` -> world point.
///
/// The service loads tile layers from the external runtime resource store under
/// `Assets/Map`. It mirrors the upstream flow in `AutoTrackPathTask` and
/// `MapCoordinate`, while keeping the three low-level stages separable for
/// testing and future Rust replacement.
final class BGIMiniMapLocalizationService: @unchecked Sendable {
    let store: BGIRuntimeResourceStore
    private let extractor: BGIMiniMapExtractor
    private let preprocessor: BGIMiniMapPreprocessor
    private let orientationEstimator: BGIMiniMapOrientationEstimator
    private let fileManager: FileManager
    private let iconMaskThreshold: Double
    private let orientationConfidenceThreshold: Double

    private var descriptorCache: [String: [BGIMiniMapLayerDescriptor]] = [:]
    private var coarseLayerCache: [String: BGIMiniMapCoarseTemplateLayer] = [:]
    private var layerCache: [String: BGIMiniMapTemplateLayer] = [:]
    private let lock = NSLock()

    /// Per‑region localization session mirroring upstream `NavigationInstance`.
    private var sessions: [String: BGIMiniMapLocalizationSession] = [:]
    private let sessionLock = NSLock()

    init(
        store: BGIRuntimeResourceStore = .defaultStore(),
        extractor: BGIMiniMapExtractor = BGIMiniMapExtractor(),
        preprocessor: BGIMiniMapPreprocessor = BGIMiniMapPreprocessor(),
        orientationEstimator: BGIMiniMapOrientationEstimator = BGIMiniMapOrientationEstimator(),
        fileManager: FileManager = .default,
        iconMaskThreshold: Double = 0.45,
        orientationConfidenceThreshold: Double = 0.15
    ) {
        self.store = store
        self.extractor = extractor
        self.preprocessor = preprocessor
        self.orientationEstimator = orientationEstimator
        self.fileManager = fileManager
        self.iconMaskThreshold = iconMaskThreshold
        self.orientationConfidenceThreshold = orientationConfidenceThreshold
    }

    // MARK: - Public API

    /// Reset the localization session for all or a specific map region.
    func reset(mapName: String? = nil) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if let mapName {
            sessions.removeValue(forKey: mapName)
        } else {
            sessions.removeAll()
        }
    }

    /// Returns the current game world position from the mini map, with upstream
    /// localization session semantics (prevLayerId, 900 ms cache, jump detection).
    func getPosition(
        from frame: CaptureImageFrame,
        near: CGPoint? = nil,
        mapName: String? = nil
    ) throws -> BGIMiniMapLocalizationResult {
        let region = mapName ?? "Teyvat"
        let now = Date()
        _ = try loadLayerDescriptors(mapName: mapName)
        let extraction = try extractor.extract(from: frame)
        let preprocess = try preprocessor.preprocess(extraction.originalImage)
        let orientation = try orientationEstimator.estimate(preprocess)

        guard orientation.confidence >= orientationConfidenceThreshold else {
            throw BGIMiniMapLocalizationError.orientationNotConfident(confidence: orientation.confidence)
        }
        guard preprocess.statistics.iconMaskRatio < iconMaskThreshold else {
            throw BGIMiniMapLocalizationError.tooManyIconPixels(ratio: preprocess.statistics.iconMaskRatio)
        }

        let matchInput = try preprocessor.makeMatchInput(from: preprocess, orientation: orientation)
        let template = try BGIMiniMapMatchContext.prepare(matchInput)

        let strictThreshold = 0.99
        let globalThreshold = 0.95

        var session = sessionLock.withLock { sessions[region] ?? BGIMiniMapLocalizationSession() }

        // --- Local match (upstream LocalMatch with prevLayerId) ---
        if let nearPoint = session.prevPosition ?? near,
           let result = try localMatch(
            template: template,
            mapName: mapName,
            near: nearPoint,
            preferredLayerId: session.prevLayerId,
            orientation: orientation,
            roughThreshold: strictThreshold,
            exactThreshold: strictThreshold
           ) {
            updateSession(&session, region: region, result: result, captureTime: now)
            return result
        }

        // Jump detection: if prevPosition is set but local match failed and near is far away,
        // reset the session so we don't keep trying an unreachable local area.
        if let prevPos = session.prevPosition, let near {
            let jump = hypot(near.x - prevPos.x, near.y - prevPos.y)
            if jump > 150 || session.prevLayerId == nil {
                session = BGIMiniMapLocalizationSession()
            }
        }

        // --- Global match fallback ---
        let best = try globalRoughMatch(template: template, mapName: mapName, earlyConfidence: globalThreshold)
        guard let best, best.result.confidence >= globalThreshold else {
            throw BGIMiniMapLocalizationError.noLayerMatched
        }

        let roughWorld = best.layer.mapToWorld(
            best.result.sourcePoint,
            zoom: Double(BGIMiniMapConstants.roughZoom),
            miniMapSize: BGIMiniMapConstants.roughMatchSize
        )
        let exactLayer = try loadLayer(mapName: mapName, descriptor: best.layer.descriptor)
        guard let exactResult = exactLayer.exactMatch(template, near: roughWorld),
              exactResult.confidence >= globalThreshold else {
            throw BGIMiniMapLocalizationError.noMatchInLayer
        }

        let result = makeResult(layer: exactLayer, matchResult: exactResult, orientation: orientation,
                                zoom: Double(BGIMiniMapConstants.exactZoom))
        updateSession(&session, region: region, result: result, captureTime: now)
        return result
    }

    /// Convenience accessor for scripts that only need the camera orientation.
    func getCameraOrientation(from frame: CaptureImageFrame) throws -> BGIMiniMapOrientationEstimate {
        let extraction = try extractor.extract(from: frame)
        let preprocess = try preprocessor.preprocess(extraction.originalImage)
        return try orientationEstimator.estimate(preprocess)
    }

    func localMatch(
        template: BGIMiniMapPreparedTemplate,
        layers: [BGIMiniMapTemplateLayer],
        near worldPoint: CGPoint,
        preferredLayerId: String?,
        orientation: BGIMiniMapOrientationEstimate,
        roughThreshold: Double,
        exactThreshold: Double
    ) -> BGIMiniMapLocalizationResult? {
        if let preferredLayerId,
           let preferred = layers.first(where: { $0.descriptor.layerId == preferredLayerId }) {
            if let result = localMatch(
                template: template,
                layer: preferred,
                near: worldPoint,
                orientation: orientation,
                roughThreshold: roughThreshold,
                exactThreshold: exactThreshold
            ) {
                return result
            }
        }

        for layer in layers where layer.descriptor.layerId != preferredLayerId {
            if let result = localMatch(
                template: template,
                layer: layer,
                near: worldPoint,
                orientation: orientation,
                roughThreshold: roughThreshold,
                exactThreshold: exactThreshold
            ) {
                return result
            }
        }
        return nil
    }

    func localMatch(
        template: BGIMiniMapPreparedTemplate,
        mapName: String?,
        near worldPoint: CGPoint,
        preferredLayerId: String?,
        orientation: BGIMiniMapOrientationEstimate,
        roughThreshold: Double,
        exactThreshold: Double
    ) throws -> BGIMiniMapLocalizationResult? {
        let descriptors = try loadLayerDescriptors(mapName: mapName)
        if let preferredLayerId,
           let preferred = descriptors.first(where: { $0.layerId == preferredLayerId }) {
            let layer = try loadLayer(mapName: mapName, descriptor: preferred)
            if let result = localMatch(
                template: template,
                layer: layer,
                near: worldPoint,
                orientation: orientation,
                roughThreshold: roughThreshold,
                exactThreshold: exactThreshold
            ) {
                return result
            }
        }

        for descriptor in descriptors where descriptor.layerId != preferredLayerId {
            let layer = try loadLayer(mapName: mapName, descriptor: descriptor)
            if let result = localMatch(
                template: template,
                layer: layer,
                near: worldPoint,
                orientation: orientation,
                roughThreshold: roughThreshold,
                exactThreshold: exactThreshold
            ) {
                return result
            }
        }
        return nil
    }

    // MARK: - Layer loading

    func loadLayers(mapName: String?) throws -> [BGIMiniMapTemplateLayer] {
        lock.lock()
        defer { lock.unlock() }

        let region = mapName ?? "Teyvat"
        let regionURL = try regionURL(for: region)
        let descriptors = try loadLayerDescriptorsLocked(region: region, regionURL: regionURL)

        return try descriptors.map { descriptor in
            try loadLayerLocked(region: region, regionURL: regionURL, descriptor: descriptor)
        }
    }

    func loadLayerDescriptors(mapName: String?) throws -> [BGIMiniMapLayerDescriptor] {
        lock.lock()
        defer { lock.unlock() }

        let region = mapName ?? "Teyvat"
        let regionURL = try regionURL(for: region)
        return try loadLayerDescriptorsLocked(region: region, regionURL: regionURL)
    }

    func loadLayer(mapName: String?, descriptor: BGIMiniMapLayerDescriptor) throws -> BGIMiniMapTemplateLayer {
        lock.lock()
        defer { lock.unlock() }

        let region = mapName ?? "Teyvat"
        let regionURL = try regionURL(for: region)
        return try loadLayerLocked(region: region, regionURL: regionURL, descriptor: descriptor)
    }

    func loadCoarseLayer(mapName: String?, descriptor: BGIMiniMapLayerDescriptor) throws -> BGIMiniMapCoarseTemplateLayer {
        lock.lock()
        defer { lock.unlock() }

        let region = mapName ?? "Teyvat"
        let regionURL = try regionURL(for: region)
        return try loadCoarseLayerLocked(region: region, regionURL: regionURL, descriptor: descriptor)
    }

    private func regionURL(for region: String) throws -> URL {
        let regionURL = store.mapsURL.appendingPathComponent(region, isDirectory: true)
        guard fileManager.fileExists(atPath: regionURL.path) else {
            throw BGIMiniMapLocalizationError.missingMapRoot(regionURL)
        }
        return regionURL
    }

    private func loadLayerDescriptorsLocked(region: String, regionURL: URL) throws -> [BGIMiniMapLayerDescriptor] {
        if let cached = descriptorCache[region] {
            return cached
        }

        guard let enumerator = fileManager.enumerator(
            at: regionURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw BGIMiniMapLocalizationError.missingCityInfo(regionURL.appendingPathComponent("city_info.json").path)
        }

        let jsonURLs = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  url.pathExtension.lowercased() == "json",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url
        }.sorted { $0.path < $1.path }

        guard !jsonURLs.isEmpty else {
            throw BGIMiniMapLocalizationError.missingCityInfo(regionURL.appendingPathComponent("city_info.json").path)
        }

        var descriptors: [BGIMiniMapLayerDescriptor] = []
        for jsonURL in jsonURLs {
            do {
                descriptors.append(contentsOf: try BGIMiniMapLayerDescriptor.decodeList(from: Data(contentsOf: jsonURL)))
            } catch {
                throw BGIMiniMapLocalizationError.invalidCityInfo(jsonURL.path)
            }
        }
        descriptors.sort { lhs, rhs in
            let lhsPriority = layerMatchPriority(lhs)
            let rhsPriority = layerMatchPriority(rhs)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.layerId < rhs.layerId
        }
        descriptorCache[region] = descriptors
        return descriptors
    }

    private func layerMatchPriority(_ descriptor: BGIMiniMapLayerDescriptor) -> Int {
        if descriptor.layerId.hasPrefix("MapBack") { return 0 }
        if descriptor.layerId.hasPrefix("City") { return 1 }
        if descriptor.layerId.hasPrefix("LayeredMap") { return 2 }
        return 3
    }

    private func loadCoarseLayerLocked(
        region: String,
        regionURL: URL,
        descriptor: BGIMiniMapLayerDescriptor
    ) throws -> BGIMiniMapCoarseTemplateLayer {
        let cacheKey = "\(region)/\(descriptor.layerId)"
        if let cached = coarseLayerCache[cacheKey] {
            return cached
        }
        let colorURL = regionURL.appendingPathComponent("\(descriptor.layerId)_color.webp")

        guard fileManager.fileExists(atPath: colorURL.path) else {
            throw BGIMiniMapLocalizationError.missingLayerTile(colorURL.path)
        }

        let coarseColorMap = try loadPixelImage(from: colorURL, mode: .rgb)
        let layer = BGIMiniMapCoarseTemplateLayer(
            descriptor: descriptor,
            coarseColorMap: coarseColorMap
        )
        coarseLayerCache[cacheKey] = layer
        return layer
    }

    private func loadLayerLocked(
        region: String,
        regionURL: URL,
        descriptor: BGIMiniMapLayerDescriptor
    ) throws -> BGIMiniMapTemplateLayer {
        let cacheKey = "\(region)/\(descriptor.layerId)"
        if let cached = layerCache[cacheKey] {
            return cached
        }

        let coarseLayer = try loadCoarseLayerLocked(region: region, regionURL: regionURL, descriptor: descriptor)
        let grayExt = descriptor.isOverSize == true ? "png" : "webp"
        let grayURL = regionURL.appendingPathComponent("\(descriptor.layerId)_gray.\(grayExt)")
        guard fileManager.fileExists(atPath: grayURL.path) else {
            throw BGIMiniMapLocalizationError.missingLayerTile(grayURL.path)
        }

        let fineGrayMap = try loadPixelImage(from: grayURL, mode: .grayscale)
        let layer = BGIMiniMapTemplateLayer(
            descriptor: descriptor,
            coarseColorMap: coarseLayer.coarseColorMap,
            fineGrayMap: fineGrayMap
        )
        layerCache[cacheKey] = layer
        return layer
    }

    private func loadPixelImage(from url: URL, mode: PixelImage.Mode) throws -> PixelImage {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw BGIMiniMapLocalizationError.cannotDecodeTile(url.path)
        }
        return try PixelImage(cgImage: image, mode: mode)
    }

    // MARK: - Helpers

    /// Find the layer that contains the given world point, returning its pixel
    /// position within that layer's fine gray map.  The distance is computed in
    /// *map‑pixel* space so that the two values share the same coordinate system.
    private func nearPoint(_ worldPoint: CGPoint, in layers: [BGIMiniMapTemplateLayer]) -> (layer: BGIMiniMapTemplateLayer, mapPoint: CGPoint)? {
        var best: (layer: BGIMiniMapTemplateLayer, mapPoint: CGPoint, distance: Double)?
        for layer in layers {
            let mapPoint = layer.worldToMap(worldPoint, zoom: Double(BGIMiniMapConstants.exactZoom))
            let bounds = CGRect(
                x: 0, y: 0,
                width: CGFloat(layer.fineGrayMap.width),
                height: CGFloat(layer.fineGrayMap.height)
            )
            guard bounds.contains(mapPoint) else { continue }
            // Use distance from the layer's own center as a simple tiebreaker
            let centerX = CGFloat(layer.fineGrayMap.width) / 2.0
            let centerY = CGFloat(layer.fineGrayMap.height) / 2.0
            let distance = Double(hypot(mapPoint.x - centerX, mapPoint.y - centerY))
            if best == nil || distance < best!.distance {
                best = (layer, mapPoint, distance)
            }
        }
        return best.map { ($0.layer, $0.mapPoint) }
    }

    private func localMatch(
        template: BGIMiniMapPreparedTemplate,
        layer: BGIMiniMapTemplateLayer,
        near worldPoint: CGPoint,
        orientation: BGIMiniMapOrientationEstimate,
        roughThreshold: Double,
        exactThreshold: Double
    ) -> BGIMiniMapLocalizationResult? {
        guard let rough = layer.roughMatch(template, near: worldPoint),
              rough.confidence >= roughThreshold else {
            return nil
        }

        let roughWorld = layer.mapToWorld(
            rough.sourcePoint,
            zoom: Double(BGIMiniMapConstants.roughZoom),
            miniMapSize: BGIMiniMapConstants.roughMatchSize
        )
        guard let exact = layer.exactMatch(template, near: roughWorld),
              exact.confidence >= exactThreshold else {
            return nil
        }

        return makeResult(
            layer: layer,
            matchResult: exact,
            orientation: orientation,
            zoom: Double(BGIMiniMapConstants.exactZoom)
        )
    }

    func globalRoughMatch(
        template: BGIMiniMapPreparedTemplate,
        layers: [BGIMiniMapTemplateLayer],
        earlyConfidence: Double? = nil
    ) -> (layer: BGIMiniMapTemplateLayer, result: BGIMiniMapMatchResult)? {
        var best: (layer: BGIMiniMapTemplateLayer, result: BGIMiniMapMatchResult)?
        for layer in layers {
            guard let result = layer.roughMatch(template) else { continue }
            if best == nil || result.confidence > best!.result.confidence {
                best = (layer, result)
            }
            if let earlyConfidence, result.confidence >= earlyConfidence {
                return (layer, result)
            }
        }
        return best
    }

    func globalRoughMatch(
        template: BGIMiniMapPreparedTemplate,
        mapName: String?,
        earlyConfidence: Double? = nil
    ) throws -> (layer: BGIMiniMapCoarseTemplateLayer, result: BGIMiniMapMatchResult)? {
        let descriptors = try loadLayerDescriptors(mapName: mapName)
        var best: (layer: BGIMiniMapCoarseTemplateLayer, result: BGIMiniMapMatchResult)?
        for descriptor in descriptors {
            let layer = try loadCoarseLayer(mapName: mapName, descriptor: descriptor)
            guard let result = layer.roughMatch(template) else { continue }
            if best == nil || result.confidence > best!.result.confidence {
                best = (layer, result)
            }
            if let earlyConfidence, result.confidence >= earlyConfidence {
                return (layer, result)
            }
        }
        return best
    }

    private func makeResult(
        layer: BGIMiniMapTemplateLayer,
        matchResult: BGIMiniMapMatchResult,
        orientation: BGIMiniMapOrientationEstimate,
        zoom: Double
    ) -> BGIMiniMapLocalizationResult {
        let world = layer.mapToWorld(
            matchResult.sourcePoint,
            zoom: zoom,
            miniMapSize: BGIMiniMapConstants.exactMatchSize
        )
        return BGIMiniMapLocalizationResult(
            worldPoint: world,
            layerId: layer.descriptor.layerId,
            layerName: layer.descriptor.name,
            orientation: orientation,
            confidence: matchResult.confidence
        )
    }

    private func updateSession(
        _ session: inout BGIMiniMapLocalizationSession,
        region: String,
        result: BGIMiniMapLocalizationResult,
        captureTime: Date
    ) {
        session.prevPosition = result.worldPoint
        session.prevLayerId = result.layerId
        session.prevCaptureTime = captureTime
        sessionLock.lock()
        sessions[region] = session
        sessionLock.unlock()
    }
}
