import Foundation

// MARK: - AutoBoss (自动首领讨伐)

/// Upstream ref: `AutoBossTask.cs` (1833 lines)
/// Teleports to boss location, navigates via pathing, enters fight, executes combat strategy.
final class BGIAutoBossService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult

    private let captureFrameProvider: CaptureFrameProvider?
    private let inputHandler: InputHandler
    private let bigMapService: BGIBigMapInteractionService
    private let autoFightService: BGIAutoFightService
    private let mainUIChecker = BGIMainUIStatusChecker()

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

    /// Run boss loop: teleport to boss coordinate, path to entrance, fight, collect.
    func runBossLoop(bossX: Double, bossY: Double, mapName: String = "Teyvat", maxCycles: Int = 1) async {
        for _ in 0..<maxCycles {
            guard !Task.isCancelled else { break }
            do {
                // 1. Teleport to boss area via nearest teleport point
                try await bigMapService.teleport(tpX: bossX, tpY: bossY, mapName: mapName, force: false)
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                // 2. Walk toward boss (hold W + sprint)
                _ = await inputHandler(.keyDown(key: .w))
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                _ = await inputHandler(.keyUp(key: .w))

                // 3. Enter boss domain / interact
                _ = await inputHandler(.keyPress(key: .f))
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                // 4. Confirm entry (click center confirm button)
                _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 960, y: 800)))
                try? await Task.sleep(nanoseconds: 5_000_000_000)

                // 5. Execute combat
                await autoFightService.executeStrategy(BGIAutoFightStrategy(
                    name: "auto-boss",
                    text: "e,q\nattack(5)\ne\nattack(3)"
                ))
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                // 6. Collect rewards (interact with blossom/chest)
                _ = await inputHandler(.keyPress(key: .f))
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                // 7. Exit domain (escape + confirm)
                _ = await inputHandler(.keyPress(key: .escape))
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 960, y: 600)))
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            } catch { break }
        }
    }
}

// MARK: - AutoDomain (自动秘境)

/// Upstream ref: `AutoDomainTask.cs` (1873 lines)
/// Teleports to domain, enters, executes combat loop, uses resin, collects rewards.
final class BGIAutoDomainService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult

    private let captureFrameProvider: CaptureFrameProvider?
    private let inputHandler: InputHandler
    private let bigMapService: BGIBigMapInteractionService
    private let autoFightService: BGIAutoFightService

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

    /// Run domain loop: teleport → enter → fight → collect → repeat.
    func runDomainLoop(domainX: Double, domainY: Double, mapName: String = "Teyvat", maxCycles: Int = 1) async {
        for _ in 0..<maxCycles {
            guard !Task.isCancelled else { break }
            do {
                // 1. Teleport to domain
                try await bigMapService.teleport(tpX: domainX, tpY: domainY, mapName: mapName, force: false)
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                // 2. Walk to domain entrance
                _ = await inputHandler(.keyDown(key: .w))
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                _ = await inputHandler(.keyUp(key: .w))

                // 3. Interact with domain door
                _ = await inputHandler(.keyPress(key: .f))
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                // 4. Use resin / start challenge (click start button ≈ right side)
                _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 1600, y: 800)))
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                _ = await inputHandler(.mouseClick(button: .left, at: CGPoint(x: 1600, y: 600)))
                try? await Task.sleep(nanoseconds: 5_000_000_000)

                // 5. Execute combat
                await autoFightService.executeStrategy(BGIAutoFightStrategy(
                    name: "auto-domain",
                    text: "e,q\nattack(5)\ne\nattack(3)"
                ))
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                // 6. Collect rewards (interact with tree)
                _ = await inputHandler(.keyPress(key: .f))
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                // 7. Exit domain
                _ = await inputHandler(.keyPress(key: .escape))
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            } catch { break }
        }
    }
}
