import CoreGraphics
import Foundation

// MARK: - Config

/// Upstream `TpConfig` parameters used by the teleport flow.
struct BGIBigMapConfig: Sendable {
    /// Zoom level at which teleport points become visible on the map.
    /// Upstream: `DisplayTpPointZoomLevel = 4.4`
    var teleportPointZoomLevel: Double = 4.4

    /// Min / max zoom levels for the map slider.
    var minZoomLevel: Double = 2.0
    var maxZoomLevel: Double = 5.0

    /// Slider button center at zoom level 1.0 in 1080p coordinates.
    /// Upstream: `TpConfig.ZoomStartY = 468`.
    var zoomStartY: Double = 468

    /// Slider button center at zoom level 6.0 in 1080p coordinates.
    /// Upstream: `TpConfig.ZoomEndY = 612`.
    var zoomEndY: Double = 612

    /// Slider button X in 1080p coordinates.
    /// Upstream: `TpConfig.ZoomButtonX = 47`.
    var zoomButtonX: Double = 47

    /// Map zoom to pixel scale factor when zoomLevel == 1.
    /// Upstream: `MapScaleFactor = 2.361`
    var mapScaleFactor: Double = 2.361

    /// Distance below which `MoveMapTo` stops moving.
    /// Upstream: `TpConfig.Tolerance = 200`.
    var mapMoveTolerance: Double = 200

    /// Distance above which `MoveMapTo` zooms out first.
    /// Upstream: `TpConfig.MapZoomOutDistance = 1000`.
    var mapZoomOutDistance: Double = 1000

    /// Distance below which `MoveMapTo` zooms in while approaching.
    /// Upstream: `TpConfig.MapZoomInDistance = 400`.
    var mapZoomInDistance: Double = 400

    /// Max iterations for big-map movement.
    /// Upstream: `TpConfig.MaxIterations = 30`.
    var mapMoveMaxIterations: Int = 30

    /// Max mouse movement length per big-map drag.
    /// Upstream: `TpConfig.MaxMouseMove = 300`.
    var mapMoveMaxMouseMove: Double = 300

    /// Step interval for `MouseMoveMap`.
    /// Upstream: `TpConfig.StepIntervalMilliseconds = 20`.
    var mapMoveStepIntervalMs: UInt64 = 20

    /// Precision threshold for deciding whether to adjust zoom.
    /// Upstream: `TpConfig.PrecisionThreshold = 0.05`.
    var mapZoomPrecisionThreshold: Double = 0.05

    /// DPI scale used by upstream `MouseMoveMap` before applying game-region scale.
    var screenDpiScale: Double = 1.0

    /// Game capture rectangle in absolute screen coordinates.
    var captureRect: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    /// Delay before pressing the map hotkey.
    var openMapPrepareMs: UInt64 = 100

    /// Delay after pressing the map hotkey.
    var openMapWaitMs: UInt64 = 800

    /// Retry count for verifying the big-map UI after pressing the map hotkey.
    /// Upstream `TpTask.TryToOpenBigMapUi` checks three times.
    var openMapCheckRetries: Int = 3

    /// Delay between big-map UI verification attempts.
    /// Upstream waits 500 ms between checks.
    var openMapRetryWaitMs: UInt64 = 500

    /// Whether map zoom adjustment is enabled.
    var mapZoomEnabled: Bool = true

    /// Wait time after clicking teleport, in milliseconds.
    var teleportConfirmDelayMs: UInt64 = 500

    /// Wait for loading screen after teleport, in milliseconds.
    var teleportLoadWaitMs: UInt64 = 1200

    /// Max attempts to wait for loading completion.
    var maxTeleportWaitAttempts: Int = 50

    /// Delay before clicking a map-choice list row.
    /// Upstream enforces at least 500 ms.
    var teleportListClickDelayMs: UInt64 = 500

    /// Retry count for waiting for the teleport button after selecting a list row.
    var teleportButtonAppearRetries: Int = 6

    /// Retry interval for waiting for the teleport button after selecting a list row.
    var teleportButtonAppearRetryMs: UInt64 = 300

    /// Retry count for waiting until the teleport button disappears after clicking it.
    var teleportButtonDisappearRetries: Int = 6

    /// Retry interval for waiting until the teleport button disappears after clicking it.
    var teleportButtonDisappearRetryMs: UInt64 = 300

    /// Wait after dragging the big-map zoom slider.
    /// Upstream waits 100 ms after `MouseClickAndMove`.
    var mapZoomAdjustWaitMs: UInt64 = 100

    static func forWindow(_ window: WindowInfo, base: BGIBigMapConfig = BGIBigMapConfig()) -> BGIBigMapConfig {
        var config = base
        let rect = window.captureRect
        if rect.origin.x.isFinite,
           rect.origin.y.isFinite,
           rect.size.width.isFinite,
           rect.size.height.isFinite,
           rect.width > 0,
           rect.height > 0 {
            config.captureRect = window.captureRect
        }
        return config
    }
}

// MARK: - Errors

enum BGIBigMapInteractionError: LocalizedError, Equatable {
    case notInBigMap
    case coordinateConversionFailed
    case teleportPointNotActivated
    case teleportTimeout
    case captureProviderUnavailable
    case zoomLevelUnavailable
    case bigMapPositionProviderUnavailable
    case bigMapPositionUnavailable
    case bigMapMoveFailed
    case unsupportedMapScene(String)
    case targetOutsideVisibleMap(Double, Double)

    var errorDescription: String? {
        switch self {
        case .notInBigMap:
            "Failed to enter big-map UI after retries"
        case .coordinateConversionFailed:
            "Could not convert coordinates for teleport click"
        case .teleportPointNotActivated:
            "Teleport point is not activated or does not exist"
        case .teleportTimeout:
            "Teleport did not complete in time"
        case .captureProviderUnavailable:
            "Big-map zoom level requires a capture provider"
        case .zoomLevelUnavailable:
            "Could not recognize the big-map zoom slider"
        case .bigMapPositionProviderUnavailable:
            "MoveMapTo requires a big-map position provider"
        case .bigMapPositionUnavailable:
            "Could not recognize the big-map center position"
        case .bigMapMoveFailed:
            "Big-map movement failed after repeated position recognition errors"
        case let .unsupportedMapScene(name):
            "Unsupported map scene: \(name) (Teyvat only)"
        case let .targetOutsideVisibleMap(x, y):
            "Target (\(x), \(y)) is outside the visible map rect"
        }
    }
}

private enum BGITeleportConfirmationResult {
    case clicked
    case pointNotActivated
    case notFound
}

private struct BGIBigMapMovement {
    var xOffset: Double
    var yOffset: Double
    var totalMoveMouseX: Double
    var totalMoveMouseY: Double

    var mouseDistance: Double {
        hypot(totalMoveMouseX, totalMoveMouseY)
    }

    func rescaled(fromZoomLevel: Double, toZoomLevel: Double) -> BGIBigMapMovement {
        guard toZoomLevel != 0 else { return self }
        let scale = fromZoomLevel / toZoomLevel
        return BGIBigMapMovement(
            xOffset: xOffset,
            yOffset: yOffset,
            totalMoveMouseX: totalMoveMouseX * scale,
            totalMoveMouseY: totalMoveMouseY * scale
        )
    }

    func drag(maxMouseMove: Double) -> (x: Int, y: Int, steps: Int) {
        let distance = max(mouseDistance, 0.0001)
        let xMagnitude = min(totalMoveMouseX, maxMouseMove * totalMoveMouseX / distance)
        let yMagnitude = min(totalMoveMouseY, maxMouseMove * totalMoveMouseY / distance)
        let moveX = Int(xMagnitude) * sign(xOffset)
        let moveY = Int(yMagnitude) * sign(yOffset)
        let length = hypot(Double(moveX), Double(moveY))
        return (moveX, moveY, max(Int(length) / 10, 3))
    }

    private func sign(_ value: Double) -> Int {
        if value > 0 { return 1 }
        if value < 0 { return -1 }
        return 0
    }
}

// MARK: - Service

/// macOS port of upstream `TpTask` responsible for opening the big map,
/// converting world coordinates to screen positions, clicking teleport
/// points, and waiting for the teleport to finish.
///
/// This implementation currently exposes the force-teleport click/confirm
/// path plus first-layer helpers for zoom and map dragging. The full upstream
/// `TpTask.TpOnce` flow still needs `GetBigMapRect` / `GetPositionFromBigMap`
/// parity before non-force teleport can be marked script-ready.
final class BGIBigMapInteractionService: @unchecked Sendable {
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias RecognitionObjectProvider = @MainActor (CaptureImageFrame, RecognitionObject) async throws -> [RecognitionObservation]
    typealias BigMapPositionProvider = @MainActor (_ mapName: String) async throws -> CGPoint
    typealias ObservationProvider = @MainActor (_ mapName: String) async throws -> BGIBigMapObservation

    private let inputHandler: InputHandler
    private let captureFrameProvider: CaptureFrameProvider?
    private let recognitionObjectProvider: RecognitionObjectProvider?
    private let bigMapPositionProvider: BigMapPositionProvider?
    private let observationProvider: ObservationProvider?
    private let keyBindings: KeyBindingsConfig
    private let config: BGIBigMapConfig
    private let sceneConverter: BGISceneMapCoordinateConverter
    private let statusRecognizer: BGIGameUIStatusRecognizer
    private let templateRecognitionEngine: TemplateMatchingRecognitionEngine
    private let mainUIStatusChecker: BGIMainUIStatusChecker

    init(
        inputHandler: @escaping InputHandler,
        captureFrameProvider: CaptureFrameProvider? = nil,
        recognitionObjectProvider: RecognitionObjectProvider? = nil,
        bigMapPositionProvider: BigMapPositionProvider? = nil,
        observationProvider: ObservationProvider? = nil,
        keyBindings: KeyBindingsConfig = .bgiDefault,
        config: BGIBigMapConfig = BGIBigMapConfig(),
        sceneConverter: BGISceneMapCoordinateConverter = .teyvat,
        statusRecognizer: BGIGameUIStatusRecognizer = BGIGameUIStatusRecognizer(),
        templateRecognitionEngine: TemplateMatchingRecognitionEngine = TemplateMatchingRecognitionEngine()
    ) {
        self.inputHandler = inputHandler
        self.captureFrameProvider = captureFrameProvider
        self.recognitionObjectProvider = recognitionObjectProvider
        self.bigMapPositionProvider = bigMapPositionProvider
        self.observationProvider = observationProvider
        self.keyBindings = keyBindings
        self.config = config
        self.sceneConverter = sceneConverter
        self.statusRecognizer = statusRecognizer
        self.templateRecognitionEngine = templateRecognitionEngine
        self.mainUIStatusChecker = BGIMainUIStatusChecker(
            statusRecognizer: statusRecognizer,
            templateRecognitionEngine: templateRecognitionEngine,
            recognitionObjectProvider: recognitionObjectProvider
        )
    }

    // MARK: - Public API

    /// Execute a force‑teleport: open the big map, click the target genshin
    /// coordinates, confirm, and block until the loading screen finishes.
    ///
    /// - Parameters:
    ///   - tpX: Target X in genshin map coordinates.
    ///   - tpY: Target Y in genshin map coordinates.
    // MARK: - Teleport

    /// Dry-run-only teleport core: opens map, moves to target, computes the
    /// viewport-correct click point using SIFT `visibleRect256`, and logs
    /// without sending mouse/keyboard input.
    func teleport(tpX: Double, tpY: Double) async throws {
        // Legacy: uses absolute-proportion click, preserves existing test behavior.
        // New code should use teleportOnceDryRun() for viewport-correct mapping.
        try await openBigMap()
        guard let imagePoint = sceneConverter.genshinToImage(CGPoint(x: tpX, y: tpY)) else {
            throw BGIBigMapInteractionError.coordinateConversionFailed
        }
        let mapRect = estimatedInteractiveMapViewport()
        let clickX = mapRect.minX + (imagePoint.x / sceneConverter.imageSize.width) * mapRect.width
        let clickY = mapRect.minY + (imagePoint.y / sceneConverter.imageSize.height) * mapRect.height
        let clickPoint = CGPoint(
            x: max(mapRect.minX + 5, min(mapRect.maxX - 5, clickX)),
            y: max(mapRect.minY + 5, min(mapRect.maxY - 5, clickY))
        )
        await perform(.mouseClick(button: .left, at: clickPoint))
        try await sleep(config.teleportConfirmDelayMs)
        switch try await confirmTeleportIfAvailable() {
        case .clicked: break
        case .pointNotActivated: throw BGIBigMapInteractionError.teleportPointNotActivated
        case .notFound: try await keyPress(action: .pickUpOrInteract)
        }
        try await sleep(config.teleportConfirmDelayMs)
        _ = try await waitForTeleportCompletion()
    }

    /// Staged execution mode for teleport verification.
    enum BGITeleportExecutionMode {
        /// Compute the click point and return structured result; no mouse/keyboard.
        case calculateOnly
        /// Open map, zoom, drag, SIFT, move mouse cursor to target — no click.
        case moveCursor
        /// Click target map point, verify teleport UI appears — no confirm click.
        case selectPoint
        /// Full teleport: click target, click confirm, wait for completion.
        case fullTeleport
    }

    /// Returns structured teleport attempt data for verification.
    struct BGITeleportAttempt {
        let targetWorld: CGPoint
        let target256: CGPoint
        let visibleRect256: CGRect
        let viewportScreen: CGRect
        let clickPoint: CGPoint
        let queryKeypoints: UInt32
        let goodMatches: UInt32
        let inliers: UInt32
        let meanReprojectionError: Double
    }

    /// 选择提瓦特子地区（蒙德/璃月/稻妻...）。
    ///
    /// 计算目标传送点最近的国家中心，点击地图右下角地区选择按钮。
    /// 当前仅点击按钮，OCR 选择国家名待接入真实 OCR provider。
    private func selectMapRegion(_ country: String) async throws {
        guard let provider = captureFrameProvider else { return }
        let capture = try await provider()
        let scale = CGFloat(capture.cgImage.width) / 1920.0

        // 点击右下角地区选择按钮（上游: rect.Width - 160 * scale, rect.Height - 60 * scale）
        let buttonX = CGFloat(capture.cgImage.width) - 160 * scale
        let buttonY = CGFloat(capture.cgImage.height) - 60 * scale
        await perform(.mouseClick(button: .left, at: CGPoint(x: buttonX, y: buttonY)))
        try await sleep(400)
        print("selectMapRegion: clicked selector for \(country)")
    }
    ///
    /// Opens the map, adjusts zoom, drags via moveMapTo, re-acquires SIFT
    /// observation, computes the viewport-correct click point, and proceeds
    /// through stages controlled by `mode`.
    ///
    /// Unlike the legacy `teleport(tpX:tpY:)`, this method does NOT fall back
    /// to absolute-proportion click mapping — it requires a working SIFT
    /// observation provider.
    func teleportOnce(
        targetX: Double,
        targetY: Double,
        mapName: String = "Teyvat",
        mode: BGITeleportExecutionMode = .calculateOnly
    ) async throws -> BGITeleportAttempt {
        // 1. Open big map.
        try await openBigMap()

        // 2. Ensure supported map scene (Teyvat only for now).
        guard mapName.caseInsensitiveCompare("Teyvat") == .orderedSame else {
            throw BGIBigMapInteractionError.unsupportedMapScene(mapName)
        }

        // 3. Select map region for coarse positioning.
        let country = BGIWorldSceneAssets.closestCountry(toX: targetX, y: targetY)
        if let country {
            try await selectMapRegion(country)
        }

        // 4. Adjust zoom.
        if captureFrameProvider != nil, config.mapZoomEnabled {
            let currentZoom = try await currentBigMapZoomLevel()
            if abs(currentZoom - config.teleportPointZoomLevel) > config.mapZoomPrecisionThreshold {
                try await setBigMapZoomLevel(config.teleportPointZoomLevel)
            }
        }

        // 5. Drag map to bring target into visible area.
        guard let observationProvider else {
            throw BGIBigMapInteractionError.bigMapPositionProviderUnavailable
        }
        if bigMapPositionProvider != nil {
            try await moveMapTo(x: targetX, y: targetY, mapName: mapName, finalZoomLevel: config.teleportPointZoomLevel)
        }

        // 6. Re-acquire SIFT observation after drag.
        let observation = try await observationProvider(mapName)

        // 7. Quality gate.
        guard observation.goodMatches >= 10,
              observation.inliers >= 8,
              observation.meanReprojectionError < 3.0 else {
            throw BGIBigMapInteractionError.zoomLevelUnavailable
        }

        // 8. Target → 256-scale → screen click.
        guard let target2048 = sceneConverter.genshinToImage(CGPoint(x: targetX, y: targetY)) else {
            throw BGIBigMapInteractionError.coordinateConversionFailed
        }
        let target256 = CGPoint(x: target2048.x / 8.0, y: target2048.y / 8.0)
        let viewport = estimatedInteractiveMapViewport()

        // 9. Safety: target must be within visible rect.
        let safeVisible = observation.visibleRect256.insetBy(dx: observation.visibleRect256.width * 0.06, dy: observation.visibleRect256.height * 0.08)
        guard safeVisible.contains(target256) else {
            throw BGIBigMapInteractionError.targetOutsideVisibleMap(targetX, targetY)
        }

        // 9. Compute click, safety: must be within viewport.
        guard let clickPoint = Self.screenPoint(for: target256, visibleRect256: observation.visibleRect256, viewportScreen: viewport, safeInsetFraction: .zero) else {
            throw BGIBigMapInteractionError.targetOutsideVisibleMap(targetX, targetY)
        }
        let safeViewport = viewport.insetBy(dx: viewport.width * 0.04, dy: viewport.height * 0.06)
        guard safeViewport.contains(clickPoint) else {
            throw BGIBigMapInteractionError.targetOutsideVisibleMap(targetX, targetY)
        }

        let attempt = BGITeleportAttempt(
            targetWorld: CGPoint(x: targetX, y: targetY),
            target256: target256,
            visibleRect256: observation.visibleRect256,
            viewportScreen: viewport,
            clickPoint: clickPoint,
            queryKeypoints: observation.queryKeypoints,
            goodMatches: observation.goodMatches,
            inliers: observation.inliers,
            meanReprojectionError: observation.meanReprojectionError
        )

        // 10. Execute per mode.
        switch mode {
        case .calculateOnly:
            print("teleportOnce calculateOnly: target=(\(targetX),\(targetY)) click=(\(clickPoint.x),\(clickPoint.y)) inliers=\(observation.inliers)")
            return attempt

        case .moveCursor:
            await perform(.mouseMove(to: clickPoint))
            print("teleportOnce moveCursor: moved to (\(clickPoint.x),\(clickPoint.y))")
            return attempt

        case .selectPoint:
            await perform(.mouseClick(button: .left, at: clickPoint))
            try await sleep(config.teleportConfirmDelayMs)
            // Verify teleport UI appeared.
            switch try await confirmTeleportIfAvailable() {
            case .clicked, .notFound: break
            case .pointNotActivated: throw BGIBigMapInteractionError.teleportPointNotActivated
            }
            return attempt

        case .fullTeleport:
            await perform(.mouseClick(button: .left, at: clickPoint))
            try await sleep(config.teleportConfirmDelayMs)
            // Process candidate list if present, then click GoTeleport.
            switch try await confirmTeleportIfAvailable() {
            case .clicked: break
            case .pointNotActivated: throw BGIBigMapInteractionError.teleportPointNotActivated
            case .notFound: throw BGIBigMapInteractionError.teleportPointNotActivated
            }
            try await sleep(config.teleportConfirmDelayMs)
            _ = try await waitForTeleportCompletion()
            return attempt
        }
    }
    func teleport(tpX: Double, tpY: Double, mapName: String = "Teyvat", force: Bool = false) async throws {
        let targetX: Double
        let targetY: Double
        if force {
            targetX = tpX
            targetY = tpY
        } else {
            let points = BGIWorldSceneAssets.nearestTeleportPoints(toX: tpX, y: tpY, mapName: mapName, n: 2)
            guard let nearest = points.first else {
                throw BGIBigMapInteractionError.teleportPointNotActivated
            }
            targetX = nearest.x
            targetY = nearest.y
        }
        try await teleport(tpX: targetX, tpY: targetY)
    }

    /// 上游 `TpTask.TpToStatueOfTheSeven`: 找到最近七天神像并传送过去。
    func teleportToStatueOfTheSeven(mapName: String = "Teyvat") async throws {
        guard let provider = bigMapPositionProvider else {
            throw BGIBigMapInteractionError.bigMapPositionProviderUnavailable
        }
        let center = try await provider(mapName)
        guard let goddess = BGIWorldSceneAssets.nearestGoddess(toX: center.x, y: center.y, mapName: mapName) else {
            throw BGIBigMapInteractionError.teleportPointNotActivated
        }
        try await teleport(tpX: goddess.x, tpY: goddess.y)
    }

    /// Open the big map UI.
    ///
    /// Mirrors upstream `TpTask.TryToOpenBigMapUi`: first capture and check
    /// `Bv.IsInBigMapUi`; only press the map hotkey when the map is not already
    /// open, then retry verification a few times.
    func openBigMap() async throws {
        guard captureFrameProvider != nil else {
            await perform(.releaseAll)
            try await sleep(config.openMapPrepareMs)
            try await keyPress(action: .openMap)
            try await sleep(config.openMapWaitMs)
            return
        }

        if try await isInBigMapUI() {
            return
        }

        await perform(.releaseAll)
        try await sleep(config.openMapPrepareMs)
        try await keyPress(action: .openMap)
        try await sleep(config.openMapWaitMs)

        for attempt in 0..<max(1, config.openMapCheckRetries) {
            if try await isInBigMapUI() {
                return
            }
            if attempt < config.openMapCheckRetries - 1 {
                try await sleep(config.openMapRetryWaitMs)
            }
        }

        throw BGIBigMapInteractionError.notInBigMap
    }

    /// Return upstream-compatible big-map zoom level.
    ///
    /// `BGIGameUIStatusRecognizer` exposes the raw slider fraction used by
    /// upstream `Bv.GetBigMapScale`. `TpTask.GetBigMapZoomLevel` converts it
    /// with `(-5 * scale) + 6`, so script-facing callers see 1.0...6.0.
    func currentBigMapZoomLevel() async throws -> Double {
        guard let captureFrameProvider else {
            throw BGIBigMapInteractionError.captureProviderUnavailable
        }
        let frame = try await captureFrameProvider()
        let status = statusRecognizer.recognize(frame)
        guard status.isInBigMapUI, let scale = status.bigMapScaleFraction else {
            throw BGIBigMapInteractionError.zoomLevelUnavailable
        }
        return Self.zoomLevel(fromScaleFraction: scale)
    }

    /// Drag the big-map zoom slider using upstream `TpTask.AdjustMapZoomLevel`
    /// coordinates.
    func setBigMapZoomLevel(_ targetZoomLevel: Double) async throws {
        try await openBigMap()
        let currentZoomLevel = try await currentBigMapZoomLevel()
        let startPoint = zoomSliderPoint(for: currentZoomLevel)
        let endPoint = zoomSliderPoint(for: targetZoomLevel)
        await perform(.mouseMove(to: startPoint))
        await perform(.mouseButtonDown(button: .left, at: startPoint))
        await perform(.mouseMove(to: endPoint))
        await perform(.mouseButtonUp(button: .left, at: endPoint))
        try await sleep(config.mapZoomAdjustWaitMs)
    }

    /// Move the currently open big map so its center approaches the target
    /// genshin-map coordinates.
    ///
    /// This mirrors the coordinate/zoom/drag loop of upstream
    /// `TpTask.MoveMapTo`.  The actual center recognition is injected through
    /// `BigMapPositionProvider`; once OpenCV/SIFT big-map localization is
    /// ported, that provider should wrap the upstream-equivalent
    /// `GetPositionFromBigMap` implementation.
    func moveMapTo(
        x targetX: Double,
        y targetY: Double,
        mapName: String = "Teyvat",
        finalZoomLevel: Double = 2.0
    ) async throws {
        guard bigMapPositionProvider != nil else {
            throw BGIBigMapInteractionError.bigMapPositionProviderUnavailable
        }

        try await openBigMap()
        var currentZoomLevel = try await currentBigMapZoomLevel()
        var exceptionTimes = 0
        var center = try await currentBigMapCenter(mapName: mapName)
        let minZoomLevel = min(finalZoomLevel, config.minZoomLevel)
        let maxZoomLevel = config.maxZoomLevel

        var movement = mapMovement(targetX: targetX, targetY: targetY, center: center, zoomLevel: currentZoomLevel)
        if config.mapZoomEnabled, movement.mouseDistance > config.mapZoomOutDistance {
            let targetZoomLevel = min(currentZoomLevel * movement.mouseDistance / config.mapZoomOutDistance, maxZoomLevel)
            try await setBigMapZoomLevel(targetZoomLevel)
            let nextZoomLevel = try await currentBigMapZoomLevel()
            movement = movement.rescaled(fromZoomLevel: currentZoomLevel, toZoomLevel: nextZoomLevel)
            currentZoomLevel = nextZoomLevel
        }

        for _ in 0..<max(1, config.mapMoveMaxIterations) {
            if config.mapZoomEnabled,
               movement.mouseDistance < config.mapZoomInDistance {
                let targetZoomLevel = max(currentZoomLevel * movement.mouseDistance / config.mapZoomInDistance, minZoomLevel)
                if currentZoomLevel > minZoomLevel + config.mapZoomPrecisionThreshold {
                    try await setBigMapZoomLevel(targetZoomLevel)
                    let nextZoomLevel = try await currentBigMapZoomLevel()
                    movement = movement.rescaled(fromZoomLevel: currentZoomLevel, toZoomLevel: nextZoomLevel)
                    currentZoomLevel = nextZoomLevel
                }
            }

            if movement.mouseDistance < config.mapMoveTolerance {
                break
            }

            let drag = movement.drag(maxMouseMove: config.mapMoveMaxMouseMove)
            try await mouseMoveMap(pixelDeltaX: drag.x, pixelDeltaY: drag.y, steps: drag.steps)

            let predicted = CGPoint(
                x: center.x + Double(drag.x) * currentZoomLevel / config.mapScaleFactor,
                y: center.y + Double(drag.y) * currentZoomLevel / config.mapScaleFactor
            )

            do {
                let newCenter = try await currentBigMapCenter(mapName: mapName)
                let jumpDistance = hypot(newCenter.x - predicted.x, newCenter.y - predicted.y)
                let expectedMoveLength = hypot(Double(drag.x), Double(drag.y)) * currentZoomLevel / config.mapScaleFactor
                if jumpDistance > max(200, expectedMoveLength * 2) {
                    throw BGIBigMapInteractionError.bigMapPositionUnavailable
                }
                center = newCenter
                exceptionTimes = 0
            } catch {
                exceptionTimes += 1
                guard exceptionTimes <= 5 else {
                    throw BGIBigMapInteractionError.bigMapMoveFailed
                }
                center = predicted
            }

            movement = mapMovement(targetX: targetX, targetY: targetY, center: center, zoomLevel: currentZoomLevel)
        }
    }

    static func zoomLevel(fromScaleFraction fraction: Double) -> Double {
        (-5.0 * fraction) + 6.0
    }

    static func mapMoveSteps(delta: Int, steps: Int) -> [Int] {
        let safeSteps = max(1, steps)
        var factors = [Double](repeating: 0, count: safeSteps)
        var sum = 0.0
        for i in 0..<safeSteps {
            factors[i] = cos(Double(i) * .pi / Double(2 * safeSteps))
            sum += factors[i]
        }

        var result = [Int](repeating: 0, count: safeSteps)
        var remaining = delta
        for i in 0..<safeSteps {
            let ratio = factors[i] / sum
            result[i] = Int(Double(delta) * ratio)
            remaining -= result[i]
        }

        let center = safeSteps / 2
        for r in 0..<abs(remaining) {
            let target = (center + r) % safeSteps
            result[target] += remaining > 0 ? 1 : -1
        }
        return result
    }

    // MARK: - Helpers

    private func keyPress(action: GIAction) async throws {
        guard let ia = keyBindings.inputAction(for: action, type: .keyPress) else {
            return
        }
        await perform(ia)
    }

    private func perform(_ action: InputAction) async {
        _ = await inputHandler(action)
    }

    /// Estimate the on-screen interactive map viewport area.
    ///
    /// This is the clickable region within the game window, NOT upstream
    /// `GetBigMapRect` which returns a rect in full-map image coordinates.
    /// Uses known UI anchor positions: MapScaleButton at left edge (~60px margin),
    /// bottom UID/button bar (~8% of height).
    ///
    /// Named `estimatedInteractiveMapViewport` to avoid confusion with
    /// upstream's full-map coordinate rect.
    private func estimatedInteractiveMapViewport() -> CGRect {
        let captureRect = config.captureRect
        let margin = max(30, captureRect.width * 0.06) // ~60px at 960w, ~115px at 1920w
        let bottomMargin = max(30, captureRect.height * 0.08)

        return CGRect(
            x: captureRect.minX + margin,           // skip scale button column
            y: captureRect.minY,                      // top edge
            width: captureRect.width - margin * 2,    // skip right-side zoom indicator
            height: captureRect.height - bottomMargin // skip bottom UID/button bar
        )
    }

    private func isInBigMapUI() async throws -> Bool {
        guard let captureFrameProvider else { return false }
        let frame = try await captureFrameProvider()
        return statusRecognizer.recognize(frame).isInBigMapUI
    }

    private func currentBigMapCenter(mapName: String) async throws -> CGPoint {
        guard let bigMapPositionProvider else {
            throw BGIBigMapInteractionError.bigMapPositionProviderUnavailable
        }
        return try await bigMapPositionProvider(mapName)
    }

    private func waitForTeleportCompletion() async throws -> Bool {
        try await sleep(config.teleportLoadWaitMs)
        guard let captureFrameProvider else { return true }

        for attempt in 0..<max(1, config.maxTeleportWaitAttempts) {
            let frame = try await captureFrameProvider()
            if try await mainUIStatusChecker.isInMainUI(frame: frame) {
                return true
            }

            let report = templateRecognitionEngine.recognize(
                imageFrame: frame,
                objects: RecognitionObject.bgiQuickTeleportTeleportObjects
            )
            _ = await clickTeleportButton(in: report)

            if attempt < config.maxTeleportWaitAttempts - 1 {
                try await sleep(config.teleportLoadWaitMs)
            }
        }

        return false
    }

    private func confirmTeleportIfAvailable() async throws -> BGITeleportConfirmationResult {
        guard let captureFrameProvider else { return .notFound }
        let frame = try await captureFrameProvider()
        let report = templateRecognitionEngine.recognize(
            imageFrame: frame,
            objects: RecognitionObject.bgiQuickTeleportTeleportObjects
        )
        if await clickTeleportButton(in: report) {
            return .clicked
        }
        if report.observations.contains(where: { $0.objectID == "QuickTeleport.MapCloseButtonRo" }) {
            return .pointNotActivated
        }
        if try await clickMapChooseOptionIfAvailable(in: frame) {
            for attempt in 0..<max(1, config.teleportButtonAppearRetries) {
                if attempt > 0 {
                    try await sleep(config.teleportButtonAppearRetryMs)
                }
                if try await confirmTeleportButtonOnly() {
                    try await waitForTeleportButtonDisappear()
                    return .clicked
                }
            }
            return .pointNotActivated
        }
        return .notFound
    }

    private func confirmTeleportButtonOnly() async throws -> Bool {
        guard let captureFrameProvider else { return false }
        let frame = try await captureFrameProvider()
        let report = templateRecognitionEngine.recognize(
            imageFrame: frame,
            objects: RecognitionObject.bgiQuickTeleportTeleportObjects
        )
        return await clickTeleportButton(in: report)
    }

    @discardableResult
    private func waitForTeleportButtonDisappear() async throws -> Bool {
        guard let captureFrameProvider else { return false }
        for attempt in 0..<max(1, config.teleportButtonDisappearRetries) {
            let frame = try await captureFrameProvider()
            let report = templateRecognitionEngine.recognize(
                imageFrame: frame,
                objects: RecognitionObject.bgiQuickTeleportTeleportObjects
            )
            if !(await clickTeleportButton(in: report)) {
                return true
            }
            if attempt < config.teleportButtonDisappearRetries - 1 {
                try await sleep(config.teleportButtonDisappearRetryMs)
            }
        }
        return false
    }

    private func clickTeleportButton(in report: TemplateRecognitionReport) async -> Bool {
        guard let observation = report.observations.first(where: { $0.objectID == "QuickTeleport.TeleportButtonRo" }) else {
            return false
        }
        await perform(.mouseClick(button: .left, at: screenPoint(for: observation.normalizedRect)))
        return true
    }

    private func clickMapChooseOptionIfAvailable(in frame: CaptureImageFrame) async throws -> Bool {
        let report = templateRecognitionEngine.recognize(
            imageFrame: frame,
            objects: RecognitionObject.bgiQuickTeleportMapChooseIconObjects
        )
        let observations = report.observations.sorted(by: { lhs, rhs in
            if lhs.normalizedRect.minY != rhs.normalizedRect.minY {
                return lhs.normalizedRect.minY < rhs.normalizedRect.minY
            }
            return lhs.normalizedRect.minX < rhs.normalizedRect.minX
        })

        for observation in observations {
            guard try await mapChooseOptionHasUsefulText(observation: observation, frame: frame) else {
                continue
            }

            try await sleep(max(500, config.teleportListClickDelayMs))
            await perform(.mouseClick(button: .left, at: mapChooseOptionTextPoint(for: observation)))
            return true
        }

        return false
    }

    private func mapChooseOptionHasUsefulText(
        observation: RecognitionObservation,
        frame: CaptureImageFrame
    ) async throws -> Bool {
        guard let recognitionObjectProvider else { return true }
        let object = mapChooseOptionTextObject(for: observation)
        let observations: [RecognitionObservation]
        do {
            observations = try await recognitionObjectProvider(frame, object)
        } catch {
            return true
        }
        let usefulText = observations
            .compactMap(\.text)
            .map { $0.replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0.count > 1 }
        return usefulText != nil
    }

    private func mapChooseOptionTextObject(for observation: RecognitionObservation) -> RecognitionObject {
        let normalizedRect = mapChooseOptionTextNormalizedRect(for: observation)
        return RecognitionObject(
            id: "QuickTeleport.MapChooseOptionText",
            recognitionType: .colorRangeAndOcr,
            regionOfInterest: RecognitionROI(
                x: normalizedRect.minX,
                y: normalizedRect.minY,
                width: normalizedRect.width,
                height: normalizedRect.height,
                coordinateSpace: .normalized
            ),
            name: "MapChooseOptionText",
            colorConversionCode: 4,
            lowerColor: BGIColorScalar(b: 249, g: 249, r: 249, a: 255),
            upperColor: BGIColorScalar(b: 255, g: 255, r: 255, a: 255),
            featureID: "quick-teleport",
            tags: ["QuickTeleport", "MapChooseIcon", "Text"]
        )
    }

    private func mapChooseOptionTextNormalizedRect(for observation: RecognitionObservation) -> CGRect {
        let raw = CGRect(
            x: observation.normalizedRect.maxX,
            y: observation.normalizedRect.minY - 8.0 / 1080.0,
            width: 200.0 / 1920.0,
            height: observation.normalizedRect.height + 16.0 / 1080.0
        )
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        return raw.intersection(full)
    }

    private func mapChooseOptionTextPoint(for observation: RecognitionObservation) -> CGPoint {
        let rect = config.captureRect
        let textRect = mapChooseOptionTextNormalizedRect(for: observation)
        return CGPoint(
            x: rect.minX + textRect.midX * rect.width,
            y: rect.minY + textRect.midY * rect.height
        )
    }

    private func screenPoint(for normalizedRect: CGRect) -> CGPoint {
        let rect = config.captureRect
        return CGPoint(
            x: rect.minX + normalizedRect.midX * rect.width,
            y: rect.minY + normalizedRect.midY * rect.height
        )
    }

    private func mouseMoveMap(pixelDeltaX: Int, pixelDeltaY: Int, steps: Int = 10) async throws {
        let dpi = max(config.screenDpiScale, 0.0001)
        let stepX = Self.mapMoveSteps(delta: Int(Double(pixelDeltaX) / dpi), steps: steps)
        let stepY = Self.mapMoveSteps(delta: Int(Double(pixelDeltaY) / dpi), steps: steps)
        var point = mapMoveStartPoint()
        await perform(.mouseMove(to: point))
        await perform(.mouseButtonDown(button: .left, at: point))

        for i in 0..<max(stepX.count, stepY.count) {
            if i > 0 || config.mapMoveStepIntervalMs > 0 {
                try await sleep(config.mapMoveStepIntervalMs)
            }
            let dx = i < stepX.count ? stepX[i] : 0
            let dy = i < stepY.count ? stepY[i] : 0
            point = point.applying(CGAffineTransform(
                translationX: CGFloat(dx) * config.captureRect.width / 1_920.0,
                y: CGFloat(dy) * config.captureRect.height / 1_080.0
            ))
            await perform(.mouseMove(to: point))
        }

        await perform(.mouseButtonUp(button: .left, at: point))
    }

    private func mapMoveStartPoint() -> CGPoint {
        CGPoint(x: config.captureRect.midX, y: config.captureRect.midY)
    }

    private func mapMovement(
        targetX: Double,
        targetY: Double,
        center: CGPoint,
        zoomLevel: Double
    ) -> BGIBigMapMovement {
        let xOffset = targetX - center.x
        let yOffset = targetY - center.y
        let totalMoveMouseX = config.mapScaleFactor * abs(xOffset) / zoomLevel
        let totalMoveMouseY = config.mapScaleFactor * abs(yOffset) / zoomLevel
        return BGIBigMapMovement(
            xOffset: xOffset,
            yOffset: yOffset,
            totalMoveMouseX: totalMoveMouseX,
            totalMoveMouseY: totalMoveMouseY
        )
    }

    private func zoomSliderPoint(for zoomLevel: Double) -> CGPoint {
        let y1080 = config.zoomStartY + (config.zoomEndY - config.zoomStartY) * (zoomLevel - 1.0) / 5.0
        return gamePoint(x: config.zoomButtonX, y: y1080)
    }

    private func gamePoint(x: Double, y: Double) -> CGPoint {
        let rect = config.captureRect
        return CGPoint(
            x: rect.minX + CGFloat(x / 1_920.0) * rect.width,
            y: rect.minY + CGFloat(y / 1_080.0) * rect.height
        )
    }

    private func sleep(_ ms: UInt64) async throws {
        try await Task.sleep(nanoseconds: ms * 1_000_000)
    }

    // MARK: - Viewport Click Math

    /// Map a target point in 256-scale full-map texture coordinates to a screen
    /// click point within the visible viewport.
    ///
    /// Formula: `(target - visibleRect.origin) / visibleRect.size * viewport.size + viewport.origin`
    ///
    /// Returns `nil` if the target is outside the visible rect's safe inset area,
    /// or if any rect has zero width/height.
    static func screenPoint(
        for target256: CGPoint,
        visibleRect256: CGRect,
        viewportScreen: CGRect,
        safeInsetFraction: CGSize = CGSize(width: 0.06, height: 0.08)
    ) -> CGPoint? {
        guard visibleRect256.width > 0, visibleRect256.height > 0,
              viewportScreen.width > 0, viewportScreen.height > 0 else { return nil }
        let safeRect = visibleRect256.insetBy(
            dx: visibleRect256.width * safeInsetFraction.width,
            dy: visibleRect256.height * safeInsetFraction.height
        )
        guard safeRect.contains(target256) else { return nil }
        let u = (target256.x - visibleRect256.minX) / visibleRect256.width
        let v = (target256.y - visibleRect256.minY) / visibleRect256.height
        return CGPoint(
            x: viewportScreen.minX + u * viewportScreen.width,
            y: viewportScreen.minY + v * viewportScreen.height
        )
    }
}
