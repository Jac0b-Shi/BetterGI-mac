import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI JS genshin command replayer")
struct BGIJSScriptGenshinCommandReplayerTests {
    @Test("Replayer executes forced teleport through big-map input")
    @MainActor
    func replayerExecutesForcedTeleportThroughBigMapInput() async {
        var actions: [InputAction] = []
        let replayer = BGIJSScriptGenshinCommandReplayer(
            bigMapConfig: BGIBigMapConfig(
                captureRect: CGRect(x: 10, y: 20, width: 1000, height: 500),
                openMapPrepareMs: 0,
                openMapWaitMs: 0,
                teleportConfirmDelayMs: 0,
                teleportLoadWaitMs: 0
            ),
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let result = await replayer.replay(
            [.teleport(x: 500, y: 500, mapName: "Teyvat", force: true)],
            targetWindow: makeGenshinWindow()
        )

        #expect(result.executedCommands == [.teleport(x: 500, y: 500, mapName: "Teyvat", force: true)])
        #expect(result.pendingCommands.isEmpty)
        #expect(result.failedCommands.isEmpty)
        #expect(actions.contains(.releaseAll))
        #expect(actions.contains(.keyPress(key: .m)))
        #expect(actions.contains(.keyPress(key: .f)))
        #expect(actions.contains { action in
            if case let .mouseClick(.left, point) = action {
                return point != nil
            }
            return false
        })
    }

    @Test("Replayer executes ReturnMainUi by pressing Escape until Paimon menu appears")
    @MainActor
    func replayerExecutesReturnMainUIByPressingEscapeUntilPaimonMenuAppears() async throws {
        var actions: [InputAction] = []
        var frames = [
            try makeBlankFrame(),
            try makeBlankFrame(),
            try makeMainUIFrame()
        ]
        let replayer = BGIJSScriptGenshinCommandReplayer(
            returnMainUIConfig: BGIReturnMainUIConfig(maxEscapeAttempts: 2, escapeWaitMs: 0, finalKeyWaitMs: 0),
            captureFrameProvider: {
                frames.isEmpty ? try makeBlankFrame() : frames.removeFirst()
            },
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let result = await replayer.replay([.returnMainUI], targetWindow: makeGenshinWindow())

        #expect(result.executedCommands == [.returnMainUI])
        #expect(result.pendingCommands.isEmpty)
        #expect(result.failedCommands.isEmpty)
        #expect(actions == [.keyPress(key: .escape), .keyPress(key: .escape)])
    }

    @Test("Replayer skips ReturnMainUi input when already in main UI")
    @MainActor
    func replayerSkipsReturnMainUIInputWhenAlreadyInMainUI() async throws {
        var actions: [InputAction] = []
        let frame = try makeMainUIFrame()
        let replayer = BGIJSScriptGenshinCommandReplayer(
            returnMainUIConfig: BGIReturnMainUIConfig(maxEscapeAttempts: 2, escapeWaitMs: 0, finalKeyWaitMs: 0),
            captureFrameProvider: { frame },
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let result = await replayer.replay([.returnMainUI], targetWindow: makeGenshinWindow())

        #expect(result.executedCommands == [.returnMainUI])
        #expect(result.pendingCommands.isEmpty)
        #expect(result.failedCommands.isEmpty)
        #expect(actions.isEmpty)
    }

    @Test("Replayer chooses talk option by OCR text")
    @MainActor
    func replayerChoosesTalkOptionByOCRText() async throws {
        var actions: [InputAction] = []
        let frame = try makeBlankFrame()
        let command = BGIJSScriptGenshinCommand.chooseTalkOption(option: "每日委托", skipTimes: 3, isOrange: false)
        let ocrRegion = CGRect(x: 650, y: 350, width: 120, height: 30)
        let replayer = BGIJSScriptGenshinCommandReplayer(
            chooseTalkOptionConfig: BGIChooseTalkOptionConfig(
                talkUIRetryTimes: 1,
                talkUIRetryIntervalMs: 0,
                skipWaitMs: 0,
                firstTextStabilizeWaitMs: 0,
                clickWaitMs: 0
            ),
            captureFrameProvider: { frame },
            recognitionObjectProvider: { frame, object in
                switch object.id {
                case "AutoSkip.DisabledUiButtonRo":
                    [makeTalkUIObservation(frame: frame)]
                case "AutoSkip.OptionIconRo":
                    [makeOptionIconObservation(frame: frame)]
                default:
                    []
                }
            },
            ocrProvider: { frame, _ in
                OCRResult(
                    regions: [
                        OCRResult.Region(
                            boundingBox: ocrRegion,
                            text: "关于每日委托",
                            confidence: 0.97
                        )
                    ],
                    sourceROI: nil,
                    frameIndex: frame.metadata.frameIndex,
                    timestamp: frame.metadata.timestamp
                )
            },
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let result = await replayer.replay([command], targetWindow: makeGenshinWindow())

        #expect(result.executedCommands == [command])
        #expect(result.pendingCommands.isEmpty)
        #expect(result.failedCommands.isEmpty)
        let clickPoint = try #require(actions.compactMap { action -> CGPoint? in
            if case let .mouseClick(.left, point) = action {
                return point
            }
            return nil
        }.first)
        #expect(abs(clickPoint.x - 749.58) < 0.5)
        #expect(abs(clickPoint.y - 357.96) < 0.5)
    }

    @Test("Replayer presses Space while waiting for talk options")
    @MainActor
    func replayerPressesSpaceWhileWaitingForTalkOptions() async throws {
        var actions: [InputAction] = []
        let frame = try makeBlankFrame()
        let command = BGIJSScriptGenshinCommand.chooseTalkOption(option: "每日委托", skipTimes: 2, isOrange: false)
        let replayer = BGIJSScriptGenshinCommandReplayer(
            chooseTalkOptionConfig: BGIChooseTalkOptionConfig(
                talkUIRetryTimes: 1,
                talkUIRetryIntervalMs: 0,
                skipWaitMs: 0,
                firstTextStabilizeWaitMs: 0,
                clickWaitMs: 0
            ),
            captureFrameProvider: { frame },
            recognitionObjectProvider: { frame, object in
                object.id == "AutoSkip.DisabledUiButtonRo" ? [makeTalkUIObservation(frame: frame)] : []
            },
            ocrProvider: { frame, _ in
                OCRResult(regions: [], sourceROI: nil, frameIndex: frame.metadata.frameIndex, timestamp: frame.metadata.timestamp)
            },
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let result = await replayer.replay([command], targetWindow: makeGenshinWindow())

        #expect(result.executedCommands.isEmpty)
        #expect(result.pendingCommands.isEmpty)
        #expect(result.failedCommands.map(\.command) == [command])
        #expect(actions == [.keyPress(key: .space), .keyPress(key: .space)])
    }

    @Test("Replayer does not advance dialogue before talk UI is visible")
    @MainActor
    func replayerDoesNotAdvanceDialogueBeforeTalkUIIsVisible() async throws {
        var actions: [InputAction] = []
        let frame = try makeBlankFrame()
        let command = BGIJSScriptGenshinCommand.chooseTalkOption(option: "每日委托", skipTimes: 2, isOrange: false)
        let replayer = BGIJSScriptGenshinCommandReplayer(
            chooseTalkOptionConfig: BGIChooseTalkOptionConfig(
                talkUIRetryTimes: 2,
                talkUIRetryIntervalMs: 0,
                skipWaitMs: 0,
                firstTextStabilizeWaitMs: 0,
                clickWaitMs: 0
            ),
            captureFrameProvider: { frame },
            recognitionObjectProvider: { _, _ in [] },
            ocrProvider: { frame, _ in
                OCRResult(regions: [], sourceROI: nil, frameIndex: frame.metadata.frameIndex, timestamp: frame.metadata.timestamp)
            },
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let result = await replayer.replay([command], targetWindow: makeGenshinWindow())

        #expect(result.executedCommands.isEmpty)
        #expect(result.pendingCommands.isEmpty)
        #expect(result.failedCommands.map(\.command) == [command])
        #expect(result.failedCommands.first?.message == "Current UI is not a talk option UI")
        #expect(actions.isEmpty)
    }

    @Test("Replayer rejects non-orange talk option when requested")
    @MainActor
    func replayerRejectsNonOrangeTalkOptionWhenRequested() async throws {
        var actions: [InputAction] = []
        let frame = try makeBlankFrame()
        let command = BGIJSScriptGenshinCommand.chooseTalkOption(option: "每日委托", skipTimes: 1, isOrange: true)
        let replayer = BGIJSScriptGenshinCommandReplayer(
            chooseTalkOptionConfig: BGIChooseTalkOptionConfig(
                talkUIRetryTimes: 1,
                talkUIRetryIntervalMs: 0,
                skipWaitMs: 0,
                firstTextStabilizeWaitMs: 0,
                clickWaitMs: 0
            ),
            captureFrameProvider: { frame },
            recognitionObjectProvider: { frame, object in
                switch object.id {
                case "AutoSkip.DisabledUiButtonRo":
                    [makeTalkUIObservation(frame: frame)]
                case "AutoSkip.OptionIconRo":
                    [makeOptionIconObservation(frame: frame)]
                default:
                    []
                }
            },
            ocrProvider: { frame, _ in
                OCRResult(
                    regions: [
                        OCRResult.Region(
                            boundingBox: CGRect(x: 650, y: 350, width: 120, height: 30),
                            text: "关于每日委托",
                            confidence: 0.97
                        )
                    ],
                    sourceROI: nil,
                    frameIndex: frame.metadata.frameIndex,
                    timestamp: frame.metadata.timestamp
                )
            },
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let result = await replayer.replay([command], targetWindow: makeGenshinWindow())

        #expect(result.executedCommands.isEmpty)
        #expect(result.failedCommands.map(\.command) == [command])
        #expect(result.failedCommands.first?.message == "Talk option found but it is not orange: 每日委托")
        #expect(actions.isEmpty)
    }

    @Test("Replayer executes SetTime through upstream clock input sequence")
    @MainActor
    func replayerExecutesSetTimeThroughClockInputSequence() async throws {
        var actions: [InputAction] = []
        let frame = try makeMainUIFrame()
        let command = BGIJSScriptGenshinCommand.setTime(hour: 6, minute: 30, skip: false)
        let replayer = BGIJSScriptGenshinCommandReplayer(
            returnMainUIConfig: BGIReturnMainUIConfig(maxEscapeAttempts: 1, escapeWaitMs: 0, finalKeyWaitMs: 0),
            setTimeConfig: fastSetTimeConfig(),
            captureFrameProvider: { frame },
            recognitionObjectProvider: { _, _ in [] },
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let result = await replayer.replay([command], targetWindow: makeGenshinWindow())

        #expect(result.executedCommands == [command])
        #expect(result.pendingCommands.isEmpty)
        #expect(result.failedCommands.isEmpty)
        #expect(actions.first == .keyPress(key: .escape))
        #expect(actions.contains(.mouseClick(button: .left, at: screenPointForGamePoint(x: 50, y: 700))))
        #expect(actions.contains(.mouseMove(to: screenPointForGamePoint(x: 1_500, y: 1_000))))
        #expect(actions.contains(.mouseClick(button: .left, at: screenPointForGamePoint(x: 1_500, y: 1_000))))
        #expect(actions.contains { action in
            if case let .mouseButtonDown(button: .left, at: point) = action {
                return point != nil
            }
            return false
        })
        #expect(actions.contains { action in
            if case let .mouseButtonUp(button: .left, at: point) = action {
                return point != nil
            }
            return false
        })
    }

    @Test("Replayer rejects invalid SetTime hour before input")
    @MainActor
    func replayerRejectsInvalidSetTimeHourBeforeInput() async throws {
        var actions: [InputAction] = []
        let command = BGIJSScriptGenshinCommand.setTime(hour: 25, minute: 0, skip: false)
        let replayer = BGIJSScriptGenshinCommandReplayer(
            setTimeConfig: fastSetTimeConfig(),
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let result = await replayer.replay([command], targetWindow: makeGenshinWindow())

        #expect(result.executedCommands.isEmpty)
        #expect(result.pendingCommands.isEmpty)
        #expect(result.failedCommands.map(\.command) == [command])
        #expect(result.failedCommands.first?.message == "Invalid hour value: 25, expected 0...24")
        #expect(actions.isEmpty)
    }

    @Test("Replayer executes Relogin through upstream retry sequence")
    @MainActor
    func replayerExecutesReloginThroughRetrySequence() async throws {
        var actions: [InputAction] = []
        var objectCalls: [String: Int] = [:]
        let command = BGIJSScriptGenshinCommand.relogin
        let replayer = BGIJSScriptGenshinCommandReplayer(
            reloginConfig: fastReloginConfig(),
            captureFrameProvider: { try makeBlankFrame() },
            recognitionObjectProvider: { frame, object in
                objectCalls[object.id, default: 0] += 1
                let call = objectCalls[object.id, default: 0]
                switch object.id {
                case "AutoWood.MenuBagRo":
                    return [makeObservation(frame: frame, objectID: object.id, objectName: "MenuBag")]
                case "AutoWood.ConfirmRo":
                    return call <= 2 ? [makeObservation(frame: frame, objectID: object.id, objectName: "Confirm")] : []
                case "AutoWood.EnterGameRo":
                    return call <= 2 ? [makeObservation(frame: frame, objectID: object.id, objectName: "EnterGame")] : []
                case "Common.Element.PaimonMenuRo":
                    return [makeObservation(frame: frame, objectID: object.id, objectName: "PaimonMenu")]
                default:
                    return []
                }
            },
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let result = await replayer.replay([command], targetWindow: makeGenshinWindow())

        #expect(result.executedCommands == [command])
        #expect(result.pendingCommands.isEmpty)
        #expect(result.failedCommands.isEmpty)
        #expect(actions.first == .keyPress(key: .escape))
        #expect(actions.contains(.mouseClick(button: .left, at: screenPointForGamePoint(x: 50, y: 1_030))))
        #expect(actions.contains(.mouseClick(button: .left, at: screenPointForGamePoint(x: 955, y: 666))))
        #expect(actions.contains { action in
            if case let .mouseClick(.left, point) = action {
                return point == screenPointForNormalizedRect(CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1))
            }
            return false
        })
    }

    @Test("Replayer rejects Relogin without capture provider")
    @MainActor
    func replayerRejectsReloginWithoutCaptureProvider() async {
        var actions: [InputAction] = []
        let command = BGIJSScriptGenshinCommand.relogin
        let replayer = BGIJSScriptGenshinCommandReplayer(
            reloginConfig: fastReloginConfig(),
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let result = await replayer.replay([command], targetWindow: makeGenshinWindow())

        #expect(result.executedCommands.isEmpty)
        #expect(result.pendingCommands.isEmpty)
        #expect(result.failedCommands.map(\.command) == [command])
        #expect(result.failedCommands.first?.message == "Relogin requires a capture provider")
        #expect(actions.isEmpty)
    }

    @Test("Replayer executes SetBigMapZoomLevel through upstream slider drag")
    @MainActor
    func replayerExecutesSetBigMapZoomLevelThroughSliderDrag() async throws {
        var actions: [InputAction] = []
        let frame = try makeBigMapStatusFrame(zoomLevel: 3.0)
        let command = BGIJSScriptGenshinCommand.setBigMapZoomLevel(4.5)
        let replayer = BGIJSScriptGenshinCommandReplayer(
            bigMapConfig: BGIBigMapConfig(
                openMapPrepareMs: 0,
                openMapWaitMs: 0,
                mapZoomAdjustWaitMs: 0
            ),
            captureFrameProvider: { frame },
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let result = await replayer.replay([command], targetWindow: makeGenshinWindow())

        let startPoint = screenPointForGamePoint(x: 47, y: sliderY1080(zoomLevel: 3.0))
        let endPoint = screenPointForGamePoint(x: 47, y: sliderY1080(zoomLevel: 4.5))
        #expect(result.executedCommands == [command])
        #expect(result.pendingCommands.isEmpty)
        #expect(result.failedCommands.isEmpty)
        #expect(actions.count == 4)
        guard actions.count == 4 else { return }
        expectMouseMove(actions[0], near: startPoint)
        expectMouseButtonDown(actions[1], near: startPoint)
        expectMouseMove(actions[2], near: endPoint)
        expectMouseButtonUp(actions[3], near: endPoint)
    }

    @Test("Replayer executes MoveMapTo when big-map position provider is available")
    @MainActor
    func replayerExecutesMoveMapToWhenBigMapPositionProviderIsAvailable() async throws {
        var actions: [InputAction] = []
        var positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: -40)
        ]
        let frame = try makeBigMapStatusFrame(zoomLevel: 4.0)
        let command = BGIJSScriptGenshinCommand.moveMapTo(x: 100, y: -40, forceCountry: nil)
        let replayer = BGIJSScriptGenshinCommandReplayer(
            bigMapConfig: BGIBigMapConfig(
                mapScaleFactor: 2.0,
                mapMoveTolerance: 1,
                mapMoveStepIntervalMs: 0,
                openMapPrepareMs: 0,
                openMapWaitMs: 0,
                mapZoomEnabled: false
            ),
            captureFrameProvider: { frame },
            bigMapPositionProvider: { _ in
                positions.isEmpty ? CGPoint(x: 100, y: -40) : positions.removeFirst()
            },
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let result = await replayer.replay([command], targetWindow: makeGenshinWindow())

        let start = CGPoint(x: makeGenshinWindow().captureRect.midX, y: makeGenshinWindow().captureRect.midY)
        let end = start.applying(CGAffineTransform(
            translationX: CGFloat(50.0 / 1_920.0) * makeGenshinWindow().captureRect.width,
            y: CGFloat(-20.0 / 1_080.0) * makeGenshinWindow().captureRect.height
        ))
        #expect(result.executedCommands == [command])
        #expect(result.pendingCommands.isEmpty)
        #expect(result.failedCommands.isEmpty)
        #expect(actions.count == 8)
        guard actions.count == 8 else { return }
        expectMouseMove(actions[0], near: start)
        expectMouseButtonDown(actions[1], near: start)
        expectMouseMove(actions[6], near: end)
        expectMouseButtonUp(actions[7], near: end)
    }

    @Test("Replayer keeps non-forced teleport pending until big-map viewport support is ported")
    @MainActor
    func replayerKeepsNonForcedTeleportPendingUntilBigMapViewportSupportIsPorted() async {
        var actions: [InputAction] = []
        let replayer = BGIJSScriptGenshinCommandReplayer(
            inputHandler: { action in
                actions.append(action)
                return .dryRun()
            }
        )

        let command = BGIJSScriptGenshinCommand.teleport(x: 500, y: 500, mapName: "Teyvat", force: false)
        let result = await replayer.replay([command], targetWindow: makeGenshinWindow())

        #expect(result.executedCommands.isEmpty)
        #expect(result.pendingCommands.map(\.command) == [command])
        #expect(result.failedCommands.isEmpty)
        #expect(result.pendingCommands.first?.reason.contains("GetBigMapRect") == true)
        #expect(actions.isEmpty)
    }

    @Test("Replayer keeps TpToStatueOfTheSeven pending until big-map viewport support is ported")
    @MainActor
    func replayerKeepsTpToStatueOfTheSevenPendingUntilBigMapViewportSupportIsPorted() async {
        let replayer = BGIJSScriptGenshinCommandReplayer(
            inputHandler: { _ in .dryRun() }
        )
        let commands: [BGIJSScriptGenshinCommand] = [
            .teleportToStatueOfTheSeven
        ]

        let result = await replayer.replay(commands, targetWindow: makeGenshinWindow())

        #expect(result.executedCommands.isEmpty)
        #expect(result.pendingCommands.map(\.command) == commands)
        #expect(result.failedCommands.isEmpty)
        #expect(result.pendingCommands.first?.reason.contains("GetBigMapRect") == true)
    }

    private func makeGenshinWindow() -> WindowInfo {
        WindowInfo(
            id: 42,
            ownerPID: 100,
            ownerName: "wine64-preloader",
            title: "原神",
            frame: CGRect(x: 10, y: 20, width: 1000, height: 500),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 2
        )
    }

    private func fastSetTimeConfig() -> BGISetTimeConfig {
        BGISetTimeConfig(
            menuOpenWaitMs: 0,
            timePageOpenWaitMs: 0,
            mouseMoveSettleWaitMs: 0,
            mouseDownWaitMs: 0,
            clockStepWaitMs: 0,
            afterClockSetWaitMs: 0,
            confirmMoveWaitMs: 0,
            confirmClickWaitMs: 0,
            skipAnimationPreWaitMs: 0,
            skipAnimationMouseDownWaitMs: 0,
            skipAnimationPostWaitMs: 0,
            postAnimationWaitMs: 0,
            pageCloseRetryTimes: 1,
            pageCloseRetryIntervalMs: 0
        )
    }

    private func fastReloginConfig() -> BGIExitAndReloginConfig {
        BGIExitAndReloginConfig(
            menuAppearAttempts: 1,
            menuAppearIntervalMs: 0,
            confirmAppearAttempts: 1,
            confirmAppearIntervalMs: 0,
            confirmDisappearAttempts: 2,
            confirmDisappearIntervalMs: 0,
            afterConfirmDisappearWaitMs: 0,
            enterGameAppearAttempts: 1,
            enterGameAppearIntervalMs: 0,
            enterGameDisappearAttempts: 2,
            enterGameDisappearIntervalMs: 0,
            mainUIAppearAttempts: 1,
            mainUIAppearIntervalMs: 0,
            finalWaitMs: 0
        )
    }

    private func screenPointForGamePoint(x: Double, y: Double) -> CGPoint {
        let rect = makeGenshinWindow().captureRect
        return CGPoint(
            x: rect.minX + CGFloat(x / 1_920.0) * rect.width,
            y: rect.minY + CGFloat(y / 1_080.0) * rect.height
        )
    }

    private func screenPointForNormalizedRect(_ rect: CGRect) -> CGPoint {
        let captureRect = makeGenshinWindow().captureRect
        return CGPoint(
            x: captureRect.minX + rect.midX * captureRect.width,
            y: captureRect.minY + rect.midY * captureRect.height
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

    private func sliderY1080(zoomLevel: Double) -> Double {
        468.0 + (612.0 - 468.0) * (zoomLevel - 1.0) / 5.0
    }

    private func makeMainUIFrame() throws -> CaptureImageFrame {
        let template = try BGIAssetResolver.scaledTemplateImage(
            for: "GameTask/Common/Element/Assets/1920x1080/paimon_menu.png",
            frameWidth: 960
        )
        let image = try makeFrame(
            templates: [(template, CGPoint(x: 12, y: 8))],
            size: CGSize(width: 960, height: 540)
        )
        return makeFrame(image: image)
    }

    private func makeBigMapStatusFrame(zoomLevel: Double) throws -> CaptureImageFrame {
        let template = try BGIAssetResolver.scaledTemplateImage(
            for: "GameTask/QuickTeleport/Assets/1920x1080/MapScaleButton.png",
            frameWidth: 960
        )
        let image = try makeFrame(
            templates: [
                (
                    template,
                    CGPoint(
                        x: 17,
                        y: CGFloat(sliderY1080(zoomLevel: zoomLevel) / 2.0) - CGFloat(template.height) / 2.0
                    )
                )
            ],
            size: CGSize(width: 960, height: 540)
        )
        return makeFrame(image: image)
    }

    private func makeBlankFrame() throws -> CaptureImageFrame {
        try makeFrame(image: makeFrame(templates: [], size: CGSize(width: 960, height: 540)))
    }

    private func makeOptionIconObservation(frame: CaptureImageFrame) -> RecognitionObservation {
        RecognitionObservation(
            id: "AutoSkip.OptionIconRo-\(frame.metadata.frameIndex)",
            objectID: "AutoSkip.OptionIconRo",
            objectName: "OptionIcon",
            recognitionType: .templateMatch,
            normalizedRect: CGRect(x: 0.64, y: 0.70, width: 0.02, height: 0.03),
            confidence: 0.93,
            text: nil,
            frameIndex: frame.metadata.frameIndex,
            timestamp: frame.metadata.timestamp
        )
    }

    private func makeTalkUIObservation(frame: CaptureImageFrame) -> RecognitionObservation {
        RecognitionObservation(
            id: "AutoSkip.DisabledUiButtonRo-\(frame.metadata.frameIndex)",
            objectID: "AutoSkip.DisabledUiButtonRo",
            objectName: "DisabledUiButton",
            recognitionType: .templateMatch,
            normalizedRect: CGRect(x: 0.03, y: 0.02, width: 0.12, height: 0.04),
            confidence: 0.94,
            text: nil,
            frameIndex: frame.metadata.frameIndex,
            timestamp: frame.metadata.timestamp
        )
    }

    private func makeObservation(
        frame: CaptureImageFrame,
        objectID: String,
        objectName: String,
        normalizedRect: CGRect = CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
    ) -> RecognitionObservation {
        RecognitionObservation(
            id: "\(objectID)-\(frame.metadata.frameIndex)",
            objectID: objectID,
            objectName: objectName,
            recognitionType: .templateMatch,
            normalizedRect: normalizedRect,
            confidence: 0.95,
            text: nil,
            frameIndex: frame.metadata.frameIndex,
            timestamp: frame.metadata.timestamp
        )
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
                sourceWindow: makeGenshinWindow()
            ),
            cgImage: image,
            backendName: "Synthetic"
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
}
