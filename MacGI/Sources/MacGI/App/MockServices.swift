import Foundation

@MainActor
protocol CoreBridge {
    func start()
    func pause()
    func heartbeat()
}

@MainActor
protocol CaptureService {
    /// Refresh the available window list.
    func refreshWindows()

    /// Save a debug frame snapshot.
    func saveDebugFrame()

    /// Available game windows (typed).
    var availableWindows: [WindowInfo] { get async }

    /// Currently selected window.
    var selectedWindow: WindowInfo? { get async }
}

@MainActor
protocol InputService {
    /// Legacy string-based action (for mock UI).
    func perform(_ action: String)

    /// Typed input action with safety gate.
    func perform(_ action: InputAction, on window: WindowInfo) async -> InputSafetyGate.GateResult
}

@MainActor
protocol GameWindowTracker {
    /// Refresh the window list.
    func refresh()

    /// Current windows (typed).
    var windows: [WindowInfo] { get async }
}

@MainActor
final class MockCoreBridge: CoreBridge {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        appState.startOrResume()
    }

    func pause() {
        appState.pause()
    }

    func heartbeat() {
        appState.addTestLog()
    }
}

@MainActor
final class MockCaptureService: CaptureService {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func refreshWindows() {
        appState.refreshWindows()
    }

    func saveDebugFrame() {
        appState.saveDebugFrameMock()
    }

    var availableWindows: [WindowInfo] {
        get async { appState.availableWindows }
    }

    var selectedWindow: WindowInfo? {
        get async { appState.selectedWindow }
    }
}

@MainActor
final class MockInputService: InputService {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func perform(_ action: String) {
        appState.testInputAction(action)
    }

    func perform(_ action: InputAction, on window: WindowInfo) async -> InputSafetyGate.GateResult {
        // Dispatch through AppState's single gate entry — no double-check.
        appState.dispatchInput(action)
        return .allow // mock always returns allow for API compat
    }
}

@MainActor
final class MockGameWindowTracker: GameWindowTracker {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func refresh() {
        appState.refreshWindows()
    }

    var windows: [WindowInfo] {
        get async { appState.availableWindows }
    }
}

@MainActor
final class MockRuntimeServices {
    let coreBridge: CoreBridge
    let captureService: CaptureService
    let inputService: InputService
    let gameWindowTracker: GameWindowTracker

    init(appState: AppState) {
        coreBridge = MockCoreBridge(appState: appState)
        captureService = MockCaptureService(appState: appState)
        inputService = MockInputService(appState: appState)
        gameWindowTracker = MockGameWindowTracker(appState: appState)
    }
}
