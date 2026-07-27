import CoreGraphics
import Foundation
@testable import MacGI
import Testing
@Suite("BetterGI Core input acknowledgement")
struct BetterGICoreInputAcknowledgementTests {
    @MainActor
    @Test("Normal launch uses real input and dry-run is explicit")
    func launchInputPolicy() {
        let normal = AppState(
            resourceStore: temporaryStore("normal-input"),
            isTargetWindowFrontmost: { _ in true },
            launchArguments: ["betterGI-mac"])
        #expect(!normal.safetyGate.dryRun)
        #expect(normal.safetyGate.realInputEnabled)
        #expect(normal.allowRuntimeRealInput)

        let dryRun = AppState(
            resourceStore: temporaryStore("dry-run"),
            isTargetWindowFrontmost: { _ in true },
            launchArguments: ["betterGI-mac", "--dry-run"])
        #expect(dryRun.safetyGate.dryRun)
        #expect(!dryRun.safetyGate.realInputEnabled)
        #expect(!dryRun.allowRuntimeRealInput)
    }

    @MainActor
    @Test("Core input callback rejects a platform dispatch failure")
    func coreInputRejectsDispatchFailure() async throws {
        let appState = AppState(
            resourceStore: BGIRuntimeResourceStore(
                rootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("bettergi-core-input-ack-\(UUID().uuidString)", isDirectory: true)
            ),
            inputDispatcher: RejectingInputDispatcher(),
            isTargetWindowFrontmost: { _ in true }
        )
        appState.selectedWindow = WindowInfo(
            id: 42,
            ownerPID: 42,
            ownerName: "wine64-preloader",
            title: "Genshin Impact",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1
        )
        appState.appStatus = .running
        appState.runtimeLifecycle = .running
        let adapter = BetterGICorePlatformAdapter(appState: appState)
        let error = await Task.detached {
            do {
                _ = try adapter.handle(
                    method: "input.dispatch",
                    parameters: ["action": "keyPress", "key": "A"]
                )
                return nil as Error?
            } catch {
                return error
            }
        }.value

        let adapterError = try #require(error as? BetterGICorePlatformAdapterError)
        guard case .inputRejected(let reason) = adapterError else {
            Issue.record("Core input callback returned the wrong error: \(adapterError)")
            return
        }
        #expect(reason.contains("Input dispatch failed"))
        #expect(appState.inputStatus == .error)
    }

    @MainActor
    @Test("Stopped runtime rejects trigger input even while scheduler is running")
    func stoppedRuntimeRejectsTriggerInput() async throws {
        let appState = AppState(
            resourceStore: BGIRuntimeResourceStore(
                rootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("bettergi-runtime-stopped-\(UUID().uuidString)", isDirectory: true)
            ),
            inputDispatcher: RejectingInputDispatcher(),
            isTargetWindowFrontmost: { _ in true }
        )
        appState.selectedWindow = WindowInfo(
            id: 42,
            ownerPID: 42,
            ownerName: "wine64-preloader",
            title: "Genshin Impact",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1
        )
        appState.appStatus = .running
        appState.runtimeLifecycle = .stopped

        let result = appState.dispatchInput(.keyPress(key: .a), source: .runtimeTrigger)

        #expect(result.isBlocked)
        #expect(result.reason == "Automation runtime is not running")
    }

    @MainActor
    @Test("Stopping runtime permits only release-all trigger input")
    func stoppingRuntimePermitsReleaseAll() {
        let dispatcher = RecordingInputDispatcher()
        let appState = AppState(
            resourceStore: temporaryStore("runtime-stopping"),
            inputDispatcher: dispatcher,
            isTargetWindowFrontmost: { _ in true }
        )
        appState.selectedWindow = WindowInfo(
            id: 42,
            ownerPID: 42,
            ownerName: "wine64-preloader",
            title: "Genshin Impact",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1
        )
        appState.appStatus = .running
        appState.runtimeLifecycle = .stopping

        let release = appState.dispatchInput(.releaseAll, source: .runtimeTrigger)
        let key = appState.dispatchInput(.keyPress(key: .a), source: .runtimeTrigger)

        #expect(release.allowed)
        #expect(dispatcher.actions == [.releaseAll])
        #expect(key.isBlocked)
        #expect(key.reason == "Automation runtime is not running")
    }

    @MainActor
    @Test("Core owns timing for consecutive runtime input")
    func runtimeInputIsNotSplitByManualRateLimit() {
        let dispatcher = RecordingInputDispatcher()
        let appState = runningAppState(
            name: "runtime-input-sequence",
            dispatcher: dispatcher
        )
        appState.safetyGate.rateLimit = 60

        let release = appState.dispatchInput(.releaseAll, source: .runtimeTrigger)
        let key = appState.dispatchInput(.keyPress(key: .space), source: .runtimeTrigger)

        #expect(release.allowed)
        #expect(key.allowed)
        #expect(dispatcher.actions == [.releaseAll, .keyPress(key: .space)])
    }

    @MainActor
    @Test("Core mouse click preserves its absolute target")
    func coreMouseClickPreservesTarget() async {
        let dispatcher = RecordingInputDispatcher()
        let appState = runningAppState(
            name: "runtime-atomic-click",
            dispatcher: dispatcher,
            scaleFactor: 2
        )
        let adapter = BetterGICorePlatformAdapter(appState: appState)

        let error = await Task.detached {
            do {
                _ = try adapter.handle(
                    method: "input.dispatch",
                    parameters: [
                        "action": "mouseClick",
                        "button": "left",
                        "x": 123.0,
                        "y": 456.0,
                    ]
                )
                return nil as Error?
            } catch {
                return error
            }
        }.value

        #expect(error == nil)
        #expect(dispatcher.actions == [
            .mouseClick(button: .left, at: CGPoint(x: 61.5, y: 228))
        ])
    }

    @MainActor
    @Test("Core relative mouse movement preserves signed deltas")
    func coreRelativeMouseMovementPreservesDeltas() async {
        let dispatcher = RecordingInputDispatcher()
        let appState = runningAppState(
            name: "runtime-relative-mouse",
            dispatcher: dispatcher,
            scaleFactor: 2
        )
        let adapter = BetterGICorePlatformAdapter(appState: appState)

        let error = await Task.detached {
            do {
                _ = try adapter.handle(
                    method: "input.dispatch",
                    parameters: [
                        "action": "moveMouseBy",
                        "x": -37,
                        "y": 19,
                    ]
                )
                return nil as Error?
            } catch {
                return error
            }
        }.value

        #expect(error == nil)
        #expect(dispatcher.actions == [
            .mouseMoveRelative(deltaX: -37, deltaY: 19)
        ])
    }

    @MainActor
    @Test("Core absolute mouse movement remains absolute")
    func coreAbsoluteMouseMovementRemainsAbsolute() async {
        let dispatcher = RecordingInputDispatcher()
        let appState = runningAppState(
            name: "runtime-absolute-mouse",
            dispatcher: dispatcher,
            scaleFactor: 2
        )
        let adapter = BetterGICorePlatformAdapter(appState: appState)

        let error = await Task.detached {
            do {
                _ = try adapter.handle(
                    method: "input.dispatch",
                    parameters: [
                        "action": "moveMouseToScreen",
                        "x": 200,
                        "y": 400,
                    ]
                )
                return nil as Error?
            } catch {
                return error
            }
        }.value

        #expect(error == nil)
        #expect(dispatcher.actions == [
            .mouseMove(to: CGPoint(x: 100, y: 200))
        ])
    }

    @MainActor
    @Test("Core text input remains a backend-owned text action")
    func coreTextInputRemainsBackendOwned() async {
        let dispatcher = RecordingInputDispatcher()
        let appState = runningAppState(
            name: "runtime-input-text",
            dispatcher: dispatcher)
        appState.updateGameWindowFocus(frontmostPID: appState.selectedWindow.ownerPID)
        let adapter = BetterGICorePlatformAdapter(appState: appState)

        let result = await Task.detached {
            do {
                let response = try adapter.handle(
                    method: "input.dispatch",
                    parameters: [
                        "action": "inputText",
                        "text": "BetterGI 测试",
                    ]) as? [String: Any]
                return (
                    response?["acknowledged"] as? Bool == true,
                    response?["delivered"] as? Bool == true)
            } catch {
                return (false, false)
            }
        }.value

        #expect(result.0)
        #expect(result.1)
        #expect(dispatcher.actions == [.inputText("BetterGI 测试")])
    }

    @MainActor
    @Test("Background text skip acknowledges without dispatching input")
    func backgroundTextSkipDoesNotDispatch() async {
        let dispatcher = RecordingInputDispatcher()
        let suiteName = "bettergi-background-text-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            resourceStore: temporaryStore("runtime-skip-input-text"),
            inputDispatcher: dispatcher,
            isTargetWindowFrontmost: { _ in true },
            userDefaults: defaults)
        appState.selectedWindow = WindowInfo(
            id: 42,
            ownerPID: 42,
            ownerName: "wine64-preloader",
            title: "Genshin Impact",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1)
        appState.appStatus = .running
        appState.runtimeLifecycle = .running
        appState.backgroundTextInputPolicy = .skipAndContinue
        appState.updateGameWindowFocus(frontmostPID: 999)
        let adapter = BetterGICorePlatformAdapter(appState: appState)

        let result = await Task.detached {
            let response = try? adapter.handle(
                method: "input.dispatch",
                parameters: [
                    "action": "inputText",
                    "text": "千星奇域",
                ]) as? [String: Any]
            return (
                response?["acknowledged"] as? Bool == true,
                response?["delivered"] as? Bool == false,
                response?["disposition"] as? String)
        }.value

        #expect(result.0)
        #expect(result.1)
        #expect(result.2 == "skippedBackgroundText")
        #expect(dispatcher.actions.isEmpty)
    }

    @MainActor
    @Test("Core input query uses the selected input backend")
    func coreInputQueryUsesSelectedBackend() async {
        let dispatcher = RecordingInputDispatcher()
        dispatcher.queryResult = true
        let appState = runningAppState(
            name: "runtime-input-query",
            dispatcher: dispatcher)
        let adapter = BetterGICorePlatformAdapter(appState: appState)

        let isDown = await Task.detached {
            guard let result = try? adapter.handle(
                method: "input.query",
                parameters: [
                    "action": "isKeyDown",
                    "key": "F",
                ]) as? [String: Any] else {
                return false
            }
            return result["isDown"] as? Bool == true
        }.value

        #expect(isDown)
        #expect(dispatcher.queries == [.key(.f)])
    }

    @MainActor
    @Test("App shutdown closes the selected input backend")
    func appShutdownClosesSelectedBackend() {
        let dispatcher = RecordingInputDispatcher()
        let appState = AppState(
            resourceStore: temporaryStore("input-backend-shutdown"),
            inputDispatcher: dispatcher)

        appState.shutdownInputBackend()

        #expect(dispatcher.shutdownCount == 1)
    }

    @Test("Relative CGEvent preserves delta and injection marker")
    func relativeCGEventPreservesDeltaAndMarker() throws {
        let event = try CGEventInputDispatcher.makeRelativeMouseEvent(
            deltaX: -42,
            deltaY: 17,
            cursorPoint: CGPoint(x: 640, y: 360))

        #expect(event.location == CGPoint(x: 640, y: 360))
        #expect(event.getIntegerValueField(.mouseEventDeltaX) == -42)
        #expect(event.getIntegerValueField(.mouseEventDeltaY) == 17)
        #expect(
            event.getIntegerValueField(.eventSourceUserData)
                == BetterGIInputEventMarker.value)
    }

    @MainActor
    @Test("Core game-coordinate click stays atomic")
    func coreGameCoordinateClickStaysAtomic() async {
        let dispatcher = RecordingInputDispatcher()
        let appState = runningAppState(
            name: "runtime-atomic-game-click",
            dispatcher: dispatcher,
            scaleFactor: 2
        )
        let adapter = BetterGICorePlatformAdapter(appState: appState)

        let error = await Task.detached {
            do {
                _ = try adapter.handle(
                    method: "input.dispatch",
                    parameters: [
                        "action": "mouseClickGame",
                        "button": "left",
                        "x": 420,
                        "y": 830,
                        "gameWidth": 1920,
                        "gameHeight": 1080,
                    ]
                )
                return nil as Error?
            } catch {
                return error
            }
        }.value

        #expect(error == nil)
        #expect(dispatcher.actions.count == 1)
        guard let action = dispatcher.actions.first,
              case let .mouseClick(button, point) = action else {
            Issue.record("Game-coordinate click was split into multiple input actions")
            return
        }
        #expect(button == .left)
        #expect(point != nil)
    }

    @MainActor
    @Test("Button-only mouse input keeps the current cursor target")
    func buttonOnlyMouseInputDoesNotInventAWindowCenterTarget() async {
        let dispatcher = RecordingInputDispatcher()
        let appState = runningAppState(
            name: "runtime-current-cursor-click",
            dispatcher: dispatcher
        )
        let adapter = BetterGICorePlatformAdapter(appState: appState)

        let error = await Task.detached {
            do {
                _ = try adapter.handle(
                    method: "input.dispatch",
                    parameters: [
                        "action": "mouseClick",
                        "button": "left",
                    ]
                )
                return nil as Error?
            } catch {
                return error
            }
        }.value

        #expect(error == nil)
        #expect(dispatcher.actions == [
            .mouseClick(button: .left, at: nil)
        ])
    }

    @Test("Button-only mouse dispatch resolves the current cursor location")
    func buttonOnlyMouseDispatchUsesCurrentCursorLocation() {
        let explicit = CGPoint(x: 30, y: 40)
        let current = CGPoint(x: 300, y: 400)
        let window = CGRect(x: 100, y: 200, width: 800, height: 600)

        #expect(CGEventInputDispatcher.resolveClickPoint(
            explicitPoint: explicit,
            currentCursorPoint: current,
            targetWindowFrame: window
        ) == explicit)
        #expect(CGEventInputDispatcher.resolveClickPoint(
            explicitPoint: nil,
            currentCursorPoint: current,
            targetWindowFrame: window
        ) == current)
        #expect(CGEventInputDispatcher.resolveClickPoint(
            explicitPoint: nil,
            currentCursorPoint: nil,
            targetWindowFrame: window
        ) == CGPoint(x: 500, y: 500))
    }

}

private func temporaryStore(_ name: String) -> BGIRuntimeResourceStore {
    BGIRuntimeResourceStore(
        rootURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-\(name)-\(UUID().uuidString)", isDirectory: true))
}

private struct RejectingInputDispatcher: InputDispatching {
    func perform(_ action: InputAction, targetWindow: WindowInfo) throws -> CGEventDispatchReport {
        throw CGEventInputDispatchError.eventCreationFailed("verification")
    }
}

private final class RecordingInputDispatcher: InputDispatching {
    private(set) var actions: [InputAction] = []
    private(set) var queries: [InputQuery] = []
    private(set) var shutdownCount = 0
    var queryResult = false

    func perform(_ action: InputAction, targetWindow: WindowInfo) throws -> CGEventDispatchReport {
        actions.append(action)
        return CGEventDispatchReport(eventCount: 1, detail: action.displayName)
    }

    func query(_ query: InputQuery, targetWindow: WindowInfo) throws -> Bool {
        queries.append(query)
        return queryResult
    }

    func shutdown() {
        shutdownCount += 1
    }
}

@MainActor
private func runningAppState(
    name: String,
    dispatcher: RecordingInputDispatcher,
    scaleFactor: CGFloat = 1
) -> AppState {
    let appState = AppState(
        resourceStore: temporaryStore(name),
        inputDispatcher: dispatcher,
        isTargetWindowFrontmost: { _ in true }
    )
    appState.selectedWindow = WindowInfo(
        id: 42,
        ownerPID: 42,
        ownerName: "wine64-preloader",
        title: "Genshin Impact",
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        layer: 0,
        isOnScreen: true,
        scaleFactor: scaleFactor
    )
    appState.appStatus = .running
    appState.runtimeLifecycle = .running
    return appState
}
