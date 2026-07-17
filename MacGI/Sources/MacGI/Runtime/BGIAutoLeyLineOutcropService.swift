import Foundation

// MARK: - AutoLeyLineOutcrop (地脉花)

/// Upstream ref: `AutoLeyLineOutcropTask.cs` (3046 lines)
/// Teleports to leyline locations, enters combat, collects rewards, uses resin.
final class BGIAutoLeyLineOutcropService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult

    private let captureFrameProvider: CaptureFrameProvider?
    private let inputHandler: InputHandler
    private let bigMapService: BGIBigMapInteractionService
    private let autoFightService: BGIAutoFightService
    private let templateEngine = TemplateMatchingRecognitionEngine()

    init(
        inputHandler: @escaping InputHandler,
        captureFrameProvider: CaptureFrameProvider? = nil,
        bigMapService: BGIBigMapInteractionService,
        autoFightService: BGIAutoFightService
    ) {
        self.inputHandler = inputHandler
        self.captureFrameProvider = captureFrameProvider
        self.bigMapService = bigMapService
        self.autoFightService = autoFightService
    }

    /// Run leyline loop: navigate to leyline → fight → collect blossom → repeat.
    func runLeylineLoop(targetX: Double, targetY: Double, maxCycles: Int = 3) async {
        for _ in 0..<maxCycles {
            guard !Task.isCancelled else { break }
            do {
                // 1. Teleport to nearest teleport point near leyline
                try await bigMapService.teleport(tpX: targetX, tpY: targetY, mapName: "Teyvat", force: false)
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                // 2. Navigate toward leyline
                _ = await inputHandler(.keyDown(key: .w))
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                _ = await inputHandler(.keyUp(key: .w))

                // 3. Start leyline challenge (interact with blossom)
                _ = await inputHandler(.keyPress(key: .f))
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                // 4. Confirm use resin (click center-right)
                _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 1300, y: 600)))
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 1300, y: 600)))
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                // 5. Combat: fight spawned enemies
                await autoFightService.executeStrategy(BGIAutoFightStrategy(
                    name: "auto-leyline",
                    text: "e,q\nattack(5)\ne\nattack(3)"
                ))
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                // 6. Collect blossom rewards (interact + wait)
                _ = await inputHandler(.keyPress(key: .f))
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                // 7. Confirm reward screen
                _ = await inputHandler(.keyPress(key: .escape))
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            } catch { break }
        }
    }
}
