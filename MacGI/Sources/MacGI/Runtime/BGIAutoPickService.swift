import Foundation

struct BGIAutoPickConfig: Sendable {
    var pickCooldownMs: Int = 50
    var forceInteraction: Bool = true

    static let `default` = BGIAutoPickConfig()
}

/// First-layer port of upstream `AutoPickTrigger.OnCapture`.
///
/// The full upstream trigger (579 lines) detects the F-key pickup icon via
/// template matching, excludes chat/settings icons, OCRs the item name, and
/// applies blacklist/whitelist filtering. This skeleton detects the F-key
/// and presses interact; full OCR filtering is pending.
final class BGIAutoPickService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult

    private let captureFrameProvider: CaptureFrameProvider?
    private let inputHandler: InputHandler
    private let config: BGIAutoPickConfig
    private let templateEngine = TemplateMatchingRecognitionEngine()

    private var lastPickTime = Date.distantPast

    init(
        inputHandler: @escaping InputHandler,
        captureFrameProvider: CaptureFrameProvider? = nil,
        config: BGIAutoPickConfig = .default
    ) {
        self.inputHandler = inputHandler
        self.captureFrameProvider = captureFrameProvider
        self.config = config
    }

    func evaluate() async {
        let cooldownMs = Double(config.pickCooldownMs) / 1000.0
        guard Date().timeIntervalSince(lastPickTime) >= cooldownMs else { return }

        guard let provider = captureFrameProvider else { return }

        do {
            let frame = try await provider()
            let results = templateEngine.recognize(
                imageFrame: frame,
                objects: RecognitionObject.bgiAutoPickObjects
            ).observations

            let fKey = results.first { $0.objectID.contains("PickF") }
            guard fKey != nil else {
                // No F-key → check scroll icon and scroll down
                if hasScrollIcon(results) {
                    await perform(.verticalScroll(clicks: 2))
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                return
            }

            let chatIcon = results.first { $0.objectID.contains("ChatIcon") }
            let settingsIcon = results.first { $0.objectID.contains("SettingsIcon") }
            if !config.forceInteraction && (chatIcon != nil || settingsIcon != nil) {
                // Exclude icons visible — likely dialogue/puzzle, not pickup
                return
            }

            // Press F to pick up
            lastPickTime = Date()
            let key = KeyBindingsConfig.bgiDefault.key(for: .pickUpOrInteract).keyCode ?? .f
            await perform(.keyPress(key: key))
        } catch {
            // capture failed
        }
    }

    private func hasScrollIcon(_ results: [RecognitionObservation]) -> Bool {
        results.contains { $0.objectID.contains("Scroll") }
    }

    private func perform(_ action: InputAction) async {
        _ = await inputHandler(action)
    }
}
