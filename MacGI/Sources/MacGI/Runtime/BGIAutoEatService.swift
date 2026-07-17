import Foundation

struct BGIAutoEatConfig: Sendable {
    var checkIntervalMs: Int = 150
    var eatIntervalMs: Int = 1000
    var enabled: Bool = false
    static let `default` = BGIAutoEatConfig()
}

/// First-layer port of upstream `AutoEatTrigger.OnCapture`.
/// Upstream ref: `better-genshin-impact/GameTask/AutoEat/AutoEatTrigger.cs` (142 lines).
///
/// Upstream uses `Bv.CurrentAvatarIsLowHp` (pixel color check on HP bar) +
/// `CheckRecovery` (template match `Recovery.png`) + `CheckResurrection`
/// (template match `Resurrection.png`). This skeleton uses the existing
/// AutoEat templates for recovery/resurrection detection and presses the
/// QuickUseGadget key.
final class BGIAutoEatService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult

    private let captureFrameProvider: CaptureFrameProvider?
    private let inputHandler: InputHandler
    private let config: BGIAutoEatConfig
    private let templateEngine = TemplateMatchingRecognitionEngine()

    private var lastCheckTime = Date.distantPast
    private var lastEatTime = Date.distantPast
    private var lastResurrectionTime = Date.distantPast

    init(
        inputHandler: @escaping InputHandler,
        captureFrameProvider: CaptureFrameProvider? = nil,
        config: BGIAutoEatConfig = .default
    ) {
        self.inputHandler = inputHandler
        self.captureFrameProvider = captureFrameProvider
        self.config = config
    }

    func evaluate() async {
        guard config.enabled else { return }
        guard Date().timeIntervalSince(lastCheckTime) * 1000 >= Double(config.checkIntervalMs) else { return }
        lastCheckTime = Date()

        guard let provider = captureFrameProvider else { return }
        guard let frame = try? await provider() else { return }

        let results = templateEngine.recognize(
            imageFrame: frame,
            objects: RecognitionObject.bgiAutoEatObjects
        ).observations

        let hasRecovery = results.contains { $0.objectID.contains("Recovery") }
        let hasResurrection = results.contains { $0.objectID.contains("Resurrection") }

        if hasRecovery,
           Date().timeIntervalSince(lastEatTime) * 1000 >= Double(config.eatIntervalMs) {
            lastEatTime = Date()
            await pressGadget()
        }

        if hasResurrection,
           Date().timeIntervalSince(lastResurrectionTime) >= 2 {
            lastResurrectionTime = Date()
            await pressGadget()
        }
    }

    private func pressGadget() async {
        guard let ia = KeyBindingsConfig.bgiDefault.inputAction(for: .quickUseGadget, type: .keyPress) else { return }
        _ = await inputHandler(ia)
    }
}
