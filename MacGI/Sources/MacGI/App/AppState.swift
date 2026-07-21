import Foundation
import SwiftUI

struct CoreCatalogIssue: Equatable, Sendable {
    let path: String
    let message: String
}

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
    case starting
    case provisioning
    case lost
    case detected
    case ready
    case missing
    case ok
    case error

    var id: String { rawValue }

    var label: String {
        switch self {
        case .starting: "Starting"
        case .provisioning: "Provisioning"
        case .lost: "Lost"
        case .detected: "Detected"
        case .ready: "Ready"
        case .missing: "Missing"
        case .ok: "OK"
        case .error: "Error"
        }
    }

    var tint: Color {
        switch self {
        case .lost, .missing, .error: BGIColors.danger
        case .starting, .provisioning: BGIColors.warning
        case .detected, .ready, .ok: BGIColors.success
        }
    }
}

enum RuntimeLifecycle: String, CaseIterable, Identifiable {
    case stopped
    case starting
    case running
    case stopping
    case failed

    var id: String { rawValue }

    var isTransitioning: Bool { self == .starting || self == .stopping }
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
    @Published var captureStatus: RuntimeStatus = .missing
    @Published var inputStatus: RuntimeStatus = .missing
    @Published var coreStatus: RuntimeStatus = .starting
    @Published var runtimeLifecycle: RuntimeLifecycle = .stopped
    @Published var isHUDVisible = false {
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
    @Published var dispatcherIntervalMs = 50
    @Published var allowRuntimeRealInput = false
    @Published var schedulerGroups: [BetterGIScriptGroupSummary] = []
    @Published var scriptProjects: [BetterGIScriptProjectSummary] = []
    @Published var schedulerCatalogIssues: [CoreCatalogIssue] = []
    @Published var schedulerCatalogStatus = "Core unavailable"
    @Published var selectedSchedulerGroupName = ""
    @Published var schedulerExecutionStatus = "Idle"
    @Published var schedulerExecutionError: String?
    @Published var currentSchedulerProjectID: String?

    // MARK: Window & capture (typed — not strings)

    /// Currently selected game window.
    @Published var selectedWindow: WindowInfo = .unavailable()

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
    private let inputDispatcher: any InputDispatching
    private let isTargetWindowFrontmost: (WindowInfo) -> Bool
    private let runtimeResourceStore: BGIRuntimeResourceStore
    let latestFrameStore = LatestFrameStore()
    private var runtimeFrameIndex: UInt64 = 0
    private var schedulerExecutionTask: Task<Void, Never>?
    private var betterGICoreSupervisor: BetterGICoreProcessSupervisor?
    private var coreStartupTask: Task<Void, Never>?
    private var coreStartupInFlight = false
    private var captureTimestamps: [Date] = []
    @Published private(set) var measuredCaptureFPS = 0

    // MARK: Derived capture metrics (from lastCapturedFrame)

    var captureFPS: Int {
        measuredCaptureFPS
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
    @Published var features: [MacGIFeature] = []
    @Published var recentLogs: [LogEntry] = []

    var onHUDVisibilityChanged: ((Bool) -> Void)?

    init(
        resourceStore: BGIRuntimeResourceStore = .defaultStore(),
        inputDispatcher: any InputDispatching = CGEventInputDispatcher(),
        isTargetWindowFrontmost: @escaping (WindowInfo) -> Bool = ForegroundWindowGuard.isTargetFrontmost
    ) {
        runtimeResourceStore = resourceStore
        self.inputDispatcher = inputDispatcher
        self.isTargetWindowFrontmost = isTargetWindowFrontmost
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

    func setSchedulerProjectEnabled(projectIndex: Int, enabled: Bool) {
        guard currentSchedulerProjectID == nil else {
            addLog(.error, "Cannot edit scheduler group while it is running.")
            return
        }
        guard let supervisor = betterGICoreSupervisor, let group = selectedSchedulerGroup else {
            addLog(.error, "Cannot edit scheduler group: Core or selected group is unavailable.")
            return
        }
        Task { [weak self] in
            do {
                try await supervisor.setScriptGroupProjectEnabled(
                    groupName: group.name, projectIndex: projectIndex, enabled: enabled
                )
                await self?.loadSchedulerGroupsFromCore()
                self?.addLog(.info, "Core updated project \(projectIndex) to \(enabled ? "Enabled" : "Disabled").")
            } catch {
                self?.addLog(.error, "Core project update failed: \(error.localizedDescription)")
            }
        }
    }

    private func startBetterGICore() async {
        guard !coreStartupInFlight else { return }
        coreStartupInFlight = true
        coreStatus = .starting
        defer { coreStartupInFlight = false }
        do {
            let supervisor = try BetterGICoreProcessSupervisor(store: runtimeResourceStore)
            let adapter = BetterGICorePlatformAdapter(appState: self)
            let handshake = try await supervisor.start(
                progressHandler: { [weak self] phase in
                    Task { @MainActor in self?.handleCoreStartupPhase(phase) }
                },
                logHandler: { [weak self] line in
                    Task { @MainActor in self?.addLog(.info, "Core: \(line)") }
                },
                platformHandler: { method, parameters in
                    try adapter.handle(method: method, parameters: parameters)
                }
            )
            betterGICoreSupervisor = supervisor
            coreStatus = .ok
            addLog(.info, "BetterGI Core \(handshake.runtimeVersion) connected (\(handshake.architecture))")
            await loadTriggerStatesFromCore()
            await loadSchedulerGroupsFromCore()
            await loadScriptProjectsFromCore()
        } catch {
            betterGICoreSupervisor = nil
            coreStatus = .error
            setCoreCatalogUnavailable(error)
            addLog(.error, "BetterGI Core startup failed: \(error.localizedDescription)")
        }
    }

    private func handleCoreStartupPhase(_ phase: BetterGICoreProcessSupervisor.StartupPhase) {
        switch phase {
        case .starting, .waitingForSocket:
            coreStatus = .starting
        case .provisioning:
            coreStatus = .provisioning
        case .ready:
            coreStatus = .ok
        case .failed(let message):
            coreStatus = .error
            addLog(.error, message)
        }
    }

    func startRuntime() {
        guard !runtimeLifecycle.isTransitioning, runtimeLifecycle != .running else { return }
        guard isWindowValid, !selectedWindow.isSynthetic else {
            runtimeLifecycle = .failed
            addLog(.error, "Cannot start runtime: no real on-screen game window is selected.")
            return
        }
        runtimeLifecycle = .starting
        Task { [weak self] in
            guard let self else { return }
            if self.betterGICoreSupervisor == nil {
                if self.coreStartupInFlight, let startupTask = self.coreStartupTask {
                    await startupTask.value
                } else {
                    await self.startBetterGICore()
                }
            }
            guard let supervisor = self.betterGICoreSupervisor, self.coreStatus == .ok else {
                self.runtimeLifecycle = .failed
                self.addLog(.error, "Cannot start runtime: BetterGI Core is not ready.")
                return
            }
            do {
                try await supervisor.startRuntime()
                _ = try await self.captureFrameForBetterGICore()
                if self.showHUDOnStart {
                    self.isHUDVisible = true
                }
                self.runtimeLifecycle = .running
                self.addLog(.info, "BetterGI runtime started with a verified ScreenCaptureKit frame.")
            } catch {
                try? await supervisor.stopRuntime()
                self.captureStatus = .error
                self.runtimeLifecycle = .failed
                self.addLog(.error, "Cannot start runtime: \(error.localizedDescription)")
            }
        }
    }

    func stopRuntime() {
        guard runtimeLifecycle == .running else { return }
        runtimeLifecycle = .stopping
        Task { [weak self] in
            guard let self else { return }
            guard let supervisor = self.betterGICoreSupervisor else {
                self.runtimeLifecycle = .failed
                self.addLog(.error, "Cannot stop runtime: BetterGI Core is not ready.")
                return
            }
            do {
                try await supervisor.stopRuntime()
                self.captureTimestamps = []
                self.measuredCaptureFPS = 0
                self.captureStatus = .missing
                self.isHUDVisible = false
                self.runtimeLifecycle = .stopped
                self.addLog(.info, "BetterGI runtime stopped.")
            } catch {
                self.runtimeLifecycle = .failed
                self.addLog(.error, "Cannot stop runtime: \(error.localizedDescription)")
            }
        }
    }

    func toggleRuntime() {
        if runtimeLifecycle == .running {
            stopRuntime()
        } else {
            startRuntime()
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

    private func loadScriptProjectsFromCore() async {
        guard let supervisor = betterGICoreSupervisor else {
            scriptProjects = []
            return
        }
        do {
            scriptProjects = try await supervisor.listScriptProjects().sorted {
                $0.folderName.localizedStandardCompare($1.folderName) == .orderedAscending
            }
            addLog(.info, "Script catalog loaded \(scriptProjects.count) project(s) through BetterGI Core")
        } catch {
            scriptProjects = []
            addLog(.error, "BetterGI Core script catalog load failed: \(error.localizedDescription)")
        }
    }

    private func setCoreCatalogUnavailable(_ error: Error) {
        schedulerGroups = []
        scriptProjects = []
        selectedSchedulerGroupName = ""
        schedulerCatalogStatus = "Core unavailable"
        schedulerCatalogIssues = [
            CoreCatalogIssue(path: "Core/catalog", message: error.localizedDescription)
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
        features.map { feature in
            OverlayStatusItem(
                id: feature.id,
                glyph: Self.triggerPresentation[feature.id]?.glyph ?? "\u{f0e7}",
                name: feature.name,
                isEnabled: feature.isEnabled
            )
        }
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

    func pause() {
        guard let supervisor = betterGICoreSupervisor, let taskID = currentSchedulerProjectID else {
            appStatus = .error
            addLog(.error, "Cannot pause: no BetterGI Core scheduler task is active.")
            return
        }
        Task { [weak self] in
            do {
                try await supervisor.pauseScheduler(taskID: taskID)
                self?.handleCoreSchedulerControlAccepted(taskID: taskID, state: "paused")
            } catch {
                self?.handleCoreSchedulerControlFailed(taskID: taskID, operation: "pause", error: error)
            }
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

    func exportLogs() {
        do {
            try runtimeResourceStore.createDirectorySkeleton()
            let destination = try UILogFileExporter.export(
                entries: recentLogs.reversed(),
                to: runtimeResourceStore.logURL
            )
            addLog(.info, "Logs exported: \(destination.path)")
        } catch {
            addLog(.error, "Log export failed: \(error.localizedDescription)")
        }
    }

    func runSchedulerGroups() {
        guard currentSchedulerProjectID == nil else {
            addLog(.error, "Cannot run scheduler: another scheduler task is already active.")
            return
        }
        guard let supervisor = betterGICoreSupervisor, coreStatus == .ok else {
            schedulerExecutionStatus = "Core unavailable"
            addLog(.error, "Cannot run scheduler: BetterGI Core is not ready.")
            return
        }
        guard runtimeLifecycle == .running else {
            schedulerExecutionStatus = "Runtime stopped"
            addLog(.error, "Cannot run scheduler: start the BetterGI runtime first.")
            return
        }
        guard selectedSchedulerGroup != nil else {
            schedulerExecutionStatus = "Group unavailable"
            addLog(.error, "Cannot run scheduler: no script group is selected.")
            return
        }
        guard isWindowValid, !selectedWindow.isSynthetic else {
            schedulerExecutionStatus = "Window unavailable"
            addLog(.error, "Cannot run scheduler: no real on-screen game window is selected.")
            return
        }
        schedulerExecutionTask?.cancel()
        let groupName = selectedSchedulerGroupName
        schedulerExecutionStatus = "Starting"
        schedulerExecutionError = nil
        schedulerExecutionTask = Task { [weak self] in
            do {
                let taskID = try await supervisor.runSchedulerGroup(name: groupName)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.handleCoreSchedulerRunAccepted(taskID: taskID, groupName: groupName)
            } catch {
                self?.schedulerExecutionStatus = "Failed"
                self?.schedulerExecutionError = error.localizedDescription
                self?.currentSchedulerProjectID = nil
                self?.appStatus = .error
                self?.addLog(.error, "Core scheduler start failed: \(error.localizedDescription)")
            }
        }
    }

    func handleCoreSchedulerRunAccepted(taskID: String, groupName: String) {
        guard !Self.terminalSchedulerStates.contains(schedulerExecutionStatus) else { return }
        currentSchedulerProjectID = taskID
        appStatus = .running
        schedulerExecutionStatus = "running"
        addLog(.info, "Core scheduler started group \(groupName) as \(taskID)")
    }

    func handleCoreSchedulerControlAccepted(taskID: String, state: String) {
        guard !Self.terminalSchedulerStates.contains(schedulerExecutionStatus) else { return }
        guard currentSchedulerProjectID == taskID else { return }
        switch state {
        case "running":
            schedulerExecutionStatus = state
            appStatus = .running
            addLog(.info, "Core scheduler resumed \(taskID)")
        case "paused":
            schedulerExecutionStatus = state
            appStatus = .paused
            addLog(.warn, "Core scheduler paused \(taskID)")
        case "stopping":
            schedulerExecutionStatus = state
            addLog(.warn, "Core scheduler stop requested for \(taskID)")
        default:
            addLog(.error, "Unsupported scheduler control response: \(state)")
        }
    }

    func handleCoreSchedulerControlFailed(taskID: String, operation: String, error: Error) {
        guard currentSchedulerProjectID == taskID else { return }
        guard !Self.terminalSchedulerStates.contains(schedulerExecutionStatus) else { return }
        schedulerExecutionStatus = "\(operation.capitalized) failed"
        schedulerExecutionError = error.localizedDescription
        appStatus = .error
        addLog(.error, "Core scheduler \(operation) failed: \(error.localizedDescription)")
    }

    func handleCoreSchedulerEvent(taskID: String, state: String, error: String?) throws {
        if let currentSchedulerProjectID, currentSchedulerProjectID != taskID {
            throw BetterGICorePlatformAdapterError.invalidParameters(
                "scheduler.event taskId \(taskID) does not match active task \(currentSchedulerProjectID)."
            )
        }

        schedulerExecutionStatus = state
        switch state {
        case "running":
            currentSchedulerProjectID = taskID
            schedulerExecutionError = nil
            appStatus = .running
        case "paused":
            currentSchedulerProjectID = taskID
            appStatus = .paused
        case "completed", "cancelled":
            currentSchedulerProjectID = nil
            schedulerExecutionError = nil
            schedulerExecutionTask = nil
            appStatus = .idle
        case "failed":
            currentSchedulerProjectID = nil
            schedulerExecutionError = error ?? "Core scheduler failed without error details."
            schedulerExecutionTask = nil
            appStatus = .error
        default:
            throw BetterGICorePlatformAdapterError.invalidParameters(
                "scheduler.event contains unsupported state \(state)."
            )
        }
    }

    private static let terminalSchedulerStates = ["completed", "cancelled", "failed"]

    var selectedSchedulerGroup: BetterGIScriptGroupSummary? {
        schedulerGroups.first { $0.name == selectedSchedulerGroupName }
    }

    var canRunScheduler: Bool {
        coreStatus == .ok
            && runtimeLifecycle == .running
            && selectedSchedulerGroup != nil
            && isWindowValid
            && !selectedWindow.isSynthetic
            && currentSchedulerProjectID == nil
    }

    var schedulerRunReadiness: String {
        guard coreStatus == .ok else { return "Core 尚未就绪" }
        guard runtimeLifecycle == .running else { return "请先启动 BetterGI 运行时" }
        guard selectedSchedulerGroup != nil else { return "尚未选择配置组" }
        guard isWindowValid, !selectedWindow.isSynthetic else { return "尚未选择真实游戏窗口" }
        guard !safetyGate.emergencyStop else { return "紧急停止已启用" }
        if safetyGate.dryRun { return "已就绪：Dry-Run，不发送真实输入" }
        guard safetyGate.realInputEnabled else { return "真实输入尚未启用" }
        guard allowRuntimeRealInput else { return "Core Runtime Input 尚未授权" }
        return "已就绪：Core 可发送真实输入"
    }

    func cancelSchedulerGroups() {
        schedulerExecutionTask?.cancel()
        schedulerExecutionTask = nil
        let taskID = currentSchedulerProjectID
        guard let supervisor = betterGICoreSupervisor, let taskID else {
            schedulerExecutionStatus = "Cancelled"
            schedulerExecutionError = nil
            appStatus = .idle
            return
        }
        Task { [weak self] in
            do {
                try await supervisor.stopScheduler(taskID: taskID)
                self?.handleCoreSchedulerControlAccepted(taskID: taskID, state: "stopping")
            } catch {
                self?.handleCoreSchedulerControlFailed(taskID: taskID, operation: "stop", error: error)
            }
        }
    }

    func featureEnabled(_ id: String) -> Bool {
        features.first(where: { $0.id == id })?.isEnabled ?? false
    }

    func canControlFeature(_ id: String) -> Bool {
        betterGICoreSupervisor != nil && features.contains(where: { $0.id == id })
    }

    func setFeature(_ id: String, enabled: Bool) {
        guard let featureName = features.first(where: { $0.id == id })?.name,
              let supervisor = betterGICoreSupervisor else {
            addLog(.error, "Feature \(id) is not exposed by BetterGI Core.")
            return
        }
        Task { [weak self] in
            do {
                try await supervisor.setTriggerEnabled(name: id, enabled: enabled)
                await self?.loadTriggerStatesFromCore()
                self?.addLog(.info, "Core \(featureName) \(enabled ? "enabled" : "disabled")")
            } catch {
                self?.addLog(.error, "Core failed to update \(featureName): \(error.localizedDescription)")
            }
        }
    }

    private static let triggerPresentation: [String: (detail: String, icon: BGIIcon, glyph: String)] = [
        "GameLoading": ("处理游戏启动和加载界面。", .symbol("hourglass"), "\u{f252}"),
        "AutoPick": ("自动拾取和交互。", .symbol("hand.wave"), "\u{f256}"),
        "AutoSkip": ("自动推进剧情和选择对话选项。", .fgi("\u{f075}"), "\u{f075}"),
        "AutoFish": ("半自动钓鱼触发器。", .fgi("\u{f578}"), "\u{f578}"),
        "AutoEat": ("检测低血量并使用营养袋。", .fgi("\u{f0f1}"), "\u{f0f1}"),
        "QuickTeleport": ("自动完成大地图传送确认。", .fgi("\u{f3c5}"), "\u{f3c5}"),
        "MapMask": ("输出地图遮罩绘制命令。", .fgi("\u{f279}"), "\u{f279}"),
        "SkillCd": ("显示角色技能冷却状态。", .symbol("timer"), "\u{f017}"),
    ]

    private func loadTriggerStatesFromCore() async {
        guard let supervisor = betterGICoreSupervisor else { return }
        do {
            let states = try await supervisor.listTriggers()
            features = states.sorted { $0.priority > $1.priority }.map { state in
                let presentation = Self.triggerPresentation[state.name]
                return MacGIFeature(
                    id: state.name,
                    name: state.displayName,
                    detail: presentation?.detail ?? "BetterGI C# Core 实时触发器。",
                    statusText: "C# Core · P\(state.priority)\(state.exclusive ? " · Exclusive" : "")",
                    icon: presentation?.icon ?? .symbol("bolt"),
                    isEnabled: state.enabled
                )
            }
        } catch {
            features = []
            addLog(.error, "BetterGI Core trigger catalog failed: \(error.localizedDescription)")
        }
    }

    func refreshWindows() {
        let windows = QuartzWindowEnumerator.enumerateApplicationWindows()
        if windows.isEmpty {
            availableWindows = []
            selectedWindow = .unavailable(title: "No game window selected")
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

    @discardableResult
    func refreshSelectedWindowGeometry() -> WindowInfo? {
        guard selectedWindow.id != 0, !selectedWindow.isSynthetic else { return nil }
        guard let refreshed = QuartzWindowEnumerator.enumerateApplicationWindows()
            .first(where: { $0.id == selectedWindow.id }) else {
            gameWindowStatus = .missing
            return nil
        }
        if refreshed != selectedWindow {
            selectedWindow = refreshed
        }
        gameWindowStatus = refreshed.isLikelyGameWindow ? .detected : .missing
        return refreshed
    }

    func setSelectedWindow(_ window: WindowInfo) {
        selectedWindow = window
        addLog(.info, "Window selected: \(window.displayName)")
        guard window.id != 0, window.isOnScreen, !window.isSynthetic, coreStatus != .ok else { return }
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
        if selectedWindow.isSynthetic {
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
                recordCapturedFrame(imageFrame)
                addLog(.info, "\(imageFrame.backendName) frame captured: \(imageFrame.metadata.sizeDescription) \(imageFrame.metadata.pixelFormatName)")
            } catch {
                captureStatus = .error
                addLog(.error, "ScreenCaptureKit capture failed: \(error.localizedDescription)")
            }
        }
    }

    private func recordInputAction(_ name: String, prefix: String) {
        let line = "[\(LogEntry.formatter.string(from: Date()))] \(prefix) \(name)"
        inputActionLog.insert(line, at: 0)
        if inputActionLog.count > 24 {
            inputActionLog.removeLast(inputActionLog.count - 24)
        }
        addLog(.debug, "Input action: \(name) [\(prefix)]")
    }

    /// Gate-checked dispatch — single entry point for platform input.
    /// Callers should NOT check the gate a second time.
    @discardableResult
    func dispatchInput(_ action: InputAction, source: ActionSource = .manual) -> InputSafetyGate.GateResult {
        let requiresForegroundCheck =
            source == .runtimeTrigger
            && !safetyGate.dryRun
            && safetyGate.realInputEnabled

        let foregroundOK = requiresForegroundCheck
            ? isTargetWindowFrontmost(selectedWindow)
            : true

        let result = safetyGate.check(
            window: selectedWindow,
            isAppRunning: source == .runtimeTrigger
                ? runtimeLifecycle == .running
                : appStatus == .running,
            source: source,
            allowRuntimeRealInput: allowRuntimeRealInput,
            isTargetFrontmost: foregroundOK
        )
        switch result {
        case .allow:
            do {
                let report = try inputDispatcher.perform(action, targetWindow: selectedWindow)
                inputStatus = .ok
                recordInputAction(action.displayName, prefix: "→")
                addLog(.debug, "CGEvent dispatched: \(report.detail), events=\(report.eventCount)")
            } catch {
                inputStatus = .error
                recordInputAction(action.displayName, prefix: "✕")
                let reason = "CGEvent dispatch failed: \(error.localizedDescription)"
                addLog(.error, reason)
                return .blocked(reason: reason)
            }
        case .dryRun:
            recordInputAction(action.displayName, prefix: "○")
        case .blocked:
            inputStatus = .error
            recordInputAction(action.displayName, prefix: "✕")
            addLog(.warn, "Input blocked: \(result.reason)")
        }
        return result
    }

    @discardableResult
    func dispatchGameAction(_ action: GIAction, type: GIKeyType = .keyPress, source: ActionSource = .manual) -> InputSafetyGate.GateResult {
        let key = keyBindings.key(for: action)
        guard let inputAction = keyBindings.inputAction(for: key, type: type) else {
            inputStatus = .error
            recordInputAction("\(action.displayName): \(key.displayName)", prefix: "✕")
            addLog(.error, "Input mapping unsupported: \(action.rawValue) -> \(key.rawValue)")
            return .blocked(reason: "Unsupported key binding: \(action.rawValue) -> \(key.rawValue)")
        }

        addLog(.debug, "Game action mapped: \(action.rawValue) -> \(key.displayName) [\(type.rawValue)]")
        return dispatchInput(inputAction, source: source)
    }

    func captureFrameForBetterGICore() async throws -> CaptureImageFrame {
        let targetWindow = selectedWindow
        guard targetWindow.id != 0, targetWindow.isOnScreen, !targetWindow.isSynthetic else {
            throw BetterGICoreRPCError.protocolViolation("No real on-screen game window is selected for Core capture.")
        }
        let imageFrame = try await frameProvider.captureWindow(targetWindow)
        recordCapturedFrame(imageFrame)
        return imageFrame
    }

    private func recordCapturedFrame(_ imageFrame: CaptureImageFrame) {
        latestFrameStore.update(imageFrame)
        lastCaptureImageFrame = imageFrame
        lastCapturedFrame = imageFrame.metadata
        let now = Date()
        captureTimestamps.append(now)
        captureTimestamps.removeAll { now.timeIntervalSince($0) > 2 }
        if let first = captureTimestamps.first, captureTimestamps.count > 1 {
            let duration = now.timeIntervalSince(first)
            measuredCaptureFPS = duration > 0
                ? Int(((Double(captureTimestamps.count - 1) / duration).rounded()))
                : 0
        } else {
            measuredCaptureFPS = 0
        }
        captureStatus = .ok
    }

    var betterGICoreRunURL: URL {
        runtimeResourceStore.rootURL.appendingPathComponent("Run", isDirectory: true)
    }

    func resetUIState() {
        schedulerExecutionTask?.cancel()
        schedulerExecutionTask = nil
        appStatus = .idle
        runtimeLifecycle = .stopped
        gameWindowStatus = .missing
        captureStatus = .missing
        inputStatus = .missing
        coreStatus = .error
        debugConfidence = 0.86
        selectedWindow = .unavailable()
        availableWindows = []
        lastCapturedFrame = nil
        lastCaptureImageFrame = nil
        captureTimestamps = []
        measuredCaptureFPS = 0
        schedulerExecutionStatus = "Idle"
        currentSchedulerProjectID = nil
        safetyGate.resetCounters()
        addLog(.info, "UI state reset")
    }
}
