import Foundation
import SwiftUI

enum AppStatus: String, CaseIterable, Identifiable {
    case idle
    case running
    case paused
    case error

    var id: String { rawValue }

    var label: String {
        switch self {
        case .idle: "Idle"
        case .running: "Running"
        case .paused: "Paused"
        case .error: "Error"
        }
    }

    var tint: Color {
        switch self {
        case .idle: BGIColors.muted
        case .running: BGIColors.success
        case .paused: BGIColors.warning
        case .error: BGIColors.danger
        }
    }
}

enum RuntimeStatus: String, CaseIterable, Identifiable {
    case lost
    case detected
    case mock
    case ready
    case missing
    case ok
    case error

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lost: "Lost"
        case .detected: "Detected"
        case .mock: "Mock"
        case .ready: "Ready"
        case .missing: "Missing"
        case .ok: "OK"
        case .error: "Error"
        }
    }

    var tint: Color {
        switch self {
        case .lost, .missing, .error: BGIColors.danger
        case .detected, .ready, .ok: BGIColors.success
        case .mock: BGIColors.accent
        }
    }
}

enum LogLevel: String, CaseIterable, Identifiable {
    case trace
    case debug
    case info
    case warn
    case error

    var id: String { rawValue }

    var label: String {
        switch self {
        case .trace: "TRC"
        case .debug: "DBG"
        case .info: "INF"
        case .warn: "WRN"
        case .error: "ERR"
        }
    }

    var tint: Color {
        switch self {
        case .trace: BGIColors.muted
        case .debug: BGIColors.accent
        case .info: BGIColors.success
        case .warn: BGIColors.warning
        case .error: BGIColors.danger
        }
    }
}

enum NavigationPage: String, CaseIterable, Identifiable {
    case launch
    case realtime
    case soloTask
    case oneDragon
    case scheduler
    case jsScript
    case mapTracking
    case recordReplay
    case macro
    case hotkey
    case notification
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .launch: "启动"
        case .realtime: "实时触发"
        case .soloTask: "独立任务"
        case .oneDragon: "一条龙"
        case .scheduler: "调度器"
        case .jsScript: "JS 脚本"
        case .mapTracking: "地图追踪"
        case .recordReplay: "录制回放"
        case .macro: "辅助操控"
        case .hotkey: "快捷键"
        case .notification: "通知"
        case .settings: "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .launch: "截图器与启动"
        case .realtime: "自动化任务"
        case .soloTask: "独立运行"
        case .oneDragon: "日常流程"
        case .scheduler: "全自动"
        case .jsScript: "脚本仓库"
        case .mapTracking: "路径追踪"
        case .recordReplay: "键鼠脚本"
        case .macro: "宏与操控"
        case .hotkey: "全局热键"
        case .notification: "推送设置"
        case .settings: "软件设置"
        }
    }

    var symbolName: String {
        switch self {
        case .launch: "play"
        case .realtime: "timer"
        case .soloTask: "checklist"
        case .oneDragon: "car"
        case .scheduler: "cpu"
        case .jsScript: "doc.text"
        case .mapTracking: "map"
        case .recordReplay: "record.circle"
        case .macro: "gamecontroller"
        case .hotkey: "bolt"
        case .notification: "bell"
        case .settings: "gearshape"
        }
    }

    var isAutomationChild: Bool {
        switch self {
        case .scheduler, .jsScript, .mapTracking, .recordReplay:
            true
        default:
            false
        }
    }
}

struct MacGIFeature: Identifiable, Equatable {
    let id: String
    var name: String
    var detail: String
    var statusText: String
    var icon: BGIIcon
    var isEnabled: Bool
}

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String

    var timeText: String {
        LogEntry.formatter.string(from: timestamp)
    }

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct RuntimeMetric: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var status: RuntimeStatus
}

struct OverlayStatusItem: Identifiable {
    let id: String
    var glyph: String
    var name: String
    var isEnabled: Bool
}

struct OverlayDisplayMetric: Identifiable {
    let id: String
    var name: String
    var value: String
}

struct OverlayMapPoint: Identifiable {
    let id: String
    var xRatio: CGFloat
    var yRatio: CGFloat
    var label: String
    var tint: Color
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedPage: NavigationPage = .launch
    @Published var appStatus: AppStatus = .idle
    @Published var gameWindowStatus: RuntimeStatus = .missing
    @Published var captureStatus: RuntimeStatus = .ok
    @Published var inputStatus: RuntimeStatus = .missing
    @Published var coreStatus: RuntimeStatus = .error
    @Published var isHUDVisible = true {
        didSet { onHUDVisibilityChanged?(isHUDVisible) }
    }
    @Published var hudOpacity = 0.82
    @Published var hudMaxLogLines = 5
    @Published var showOverlayLogBox = true
    @Published var showOverlayStatus = true
    @Published var showOverlayMetrics = true
    @Published var showOverlayBorder = true
    @Published var showOverlayRecognition = true
    @Published var showOverlayDirections = true
    @Published var showOverlayMapPoints = true
    @Published var overlayUidCoverEnabled = true
    @Published var overlayLayoutEditEnabled = false
    @Published var launchAtLogin = false
    @Published var showHUDOnStart = true
    @Published var keepWindowOnTop = false
    @Published var debugPageEnabled = true
    @Published var debugConfidence = 0.86
    @Published var computePreference: BGIComputePreference = .automatic
    @Published var lastEpAssignment: BGIEpAssignment = .unknown
    var isCoreMLAvailable: Bool {
#if canImport(OnnxRuntimeBindings)
        BGIInferenceSessionFactory.isCoreMLAvailable
#else
        false
#endif
    }
    @Published var dispatcherIntervalMs = 50
    @Published var allowRuntimeRealInput = false
    @Published var schedulerGroups: [BetterGIScriptGroupSummary] = []
    @Published var schedulerCatalogIssues: [BGIScriptRepositoryCatalogIssue] = []
    @Published var schedulerCatalogStatus = "Core unavailable"
    @Published var selectedSchedulerGroupName = ""
    @Published var schedulerExecutionStatus = "Idle"
    @Published var currentSchedulerProjectID: String?

    // MARK: Window & capture (typed — not strings)

    /// Currently selected game window.
    @Published var selectedWindow: WindowInfo = .mock()

    /// Available game windows from the tracker.
    @Published var availableWindows: [WindowInfo] = []

    /// Most recently captured frame (nil if no capture session).
    @Published var lastCapturedFrame: CapturedFrame?

    /// Most recent captured image frame for OCR/template matching.
    @Published var lastCaptureImageFrame: CaptureImageFrame?

    /// Key bindings mirrored from BetterGI `KeyBindingsConfig`.
    @Published var keyBindings: KeyBindingsConfig = .bgiDefault


    /// Input safety gate (dry-run, emergency stop, rate limiting).
    let safetyGate = InputSafetyGate()

    private let frameProvider = ScreenCaptureKitFrameProvider()
    private let inputDispatcher = CGEventInputDispatcher()
    private let runtimeResourceStore: BGIRuntimeResourceStore
    let latestFrameStore = LatestFrameStore()
    private var runtimeFrameIndex: UInt64 = 0
    private var schedulerExecutionTask: Task<Void, Never>?
    private var betterGICoreSupervisor: BetterGICoreProcessSupervisor?
    private var coreStartupTask: Task<Void, Never>?
    private var coreStartupInFlight = false

    // MARK: Derived capture metrics (from lastCapturedFrame)

    var captureFPS: Int {
        guard lastCapturedFrame != nil else { return max(1, 1000 / dispatcherIntervalMs) }
        return max(1, 1000 / dispatcherIntervalMs)
    }

    var frameSize: String {
        lastCapturedFrame?.sizeDescription ?? "Unavailable"
    }

    var pixelFormat: String {
        lastCapturedFrame?.pixelFormatName ?? "Unavailable"
    }

    @Published var logLevelFilter: LogLevel = .trace
    @Published var logSearchText = ""
    @Published var inputActionLog: [String] = []
    @Published var features: [MacGIFeature] = [
        MacGIFeature(
            id: "auto-pickup",
            name: "自动拾取",
            detail: "选项不是NPC对话且不在黑名单时，自动按下 F 拾取/交互。",
            statusText: "C# Core",
            icon: .symbol("hand.wave"),
            isEnabled: true
        ),
        MacGIFeature(
            id: "auto-dialog",
            name: "自动剧情",
            detail: "快速跳过剧情文本、自动选择选项、自动提交物品等。",
            statusText: "Interval 450 ms",
            icon: .fgi("\u{f075}"),
            isEnabled: true
        ),
        MacGIFeature(
            id: "auto-hangout",
            name: "自动邀约",
            detail: "自动剧情开启的情况下此功能才会生效，自动选择邀约选项。",
            statusText: "Disabled",
            icon: .fgi("\u{e5c8}"),
            isEnabled: false
        ),
        MacGIFeature(
            id: "semi-auto-fishing",
            name: "半自动钓鱼",
            detail: "半自动钓鱼需要手动抛竿。",
            statusText: "Manual",
            icon: .fgi("\u{f578}"),
            isEnabled: false
        ),
        MacGIFeature(
            id: "auto-heal",
            name: "自动吃药",
            detail: "检测角色红血状态，自动使用便携营养袋回复生命值。",
            statusText: "C# Core",
            icon: .fgi("\u{f0f1}"),
            isEnabled: false
        ),
        MacGIFeature(
            id: "quick-teleport",
            name: "快速传送",
            detail: "在大地图上点击传送点时，自动点击传送。",
            statusText: "C# Core",
            icon: .fgi("\u{f3c5}"),
            isEnabled: false
        ),
        MacGIFeature(
            id: "map-overlay",
            name: "地图遮罩",
            detail: "在遮罩窗口中显示大地图位置与标点信息。",
            statusText: "HUD",
            icon: .fgi("\u{f279}"),
            isEnabled: false
        ),
        MacGIFeature(
            id: "cooldown-reminder",
            name: "冷却提示",
            detail: "在头像旁显示角色元素战技剩余冷却时间。",
            statusText: "C# Core",
            icon: .symbol("timer"),
            isEnabled: false
        )
    ]
    @Published var recentLogs: [LogEntry] = []

    var onHUDVisibilityChanged: ((Bool) -> Void)?

    init(resourceStore: BGIRuntimeResourceStore = .defaultStore()) {
        runtimeResourceStore = resourceStore
        addLog(.info, "betterGI-mac Swift UI initialized")
        addLog(.info, "Waiting for BetterGI C# Core Host")
        refreshWindows()
        coreStartupTask = Task { [weak self] in
            await self?.startBetterGICore()
        }
    }

    func reloadSchedulerGroupsFromCore() {
        Task { [weak self] in
            await self?.loadSchedulerGroupsFromCore()
        }
    }

    private func startBetterGICore() async {
        guard !coreStartupInFlight else { return }
        coreStartupInFlight = true
        defer { coreStartupInFlight = false }
        do {
            let supervisor = try BetterGICoreProcessSupervisor(store: runtimeResourceStore)
            let adapter = BetterGICorePlatformAdapter(appState: self)
            let handshake = try await supervisor.start { method, parameters in
                try adapter.handle(method: method, parameters: parameters)
            }
            betterGICoreSupervisor = supervisor
            coreStatus = .ok
            addLog(.info, "BetterGI Core \(handshake.runtimeVersion) connected (\(handshake.architecture))")
            await loadTriggerStatesFromCore()
            await loadSchedulerGroupsFromCore()
        } catch {
            betterGICoreSupervisor = nil
            coreStatus = .error
            setCoreCatalogUnavailable(error)
            addLog(.error, "BetterGI Core startup failed: \(error.localizedDescription)")
        }
    }

    private func loadSchedulerGroupsFromCore() async {
        guard let supervisor = betterGICoreSupervisor else {
            setCoreCatalogUnavailable(BetterGICoreRPCError.socket("BetterGI Core is not running."))
            return
        }
        do {
            schedulerGroups = try await supervisor.listScriptGroups().sorted {
                if $0.index != $1.index { return $0.index < $1.index }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            schedulerCatalogIssues = []
            if !schedulerGroups.contains(where: { $0.name == selectedSchedulerGroupName }) {
                selectedSchedulerGroupName = schedulerGroups.first?.name ?? ""
            }
            schedulerCatalogStatus = "Core loaded \(schedulerGroups.count)"
            addLog(.info, "Scheduler catalog loaded \(schedulerGroups.count) group(s) through BetterGI Core")
        } catch {
            setCoreCatalogUnavailable(error)
            addLog(.error, "BetterGI Core catalog load failed: \(error.localizedDescription)")
        }
    }

    private func setCoreCatalogUnavailable(_ error: Error) {
        schedulerGroups = []
        selectedSchedulerGroupName = ""
        schedulerCatalogStatus = "Core unavailable"
        schedulerCatalogIssues = [
            BGIScriptRepositoryCatalogIssue(path: "Core/catalog", message: error.localizedDescription)
        ]
    }

    var enabledFeatures: [MacGIFeature] {
        features.filter(\.isEnabled)
    }

    var runtimeMetrics: [RuntimeMetric] {
        [
            RuntimeMetric(title: "Game Window", value: gameWindowStatus.label, status: gameWindowStatus),
            RuntimeMetric(title: "Capture", value: "\(captureFPS) FPS", status: captureStatus),
            RuntimeMetric(title: "Input", value: inputStatus.label, status: inputStatus),
            RuntimeMetric(title: "Core", value: coreStatus.label, status: coreStatus),
            RuntimeMetric(title: "HUD", value: isHUDVisible ? "Visible" : "Hidden", status: isHUDVisible ? .ok : .missing)
        ]
    }

    var overlayStatusItems: [OverlayStatusItem] {
        [
            OverlayStatusItem(id: "pickup", glyph: "\u{f256}", name: "拾取", isEnabled: featureEnabled("auto-pickup")),
            OverlayStatusItem(id: "dialog", glyph: "\u{f075}", name: "剧情", isEnabled: featureEnabled("auto-dialog")),
            OverlayStatusItem(id: "hangout", glyph: "\u{e5c8}", name: "邀约", isEnabled: featureEnabled("auto-hangout")),
            OverlayStatusItem(id: "fishing", glyph: "\u{f578}", name: "钓鱼", isEnabled: featureEnabled("semi-auto-fishing")),
            OverlayStatusItem(id: "teleport", glyph: "\u{f3c5}", name: "传送", isEnabled: featureEnabled("quick-teleport"))
        ]
    }

    var overlayMetricDisplayItems: [OverlayDisplayMetric] {
        [
            OverlayDisplayMetric(id: "game-fps", name: "游戏帧率", value: "\(captureFPS)"),
            OverlayDisplayMetric(id: "core-status", name: "Core", value: coreStatus.label),
            OverlayDisplayMetric(id: "scheduler-status", name: "调度器", value: schedulerExecutionStatus)
        ]
    }

    var overlayMapPoints: [OverlayMapPoint] {
        []
    }

    var filteredLogs: [LogEntry] {
        recentLogs
            .filter { entry in
                LogLevel.allCases.firstIndex(of: entry.level)! >= LogLevel.allCases.firstIndex(of: logLevelFilter)!
            }
            .filter { entry in
                logSearchText.isEmpty || entry.message.localizedCaseInsensitiveContains(logSearchText)
            }
    }

    var stateDump: String {
        """
        {
          "appStatus": "\(appStatus.label)",
          "gameWindowStatus": "\(gameWindowStatus.label)",
          "captureStatus": "\(captureStatus.label)",
          "inputStatus": "\(inputStatus.label)",
          "coreStatus": "\(coreStatus.label)",
          "hudVisible": \(isHUDVisible),
          "overlay": {
            "logBox": \(showOverlayLogBox),
            "status": \(showOverlayStatus),
            "metrics": \(showOverlayMetrics),
            "directions": \(showOverlayDirections),
            "uidCover": \(overlayUidCoverEnabled)
          },
          "enabledFeatures": [\(enabledFeatures.map { "\"\($0.id)\"" }.joined(separator: ", "))],
          "keyBindings": {
            "globalKeyMappingEnabled": \(keyBindings.globalKeyMappingEnabled),
            "bindings": \(keyBindings.bindings.count),
            "pickUpOrInteract": "\(keyBindings.key(for: .pickUpOrInteract).displayName)"
          },
          "coreScheduler": {
            "taskId": "\(currentSchedulerProjectID ?? "")",
            "status": "\(schedulerExecutionStatus)",
            "selectedGroup": "\(selectedSchedulerGroupName)"
          },
          "debugConfidence": \(String(format: "%.2f", debugConfidence)),
          "selectedWindow": "\(selectedWindow.displayName)",
          "windowValid": \(isWindowValid)
        }
        """
    }

    func startOrResume() {
        safetyGate.emergencyStop = false
        safetyGate.resetCounters()
        if let supervisor = betterGICoreSupervisor, let taskID = currentSchedulerProjectID, appStatus == .paused {
            Task { [weak self] in
                do {
                    try await supervisor.resumeScheduler(taskID: taskID)
                    self?.appStatus = .running
                    self?.schedulerExecutionStatus = "running"
                    self?.addLog(.info, "Core scheduler resumed \(taskID)")
                } catch {
                    self?.appStatus = .error
                    self?.addLog(.error, "Core scheduler resume failed: \(error.localizedDescription)")
                }
            }
            return
        }
        guard betterGICoreSupervisor != nil, !selectedSchedulerGroupName.isEmpty else {
            appStatus = .error
            addLog(.error, "Cannot start: BetterGI Core or selected script group is unavailable.")
            return
        }
        runSchedulerGroups()
    }

    func pause() {
        guard let supervisor = betterGICoreSupervisor, let taskID = currentSchedulerProjectID else {
            appStatus = .error
            addLog(.error, "Cannot pause: no BetterGI Core scheduler task is active.")
            return
        }
        Task { [weak self] in
            do {
                try await supervisor.pauseScheduler(taskID: taskID)
                self?.appStatus = .paused
                self?.schedulerExecutionStatus = "paused"
                self?.addLog(.warn, "Core scheduler paused \(taskID)")
            } catch {
                self?.appStatus = .error
                self?.addLog(.error, "Core scheduler pause failed: \(error.localizedDescription)")
            }
        }
    }

    func toggleStartPause() {
        switch appStatus {
        case .running:
            pause()
        case .idle, .paused, .error:
            startOrResume()
        }
    }

    func toggleHUD() {
        isHUDVisible.toggle()
        addLog(.info, "HUD \(isHUDVisible ? "shown" : "hidden")")
    }

    func addTestLog() {
        addLog(.info, "Core=\(coreStatus.label), scheduler=\(schedulerExecutionStatus), group=\(selectedSchedulerGroupName)")
    }

    func addLog(_ level: LogLevel, _ message: String) {
        recentLogs.insert(LogEntry(timestamp: Date(), level: level, message: message), at: 0)
        if recentLogs.count > 160 {
            recentLogs.removeLast(recentLogs.count - 160)
        }
    }

    func clearLogs() {
        recentLogs.removeAll()
        addLog(.info, "Logs cleared")
    }

    func exportLogsMock() {
        addLog(.info, "Export logs requested (mock)")
    }

    func runSchedulerGroups() {
        schedulerExecutionTask?.cancel()
        currentSchedulerProjectID = nil
        guard let supervisor = betterGICoreSupervisor,
              !selectedSchedulerGroupName.isEmpty else {
            schedulerExecutionStatus = "Core unavailable"
            addLog(.error, "Cannot run scheduler: BetterGI Core or selected group is unavailable.")
            return
        }
        let groupName = selectedSchedulerGroupName
        schedulerExecutionStatus = "Starting"
        schedulerExecutionTask = Task { [weak self] in
            do {
                let taskID = try await supervisor.runSchedulerGroup(name: groupName)
                guard !Task.isCancelled else { return }
                self?.currentSchedulerProjectID = taskID
                self?.appStatus = .running
                self?.schedulerExecutionStatus = "running"
                self?.addLog(.info, "Core scheduler started group \(groupName) as \(taskID)")
            } catch {
                self?.schedulerExecutionStatus = "Failed"
                self?.addLog(.error, "Core scheduler start failed: \(error.localizedDescription)")
            }
        }
    }

    func schedulerGroupsForCurrentSelection() -> [BetterGIScriptGroupSummary] {
        let selectedGroups = schedulerGroups.filter { $0.name == selectedSchedulerGroupName }
        return selectedGroups.isEmpty ? schedulerGroups : selectedGroups
    }

    func cancelSchedulerGroups() {
        schedulerExecutionTask?.cancel()
        schedulerExecutionTask = nil
        let taskID = currentSchedulerProjectID
        currentSchedulerProjectID = nil
        guard let supervisor = betterGICoreSupervisor, let taskID else {
            schedulerExecutionStatus = "Cancelled"
            return
        }
        Task { [weak self] in
            do {
                try await supervisor.stopScheduler(taskID: taskID)
                self?.schedulerExecutionStatus = "stopping"
                self?.addLog(.warn, "Core scheduler stop requested for \(taskID)")
            } catch {
                self?.schedulerExecutionStatus = "Stop failed"
                self?.addLog(.error, "Core scheduler stop failed: \(error.localizedDescription)")
            }
        }
    }

    func featureEnabled(_ id: String) -> Bool {
        features.first(where: { $0.id == id })?.isEnabled ?? false
    }

    func canControlFeature(_ id: String) -> Bool {
        betterGICoreSupervisor != nil && Self.coreTriggerNames[id] != nil
    }

    func setFeature(_ id: String, enabled: Bool) {
        guard let triggerName = Self.coreTriggerNames[id],
              let featureName = features.first(where: { $0.id == id })?.name,
              let supervisor = betterGICoreSupervisor else {
            addLog(.error, "Feature \(id) is not exposed by BetterGI Core.")
            return
        }
        Task { [weak self] in
            do {
                try await supervisor.setTriggerEnabled(name: triggerName, enabled: enabled)
                await self?.loadTriggerStatesFromCore()
                self?.addLog(.info, "Core \(featureName) \(enabled ? "enabled" : "disabled")")
            } catch {
                self?.addLog(.error, "Core failed to update \(featureName): \(error.localizedDescription)")
            }
        }
    }

    private static let coreTriggerNames: [String: String] = [
        "auto-pickup": "AutoPick",
        "auto-dialog": "AutoSkip",
        "semi-auto-fishing": "AutoFish",
        "auto-heal": "AutoEat",
        "quick-teleport": "QuickTeleport",
        "map-overlay": "MapMask",
        "cooldown-reminder": "SkillCd",
    ]

    private func loadTriggerStatesFromCore() async {
        guard let supervisor = betterGICoreSupervisor else { return }
        do {
            let states = try await supervisor.listTriggers()
            let byName = Dictionary(uniqueKeysWithValues: states.map { ($0.name, $0) })
            for index in features.indices {
                guard let triggerName = Self.coreTriggerNames[features[index].id],
                      let state = byName[triggerName] else {
                    features[index].isEnabled = false
                    features[index].statusText = "Core unavailable"
                    continue
                }
                features[index].isEnabled = state.enabled
                features[index].statusText = "C# Core · P\(state.priority)"
            }
        } catch {
            for index in features.indices {
                features[index].isEnabled = false
                features[index].statusText = "Core unavailable"
            }
            addLog(.error, "BetterGI Core trigger catalog failed: \(error.localizedDescription)")
        }
    }

    func refreshWindows() {
        let windows = QuartzWindowEnumerator.enumerateApplicationWindows()
        if windows.isEmpty {
            availableWindows = []
            selectedWindow = .mock(title: "No game window selected")
            gameWindowStatus = .missing
            addLog(.warn, "Quartz window list contains no selectable game window")
            return
        }

        availableWindows = windows
        if let preserved = windows.first(where: { $0.id == selectedWindow.id }) {
            selectedWindow = preserved
        } else if let best = QuartzWindowEnumerator.bestGameWindow(from: windows) {
            selectedWindow = best
        }

        gameWindowStatus = selectedWindow.isLikelyGameWindow ? .detected : .missing
        let likelyCount = windows.filter(\.isLikelyGameWindow).count
        addLog(.debug, "Quartz window list refreshed — \(windows.count) windows, \(likelyCount) likely game windows")
        addLog(.info, "Selected game window: \(selectedWindow.displayName)")
    }

    func setSelectedWindow(_ window: WindowInfo) {
        selectedWindow = window
        addLog(.info, "Window selected: \(window.displayName)")
        guard window.id != 0, window.isOnScreen, !window.isMock, coreStatus != .ok else { return }
        coreStartupTask = Task { [weak self] in
            await self?.startBetterGICore()
        }
    }

    func selectWindow(byID id: CGWindowID) {
        guard let match = availableWindows.first(where: { $0.id == id }) else {
            addLog(.warn, "No window found for id \(id)")
            return
        }
        setSelectedWindow(match)
    }

    var isWindowValid: Bool {
        selectedWindow.id != 0 && selectedWindow.isOnScreen
    }

    func captureSelectedWindowOnce() {
        if selectedWindow.isMock {
            captureStatus = .error
            addLog(.error, "Capture rejected: no real on-screen game window is selected")
            return
        }

        let targetWindow = selectedWindow
        captureStatus = .detected
        addLog(.info, "ScreenCaptureKit one-shot capture requested: \(targetWindow.displayName)")
        Task {
            do {
                let imageFrame = try await frameProvider.captureWindow(targetWindow)
                latestFrameStore.update(imageFrame)
                lastCaptureImageFrame = imageFrame
                lastCapturedFrame = imageFrame.metadata
                captureStatus = .ok
                addLog(.info, "\(imageFrame.backendName) frame captured: \(imageFrame.metadata.sizeDescription) \(imageFrame.metadata.pixelFormatName)")
            } catch {
                captureStatus = .error
                addLog(.error, "ScreenCaptureKit capture failed: \(error.localizedDescription)")
            }
        }
    }

    func saveDebugFrameMock() {
        lastCaptureImageFrame = nil
        lastCapturedFrame = .mock(window: selectedWindow)
        addLog(.info, "Mock debug frame captured: \(frameSize) \(pixelFormat)")
    }

    func testInputAction(_ name: String, prefix: String = "○") {
        inputStatus = .ok
        let line = "[\(LogEntry.formatter.string(from: Date()))] \(prefix) \(name)"
        inputActionLog.insert(line, at: 0)
        if inputActionLog.count > 24 {
            inputActionLog.removeLast(inputActionLog.count - 24)
        }
        addLog(.debug, "Input action: \(name) [\(prefix)]")
    }

    /// Gate-checked dispatch — single entry point for real/mock input.
    /// Callers should NOT check the gate a second time.
    @discardableResult
    func dispatchInput(_ action: InputAction, source: ActionSource = .manual) -> InputSafetyGate.GateResult {
        let requiresForegroundCheck =
            source == .runtimeTrigger
            && !safetyGate.dryRun
            && safetyGate.realInputEnabled

        let foregroundOK = requiresForegroundCheck
            ? ForegroundWindowGuard.isTargetFrontmost(selectedWindow)
            : true

        let result = safetyGate.check(
            window: selectedWindow,
            isAppRunning: appStatus == .running,
            source: source,
            allowRuntimeRealInput: allowRuntimeRealInput,
            isTargetFrontmost: foregroundOK
        )
        switch result {
        case .allow:
            do {
                let report = try inputDispatcher.perform(action, targetWindow: selectedWindow)
                inputStatus = .ok
                testInputAction(action.displayName, prefix: "→")
                addLog(.debug, "CGEvent dispatched: \(report.detail), events=\(report.eventCount)")
            } catch {
                inputStatus = .error
                testInputAction(action.displayName, prefix: "✕")
                addLog(.error, "CGEvent dispatch failed: \(error.localizedDescription)")
            }
        case .dryRun:
            testInputAction(action.displayName, prefix: "○")
        case .blocked:
            inputStatus = .error
            testInputAction(action.displayName, prefix: "✕")
            addLog(.warn, "Input blocked: \(result.reason)")
        }
        return result
    }

    @discardableResult
    func dispatchGameAction(_ action: GIAction, type: GIKeyType = .keyPress, source: ActionSource = .manual) -> InputSafetyGate.GateResult {
        let key = keyBindings.key(for: action)
        guard let inputAction = keyBindings.inputAction(for: key, type: type) else {
            inputStatus = .error
            testInputAction("\(action.displayName): \(key.displayName)", prefix: "✕")
            addLog(.error, "Input mapping unsupported: \(action.rawValue) -> \(key.rawValue)")
            return .blocked(reason: "Unsupported key binding: \(action.rawValue) -> \(key.rawValue)")
        }

        addLog(.debug, "Game action mapped: \(action.rawValue) -> \(key.displayName) [\(type.rawValue)]")
        return dispatchInput(inputAction, source: source)
    }

    func captureFrameForBetterGICore() async throws -> CaptureImageFrame {
        let targetWindow = selectedWindow
        guard targetWindow.id != 0, targetWindow.isOnScreen, !targetWindow.isMock else {
            throw BetterGICoreRPCError.protocolViolation("No real on-screen game window is selected for Core capture.")
        }
        let imageFrame = try await frameProvider.captureWindow(targetWindow)
        latestFrameStore.update(imageFrame)
        lastCaptureImageFrame = imageFrame
        lastCapturedFrame = imageFrame.metadata
        captureStatus = .ok
        return imageFrame
    }

    var betterGICoreRunURL: URL {
        runtimeResourceStore.rootURL.appendingPathComponent("Run", isDirectory: true)
    }

    func resetUIState() {
        schedulerExecutionTask?.cancel()
        schedulerExecutionTask = nil
        appStatus = .idle
        gameWindowStatus = .missing
        captureStatus = .ok
        inputStatus = .missing
        coreStatus = .error
        debugConfidence = 0.86
        selectedWindow = .mock()
        availableWindows = []
        lastCapturedFrame = nil
        lastCaptureImageFrame = nil
        schedulerExecutionStatus = "Idle"
        currentSchedulerProjectID = nil
        safetyGate.resetCounters()
        addLog(.info, "UI state reset")
    }
}
