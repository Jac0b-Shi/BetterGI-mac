import CoreGraphics
import Foundation

// MARK: - Errors

enum BGIPathingNavigationBackendError: LocalizedError, Equatable {
    case targetWindowInvalid
    case captureFailed(String)
    case localizationFailed(String)
    case inputBlocked(String)
    case moveTimeout

    var errorDescription: String? {
        switch self {
        case .targetWindowInvalid:
            "Pathing navigation target window is invalid or mock"
        case let .captureFailed(message):
            "Pathing capture failed: \(message)"
        case let .localizationFailed(message):
            "Pathing localization failed: \(message)"
        case let .inputBlocked(message):
            "Pathing input blocked: \(message)"
        case .moveTimeout:
            "Pathing move timed out before reaching target"
        }
    }
}

// MARK: - Backend config

/// Tunables matching upstream BetterGI `PathExecutor` constants.
struct BGIPathingNavigationBackendConfig: Sendable {
    /// Distance threshold for path‑point arrival (upstream `distance < 4`).
    var arrivalDistance: Double = 4.0

    /// Distance threshold for target arrival (upstream `distance < 2`).
    var closeArrivalDistance: Double = 2.0

    /// MoveTo timeout (upstream 240 s).
    var moveTimeoutSeconds: TimeInterval = 240

    /// MoveCloseTo step limit (upstream 25).
    var moveCloseToMaxSteps: Int = 25

    /// MoveCloseTo W‑hold duration per step (upstream 60 ms).
    var moveCloseToStepMs: UInt64 = 60

    /// MoveCloseTo pause between steps (upstream 20 ms).
    var moveCloseToSleepMs: UInt64 = 20

    /// Delay after reaching a target (upstream ~1000 ms).
    var targetArrivalDelayMs: UInt64 = 1000

    /// Tick interval for the MoveTo loop (upstream ~100 ms).
    var moveTickMs: UInt64 = 100

    /// Distance above which auto‑sprint is enabled in the default move mode.
    /// Upstream `distance > 20` with 2500 ms cooldown.
    var autoSprintDistance: Double = 20

    /// Cooldown between auto‑sprint triggers (upstream 2500 ms).
    var autoSprintCooldownMs: UInt64 = 2500

    /// Cooldown between dash triggers (upstream 1000 ms).
    var dashCooldownMs: UInt64 = 1000

    /// Distance above which the current position is considered too far from
    /// the waypoint. Upstream `distance > 500` → 50 retries → abandon.
    var tooFarDistance: Double = 500

    /// Max number of consecutive "too far" ticks before abandoning.
    var tooFarMaxRetries: Int = 50

    /// Faces the waypoint with `WaitUntilRotatedTo(target, 5)` (path) or `(target, 2)` (target).
    var pathFaceMaxDiff: Int = 5
    var targetFaceMaxDiff: Int = 2

    /// Teleport load‑wait, in ms. Upstream uses a polling loop with `Delay(delayMs, ct)`.
    var teleportLoadWaitMs: UInt64 = 1200
    var teleportMaxAttempts: Int = 50
}

// MARK: - Backend

/// Real implementation of `BGIPathingNavigationBackend` for macOS.
///
/// Mirrors the upstream `PathExecutor` class in parameter choices and control flow:
///   - `MoveTo`:  holds W, loops at ~100 ms ticks until `distance < 4`.
///   - `MoveCloseTo`: micro‑steps with 60 ms W presses, max 25 steps.
///   - `FaceTo`:  delegates to `BGICameraRotateService.waitUntilRotatedTo`.
///   - Sprint: uses `SprintMouse` (right mouse button), **not** `SprintKeyboard`.
///   - Teleport: delegates to `BGIBigMapInteractionService.teleport(tpX:tpY:)`.
///   - Action dispatch: delegates to a pluggable `afterActionHandler` closure.
///
/// This class is **not** `@MainActor` to keep heavy navigation loops off the UI
/// thread.  It hops to the main actor only for frame capture and input dispatch.
final class BGIRealPathingNavigationBackend: BGIPathingNavigationBackend, @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    typealias AfterActionHandler = (String?, BGIPathingWaypointForTrack) async -> Void

    // MARK: Dependencies

    private let targetWindow: WindowInfo
    private let miniMapService: BGIMiniMapLocalizationService
    private let captureFrameProvider: CaptureFrameProvider
    private let keyBindings: KeyBindingsConfig
    private let inputHandler: InputHandler
    private let cameraRotate: BGICameraRotateService
    private let bigMapService: BGIBigMapInteractionService
    private let config: BGIPathingNavigationBackendConfig
    private let afterActionHandler: AfterActionHandler?
    private lazy var autoSkipService = BGIAutoSkipService(
        inputHandler: inputHandler,
        captureFrameProvider: captureFrameProvider
    )
    private lazy var autoPickService = BGIAutoPickService(
        inputHandler: inputHandler,
        captureFrameProvider: captureFrameProvider
    )
    private lazy var autoEatService = BGIAutoEatService(
        inputHandler: inputHandler,
        captureFrameProvider: captureFrameProvider,
        config: BGIAutoEatConfig(enabled: true)
    )
    private lazy var autoFightService: BGIAutoFightService = {
        let pipeline: BGIYOLODetectionPipeline? = {
            guard let runtime = try? BGIYOLORuntime(),
                  let session = try? runtime.makeSession(model: .bgiWorld) else { return nil }
            return BGIYOLODetectionPipeline(
                session: session,
                labels: BGIOnnxModel.bgiWorld.defaultYOLOLabels
            )
        }()
        return BGIAutoFightService(
            inputHandler: inputHandler,
            keyBindings: keyBindings,
            monsterPipeline: pipeline
        )
    }()

    // MARK: State

    private let stateLock = NSLock()
    private var heldKeys: Set<KeyCode> = []
    private var lastPosition: CGPoint?
    private var lastOrientation: Double?
    private var lastSprintTime = Date.distantPast
    private var lastDashTime = Date.distantPast

    // MARK: Init

    init(
        targetWindow: WindowInfo,
        miniMapService: BGIMiniMapLocalizationService,
        captureFrameProvider: @escaping CaptureFrameProvider,
        keyBindings: KeyBindingsConfig,
        inputHandler: @escaping InputHandler,
        cameraRotate: BGICameraRotateService,
        bigMapService: BGIBigMapInteractionService,
        config: BGIPathingNavigationBackendConfig = BGIPathingNavigationBackendConfig(),
        afterActionHandler: AfterActionHandler? = nil
    ) {
        self.targetWindow = targetWindow
        self.miniMapService = miniMapService
        self.captureFrameProvider = captureFrameProvider
        self.keyBindings = keyBindings
        self.inputHandler = inputHandler
        self.cameraRotate = cameraRotate
        self.bigMapService = bigMapService
        self.config = config
        self.afterActionHandler = afterActionHandler
    }

    // MARK: - Lifecycle

    func switchPartyBefore(task: BGIPathingTask) async throws -> Bool {
        // Full upstream logic involves party detection (OCR), condition
        // matching, and a dedicated `SwitchPartyTask`.  This stub opens
        // the party screen and switches to the first slot.
        try await keyPress(action: .openPartySetupScreen)
        try await sleep(500)
        try await keyPress(action: .switchMember1)
        try await sleep(200)
        try await keyPress(action: .openPaimonMenu)
        try await sleep(200)
        return true
    }

    func validateGameWithTask(task: BGIPathingTask) async throws -> Bool {
        guard targetWindow.isOnScreen, !targetWindow.isMock else {
            return false
        }
        try await warmUpLocalization()
        return true
    }

    func initializePathing(task: BGIPathingTask) async throws {
        await releaseAllInputs()
        stateLock.withLock {
            lastPosition = nil
            lastOrientation = nil
            heldKeys.removeAll()
        }
    }

    func warmUpNavigation(mapMatchMethod: String) async throws {
        _ = mapMatchMethod
        try await warmUpLocalization()
    }

    func setPreviousPosition(_ waypoint: BGIPathingWaypointForTrack) async throws {
        stateLock.withLock {
            lastPosition = CGPoint(x: waypoint.gameX, y: waypoint.gameY)
        }
    }

    func recoverWhenLowHp(_ waypoint: BGIPathingWaypointForTrack) async throws {
        // Low‑HP detection requires `Bv.CurrentAvatarIsLowHp` which is not
        // yet ported.  For now this simply releases all inputs.
        await releaseAllInputs()
    }

    // MARK: - Teleport

    func handleTeleportWaypoint(_ waypoint: BGIPathingWaypointForTrack, force: Bool) async throws {
        _ = force
        await releaseAllInputs()

        // Use the new big‑map service for the actual teleport.
        // Fallback: if the service throws, open map + click + confirm as
        // a last resort (the upstream TpTask is preferred but requires
        // template‑matching infrastructure for GetBigMapRect / IsPointInBigMapWindow).
        do {
            try await bigMapService.teleport(tpX: waypoint.gameX, tpY: waypoint.gameY)
        } catch {
            // Fallback: open map, click near center, confirm.
            try await keyPress(action: .openMap)
            try await sleep(800)
            await perform(.mouseClick(button: .left, at: windowCenter()))
            try await sleep(400)
            try await keyPress(action: .pickUpOrInteract)
            try await sleep(config.teleportLoadWaitMs)
        }

        // Refresh position after teleport.
        try await warmUpLocalization()
    }

    // MARK: - Orientation

    func faceTo(_ waypoint: BGIPathingWaypointForTrack) async throws {
        try await updatePose()
        let targetAngle = angle(to: waypoint)
        try await cameraRotate.waitUntilRotatedTo(
            targetOrientation: targetAngle,
            maxDiff: config.targetFaceMaxDiff,
            getCurrentOrientation: { [weak self] in
                self?.lastOrientation
            }
        )
        try await sleep(500)
    }

    // MARK: - Movement

    func beforeMoveToTarget(_ waypoint: BGIPathingWaypointForTrack) async throws {
        await releaseAllInputs()
    }

    func moveTo(_ waypoint: BGIPathingWaypointForTrack) async throws {
        let start = Date()

        // Hold W for the entire movement segment.
        await keyDown(key: forwardKey, tracking: false)

        var num = 0
        var consecutiveRotationBeyondAngle = 0
        var tooFarRetryCount = 0
        var prevNotTooFarPosition: CGPoint?
        var positions: [CGPoint] = []
        var lastPositionRecord = Date()

        while Date().timeIntervalSince(start) < config.moveTimeoutSeconds {
            num += 1

            // Re‑press W if it was lifted (e.g. by Anomalies).
            await keepKeyDown(forwardKey)

            try await updatePose()
            await evaluateAutoSkipIfNeeded()
            guard let currentPosition = lastPosition else {
                try await sleep(config.moveTickMs)
                continue
            }

            let distance = hypot(
                waypoint.gameX - currentPosition.x,
                waypoint.gameY - currentPosition.y
            )

            // --- distance < 4 → arrival
            if distance < config.arrivalDistance {
                break
            }

            // --- distance > 500 → handle "too far"
            if distance > config.tooFarDistance {
                tooFarRetryCount += 1
                if tooFarRetryCount > config.tooFarMaxRetries {
                    await releaseAllInputs()
                    return
                }
                if tooFarRetryCount % 10 == 0, let prev = prevNotTooFarPosition {
                    stateLock.withLock { lastPosition = prev }
                }
                try await sleep(50)
                continue
            } else {
                prevNotTooFarPosition = currentPosition
            }

            // --- Stuck detection (8 positions, < 3 delta → trap)
            if (Date().timeIntervalSince(lastPositionRecord)) > 1.0 {
                lastPositionRecord = Date()
                positions.append(currentPosition)
                if positions.count > 8 {
                    let delta = positions[positions.count - 1] - positions[positions.count - 8]
                    if abs(delta.x) + abs(delta.y) < 3 {
                        // Simple escape: release W, rotate 90°, move, re‑press W
                        await keyUp(key: forwardKey)
                        let escapeAngle = (lastOrientation ?? 0) + 90
                        try await cameraRotate.waitUntilRotatedTo(
                            targetOrientation: escapeAngle.truncatingRemainder(dividingBy: 360),
                            maxDiff: 5,
                            getCurrentOrientation: { [weak self] in self?.lastOrientation }
                        )
                        await keyDown(key: forwardKey)
                        try await sleep(200)
                        await keyUp(key: forwardKey)
                        await keepKeyDown(forwardKey)
                        continue
                    }
                }
            }

            // --- Orientation
            let targetOrientation = angle(to: waypoint)
            let diff = await cameraRotate.rotateToApproach(
                targetOrientation: targetOrientation,
                currentOrientation: orientation(from: waypoint, currentPosition: currentPosition)
            )

            if num > 20 {
                if abs(diff) > 5 {
                    consecutiveRotationBeyondAngle += 1
                } else {
                    consecutiveRotationBeyondAngle = 0
                }
                if consecutiveRotationBeyondAngle > 10 {
                    try await cameraRotate.waitUntilRotatedTo(
                        targetOrientation: targetOrientation,
                        maxDiff: config.targetFaceMaxDiff,
                        getCurrentOrientation: { [weak self] in self?.lastOrientation }
                    )
                }
            }

            // --- Sprint / speed control
            // Upstream uses SprintMouse (right mouse button), NOT SprintKeyboard.
            switch waypoint.moveMode {
            case BGIPathingMoveMode.run:
                if distance > config.autoSprintDistance {
                    await keyDown(key: sprintMouseKey, tracking: false)
                } else {
                    await keyUp(key: sprintMouseKey)
                }
            case BGIPathingMoveMode.dash:
                if distance > config.autoSprintDistance,
                   (Date().timeIntervalSince(lastDashTime) * 1000) > Double(config.dashCooldownMs) {
                    lastDashTime = Date()
                    await keyPress(key: sprintMouseKey)
                }
            case BGIPathingMoveMode.walk:
                await keyUp(key: sprintMouseKey)
            case BGIPathingMoveMode.fly:
                await keyPress(key: jumpKey)
            case BGIPathingMoveMode.jump:
                await keyPress(key: jumpKey)
            case BGIPathingMoveMode.climb:
                break
            default:
                // Default auto‑sprint: distance > 20, cooldown 2500 ms
                if distance > config.autoSprintDistance,
                   (Date().timeIntervalSince(lastSprintTime) * 1000) > Double(config.autoSprintCooldownMs) {
                    lastSprintTime = Date()
                    await keyPress(key: sprintMouseKey)
                }
            }

            try await sleep(config.moveTickMs)
        }

        await releaseAllInputs()
    }

    func beforeMoveCloseToTarget(_ waypoint: BGIPathingWaypointForTrack) async throws {
        // Upstream handles stopFlying here; we release all as a safe default.
        if waypoint.moveMode == BGIPathingMoveMode.fly,
           waypoint.action == BGIPathingAction.stopFlying {
            try await keyPress(action: .drop)
        }
        await releaseAllInputs()
    }

    func moveCloseTo(_ waypoint: BGIPathingWaypointForTrack) async throws {
        for _ in 0..<config.moveCloseToMaxSteps {
            try await updatePose()
            guard let currentPosition = lastPosition else {
                try await sleep(100)
                continue
            }

            let distance = hypot(
                waypoint.gameX - currentPosition.x,
                waypoint.gameY - currentPosition.y
            )
            if distance < config.closeArrivalDistance { break }

            let targetOrientation = angle(to: waypoint)
            try await cameraRotate.waitUntilRotatedTo(
                targetOrientation: targetOrientation,
                maxDiff: config.targetFaceMaxDiff,
                getCurrentOrientation: { [weak self] in self?.lastOrientation }
            )

            // Micro‑step: 60 ms W press → release → 20 ms
            await keyDown(key: forwardKey, tracking: false)
            try await Task.sleep(nanoseconds: config.moveCloseToStepMs * 1_000_000)
            await keyUp(key: forwardKey)
            try await sleep(config.moveCloseToSleepMs)
        }

        await releaseAllInputs()
        try await sleep(config.targetArrivalDelayMs)
    }

    // MARK: - Action

    func afterMoveToTarget(_ waypoint: BGIPathingWaypointForTrack) async throws {
        await releaseAllInputs()
        if let handler = afterActionHandler {
            await handler(waypoint.action, waypoint)
        } else {
            await defaultAfterAction(waypoint)
        }
        try await sleep(1000)
    }

    private func defaultAfterAction(_ waypoint: BGIPathingWaypointForTrack) async {
        guard let action = waypoint.action else { return }
        switch action {
        case BGIPathingAction.fight:
            // Execute combat strategy; if YOLO pipeline available, repeat while
            // monsters detected up to a max 3 rounds to avoid infinite loops.
            for _ in 0..<3 {
                await autoFightService.executeStrategy(BGIAutoFightStrategy(
                    name: "waypoint-fight",
                    text: "e,q\nattack(3)"
                ))
                try? await sleep(1000)
                // Refresh frame to check for remaining monsters
                if let frame = try? await captureFrameProvider() {
                    let count = autoFightService.detectMonsters(in: frame.cgImage)
                    if count == 0 { break }
                }
            }
            try? await sleep(500)
        case BGIPathingAction.nahidaCollect,
             BGIPathingAction.pickAround,
             BGIPathingAction.hydroCollect,
             BGIPathingAction.electroCollect,
             BGIPathingAction.anemoCollect,
             BGIPathingAction.pyroCollect,
             BGIPathingAction.pickUpCollect:
            for _ in 0..<3 {
                try? await keyPress(action: .pickUpOrInteract)
                try? await sleep(400)
            }
        case BGIPathingAction.stopFlying:
            try? await keyPress(action: .drop)
        case BGIPathingAction.mining,
             BGIPathingAction.linneaMining:
            for _ in 0..<4 {
                try? await keyPress(action: .normalAttack)
                try? await sleep(600)
            }
        case BGIPathingAction.useGadget:
            try? await keyPress(action: .quickUseGadget)
        default:
            break
        }
    }

    // MARK: - Cleanup

    func releaseAllInputs() async {
        await perform(.releaseAll)
        stateLock.withLock { heldKeys.removeAll() }
    }

    // MARK: - Localization

    private func warmUpLocalization() async throws {
        try await updatePose()
    }

    private func evaluateAutoSkipIfNeeded() async {
        await autoSkipService.evaluate()
        await autoPickService.evaluate()
        await autoEatService.evaluate()
    }

    private func updatePose() async throws {
        let frame = try await captureFrameProvider()
        let near = stateLock.withLock { lastPosition }
        let result = try miniMapService.getPosition(from: frame, near: near, mapName: nil)
        stateLock.withLock {
            lastPosition = result.worldPoint
            lastOrientation = result.orientation.degrees
        }
    }

    // MARK: - Geometry

    private func angle(to waypoint: BGIPathingWaypointForTrack) -> Double {
        guard let current = stateLock.withLock({ lastPosition }) else { return 0 }
        let dx = waypoint.gameX - current.x
        let dy = waypoint.gameY - current.y
        guard !(dx == 0 && dy == 0) else { return 0 }
        var degrees = atan2(dy, dx) * 180 / .pi
        degrees = (degrees + 360).truncatingRemainder(dividingBy: 360)
        return degrees
    }

    private func orientation(from waypoint: BGIPathingWaypointForTrack, currentPosition: CGPoint) -> Double {
        let dx = waypoint.gameX - currentPosition.x
        let dy = waypoint.gameY - currentPosition.y
        guard !(dx == 0 && dy == 0) else { return lastOrientation ?? 0 }
        return atan2(dy, dx) * 180 / .pi
    }

    // MARK: - Key code helpers

    private var forwardKey: KeyCode {
        keyBindings.key(for: .moveForward).keyCode ?? .w
    }

    private var sprintMouseKey: KeyCode {
        keyBindings.key(for: .sprintMouse).keyCode ?? .j // will be unused if not bound
    }

    private var jumpKey: KeyCode {
        keyBindings.key(for: .jump).keyCode ?? .space
    }

    // MARK: - Input helpers

    private func keyPress(action: GIAction) async throws {
        guard let ia = keyBindings.inputAction(for: action, type: .keyPress) else { return }
        await perform(ia)
    }

    private func keyPress(key: KeyCode) async {
        await perform(.keyPress(key: key))
    }

    private func keyDown(key: KeyCode, tracking: Bool = true) async {
        if tracking {
            let alreadyHeld = !stateLock.withLock({ heldKeys.insert(key).inserted })
            guard !alreadyHeld else { return }
        }
        await perform(.keyDown(key: key))
    }

    private func keyUp(key: KeyCode) async {
        let wasHeld = stateLock.withLock { heldKeys.remove(key) != nil }
        guard wasHeld else { return }
        await perform(.keyUp(key: key))
    }

    /// Re‑send keyDown for W if it might have been released externally.
    private func keepKeyDown(_ key: KeyCode) async {
        let isHeld = stateLock.withLock { heldKeys.contains(key) }
        if !isHeld {
            await perform(.keyDown(key: key))
            stateLock.withLock { _ = heldKeys.insert(key) }
        }
    }

    private func perform(_ action: InputAction) async {
        _ = await inputHandler(action)
    }

    private func windowCenter() -> CGPoint {
        CGPoint(
            x: targetWindow.captureRect.midX,
            y: targetWindow.captureRect.midY
        )
    }

    private func sleep(_ ms: UInt64) async throws {
        try await Task.sleep(nanoseconds: ms * 1_000_000)
    }
}

// MARK: - Extensions

private extension CGPoint {
    static func -(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}

private extension NSLock {
    func withLock<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}
