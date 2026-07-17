import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI big map interaction service")
struct BGIBigMapInteractionServiceTests {
    @Test("Big map config derives capture rect from target window")
    func bigMapConfigDerivesCaptureRectFromTargetWindow() {
        let window = WindowInfo(
            id: 42,
            ownerPID: 100,
            ownerName: "wine64-preloader",
            title: "原神",
            frame: CGRect(x: 120, y: 80, width: 1280, height: 720),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 2
        )

        let config = BGIBigMapConfig.forWindow(window)

        #expect(config.captureRect == window.captureRect)
    }

    @Test("Teleport click maps into target window capture rect")
    @MainActor
    func teleportClickMapsIntoTargetWindowCaptureRect() async throws {
        var actions: [InputAction] = []
        let config = BGIBigMapConfig(
            captureRect: CGRect(x: 100, y: 200, width: 1280, height: 720),
            openMapPrepareMs: 0,
            openMapWaitMs: 0,
            teleportConfirmDelayMs: 0,
            teleportLoadWaitMs: 0
        )
        let sceneConverter = BGISceneMapCoordinateConverter(
            mapOriginInImage: CGPoint(x: 1000, y: 1000),
            imageBlockWidthScale: 1,
            imageSize: CGSize(width: 1000, height: 1000)
        )
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            keyBindings: .bgiDefault,
            config: config,
            sceneConverter: sceneConverter
        )

        try await service.teleport(tpX: 500, tpY: 500)

        let clickPoints = actions.compactMap { action -> CGPoint? in
            if case let .mouseClick(.left, point) = action {
                return point
            }
            return nil
        }
        let point = try #require(clickPoints.first)

        #expect(point.x >= 730 && point.x <= 750)
        #expect(point.y >= 520 && point.y <= 570)
        #expect(config.captureRect.contains(point))
    }

    @Test("Teleport confirms by clicking GoTeleport button when visible")
    @MainActor
    func teleportConfirmsByClickingGoTeleportButtonWhenVisible() async throws {
        var actions: [InputAction] = []
        var frames = [
            try makeBigMapStatusFrame(),
            try makeTeleportButtonFrame(),
            try makeMainUIFrame()
        ]
        let config = BGIBigMapConfig(
            captureRect: CGRect(x: 0, y: 0, width: 960, height: 540),
            openMapPrepareMs: 0,
            openMapWaitMs: 0,
            teleportConfirmDelayMs: 0,
            teleportLoadWaitMs: 0
        )
        let sceneConverter = BGISceneMapCoordinateConverter(
            mapOriginInImage: CGPoint(x: 1000, y: 1000),
            imageBlockWidthScale: 1,
            imageSize: CGSize(width: 1000, height: 1000)
        )
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: {
                frames.isEmpty ? try makeBlankFrame() : frames.removeFirst()
            },
            config: config,
            sceneConverter: sceneConverter
        )

        try await service.teleport(tpX: 500, tpY: 500)

        let leftClicks = actions.compactMap { action -> CGPoint? in
            if case let .mouseClick(.left, point) = action {
                return point
            }
            return nil
        }
        #expect(leftClicks.count == 2)
        #expect(leftClicks[0].x >= 470 && leftClicks[0].x <= 490)
        #expect(leftClicks[0].y >= 240 && leftClicks[0].y <= 280)
        #expect(leftClicks[1].x > 720)
        #expect(leftClicks[1].y > 480)
        #expect(!actions.contains(.keyPress(key: .f)))
    }

    @Test("Teleport completion ignores revive prompt even when Paimon menu is visible")
    @MainActor
    func teleportCompletionIgnoresRevivePromptEvenWhenPaimonMenuIsVisible() async throws {
        var actions: [InputAction] = []
        var reviveOCRRequests = 0
        var frames = [
            try makeBigMapStatusFrame(),
            try makeTeleportButtonFrame(),
            try makeRevivePromptFrame(),
            try makeMainUIFrame()
        ]
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: {
                frames.isEmpty ? try makeBlankFrame() : frames.removeFirst()
            },
            recognitionObjectProvider: { frame, object in
                guard object.id == "Common.BvStatus.RevivePromptText" else {
                    return []
                }
                reviveOCRRequests += 1
                let roi = object.regionOfInterest?.normalizedRect() ?? .zero
                #expect(roi == CGRect(x: 0, y: 0, width: 1, height: 0.5))
                return [
                    RecognitionObservation(
                        id: "\(object.id)-\(frame.metadata.frameIndex)",
                        objectID: object.id,
                        objectName: object.name ?? object.id,
                        recognitionType: object.recognitionType,
                        normalizedRect: roi,
                        confidence: 0.92,
                        text: "复苏",
                        frameIndex: frame.metadata.frameIndex,
                        timestamp: frame.metadata.timestamp
                    )
                ]
            },
            config: BGIBigMapConfig(
                captureRect: CGRect(x: 0, y: 0, width: 960, height: 540),
                openMapPrepareMs: 0,
                openMapWaitMs: 0,
                teleportConfirmDelayMs: 0,
                teleportLoadWaitMs: 0,
                maxTeleportWaitAttempts: 2
            ),
            sceneConverter: BGISceneMapCoordinateConverter(
                mapOriginInImage: CGPoint(x: 1000, y: 1000),
                imageBlockWidthScale: 1,
                imageSize: CGSize(width: 1000, height: 1000)
            )
        )

        try await service.teleport(tpX: 500, tpY: 500)

        let leftClicks = actions.compactMap { action -> CGPoint? in
            if case let .mouseClick(.left, point) = action {
                return point
            }
            return nil
        }
        #expect(reviveOCRRequests == 1)
        #expect(leftClicks.count == 2)
        #expect(leftClicks[0].x >= 470 && leftClicks[0].x <= 490)
        #expect(leftClicks[0].y >= 240 && leftClicks[0].y <= 280)
        #expect(leftClicks[1].x > 720)
        #expect(leftClicks[1].y > 480)
        #expect(!actions.contains(.keyPress(key: .f)))
    }

    @Test("Teleport fails as not activated when map close button appears without GoTeleport")
    @MainActor
    func teleportFailsAsNotActivatedWhenMapCloseButtonAppearsWithoutGoTeleport() async throws {
        var actions: [InputAction] = []
        var frames = [
            try makeBigMapStatusFrame(),
            try makeMapCloseButtonFrame()
        ]
        let config = BGIBigMapConfig(
            captureRect: CGRect(x: 0, y: 0, width: 960, height: 540),
            openMapPrepareMs: 0,
            openMapWaitMs: 0,
            teleportConfirmDelayMs: 0,
            teleportLoadWaitMs: 0
        )
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: {
                frames.isEmpty ? try makeMapCloseButtonFrame() : frames.removeFirst()
            },
            config: config,
            sceneConverter: BGISceneMapCoordinateConverter(
                mapOriginInImage: CGPoint(x: 1000, y: 1000),
                imageBlockWidthScale: 1,
                imageSize: CGSize(width: 1000, height: 1000)
            )
        )

        await #expect(throws: BGIBigMapInteractionError.teleportPointNotActivated) {
            try await service.teleport(tpX: 500, tpY: 500)
        }
        #expect(!actions.contains(.keyPress(key: .f)))
    }

    @Test("Teleport selects map choice row before clicking GoTeleport")
    @MainActor
    func teleportSelectsMapChoiceRowBeforeClickingGoTeleport() async throws {
        var actions: [InputAction] = []
        var frames = [
            try makeBigMapStatusFrame(),
            try makeMapChooseIconFrame(),
            try makeTeleportButtonFrame(),
            try makeBlankFrame(),
            try makeMainUIFrame()
        ]
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: {
                frames.isEmpty ? try makeBlankFrame() : frames.removeFirst()
            },
            config: BGIBigMapConfig(
                captureRect: CGRect(x: 0, y: 0, width: 960, height: 540),
                openMapPrepareMs: 0,
                openMapWaitMs: 0,
                teleportConfirmDelayMs: 0,
                teleportLoadWaitMs: 0,
                teleportListClickDelayMs: 0,
                teleportButtonAppearRetryMs: 0
            ),
            sceneConverter: BGISceneMapCoordinateConverter(
                mapOriginInImage: CGPoint(x: 1000, y: 1000),
                imageBlockWidthScale: 1,
                imageSize: CGSize(width: 1000, height: 1000)
            )
        )

        try await service.teleport(tpX: 500, tpY: 500)

        let leftClicks = actions.compactMap { action -> CGPoint? in
            if case let .mouseClick(.left, point) = action {
                return point
            }
            return nil
        }
        #expect(leftClicks.count == 3)
        #expect(leftClicks[0].x >= 470 && leftClicks[0].x <= 490)
        #expect(leftClicks[0].y >= 240 && leftClicks[0].y <= 280)
        #expect(leftClicks[1].x > 660)
        #expect(leftClicks[1].y < 120)
        #expect(leftClicks[2].x > 720)
        #expect(leftClicks[2].y > 480)
        #expect(!actions.contains(.keyPress(key: .f)))
    }

    @Test("Teleport retries GoTeleport click until button disappears after map choice")
    @MainActor
    func teleportRetriesGoTeleportClickUntilButtonDisappearsAfterMapChoice() async throws {
        var actions: [InputAction] = []
        var frames = [
            try makeBigMapStatusFrame(),
            try makeMapChooseIconFrame(),
            try makeTeleportButtonFrame(),
            try makeTeleportButtonFrame(),
            try makeBlankFrame(),
            try makeMainUIFrame()
        ]
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: {
                frames.isEmpty ? try makeBlankFrame() : frames.removeFirst()
            },
            config: BGIBigMapConfig(
                captureRect: CGRect(x: 0, y: 0, width: 960, height: 540),
                openMapPrepareMs: 0,
                openMapWaitMs: 0,
                teleportConfirmDelayMs: 0,
                teleportLoadWaitMs: 0,
                teleportListClickDelayMs: 0,
                teleportButtonAppearRetryMs: 0,
                teleportButtonDisappearRetryMs: 0
            ),
            sceneConverter: BGISceneMapCoordinateConverter(
                mapOriginInImage: CGPoint(x: 1000, y: 1000),
                imageBlockWidthScale: 1,
                imageSize: CGSize(width: 1000, height: 1000)
            )
        )

        try await service.teleport(tpX: 500, tpY: 500)

        let leftClicks = actions.compactMap { action -> CGPoint? in
            if case let .mouseClick(.left, point) = action {
                return point
            }
            return nil
        }
        let teleportButtonClicks = leftClicks.filter { $0.x > 720 && $0.y > 480 }
        #expect(leftClicks.count == 4)
        #expect(teleportButtonClicks.count == 2)
        #expect(!actions.contains(.keyPress(key: .f)))
    }

    @Test("Teleport skips map choice rows without useful OCR text")
    @MainActor
    func teleportSkipsMapChoiceRowsWithoutUsefulOCRText() async throws {
        var actions: [InputAction] = []
        var requestedTextROIs: [CGRect] = []
        var frames = [
            try makeBigMapStatusFrame(),
            try makeMapChooseIconFrame(icons: [
                ("TeleportWaypoint.png", CGPoint(x: 636, y: 52)),
                ("StatueOfTheSeven.png", CGPoint(x: 636, y: 140))
            ]),
            try makeTeleportButtonFrame(),
            try makeBlankFrame(),
            try makeMainUIFrame()
        ]
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: {
                frames.isEmpty ? try makeBlankFrame() : frames.removeFirst()
            },
            recognitionObjectProvider: { frame, object in
                let roi = object.regionOfInterest?.normalizedRect() ?? .zero
                requestedTextROIs.append(roi)
                let text = roi.midY < 0.16 ? "锚" : "传送锚点"
                return [
                    RecognitionObservation(
                        id: "\(object.id)-\(frame.metadata.frameIndex)",
                        objectID: object.id,
                        objectName: object.name ?? object.id,
                        recognitionType: object.recognitionType,
                        normalizedRect: roi,
                        confidence: 0.9,
                        text: text,
                        frameIndex: frame.metadata.frameIndex,
                        timestamp: frame.metadata.timestamp
                    )
                ]
            },
            config: BGIBigMapConfig(
                captureRect: CGRect(x: 0, y: 0, width: 960, height: 540),
                openMapPrepareMs: 0,
                openMapWaitMs: 0,
                teleportConfirmDelayMs: 0,
                teleportLoadWaitMs: 0,
                teleportListClickDelayMs: 0,
                teleportButtonAppearRetryMs: 0,
                teleportButtonDisappearRetryMs: 0
            ),
            sceneConverter: BGISceneMapCoordinateConverter(
                mapOriginInImage: CGPoint(x: 1000, y: 1000),
                imageBlockWidthScale: 1,
                imageSize: CGSize(width: 1000, height: 1000)
            )
        )

        try await service.teleport(tpX: 500, tpY: 500)

        let leftClicks = actions.compactMap { action -> CGPoint? in
            if case let .mouseClick(.left, point) = action {
                return point
            }
            return nil
        }
        #expect(requestedTextROIs.contains { $0.midY < 0.16 })
        #expect(requestedTextROIs.contains { $0.midY > 0.16 })
        #expect(leftClicks.count == 3)
        #expect(leftClicks[1].x > 660)
        #expect(leftClicks[1].y > 130)
        #expect(leftClicks[2].x > 720)
        #expect(leftClicks[2].y > 480)
        #expect(!actions.contains(.keyPress(key: .f)))
    }

    @Test("Teleport scans multiple rows with the same map choice icon")
    @MainActor
    func teleportScansMultipleRowsWithSameMapChoiceIcon() async throws {
        var actions: [InputAction] = []
        var requestedTextROIs: [CGRect] = []
        var frames = [
            try makeBigMapStatusFrame(),
            try makeMapChooseIconFrame(icons: [
                ("TeleportWaypoint.png", CGPoint(x: 636, y: 52)),
                ("TeleportWaypoint.png", CGPoint(x: 636, y: 140))
            ]),
            try makeTeleportButtonFrame(),
            try makeBlankFrame(),
            try makeMainUIFrame()
        ]
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: {
                frames.isEmpty ? try makeBlankFrame() : frames.removeFirst()
            },
            recognitionObjectProvider: { frame, object in
                let roi = object.regionOfInterest?.normalizedRect() ?? .zero
                requestedTextROIs.append(roi)
                let text = roi.midY < 0.16 ? "锚" : "传送锚点"
                return [
                    RecognitionObservation(
                        id: "\(object.id)-\(frame.metadata.frameIndex)",
                        objectID: object.id,
                        objectName: object.name ?? object.id,
                        recognitionType: object.recognitionType,
                        normalizedRect: roi,
                        confidence: 0.9,
                        text: text,
                        frameIndex: frame.metadata.frameIndex,
                        timestamp: frame.metadata.timestamp
                    )
                ]
            },
            config: BGIBigMapConfig(
                captureRect: CGRect(x: 0, y: 0, width: 960, height: 540),
                openMapPrepareMs: 0,
                openMapWaitMs: 0,
                teleportConfirmDelayMs: 0,
                teleportLoadWaitMs: 0,
                teleportListClickDelayMs: 0,
                teleportButtonAppearRetryMs: 0,
                teleportButtonDisappearRetryMs: 0
            ),
            sceneConverter: BGISceneMapCoordinateConverter(
                mapOriginInImage: CGPoint(x: 1000, y: 1000),
                imageBlockWidthScale: 1,
                imageSize: CGSize(width: 1000, height: 1000)
            )
        )

        try await service.teleport(tpX: 500, tpY: 500)

        let leftClicks = actions.compactMap { action -> CGPoint? in
            if case let .mouseClick(.left, point) = action {
                return point
            }
            return nil
        }
        #expect(requestedTextROIs.contains { $0.midY < 0.16 })
        #expect(requestedTextROIs.contains { $0.midY > 0.16 })
        #expect(leftClicks.count == 3)
        #expect(leftClicks[1].x > 660)
        #expect(leftClicks[1].y > 130)
        #expect(leftClicks[2].x > 720)
        #expect(leftClicks[2].y > 480)
        #expect(!actions.contains(.keyPress(key: .f)))
    }

    @Test("Teleport fails when map choice row never produces GoTeleport")
    @MainActor
    func teleportFailsWhenMapChoiceRowNeverProducesGoTeleport() async throws {
        var actions: [InputAction] = []
        var frames = [
            try makeBigMapStatusFrame(),
            try makeMapChooseIconFrame(),
            try makeBlankFrame(),
            try makeBlankFrame()
        ]
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: {
                frames.isEmpty ? try makeBlankFrame() : frames.removeFirst()
            },
            config: BGIBigMapConfig(
                captureRect: CGRect(x: 0, y: 0, width: 960, height: 540),
                openMapPrepareMs: 0,
                openMapWaitMs: 0,
                teleportConfirmDelayMs: 0,
                teleportLoadWaitMs: 0,
                teleportListClickDelayMs: 0,
                teleportButtonAppearRetries: 2,
                teleportButtonAppearRetryMs: 0
            ),
            sceneConverter: BGISceneMapCoordinateConverter(
                mapOriginInImage: CGPoint(x: 1000, y: 1000),
                imageBlockWidthScale: 1,
                imageSize: CGSize(width: 1000, height: 1000)
            )
        )

        await #expect(throws: BGIBigMapInteractionError.teleportPointNotActivated) {
            try await service.teleport(tpX: 500, tpY: 500)
        }
        #expect(!actions.contains(.keyPress(key: .f)))
    }

    @Test("Open big map does not press map hotkey when already in big-map UI")
    @MainActor
    func openBigMapDoesNotPressMapHotkeyWhenAlreadyInBigMapUI() async throws {
        var actions: [InputAction] = []
        let frame = try makeBigMapStatusFrame()
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: { frame },
            config: BGIBigMapConfig(openMapPrepareMs: 0, openMapWaitMs: 0, openMapRetryWaitMs: 0)
        )

        try await service.openBigMap()

        #expect(actions.isEmpty)
    }

    @Test("Open big map presses map hotkey and verifies when not already in big-map UI")
    @MainActor
    func openBigMapPressesMapHotkeyAndVerifiesWhenNeeded() async throws {
        var actions: [InputAction] = []
        var frames = [
            try makeBlankFrame(),
            try makeBigMapStatusFrame()
        ]
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: {
                frames.isEmpty ? try makeBigMapStatusFrame() : frames.removeFirst()
            },
            config: BGIBigMapConfig(openMapPrepareMs: 0, openMapWaitMs: 0, openMapRetryWaitMs: 0)
        )

        try await service.openBigMap()

        #expect(actions.contains(.releaseAll))
        #expect(actions.contains(.keyPress(key: .m)))
    }

    @Test("Current big-map zoom level follows upstream 1 to 6 scale")
    @MainActor
    func currentBigMapZoomLevelFollowsUpstreamScale() async throws {
        let frame = try makeBigMapStatusFrame(zoomLevel: 3.0)
        let service = BGIBigMapInteractionService(
            inputHandler: { _ in .dryRun() },
            captureFrameProvider: { frame }
        )

        let zoomLevel = try await service.currentBigMapZoomLevel()

        #expect(abs(zoomLevel - 3.0) < 0.05)
    }

    @Test("Set big-map zoom level drags upstream slider coordinates")
    @MainActor
    func setBigMapZoomLevelDragsUpstreamSliderCoordinates() async throws {
        var actions: [InputAction] = []
        let frame = try makeBigMapStatusFrame(zoomLevel: 3.0)
        let config = BGIBigMapConfig(
            captureRect: CGRect(x: 0, y: 0, width: 960, height: 540),
            openMapPrepareMs: 0,
            openMapWaitMs: 0,
            mapZoomAdjustWaitMs: 0
        )
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: { frame },
            config: config
        )

        try await service.setBigMapZoomLevel(4.5)

        let startPoint = sliderPoint(zoomLevel: 3.0, captureRect: config.captureRect)
        let endPoint = sliderPoint(zoomLevel: 4.5, captureRect: config.captureRect)
        #expect(actions.count == 4)
        guard actions.count == 4 else { return }
        expectMouseMove(actions[0], near: startPoint)
        expectMouseButtonDown(actions[1], near: startPoint)
        expectMouseMove(actions[2], near: endPoint)
        expectMouseButtonUp(actions[3], near: endPoint)
    }

    @Test("Map move steps follow upstream cosine distribution")
    func mapMoveStepsFollowUpstreamCosineDistribution() {
        #expect(BGIBigMapInteractionService.mapMoveSteps(delta: 50, steps: 5) == [13, 13, 12, 8, 4])
        #expect(BGIBigMapInteractionService.mapMoveSteps(delta: -20, steps: 5) == [-5, -5, -5, -4, -1])
    }

    @Test("MoveMapTo drags big map with upstream pixel-distance formula")
    @MainActor
    func moveMapToDragsBigMapWithUpstreamPixelDistanceFormula() async throws {
        var actions: [InputAction] = []
        var positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: -40)
        ]
        let frame = try makeBigMapStatusFrame(zoomLevel: 4.0)
        let config = BGIBigMapConfig(
            mapScaleFactor: 2.0,
            mapMoveTolerance: 1,
            mapMoveStepIntervalMs: 0,
            captureRect: CGRect(x: 0, y: 0, width: 960, height: 540),
            openMapPrepareMs: 0,
            openMapWaitMs: 0,
            mapZoomEnabled: false
        )
        let service = BGIBigMapInteractionService(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            },
            captureFrameProvider: { frame },
            bigMapPositionProvider: { _ in
                positions.isEmpty ? CGPoint(x: 100, y: -40) : positions.removeFirst()
            },
            config: config
        )

        try await service.moveMapTo(x: 100, y: -40, mapName: "Teyvat")

        #expect(actions.count == 8)
        guard actions.count == 8 else { return }
        let start = CGPoint(x: 480, y: 270)
        let end = CGPoint(x: 505, y: 260)
        expectMouseMove(actions[0], near: start)
        expectMouseButtonDown(actions[1], near: start)
        expectMouseMove(actions[6], near: end)
        expectMouseButtonUp(actions[7], near: end)
    }

    private func makeBigMapStatusFrame() throws -> CaptureImageFrame {
        try makeBigMapStatusFrame(zoomLevel: 4.0)
    }

    private func makeBigMapStatusFrame(zoomLevel: Double) throws -> CaptureImageFrame {
        let template = try BGIAssetResolver.scaledTemplateImage(
            for: "GameTask/QuickTeleport/Assets/1920x1080/MapScaleButton.png",
            frameWidth: 960
        )
        let centerY1080 = 468.0 + (612.0 - 468.0) * (zoomLevel - 1.0) / 5.0
        let image = try makeFrame(
            template: template,
            at: CGPoint(
                x: 17,
                y: CGFloat(centerY1080 / 2.0) - CGFloat(template.height) / 2.0
            ),
            size: CGSize(width: 960, height: 540)
        )
        return makeFrame(image: image)
    }

    private func sliderPoint(zoomLevel: Double, captureRect: CGRect) -> CGPoint {
        let y1080 = 468.0 + (612.0 - 468.0) * (zoomLevel - 1.0) / 5.0
        return CGPoint(
            x: captureRect.minX + CGFloat(47.0 / 1_920.0) * captureRect.width,
            y: captureRect.minY + CGFloat(y1080 / 1_080.0) * captureRect.height
        )
    }

    private func expectMouseMove(_ action: InputAction, near point: CGPoint) {
        guard case let .mouseMove(actual) = action else {
            Issue.record("Expected mouseMove, got \(action)")
            return
        }
        expectPoint(actual, near: point)
    }

    private func expectMouseButtonDown(_ action: InputAction, near point: CGPoint) {
        guard case let .mouseButtonDown(button: .left, at: actual?) = action else {
            Issue.record("Expected left mouseButtonDown, got \(action)")
            return
        }
        expectPoint(actual, near: point)
    }

    private func expectMouseButtonUp(_ action: InputAction, near point: CGPoint) {
        guard case let .mouseButtonUp(button: .left, at: actual?) = action else {
            Issue.record("Expected left mouseButtonUp, got \(action)")
            return
        }
        expectPoint(actual, near: point)
    }

    private func expectPoint(_ actual: CGPoint, near expected: CGPoint, tolerance: CGFloat = 0.25) {
        #expect(abs(actual.x - expected.x) <= tolerance)
        #expect(abs(actual.y - expected.y) <= tolerance)
    }

    private func makeTeleportButtonFrame() throws -> CaptureImageFrame {
        let template = try BGIAssetResolver.scaledTemplateImage(
            for: "GameTask/QuickTeleport/Assets/1920x1080/GoTeleport.png",
            frameWidth: 960
        )
        let image = try makeFrame(
            template: template,
            at: CGPoint(x: 724, y: 486),
            size: CGSize(width: 960, height: 540)
        )
        return makeFrame(image: image)
    }

    private func makeMapCloseButtonFrame() throws -> CaptureImageFrame {
        let template = try BGIAssetResolver.scaledTemplateImage(
            for: "GameTask/QuickTeleport/Assets/1920x1080/MapCloseButton.png",
            frameWidth: 960
        )
        let image = try makeFrame(
            template: template,
            at: CGPoint(x: 906, y: 10),
            size: CGSize(width: 960, height: 540)
        )
        return makeFrame(image: image)
    }

    private func makeMapChooseIconFrame() throws -> CaptureImageFrame {
        try makeMapChooseIconFrame(icons: [("TeleportWaypoint.png", CGPoint(x: 636, y: 52))])
    }

    private func makeMapChooseIconFrame(icons: [(String, CGPoint)]) throws -> CaptureImageFrame {
        let templates = try icons.map { assetName, point in
            let template = try BGIAssetResolver.scaledTemplateImage(
                for: "GameTask/QuickTeleport/Assets/1920x1080/\(assetName)",
                frameWidth: 960
            )
            return (template, point)
        }
        let image = try makeFrame(
            templates: templates,
            size: CGSize(width: 960, height: 540)
        )
        return makeFrame(image: image)
    }

    private func makeMainUIFrame() throws -> CaptureImageFrame {
        let template = try BGIAssetResolver.scaledTemplateImage(
            for: "GameTask/Common/Element/Assets/1920x1080/paimon_menu.png",
            frameWidth: 960
        )
        let image = try makeFrame(
            template: template,
            at: CGPoint(x: 12, y: 8),
            size: CGSize(width: 960, height: 540)
        )
        return makeFrame(image: image)
    }

    private func makeRevivePromptFrame() throws -> CaptureImageFrame {
        let paimonTemplate = try BGIAssetResolver.scaledTemplateImage(
            for: "GameTask/Common/Element/Assets/1920x1080/paimon_menu.png",
            frameWidth: 960
        )
        let confirmTemplate = try BGIAssetResolver.scaledTemplateImage(
            for: "GameTask/AutoFight/Assets/1920x1080/confirm.png",
            frameWidth: 960
        )
        let image = try makeFrame(
            templates: [
                (paimonTemplate, CGPoint(x: 12, y: 8)),
                (confirmTemplate, CGPoint(x: 760, y: 458))
            ],
            size: CGSize(width: 960, height: 540)
        )
        return makeFrame(image: image)
    }

    private func makeBlankFrame() throws -> CaptureImageFrame {
        try makeFrame(image: makeFrame(template: nil, at: .zero, size: CGSize(width: 960, height: 540)))
    }

    private func makeFrame(image: CGImage) -> CaptureImageFrame {
        let width = image.width
        let height = image.height
        return CaptureImageFrame(
            metadata: CapturedFrame(
                frameIndex: 1,
                timestamp: Date(timeIntervalSince1970: 1),
                width: width,
                height: height,
                scaleFactor: 1,
                pixelFormat: 0x42475241,
                bytesPerRow: width * 4,
                sourceWindow: WindowInfo(
                    id: 42,
                    ownerPID: 100,
                    ownerName: "wine64-preloader",
                    title: "原神",
                    frame: CGRect(x: 0, y: 0, width: width, height: height),
                    layer: 0,
                    isOnScreen: true,
                    scaleFactor: 1
                )
            ),
            cgImage: image,
            backendName: "Synthetic"
        )
    }

    private func makeFrame(template: CGImage?, at point: CGPoint, size: CGSize) throws -> CGImage {
        try makeFrame(
            templates: template.map { [($0, point)] } ?? [],
            size: size
        )
    }

    private func makeFrame(templates: [(CGImage, CGPoint)], size: CGSize) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        for (template, point) in templates {
            let templatePixels = try rgbaPixels(from: template)
            let templateBytesPerRow = template.width * bytesPerPixel
            let originX = Int(point.x.rounded())
            let originY = Int(point.y.rounded())

            for templateY in 0..<template.height {
                let destinationY = originY + templateY
                guard destinationY >= 0, destinationY < height else { continue }
                for templateX in 0..<template.width {
                    let destinationX = originX + templateX
                    guard destinationX >= 0, destinationX < width else { continue }
                    let sourceIndex = templateY * templateBytesPerRow + templateX * bytesPerPixel
                    let destinationIndex = destinationY * bytesPerRow + destinationX * bytesPerPixel
                    pixels[destinationIndex..<(destinationIndex + bytesPerPixel)] =
                        templatePixels[sourceIndex..<(sourceIndex + bytesPerPixel)]
                }
            }
        }

        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
        ))
        return try #require(context.makeImage())
    }

    private func rgbaPixels(from image: CGImage) throws -> [UInt8] {
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    // MARK: - screenPoint Tests

    @Test("screenPoint maps visible-rect center to viewport center")
    func screenPointMapsCenterToCenter() {
        let visible = CGRect(x: 100, y: 200, width: 500, height: 300)
        let viewport = CGRect(x: 50, y: 60, width: 400, height: 240)
        let target = CGPoint(x: visible.midX, y: visible.midY)
        let result = BGIBigMapInteractionService.screenPoint(
            for: target, visibleRect256: visible, viewportScreen: viewport
        )
        #expect(result != nil)
        #expect(abs(result!.x - viewport.midX) < 1)
        #expect(abs(result!.y - viewport.midY) < 1)
    }

    @Test("screenPoint maps corner to corner with zero safe inset")
    func screenPointMapsCornerToCorner() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let viewport = CGRect(x: 10, y: 20, width: 500, height: 400)
        let result = BGIBigMapInteractionService.screenPoint(
            for: CGPoint(x: 999, y: 799),
            visibleRect256: visible,
            viewportScreen: viewport,
            safeInsetFraction: .zero
        )
        #expect(result != nil)
        #expect(abs(result!.x - viewport.maxX) < 1)
        #expect(abs(result!.y - viewport.maxY) < 1)
    }

    @Test("screenPoint returns nil for target outside visible rect")
    func screenPointReturnsNilForOutsideTarget() {
        let visible = CGRect(x: 100, y: 100, width: 400, height: 300)
        let viewport = CGRect(x: 0, y: 0, width: 400, height: 300)
        let result = BGIBigMapInteractionService.screenPoint(
            for: CGPoint(x: 10, y: 10), visibleRect256: visible, viewportScreen: viewport
        )
        #expect(result == nil)
    }

    @Test("screenPoint returns nil for zero-size rects")
    func screenPointReturnsNilForZeroRects() {
        #expect(BGIBigMapInteractionService.screenPoint(
            for: .zero, visibleRect256: .zero, viewportScreen: CGRect(x: 0, y: 0, width: 100, height: 100)
        ) == nil)
        #expect(BGIBigMapInteractionService.screenPoint(
            for: .zero, visibleRect256: CGRect(x: 0, y: 0, width: 100, height: 100), viewportScreen: .zero
        ) == nil)
    }
}
