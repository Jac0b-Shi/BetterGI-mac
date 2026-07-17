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
    @Published var gameWindowStatus: RuntimeStatus = .mock
    @Published var captureStatus: RuntimeStatus = .ok
    @Published var inputStatus: RuntimeStatus = .mock
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
    @Published var runtimeLoopTickCount: UInt64 = 0
    @Published var runtimeLoopSkippedTicks: UInt32 = 0
    @Published var runtimeLoopLastTickCostMs: Double = 0
    @Published var allowRuntimeRealInput = false
    @Published var jsScriptExecutionStatus = "Idle"
    @Published var lastJSScriptExecutionResult: BGIJSScriptExecutionResult?
    @Published var schedulerGroups: [BGIScriptGroup] = []
    @Published var schedulerCatalogIssues: [BGIScriptRepositoryCatalogIssue] = []
    @Published var schedulerCatalogStatus = "Core unavailable"
    @Published var selectedSchedulerGroupName = ""
    @Published var schedulerExecutionStatus = "Idle"
    @Published var currentSchedulerProjectID: String?
    @Published var lastKeyMousePlaybackResult: BGIKeyMousePlaybackResult?
    @Published var lastShellExecutionResult: BGIShellExecutionResult?
    @Published var lastPathingExecutionResult: BGIPathingExecutionResult?

    // MARK: Window & capture (typed — not strings)

    /// Currently selected game window.
    @Published var selectedWindow: WindowInfo = .mock()

    /// Available game windows from the tracker.
    @Published var availableWindows: [WindowInfo] = [
        .mock(), .mock(title: "Genshin Impact (Mock)")
    ]

    /// Most recently captured frame (nil if no capture session).
    @Published var lastCapturedFrame: CapturedFrame?

    /// Most recent captured image frame for OCR/template matching.
    @Published var lastCaptureImageFrame: CaptureImageFrame?

    /// Recognition objects mirrored from BetterGI `RecognitionObject` definitions.
    @Published var recognitionObjects: [RecognitionObject] = RecognitionObject.bgiP0Defaults

    /// Key bindings mirrored from BetterGI `KeyBindingsConfig`.
    @Published var keyBindings: KeyBindingsConfig = .bgiDefault

    /// Trigger descriptors mirrored from BetterGI `GameTaskManager.LoadInitialTriggers()`.
    @Published var triggerDescriptors: [TaskTriggerDescriptor] = TaskTriggerDescriptor.bgiInitialTriggers

    /// Last dispatcher tick result.
    @Published var runtimeSnapshot: AutomationRuntimeSnapshot = .empty

    /// Input safety gate (dry-run, emergency stop, rate limiting).
    let safetyGate = InputSafetyGate()

    private let automationRuntime = MockAutomationRuntime()
    private let templateRecognitionEngine = TemplateMatchingRecognitionEngine()
    private let frameProvider = ScreenCaptureKitFrameProvider()
    private let inputDispatcher = CGEventInputDispatcher()
    private let runtimeLoop = TaskTriggerLoopController()
    private let rustCoreBridge: RustCoreBridge?
    private let miniMapService: BGIMiniMapLocalizationService
    private let runtimeResourceStore: BGIRuntimeResourceStore
    let latestFrameStore = LatestFrameStore()
    private var runtimeFrameIndex: UInt64 = 0
    private var jsScriptExecutionTask: Task<Void, Never>?
    private var schedulerExecutionTask: Task<Void, Never>?
    private var betterGICoreSupervisor: BetterGICoreProcessSupervisor?
    private var coreStartupTask: Task<Void, Never>?

    // MARK: Derived capture metrics (from lastCapturedFrame)

    var captureFPS: Int {
        guard lastCapturedFrame != nil else { return max(1, 1000 / dispatcherIntervalMs) }
        return max(1, 1000 / dispatcherIntervalMs)
    }

    var frameSize: String {
        lastCapturedFrame?.sizeDescription ?? "2560 × 1440"
    }

    var pixelFormat: String {
        lastCapturedFrame?.pixelFormatName ?? "BGRA8888"
    }

    var lastFrameTime: String {
        String(format: "%.1f ms", runtimeSnapshot.metrics.processingCostMs)
    }
    @Published var logLevelFilter: LogLevel = .trace
    @Published var logSearchText = ""
    @Published var inputActionLog: [String] = [
        "Mock input service ready",
        "Accessibility permission: Mock",
        "Screen recording permission: Mock"
    ]
    @Published var features: [MacGIFeature] = [
        MacGIFeature(
            id: "auto-pickup",
            name: "自动拾取",
            detail: "选项不是NPC对话且不在黑名单时，自动按下 F 拾取/交互。",
            statusText: "OCR Mock",
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
            statusText: "Mock",
            icon: .fgi("\u{f0f1}"),
            isEnabled: false
        ),
        MacGIFeature(
            id: "quick-teleport",
            name: "快速传送",
            detail: "在大地图上点击传送点时，自动点击传送。",
            statusText: "Mock",
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
            statusText: "Mock",
            icon: .symbol("timer"),
            isEnabled: false
        )
    ]
    @Published var recentLogs: [LogEntry] = []

    var onHUDVisibilityChanged: ((Bool) -> Void)?

    init(resourceStore: BGIRuntimeResourceStore = .defaultStore()) {
        runtimeResourceStore = resourceStore
        let bridge = RustCoreBridge.loadDefault()
        rustCoreBridge = bridge
        miniMapService = BGIMiniMapLocalizationService()
        addLog(.info, "betterGI-mac Swift UI prototype initialized")
        addLog(.info, "HUD panel prepared in mock mode")
        if let bridge {
            addLog(.debug, "Core bridge: \(bridge.statusText) at \(bridge.libraryPath)")
        } else {
            addLog(.debug, "Rust acceleration bridge unavailable")
        }
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
        do {
            let supervisor = try BetterGICoreProcessSupervisor(store: runtimeResourceStore)
            let adapter = BetterGICorePlatformAdapter(appState: self)
            let handshake = try await supervisor.start { method, parameters in
                try adapter.handle(method: method, parameters: parameters)
            }
            betterGICoreSupervisor = supervisor
            coreStatus = .ok
            addLog(.info, "BetterGI Core \(handshake.runtimeVersion) connected (\(handshake.architecture))")
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
            let summaries = try await supervisor.listScriptGroups()
            var groups: [BGIScriptGroup] = []
            groups.reserveCapacity(summaries.count)
            let decoder = JSONDecoder()
            for summary in summaries {
                let document = try await supervisor.getScriptGroup(name: summary.name)
                groups.append(try decoder.decode(BGIScriptGroup.self, from: document.documentData))
            }
            schedulerGroups = groups.sorted {
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
            OverlayDisplayMetric(id: "processing-cost", name: "处理耗时", value: lastFrameTime),
            OverlayDisplayMetric(id: "confidence", name: "识别置信", value: String(format: "%.2f", runtimeSnapshot.metrics.confidence)),
            OverlayDisplayMetric(id: "capture-cost", name: "截图耗时", value: String(format: "%.1f ms", runtimeSnapshot.metrics.captureCostMs)),
            OverlayDisplayMetric(id: "trigger-cost", name: "触发耗时", value: String(format: "%.1f ms", runtimeSnapshot.metrics.triggerCostMs)),
            OverlayDisplayMetric(id: "skipped-ticks", name: "跳过次数", value: "\(runtimeLoopSkippedTicks + runtimeSnapshot.metrics.skippedTicks)"),
            OverlayDisplayMetric(id: "gpu-usage", name: "显卡占用", value: "Mock"),
            OverlayDisplayMetric(id: "cpu-usage", name: "CPU占用", value: "12%"),
            OverlayDisplayMetric(id: "memory-usage", name: "内存占用", value: "48%")
        ]
    }

    var overlayMapPoints: [OverlayMapPoint] {
        [
            OverlayMapPoint(id: "teleport", xRatio: 0.58, yRatio: 0.34, label: "传送点", tint: BGIColors.accent),
            OverlayMapPoint(id: "ore", xRatio: 0.68, yRatio: 0.48, label: "矿点", tint: BGIColors.warning),
            OverlayMapPoint(id: "boss", xRatio: 0.47, yRatio: 0.58, label: "首领", tint: BGIColors.danger),
            OverlayMapPoint(id: "route", xRatio: 0.61, yRatio: 0.68, label: "路径", tint: BGIColors.success)
        ]
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
          "dispatcher": {
            "frameIndex": \(runtimeSnapshot.frameIndex),
            "uiCategory": "\(runtimeSnapshot.currentGameUiCategory.rawValue)",
            "recognitionObjects": \(runtimeSnapshot.recognitionObjects.count),
            "observations": \(runtimeSnapshot.observations.count),
            "decisions": \(runtimeSnapshot.decisions.count)
          },
          "keyBindings": {
            "globalKeyMappingEnabled": \(keyBindings.globalKeyMappingEnabled),
            "bindings": \(keyBindings.bindings.count),
            "pickUpOrInteract": "\(keyBindings.key(for: .pickUpOrInteract).displayName)"
          },
          "runtimeLoop": {
            "running": \(runtimeLoop.isRunning),
            "intervalMs": \(dispatcherIntervalMs),
            "tickCount": \(runtimeLoopTickCount),
            "skippedTicks": \(runtimeLoopSkippedTicks),
            "lastTickCostMs": \(String(format: "%.1f", runtimeLoopLastTickCostMs))
          },
          "debugConfidence": \(String(format: "%.2f", debugConfidence)),
          "selectedWindow": "\(selectedWindow.displayName)",
          "windowValid": \(isWindowValid)
        }
        """
    }

    // MARK: - Computed properties for DebugPage / runtime status

    var isRustCoreAvailable: Bool {
        rustCoreBridge != nil
    }

    var rustCoreStatusText: String {
        rustCoreBridge?.statusText ?? "Rust acceleration unavailable"
    }

    /// Minimal asset coverage placeholder.
    /// Real implementation should query BGIAssetResolver / BGIModelAssetResolver.
    struct AssetCoverage {
        let total: Int
        let missing: [String]
    }

    var bgiAssetCoverage: AssetCoverage {
        AssetCoverage(total: 9, missing: [])
    }

    var bgiAssetStatusText: String {
        "Asset coverage: placeholder"
    }

    var bgiModelAssetCoverage: AssetCoverage {
        AssetCoverage(total: 3, missing: [])
    }

    var bgiModelAssetStatusText: String {
        "Model coverage: placeholder"
    }

    var isPaddleOCRRuntimeReady: Bool {
        // TODO: wire to actual PaddleOCROnnxRuntime initialization status
        false
    }

    var paddleOCRRuntimeStatusText: String {
        "OCR runtime: unchecked"
    }

    func startOrResume() {
        appStatus = .running
        gameWindowStatus = .detected
        captureStatus = .ok
        inputStatus = .ok
        rustCoreBridge?.start()
        safetyGate.emergencyStop = false
        safetyGate.resetCounters()
        startRuntimeLoop()
        addLog(.info, "Task dispatcher started")
    }

    func pause() {
        if appStatus == .running && !selectedWindow.isMock {
            dispatchInput(.releaseAll)
        }
        rustCoreBridge?.pause()
        stopRuntimeLoop()
        appStatus = .paused
        addLog(.warn, "Task dispatcher paused")
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
        if appStatus == .running {
            Task { await runDispatcherTick(forceMockCapture: false) }
        } else {
            let messages = [
                "MOCK Core idle: dispatcher waits for Start",
                "MOCK RecognitionObject loaded: \(recognitionObjects.count)",
                "MOCK Trigger list loaded: \(triggerDescriptors.count)",
                "MOCK Game window bounds updated"
            ]
            addLog(.info, messages.randomElement() ?? "MOCK heartbeat")
        }
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

    func runInstalledJSScript(folderName: String, settingsJSON: String = "{}") {
        _ = (folderName, settingsJSON)
        jsScriptExecutionTask?.cancel()
        jsScriptExecutionTask = nil
        jsScriptExecutionStatus = "Core scheduler unavailable"
        addLog(.error, "JS execution is disabled until BetterGI Core advertises scheduler.run; Swift JavaScriptCore fallback is prohibited.")
    }

    func cancelInstalledJSScript() {
        jsScriptExecutionTask?.cancel()
        jsScriptExecutionTask = nil
        jsScriptExecutionStatus = "Cancelled"
        addLog(.warn, "JS script execution cancelled")
    }

    func runSchedulerGroups() {
        schedulerExecutionTask?.cancel()
        cancelInstalledJSScript()
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
                self?.schedulerExecutionStatus = "running"
                self?.addLog(.info, "Core scheduler started group \(groupName) as \(taskID)")
            } catch {
                self?.schedulerExecutionStatus = "Failed"
                self?.addLog(.error, "Core scheduler start failed: \(error.localizedDescription)")
            }
        }
    }

    func schedulerGroupsForCurrentSelection() -> [BGIScriptGroup] {
        let selectedGroups = schedulerGroups.filter { $0.name == selectedSchedulerGroupName }
        return selectedGroups.isEmpty ? schedulerGroups : selectedGroups
    }

    func cancelSchedulerGroups() {
        schedulerExecutionTask?.cancel()
        schedulerExecutionTask = nil
        cancelInstalledJSScript()
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

    // MARK: - Scheduler UI Actions

    func toggleSchedulerProject(at index: Int) {
        guard let groupIdx = schedulerGroups.firstIndex(where: { $0.name == selectedSchedulerGroupName }) ?? 0 as Int?,
              index < schedulerGroups[groupIdx].projects.count else { return }
        let current = schedulerGroups[groupIdx].projects[index].status
        schedulerGroups[groupIdx].projects[index].status = current == .enabled ? .disabled : .enabled
    }

    func addSchedulerProject(type: String) {
        guard let idx = schedulerGroups.firstIndex(where: { $0.name == selectedSchedulerGroupName }) ?? 0 as Int? else { return }
        let count = schedulerGroups[idx].projects.count
        let projectType = BGIScriptGroupProjectType(rawValue: type) ?? .javascript
        schedulerGroups[idx].projects.append(BGIScriptGroupProject(
            index: count + 1,
            name: "新项目",
            folderName: "",
            type: projectType,
            status: .enabled
        ))
    }

    func removeSchedulerProject(at index: Int) {
        guard let idx = schedulerGroups.firstIndex(where: { $0.name == selectedSchedulerGroupName }) ?? 0 as Int?,
              index < schedulerGroups[idx].projects.count else { return }
        schedulerGroups[idx].projects.remove(at: index)
    }

    func setNextFlag(at index: Int) {
        guard let idx = schedulerGroups.firstIndex(where: { $0.name == selectedSchedulerGroupName }) ?? 0 as Int?,
              index < schedulerGroups[idx].projects.count else { return }
        schedulerGroups[idx].projects[index].nextFlag = true
        currentSchedulerProjectID = "\(schedulerGroups[idx].projects[index].index)"
    }

    func clearSchedulerProjects() {
        guard let idx = schedulerGroups.firstIndex(where: { $0.name == selectedSchedulerGroupName }) ?? 0 as Int? else { return }
        schedulerGroups[idx].projects.removeAll()
        persistCurrentSchedulerGroup()
    }

    func reverseSchedulerProjects() {
        guard let idx = schedulerGroups.firstIndex(where: { $0.name == selectedSchedulerGroupName }) ?? 0 as Int? else { return }
        schedulerGroups[idx].projects.reverse()
        for i in 0..<schedulerGroups[idx].projects.count {
            schedulerGroups[idx].projects[i].index = i + 1
        }
        persistCurrentSchedulerGroup()
    }

    /// Persist the currently selected scheduler group back to User/ScriptGroup/{name}.json
    private func persistCurrentSchedulerGroup() {
        guard let group = schedulerGroups.first(where: { $0.name == selectedSchedulerGroupName }) else { return }
        let url = runtimeResourceStore.userScriptGroupURL(for: group.name)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(group)
            try data.write(to: url)
            addLog(.info, "Saved scheduler group: \(group.name)")
        } catch {
            addLog(.error, "Failed to save scheduler group \(group.name): \(error.localizedDescription)")
        }
    }

    private func waitForCurrentJSScriptTask() async {
        while jsScriptExecutionTask != nil && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func runInstalledKeyMouseScript(name: String) async throws -> BGIKeyMousePlaybackResult {
        let targetWindow = selectedWindow
        let executor = BGIKeyMouseMacroExecutor()
        return try await executor.executeInstalledScript(
            name: name,
            targetWindow: targetWindow
        ) { [weak self] action in
            guard let self else { return }
            _ = self.dispatchInput(action, source: .runtimeTrigger)
        }
    }

    private func runShellProject(
        _ project: BGIScriptGroupProject,
        in group: BGIScriptGroup
    ) async throws -> BGIShellExecutionResult {
        let config = group.config.enableShellConfig ? group.config.shellConfig : BGIShellConfig()
        let executor = BGIShellTaskExecutor()
        return try await executor.execute(command: project.name, config: config)
    }

    private func runPathingProject(_ project: BGIScriptGroupProject) async throws -> BGIPathingExecutionResult {
        let executor = BGIPathingTaskExecutor()
        let inputHandler: @MainActor (InputAction) -> InputSafetyGate.GateResult = { [weak self] action in
            guard let self else { return .blocked(reason: "AppState released") }
            return self.dispatchInput(action, source: .runtimeTrigger)
        }
        let captureForBigMapPosition: BGIBigMapInteractionService.CaptureFrameProvider = { [weak self] in
            guard let self else {
                throw BGIPathingNavigationBackendError.targetWindowInvalid
            }
            let frame = try await self.frameProvider.captureWindow(self.selectedWindow)
            self.latestFrameStore.update(frame)
            return frame
        }
        let siftPositionProvider = rustCoreBridge?.makeBigMapSiftBridge().map { bridge in
            BGIBigMapSiftPositionProvider(
                captureFrameProvider: captureForBigMapPosition,
                matcher: bridge,
                store: runtimeResourceStore
            )
        }
        let bigMapPositionProvider: BGIBigMapInteractionService.BigMapPositionProvider = { [weak self] mapName in
            guard let self else { throw BGIPathingNavigationBackendError.targetWindowInvalid }
            if let siftPositionProvider {
                return try await siftPositionProvider.getBigMapCenter(mapName: mapName)
            }
            // SIFT not available (no big-map-sift feature dylib) → minimap fallback
            let frame = try await captureForBigMapPosition()
            let result = try self.miniMapService.getPosition(from: frame, near: nil, mapName: mapName)
            guard result.worldPoint.x != 0 || result.worldPoint.y != 0 else {
                throw BGIBigMapInteractionError.bigMapPositionUnavailable
            }
            return result.worldPoint
        }
        let backend = BGIRealPathingNavigationBackend(
            targetWindow: selectedWindow,
            miniMapService: miniMapService,
            captureFrameProvider: { [weak self] in
                guard let self else {
                    throw BGIPathingNavigationBackendError.targetWindowInvalid
                }
                let frame = try await self.frameProvider.captureWindow(self.selectedWindow)
                self.latestFrameStore.update(frame)
                return frame
            },
            keyBindings: keyBindings,
            inputHandler: inputHandler,
            cameraRotate: BGICameraRotateService(inputHandler: inputHandler),
            bigMapService: BGIBigMapInteractionService(
                inputHandler: inputHandler,
                captureFrameProvider: captureForBigMapPosition,
                recognitionObjectProvider: { frame, object in
                    let engine = try PaddleOCRRecognitionEngine()
                    return engine.recognize(imageFrame: frame, objects: [object]).observations
                },
                bigMapPositionProvider: bigMapPositionProvider,
                keyBindings: keyBindings,
                config: .forWindow(selectedWindow)
            )
        )
        return try await executor.executeInstalledProject(
            name: project.name,
            folderName: project.folderName,
            navigationBackend: backend
        )
    }

    func featureEnabled(_ id: String) -> Bool {
        features.first(where: { $0.id == id })?.isEnabled ?? false
    }

    func setFeature(_ id: String, enabled: Bool) {
        guard let index = features.firstIndex(where: { $0.id == id }) else { return }
        features[index].isEnabled = enabled
        addLog(.info, "\(features[index].name) \(enabled ? "enabled" : "disabled")")
    }

    func refreshWindows() {
        let windows = QuartzWindowEnumerator.enumerateApplicationWindows()
        if windows.isEmpty {
            availableWindows = [.mock(), .mock(title: "Genshin Impact (Mock)")]
            selectedWindow = availableWindows[0]
            gameWindowStatus = .mock
            addLog(.warn, "Quartz window list empty; using mock game windows")
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
            saveDebugFrameMock()
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

    func runMockDispatcherTick() {
        Task { await runDispatcherTick(forceMockCapture: true) }
    }

    /// Last template recognition report for tick logging.
    private var lastTemplateReport: TemplateRecognitionReport?

    func runDispatcherTick(forceMockCapture: Bool = false) async {
        guard appStatus == .running else {
            addLog(.warn, "Dispatcher tick ignored because app is not running")
            return
        }

        let captureStartedAt = Date()
        guard let frame = await captureFrameForDispatcher(forceMockCapture: forceMockCapture) else {
            return
        }
        let captureCostMs = Date().timeIntervalSince(captureStartedAt) * 1000

        runtimeSnapshot = automationRuntime.process(
            frame: frame,
            recognitionObjects: recognitionObjects,
            triggerDescriptors: triggerDescriptors,
            enabledFeatureIDs: Set(enabledFeatures.map(\.id)),
            confidenceFloor: debugConfidence,
            keyBindings: keyBindings,
            captureCostMs: captureCostMs,
            observationProvider: recognitionObservationProvider(for: lastCaptureImageFrame)
        )

        captureStatus = .ok
        inputStatus = .ok
        let shouldLogTick = !runtimeLoop.isRunning || runtimeSnapshot.frameIndex % 20 == 0 || !runtimeSnapshot.decisions.isEmpty
        if shouldLogTick {
            var logParts = "Dispatcher tick #\(runtimeSnapshot.frameIndex): ui=\(runtimeSnapshot.currentGameUiCategory.rawValue) ro=\(runtimeSnapshot.recognitionObjects.count) obs=\(runtimeSnapshot.observations.count) decisions=\(runtimeSnapshot.decisions.count)"
            if let report = lastTemplateReport {
                logParts += " tmpl backend=\(report.backendName) objects=\(report.objectCount) matched=\(report.matchedCount) cost=\(String(format: "%.1f", report.costMs))ms"
                let ids = report.observations.prefix(5).map(\.objectName)
                if !ids.isEmpty {
                    logParts += " top=\(ids.joined(separator: ","))"
                }
            }
            addLog(.debug, logParts)

            for observation in runtimeSnapshot.observations.prefix(3) {
                addLog(.trace, "RecognitionObject \(observation.objectName): \(String(format: "%.2f", observation.confidence))")
            }
        }

        for decision in runtimeSnapshot.decisions {
            addLog(.info, "\(decision.triggerID.label): \(decision.reason)")
            for action in decision.actions {
                dispatchInput(action, source: .runtimeTrigger)
            }
        }
    }

    private func recognitionObservationProvider(
        for imageFrame: CaptureImageFrame?
    ) -> (([RecognitionObject]) -> [RecognitionObservation])? {
        guard let imageFrame else { return nil }
        return { [rustCoreBridge, templateRecognitionEngine] activeObjects in
            if let report = rustCoreBridge?.recognizeTemplates(
                imageFrame: imageFrame,
                objects: activeObjects
            ) {
                Task { @MainActor [weak self] in
                    self?.lastTemplateReport = report
                }
                return report.observations
            }
            let fallbackReport = templateRecognitionEngine.recognize(
                imageFrame: imageFrame,
                objects: activeObjects
            )
            Task { @MainActor [weak self] in
                self?.lastTemplateReport = fallbackReport
            }
            return fallbackReport.observations
        }
    }

    private func captureFrameForJSScript(targetWindow: WindowInfo) async throws -> CaptureImageFrame {
        if let lastCaptureImageFrame {
            return lastCaptureImageFrame
        }
        if targetWindow.isMock {
            let imageFrame = try makeMockJSScriptCaptureFrame(window: targetWindow)
            lastCaptureImageFrame = imageFrame
            lastCapturedFrame = imageFrame.metadata
            return imageFrame
        }
        let imageFrame = try await frameProvider.captureWindow(targetWindow)
        latestFrameStore.update(imageFrame)
        lastCaptureImageFrame = imageFrame
        lastCapturedFrame = imageFrame.metadata
        return imageFrame
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

    private func makeMockJSScriptCaptureFrame(window: WindowInfo) throws -> CaptureImageFrame {
        let width = 320
        let height = 180
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        for pixelIndex in 0..<(width * height) {
            let offset = pixelIndex * bytesPerPixel
            rgba[offset] = 18
            rgba[offset + 1] = 20
            rgba[offset + 2] = 24
            rgba[offset + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw BGIJSScriptRuntimeError.scriptException("Unable to create mock JS capture image.")
        }

        runtimeFrameIndex = (runtimeFrameIndex + 1) % UInt64(CapturedFrame.maxFrameIndex(intervalMs: dispatcherIntervalMs))
        let metadata = CapturedFrame(
            frameIndex: runtimeFrameIndex,
            timestamp: Date(),
            width: width,
            height: height,
            scaleFactor: window.scaleFactor,
            pixelFormat: 0x42475241,
            bytesPerRow: bytesPerRow,
            sourceWindow: window
        )
        return CaptureImageFrame(metadata: metadata, cgImage: image, backendName: "MockJS")
    }

    private func ocrResult(
        frame: CaptureImageFrame,
        roi: CGRect?,
        engine: PaddleOCRRecognitionEngine
    ) -> OCRResult {
        let object = RecognitionObject(
            id: "JS.Ocr",
            recognitionType: .ocr,
            regionOfInterest: roi.map {
                RecognitionROI(
                    x: $0.minX / max(1, Double(frame.metadata.width)),
                    y: $0.minY / max(1, Double(frame.metadata.height)),
                    width: $0.width / max(1, Double(frame.metadata.width)),
                    height: $0.height / max(1, Double(frame.metadata.height)),
                    coordinateSpace: .normalized
                )
            },
            name: "JS.Ocr"
        )
        let report = engine.recognize(imageFrame: frame, objects: [object])
        return OCRResult(
            regions: report.observations.map { observation in
                OCRResult.Region(
                    boundingBox: CGRect(
                        x: observation.normalizedRect.minX * CGFloat(frame.metadata.width),
                        y: observation.normalizedRect.minY * CGFloat(frame.metadata.height),
                        width: observation.normalizedRect.width * CGFloat(frame.metadata.width),
                        height: observation.normalizedRect.height * CGFloat(frame.metadata.height)
                    ),
                    text: observation.text ?? "",
                    confidence: Float(observation.confidence)
                )
            },
            sourceROI: nil,
            frameIndex: frame.metadata.frameIndex,
            timestamp: frame.metadata.timestamp
        )
    }

    private func dispatchRecordedJSScriptInputCommands(
        _ commands: [BGIJSScriptInputCommand],
        targetWindow: WindowInfo,
        imageFrame: CaptureImageFrame
    ) {
        let gameMetrics = [
            Double(imageFrame.metadata.width),
            Double(imageFrame.metadata.height),
            Double(imageFrame.metadata.scaleFactor)
        ]
        for command in commands {
            guard let action = BGIJSScriptTaskExecutor.inputAction(
                for: command,
                targetWindow: targetWindow,
                gameMetrics: gameMetrics
            ) else {
                continue
            }
            _ = dispatchInput(action, source: .runtimeTrigger)
        }
    }

    func dispatchRecordedJSScriptGenshinCommands(
        _ commands: [BGIJSScriptGenshinCommand],
        targetWindow: WindowInfo
    ) {
        guard !commands.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.replayRecordedJSScriptGenshinCommands(commands, targetWindow: targetWindow)
        }
    }

    @discardableResult
    func replayRecordedJSScriptGenshinCommands(
        _ commands: [BGIJSScriptGenshinCommand],
        targetWindow: WindowInfo,
        bigMapConfig: BGIBigMapConfig = BGIBigMapConfig()
    ) async -> BGIJSScriptGenshinCommandReplayResult {
        let replayer = BGIJSScriptGenshinCommandReplayer(
            keyBindings: keyBindings,
            bigMapConfig: bigMapConfig,
            captureFrameProvider: { [weak self] in
                guard let self else {
                    throw BGIPathingNavigationBackendError.targetWindowInvalid
                }
                let frame = try await self.frameProvider.captureWindow(targetWindow)
                self.latestFrameStore.update(frame)
                return frame
            },
            recognitionObjectProvider: { frame, object in
                if object.recognitionType == .templateMatch {
                    return TemplateMatchingRecognitionEngine()
                        .recognize(imageFrame: frame, objects: [object])
                        .observations
                }
                let engine = try PaddleOCRRecognitionEngine()
                return engine.recognize(imageFrame: frame, objects: [object]).observations
            },
            ocrProvider: { [weak self] frame, roi in
                guard let self else {
                    throw BGIJSScriptRuntimeError.ocrUnavailable
                }
                let engine = try PaddleOCRRecognitionEngine()
                return self.ocrResult(frame: frame, roi: roi, engine: engine)
            },
            inputHandler: { [weak self] action in
                guard let self else { return .blocked(reason: "AppState released") }
                return self.dispatchInput(action, source: .runtimeTrigger)
            }
        )
        let result = await replayer.replay(commands, targetWindow: targetWindow)
        if result.executedCount > 0 || result.pendingCount > 0 || result.failedCount > 0 {
            addLog(
                result.failedCount == 0 ? .info : .warn,
                "JS genshin replay: executed=\(result.executedCount) pending=\(result.pendingCount) failed=\(result.failedCount)"
            )
        }
        for pending in result.pendingCommands.prefix(3) {
            addLog(.debug, "JS genshin pending: \(pending.reason)")
        }
        for failure in result.failedCommands.prefix(3) {
            addLog(.error, "JS genshin replay failed: \(failure.message)")
        }
        return result
    }

    func simulatePickupMatch() {
        debugConfidence = min(0.99, debugConfidence + 0.04)
        appStatus = .running
        startRuntimeLoop()
        addLog(.info, "Mock pickup match: confidence \(String(format: "%.2f", debugConfidence))")
    }

    func simulateCaptureLost() {
        captureStatus = .lost
        gameWindowStatus = .lost
        appStatus = .error
        addLog(.error, "Mock capture lost")
    }

    func simulateCoreError() {
        coreStatus = .error
        appStatus = .error
        addLog(.error, "Mock Rust core bridge error")
    }

    func resetMockState() {
        schedulerExecutionTask?.cancel()
        schedulerExecutionTask = nil
        jsScriptExecutionTask?.cancel()
        jsScriptExecutionTask = nil
        stopRuntimeLoop()
        appStatus = .idle
        gameWindowStatus = .mock
        captureStatus = .ok
        inputStatus = .mock
        coreStatus = .mock
        debugConfidence = 0.86
        selectedWindow = .mock()
        availableWindows = [.mock(), .mock(title: "Genshin Impact (Mock)")]
        lastCapturedFrame = nil
        lastCaptureImageFrame = nil
        runtimeSnapshot = .empty
        runtimeFrameIndex = 0
        runtimeLoopTickCount = 0
        runtimeLoopSkippedTicks = 0
        runtimeLoopLastTickCostMs = 0
        jsScriptExecutionStatus = "Idle"
        lastJSScriptExecutionResult = nil
        schedulerExecutionStatus = "Idle"
        currentSchedulerProjectID = nil
        lastKeyMousePlaybackResult = nil
        lastShellExecutionResult = nil
        lastPathingExecutionResult = nil
        safetyGate.resetCounters()
        addLog(.info, "Mock state reset")
    }

    private func startRuntimeLoop() {
        runtimeLoop.onStatsChanged = { [weak self] stats in
            self?.runtimeLoopTickCount = stats.tickCount
            self?.runtimeLoopSkippedTicks = stats.skippedTickCount
            self?.runtimeLoopLastTickCostMs = stats.lastTickCostMs
        }

        runtimeLoop.start(intervalMs: dispatcherIntervalMs) { [weak self] in
            await self?.runDispatcherTick(forceMockCapture: false)
        }
    }

    private func stopRuntimeLoop() {
        runtimeLoop.stop()
    }

    private func captureFrameForDispatcher(forceMockCapture: Bool) async -> CapturedFrame? {
        if forceMockCapture || selectedWindow.isMock {
            runtimeFrameIndex = (runtimeFrameIndex + 1) % UInt64(CapturedFrame.maxFrameIndex(intervalMs: dispatcherIntervalMs))
            let frame = CapturedFrame.mock(window: selectedWindow, frameIndex: runtimeFrameIndex)
            lastCaptureImageFrame = nil
            lastCapturedFrame = frame
            captureStatus = .ok
            return frame
        }

        let targetWindow = selectedWindow
        do {
            let imageFrame = try await frameProvider.captureWindow(targetWindow)
            latestFrameStore.update(imageFrame)
            lastCaptureImageFrame = imageFrame
            lastCapturedFrame = imageFrame.metadata
            captureStatus = .ok
            if !runtimeLoop.isRunning || imageFrame.metadata.frameIndex % 60 == 0 {
                addLog(.debug, "Capture backend: \(imageFrame.backendName)")
            }
            return imageFrame.metadata
        } catch {
            captureStatus = .error
            appStatus = .error
            stopRuntimeLoop()
            addLog(.error, "Dispatcher capture failed: \(error.localizedDescription)")
            return nil
        }
    }
}
