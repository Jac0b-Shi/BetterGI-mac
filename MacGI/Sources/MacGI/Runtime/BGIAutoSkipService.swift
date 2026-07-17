import Foundation

struct BGIAutoSkipConfig: Sendable {
    var skipCooldownMs: Int = 100
    var isUseInteractionKey: Bool = false
    var closePopupEnabled: Bool = true
    var popupCloseDelaySeconds: Double = 3.0

    static let `default` = BGIAutoSkipConfig()
}

/// First-layer port of upstream `AutoSkipTrigger.OnCapture`.
///
/// Handles: talk-UI detection + Space skip, popup closing via PageCloseRo,
/// and submit-goods detection. Full OCR-based dialogue option selection,
/// daily rewards, hangout events, and VAD voice-wait are pending.
final class BGIAutoSkipService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult

    private let captureFrameProvider: CaptureFrameProvider?
    private let inputHandler: InputHandler
    private let config: BGIAutoSkipConfig
    private let templateEngine = TemplateMatchingRecognitionEngine()

    private let audioWaiter = BGIDialogueAudioWaiter()
    private var lastSkipTime = Date.distantPast
    private var lastPlayingTime = Date.distantPast

    init(
        inputHandler: @escaping InputHandler,
        captureFrameProvider: CaptureFrameProvider? = nil,
        config: BGIAutoSkipConfig = .default
    ) {
        self.inputHandler = inputHandler
        self.captureFrameProvider = captureFrameProvider
        self.config = config
    }

    func evaluate() async {
        let cooldownMs = Double(config.skipCooldownMs) / 1000.0
        guard Date().timeIntervalSince(lastSkipTime) >= cooldownMs else { return }

        guard let provider = captureFrameProvider else {
            await skip()
            return
        }

        do {
            let frame = try await provider()
            let results = templateEngine.recognize(
                imageFrame: frame,
                objects: RecognitionObject.bgiAutoSkipObjects
            ).observations

            let isPlaying = results.contains { $0.objectID.contains("DisabledUiButton")
                || $0.objectID.contains("PlayingTextRo")
                || $0.objectID.contains("StopAutoButton") }

            let hasOption = results.contains { $0.objectID.contains("OptionIconRo") }

            if isPlaying {
                lastPlayingTime = Date()

                // If options are visible but we're still in talk UI,
                // the dialogue needs advancing (not option selection)
                if !hasOption {
                    await skip()
                }
                // If both play state AND options visible, skip to reach options
                // (Space will auto-advance to options)
                return
            }

            // Options visible but NOT in talk UI → need to select
            // Upstream: wait for dialogue voice to finish before clicking option
            if hasOption {
                if audioWaiter.isWaiting {
                    if audioWaiter.update() {
                        await selectOption(frame, results: results)
                    }
                } else {
                    _ = audioWaiter.start()
                }
                return
            }

            // Hangout event: skip button → click it; unselected option → click first
            if let hangoutSkip = results.first(where: { $0.objectID.contains("HangoutSkipRo") }) {
                await clickIcon(hangoutSkip, in: frame)
                return
            }
            if let unselected = results.first(where: { $0.objectID.contains("HangoutUnselected") }) {
                await clickIcon(unselected, in: frame)
                return
            }

            // Daily reward + explore dispatch icons (independent of dialog state)
            if let dailyReward = results.first(where: { $0.objectID.contains("DailyRewardIcon") }) {
                await clickIcon(dailyReward, in: frame)
                return
            }
            if let explore = results.first(where: { $0.objectID.contains("ExploreIcon") }) {
                await clickIcon(explore, in: frame)
                return
            }

            // After dialogue ends, close popups within a short window
            if config.closePopupEnabled,
               Date().timeIntervalSince(lastPlayingTime) <= config.popupCloseDelaySeconds {
                if await closePopup(frame, results: results) {
                    return
                }
            }
        } catch {
            // capture failed
        }
    }

    private func closePopup(_ frame: CaptureImageFrame, results: [RecognitionObservation]) async -> Bool {
        // PageCloseRo (character/item popup close button)
        if results.contains(where: { $0.objectID.contains("PageCloseRo") }) {
            await perform(.keyPress(key: .escape))
            return true
        }
        // SubmitGoodsRo (item submission dialog)
        if results.contains(where: { $0.objectID.contains("SubmitGoodsRo") }) {
            await perform(.keyPress(key: .space))
            return true
        }
        return false
    }

    private func clickIcon(_ obs: RecognitionObservation, in frame: CaptureImageFrame) async {
        let w = Double(frame.metadata.width)
        let h = Double(frame.metadata.height)
        let cx = obs.normalizedRect.midX * w
        let cy = obs.normalizedRect.midY * h
        lastSkipTime = Date()
        await perform(.mouseClick(button: .left, at: CGPoint(x: cx, y: cy)))
    }

    private func selectOption(_ frame: CaptureImageFrame, results: [RecognitionObservation]) async {
        guard let option = results
            .filter({ $0.objectID.contains("OptionIconRo") })
            .min(by: { $0.normalizedRect.maxY < $1.normalizedRect.maxY }) else { return }
        let w = Double(frame.metadata.width)
        let h = Double(frame.metadata.height)
        let clickX = (option.normalizedRect.maxX * w) + (w * 0.02)
        let clickY = option.normalizedRect.midY * h
        lastSkipTime = Date()
        await perform(.mouseClick(button: .left, at: CGPoint(x: clickX, y: clickY)))
    }

    private func skip() async {
        lastSkipTime = Date()
        let key: KeyCode = config.isUseInteractionKey
            ? (KeyBindingsConfig.bgiDefault.key(for: .pickUpOrInteract).keyCode ?? .f)
            : .space
        await perform(.keyPress(key: key))
    }

    private func perform(_ action: InputAction) async {
        _ = await inputHandler(action)
    }
}
