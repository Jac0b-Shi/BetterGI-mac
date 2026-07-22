import AppKit
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
    var settingsAvailable: Bool
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
    @Published private(set) var screenCapturePermissionGranted = false
    @Published private(set) var accessibilityPermissionGranted = false
    @Published private(set) var screenCapturePermissionRequestMessage: String?
    @Published private(set) var runtimeLifecycleMessage = "运行时尚未启动。"
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
    private var autoStartRuntimePending: Bool
    private var runtimeGeometryPixelSize: CGSize?
    private var pendingRuntimeGeometryPixelSize: CGSize?
    private var runtimeGeometryRefreshTask: Task<Void, Never>?
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
    @Published var soloTasks: [BetterGICoreSoloTask] = []
    @Published var soloTaskInputDrafts: [String: String] = [:]
    @Published private(set) var soloTaskStatus = BetterGICoreSoloTaskStatus(
        taskID: nil, name: nil, state: "idle", error: nil)
    @Published private(set) var autoGeniusInvokationSettings:
        BetterGICoreAutoGeniusInvokationSettings?
    @Published private(set) var autoCookSettings: BetterGICoreAutoCookSettings?
    @Published private(set) var autoFishingSettings: BetterGICoreAutoFishingSettings?
    @Published private(set) var autoWoodSettings: BetterGICoreAutoWoodSettings?
    @Published private(set) var autoMusicGameSettings: BetterGICoreAutoMusicGameSettings?
    @Published private(set) var autoBossSettings: BetterGICoreAutoBossSettings?
    @Published private(set) var autoLeyLineOutcropSettings: BetterGICoreAutoLeyLineOutcropSettings?
    @Published private(set) var autoStygianOnslaughtSettings: BetterGICoreAutoStygianOnslaughtSettings?
    @Published private(set) var autoDomainSettings: BetterGICoreAutoDomainSettings?
    @Published private(set) var autoArtifactSalvageSettings: BetterGICoreAutoArtifactSalvageSettings?
    @Published private(set) var autoFightSettings: BetterGICoreAutoFightSettings?
    @Published private(set) var autoEatTriggerSettings: BetterGICoreAutoEatTriggerSettings?
    @Published private(set) var autoPickTriggerSettings: BetterGICoreAutoPickTriggerSettings?
    @Published var autoPickExactBlackListDraft = ""
    @Published var autoPickFuzzyBlackListDraft = ""
    @Published var autoPickWhiteListDraft = ""
    @Published private(set) var quickTeleportTriggerSettings: BetterGICoreQuickTeleportTriggerSettings?
    @Published private(set) var mapMaskTriggerSettings: BetterGICoreMapMaskTriggerSettings?
    @Published var recentLogs: [LogEntry] = []

    var onHUDVisibilityChanged: ((Bool) -> Void)?

    init(
        resourceStore: BGIRuntimeResourceStore = .defaultStore(),
        inputDispatcher: any InputDispatching = CGEventInputDispatcher(),
        isTargetWindowFrontmost: @escaping (WindowInfo) -> Bool = ForegroundWindowGuard.isTargetFrontmost,
        launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        runtimeResourceStore = resourceStore
        self.inputDispatcher = inputDispatcher
        self.isTargetWindowFrontmost = isTargetWindowFrontmost
        autoStartRuntimePending = launchArguments.contains("--start-runtime")
        addLog(.info, "betterGI-mac Swift UI initialized")
        addLog(.info, "Waiting for BetterGI C# Core Host")
        refreshPermissionStatus()
        refreshWindows()
    }

    func beginCoreStartup() {
        guard coreStartupTask == nil, !coreStartupInFlight, betterGICoreSupervisor == nil else { return }
        NSLog("BetterGI Core startup scheduled")
        coreStartupTask = Task {
            await startBetterGICore()
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

    func loadProjectCommonSettings(_ projectIndex: Int) async throws -> BetterGIProjectCommonSettings {
        guard let supervisor = betterGICoreSupervisor, let group = selectedSchedulerGroup else {
            throw BetterGICoreRPCError.socket("Core or selected script group is unavailable.")
        }
        return try await supervisor.projectCommonSettings(groupName: group.name, projectIndex: projectIndex)
    }

    func saveProjectCommonSettings(_ settings: BetterGIProjectCommonSettings) async throws {
        guard let supervisor = betterGICoreSupervisor, let group = selectedSchedulerGroup else {
            throw BetterGICoreRPCError.socket("Core or selected script group is unavailable.")
        }
        try await supervisor.saveProjectCommonSettings(groupName: group.name, settings: settings)
        await loadSchedulerGroupsFromCore()
    }

    func loadProjectCustomSettings(_ projectIndex: Int) async throws -> BetterGIProjectCustomSettings {
        guard let supervisor = betterGICoreSupervisor, let group = selectedSchedulerGroup else {
            throw BetterGICoreRPCError.socket("Core or selected script group is unavailable.")
        }
        return try await supervisor.projectCustomSettings(groupName: group.name, projectIndex: projectIndex)
    }

    func saveProjectCustomSettings(_ settings: BetterGIProjectCustomSettings) async throws {
        guard let supervisor = betterGICoreSupervisor, let group = selectedSchedulerGroup else {
            throw BetterGICoreRPCError.socket("Core or selected script group is unavailable.")
        }
        try await supervisor.saveProjectCustomSettings(groupName: group.name, settings: settings)
        await loadSchedulerGroupsFromCore()
    }

    func loadSchedulerAddCandidates(type: String) async throws -> [BetterGIAddCandidate] {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        return try await supervisor.listAddCandidates(type: type)
    }

    func addSchedulerProjects(type: String, candidateIDs: [String] = [], shellCommand: String? = nil) {
        performSchedulerCatalogMutation(.add(type: type, candidateIDs: candidateIDs, shellCommand: shellCommand))
    }

    func performSchedulerCatalogMutation(_ mutation: BetterGISchedulerCatalogMutation) {
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
                try await supervisor.mutateSchedulerCatalog(groupName: group.name, mutation: mutation)
                await self?.loadSchedulerGroupsFromCore()
            } catch { self?.addLog(.error, "Scheduler edit failed: \(error.localizedDescription)") }
        }
    }

    func openSchedulerProjectLocation(projectIndex: Int) {
        guard let supervisor = betterGICoreSupervisor, let group = selectedSchedulerGroup else { return }
        Task { [weak self] in
            do {
                let path = try await supervisor.projectLocation(groupName: group.name, projectIndex: projectIndex)
                guard NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
                    throw BetterGICoreRPCError.socket("Finder could not open the project directory.")
                }
            } catch { self?.addLog(.error, "Open project directory failed: \(error.localizedDescription)") }
        }
    }

    func loadSelectedGroupConfig() async throws -> BetterGIGroupConfigSettings {
        guard let supervisor = betterGICoreSupervisor, let group = selectedSchedulerGroup else {
            throw BetterGICoreRPCError.socket("Core or selected script group is unavailable.")
        }
        return try await supervisor.groupConfig(groupName: group.name)
    }

    func saveSelectedGroupConfig(_ settings: BetterGIGroupConfigSettings) async throws {
        guard let supervisor = betterGICoreSupervisor, let group = selectedSchedulerGroup else {
            throw BetterGICoreRPCError.socket("Core or selected script group is unavailable.")
        }
        try await supervisor.saveGroupConfig(groupName: group.name, settings: settings)
        await loadSchedulerGroupsFromCore()
    }

    private func startBetterGICore() async {
        guard !coreStartupInFlight else { return }
        NSLog("BetterGI Core startup entered")
        coreStartupInFlight = true
        coreStatus = .starting
        defer { coreStartupInFlight = false }
        do {
            NSLog("BetterGI Core supervisor resolving packaged executable")
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
            NSLog("BetterGI Core supervisor connected")
            coreStatus = .ok
            addLog(.info, "BetterGI Core \(handshake.runtimeVersion) connected (\(handshake.architecture))")
            await loadTriggerStatesFromCore()
            await loadSoloTasksFromCore()
            await loadSchedulerGroupsFromCore()
            await loadScriptProjectsFromCore()
            attemptAutoStartRuntime()
        } catch {
            NSLog("BetterGI Core startup failed: %@", error.localizedDescription)
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
        guard !runtimeLifecycle.isTransitioning else {
            runtimeLifecycleMessage = "运行时正在\(runtimeLifecycle == .starting ? "启动" : "停止")，请稍候。"
            addLog(.warn, "Runtime request ignored while lifecycle is \(runtimeLifecycle.rawValue).")
            return
        }
        guard runtimeLifecycle != .running else {
            runtimeLifecycleMessage = "运行时已经启动。"
            addLog(.info, "BetterGI runtime is already running.")
            return
        }
        refreshPermissionStatus()
        guard screenCapturePermissionGranted, accessibilityPermissionGranted else {
            runtimeLifecycle = .failed
            runtimeLifecycleMessage = "无法启动：请先授予屏幕录制和辅助功能权限。"
            appStatus = .error
            addLog(.error, "Cannot start runtime: grant Screen Recording and Accessibility in the macOS permissions section.")
            return
        }
        guard isWindowValid, !selectedWindow.isSynthetic else {
            runtimeLifecycle = .failed
            runtimeLifecycleMessage = "无法启动：没有选中真实、可见的原神窗口。"
            appStatus = .error
            addLog(.error, "Cannot start runtime: no real on-screen game window is selected.")
            return
        }
        runtimeLifecycle = .starting
        runtimeLifecycleMessage = "正在启动 BetterGI Core 与截图器..."
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
                self.runtimeLifecycleMessage = "无法启动：BetterGI Core 尚未就绪。"
                self.appStatus = .error
                self.addLog(.error, "Cannot start runtime: BetterGI Core is not ready.")
                return
            }
            do {
                try await supervisor.startRuntime()
                _ = try await self.captureFrameForBetterGICore()
                if self.showHUDOnStart {
                    self.isHUDVisible = true
                }
                self.runtimeGeometryPixelSize = self.selectedWindow.capturePixelSize
                self.runtimeLifecycle = .running
                self.runtimeLifecycleMessage = "运行时已启动，截图器正在持续捕获。"
                self.appStatus = .running
                self.addLog(.info, "BetterGI runtime started with a verified ScreenCaptureKit frame.")
            } catch {
                try? await supervisor.stopRuntime()
                self.captureStatus = .error
                self.runtimeLifecycle = .failed
                self.runtimeLifecycleMessage = "无法启动：\(error.localizedDescription)"
                self.appStatus = .error
                self.addLog(.error, "Cannot start runtime: \(error.localizedDescription)")
            }
        }
    }

    func refreshPermissionStatus() {
        screenCapturePermissionGranted = MacGIPermissionRequester.screenCaptureGranted
        accessibilityPermissionGranted = MacGIPermissionRequester.accessibilityGranted
    }

    func requestScreenCapturePermission() {
        let result = MacGIPermissionRequester.requestScreenCapture()
        logPermissionRequestResult(result, name: "Screen Recording")
        refreshPermissionStatus()
        screenCapturePermissionRequestMessage = screenCapturePermissionGranted
            ? nil
            : "已向 macOS 请求授权；若系统未显示弹窗，请检查当前 App 的 TCC 记录。"
    }

    func requestAccessibilityPermission() {
        let result = MacGIPermissionRequester.requestAccessibility()
        logPermissionRequestResult(result, name: "Accessibility")
        refreshPermissionStatus()
    }

    private func logPermissionRequestResult(
        _ result: MacGIPermissionRequester.RequestResult,
        name: String
    ) {
        switch result {
        case .alreadyGranted:
            addLog(.info, "macOS \(name) permission is already granted.")
        case .requestSubmitted:
            addLog(.info, "Submitted macOS \(name) permission request; reopen BetterGI after granting access if required.")
        }
    }

    private func attemptAutoStartRuntime() {
        guard autoStartRuntimePending,
              coreStatus == .ok,
              isWindowValid,
              !selectedWindow.isSynthetic,
              runtimeLifecycle == .stopped else { return }
        autoStartRuntimePending = false
        addLog(.info, "--start-runtime conditions satisfied; starting BetterGI runtime.")
        startRuntime()
    }

    func stopRuntime() {
        guard runtimeLifecycle == .running else { return }
        runtimeLifecycle = .stopping
        runtimeLifecycleMessage = "正在停止 BetterGI 运行时..."
        Task { [weak self] in
            guard let self else { return }
            guard let supervisor = self.betterGICoreSupervisor else {
                self.runtimeLifecycle = .failed
                self.addLog(.error, "Cannot stop runtime: BetterGI Core is not ready.")
                return
            }
            do {
                try await supervisor.stopRuntime()
                self.cancelRuntimeGeometryRefresh()
                self.captureTimestamps = []
                self.measuredCaptureFPS = 0
                self.captureStatus = .missing
                self.isHUDVisible = false
                self.runtimeLifecycle = .stopped
                self.runtimeLifecycleMessage = "运行时已停止。"
                self.appStatus = .idle
                self.addLog(.info, "BetterGI runtime stopped.")
            } catch {
                self.runtimeLifecycle = .failed
                self.runtimeLifecycleMessage = "停止失败：\(error.localizedDescription)"
                self.appStatus = .error
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
                    isEnabled: state.enabled,
                    settingsAvailable: state.settingsAvailable
                )
            }
            let autoPickSettings = try await supervisor.autoPickTriggerSettings()
            autoPickTriggerSettings = autoPickSettings
            autoPickExactBlackListDraft = autoPickSettings.exactBlackList
            autoPickFuzzyBlackListDraft = autoPickSettings.fuzzyBlackList
            autoPickWhiteListDraft = autoPickSettings.whiteList
            autoEatTriggerSettings = try await supervisor.autoEatTriggerSettings()
            quickTeleportTriggerSettings = try await supervisor.quickTeleportTriggerSettings()
            mapMaskTriggerSettings = try await supervisor.mapMaskTriggerSettings()
        } catch {
            features = []
            autoPickTriggerSettings = nil
            autoEatTriggerSettings = nil
            quickTeleportTriggerSettings = nil
            mapMaskTriggerSettings = nil
            addLog(.error, "BetterGI Core trigger catalog failed: \(error.localizedDescription)")
        }
    }

    func saveAutoPickTriggerConfiguration(
        ocrEngine: String? = nil,
        blackListEnabled: Bool? = nil,
        whiteListEnabled: Bool? = nil,
        pickKey: String? = nil
    ) {
        guard let current = autoPickTriggerSettings else { return }
        saveAutoPickTriggerSettings(.init(
            ocrEngine: ocrEngine ?? current.ocrEngine,
            ocrEngineOptions: current.ocrEngineOptions,
            blackListEnabled: blackListEnabled ?? current.blackListEnabled,
            exactBlackList: current.exactBlackList,
            fuzzyBlackList: current.fuzzyBlackList,
            whiteListEnabled: whiteListEnabled ?? current.whiteListEnabled,
            whiteList: current.whiteList,
            pickKey: pickKey ?? current.pickKey,
            pickKeyOptions: current.pickKeyOptions))
    }

    func saveAutoPickBlackLists() {
        guard let current = autoPickTriggerSettings else { return }
        let exactDraft = autoPickExactBlackListDraft
        let fuzzyDraft = autoPickFuzzyBlackListDraft
        saveAutoPickTriggerSettings(.init(
            ocrEngine: current.ocrEngine, ocrEngineOptions: current.ocrEngineOptions,
            blackListEnabled: current.blackListEnabled,
            exactBlackList: exactDraft, fuzzyBlackList: fuzzyDraft,
            whiteListEnabled: current.whiteListEnabled, whiteList: current.whiteList,
            pickKey: current.pickKey, pickKeyOptions: current.pickKeyOptions)) { [weak self] saved in
                self?.autoPickExactBlackListDraft = saved.exactBlackList
                self?.autoPickFuzzyBlackListDraft = saved.fuzzyBlackList
            }
    }

    func saveAutoPickWhiteList() {
        guard let current = autoPickTriggerSettings else { return }
        let whiteDraft = autoPickWhiteListDraft
        saveAutoPickTriggerSettings(.init(
            ocrEngine: current.ocrEngine, ocrEngineOptions: current.ocrEngineOptions,
            blackListEnabled: current.blackListEnabled,
            exactBlackList: current.exactBlackList, fuzzyBlackList: current.fuzzyBlackList,
            whiteListEnabled: current.whiteListEnabled, whiteList: whiteDraft,
            pickKey: current.pickKey, pickKeyOptions: current.pickKeyOptions)) { [weak self] saved in
                self?.autoPickWhiteListDraft = saved.whiteList
            }
    }

    private func saveAutoPickTriggerSettings(
        _ settings: BetterGICoreAutoPickTriggerSettings,
        afterSave: ((BetterGICoreAutoPickTriggerSettings) -> Void)? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor else { return }
        Task { [weak self] in
            do {
                let saved = try await supervisor.saveAutoPickTriggerSettings(settings)
                self?.autoPickTriggerSettings = saved
                afterSave?(saved)
            } catch {
                self?.addLog(.error, "Core failed to save AutoPick settings: \(error.localizedDescription)")
            }
        }
    }

    func saveAutoEatTriggerSettings(checkInterval: Int? = nil, eatInterval: Int? = nil) {
        guard let supervisor = betterGICoreSupervisor, let current = autoEatTriggerSettings else { return }
        let next = BetterGICoreAutoEatTriggerSettings(
            checkInterval: checkInterval ?? current.checkInterval,
            eatInterval: eatInterval ?? current.eatInterval)
        Task { [weak self] in
            do { self?.autoEatTriggerSettings = try await supervisor.saveAutoEatTriggerSettings(next) }
            catch { self?.addLog(.error, "Core failed to save AutoEat settings: \(error.localizedDescription)") }
        }
    }

    func saveQuickTeleportTriggerSettings(
        teleportListClickDelay: Int? = nil,
        waitTeleportPanelDelay: Int? = nil,
        hotkeyTpEnabled: Bool? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor, let current = quickTeleportTriggerSettings else { return }
        let next = BetterGICoreQuickTeleportTriggerSettings(
            teleportListClickDelay: teleportListClickDelay ?? current.teleportListClickDelay,
            waitTeleportPanelDelay: waitTeleportPanelDelay ?? current.waitTeleportPanelDelay,
            hotkeyTpEnabled: hotkeyTpEnabled ?? current.hotkeyTpEnabled)
        Task { [weak self] in
            do { self?.quickTeleportTriggerSettings = try await supervisor.saveQuickTeleportTriggerSettings(next) }
            catch { self?.addLog(.error, "Core failed to save QuickTeleport settings: \(error.localizedDescription)") }
        }
    }

    func saveMapMaskTriggerSettings(miniMapMaskEnabled: Bool) {
        guard let supervisor = betterGICoreSupervisor else { return }
        Task { [weak self] in
            do {
                self?.mapMaskTriggerSettings = try await supervisor.saveMapMaskTriggerSettings(
                    .init(miniMapMaskEnabled: miniMapMaskEnabled))
            } catch {
                self?.addLog(.error, "Core failed to save MapMask settings: \(error.localizedDescription)")
            }
        }
    }

    private func loadSoloTasksFromCore() async {
        guard let supervisor = betterGICoreSupervisor else {
            soloTasks = []
            return
        }
        do {
            soloTasks = try await supervisor.listSoloTasks()
            soloTaskStatus = try await supervisor.soloTaskStatus()
            autoGeniusInvokationSettings = try await supervisor.autoGeniusInvokationSettings()
            autoCookSettings = try await supervisor.autoCookSettings()
            autoFishingSettings = try await supervisor.autoFishingSettings()
            autoWoodSettings = try await supervisor.autoWoodSettings()
            autoMusicGameSettings = try await supervisor.autoMusicGameSettings()
            autoBossSettings = try await supervisor.autoBossSettings()
            autoLeyLineOutcropSettings = try await supervisor.autoLeyLineOutcropSettings()
            autoStygianOnslaughtSettings = try await supervisor.autoStygianOnslaughtSettings()
            autoDomainSettings = try await supervisor.autoDomainSettings()
            autoArtifactSalvageSettings = try await supervisor.autoArtifactSalvageSettings()
            autoFightSettings = try await supervisor.autoFightSettings()
        } catch {
            soloTasks = []
            autoGeniusInvokationSettings = nil
            autoCookSettings = nil
            autoFishingSettings = nil
            autoWoodSettings = nil
            autoMusicGameSettings = nil
            autoBossSettings = nil
            autoLeyLineOutcropSettings = nil
            autoStygianOnslaughtSettings = nil
            autoDomainSettings = nil
            autoArtifactSalvageSettings = nil
            autoFightSettings = nil
            addLog(.error, "BetterGI Core solo task catalog failed: \(error.localizedDescription)")
        }
    }

    func saveAutoGeniusInvokationSettings(
        strategyName: String? = nil, sleepDelay: Int? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor,
              let current = autoGeniusInvokationSettings else { return }
        let next = BetterGICoreAutoGeniusInvokationSettings(
            strategyName: strategyName ?? current.strategyName,
            strategyOptions: current.strategyOptions,
            sleepDelay: sleepDelay ?? current.sleepDelay)
        Task { [weak self] in
            do {
                self?.autoGeniusInvokationSettings =
                    try await supervisor.saveAutoGeniusInvokationSettings(next)
            } catch {
                self?.addLog(.error,
                    "AutoGeniusInvokation settings save failed: \(error.localizedDescription)")
            }
        }
    }

    func saveAutoCookSettings(checkIntervalMs: Int? = nil, stopWhenDetected: Bool? = nil) {
        guard let supervisor = betterGICoreSupervisor, let current = autoCookSettings else { return }
        let next = BetterGICoreAutoCookSettings(
            checkIntervalMs: checkIntervalMs ?? current.checkIntervalMs,
            stopTaskWhenRecoverButtonDetected:
                stopWhenDetected ?? current.stopTaskWhenRecoverButtonDetected
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                self.autoCookSettings = try await supervisor.saveAutoCookSettings(next)
            } catch {
                self.addLog(.error, "AutoCook settings save failed: \(error.localizedDescription)")
            }
        }
    }

    func saveAutoFishingSettings(
        autoThrowRodTimeOut: Int? = nil,
        wholeProcessTimeoutSeconds: Int? = nil,
        fishingTimePolicy: String? = nil,
        saveScreenshotOnKeyTick: Bool? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor,
              let current = autoFishingSettings else { return }
        let next = BetterGICoreAutoFishingSettings(
            autoThrowRodTimeOut: autoThrowRodTimeOut ?? current.autoThrowRodTimeOut,
            wholeProcessTimeoutSeconds:
                wholeProcessTimeoutSeconds ?? current.wholeProcessTimeoutSeconds,
            fishingTimePolicy: fishingTimePolicy ?? current.fishingTimePolicy,
            fishingTimePolicyOptions: current.fishingTimePolicyOptions,
            saveScreenshotOnKeyTick:
                saveScreenshotOnKeyTick ?? current.saveScreenshotOnKeyTick,
            torchDllFullPath: current.torchDllFullPath,
            torchDllSupported: current.torchDllSupported)
        Task { [weak self] in
            do {
                self?.autoFishingSettings = try await supervisor.saveAutoFishingSettings(next)
            } catch {
                self?.addLog(.error,
                    "AutoFishing settings save failed: \(error.localizedDescription)")
            }
        }
    }

    func saveAutoWoodSettings(
        roundNum: Int? = nil, dailyMaxCount: Int? = nil,
        useWonderlandRefresh: Bool? = nil, woodCountOcrEnabled: Bool? = nil,
        afterZSleepDelay: Int? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor, let current = autoWoodSettings else { return }
        let next = BetterGICoreAutoWoodSettings(
            roundNum: roundNum ?? current.roundNum,
            dailyMaxCount: dailyMaxCount ?? current.dailyMaxCount,
            useWonderlandRefresh: useWonderlandRefresh ?? current.useWonderlandRefresh,
            woodCountOcrEnabled: woodCountOcrEnabled ?? current.woodCountOcrEnabled,
            afterZSleepDelay: afterZSleepDelay ?? current.afterZSleepDelay)
        Task { [weak self] in
            do { self?.autoWoodSettings = try await supervisor.saveAutoWoodSettings(next) }
            catch { self?.addLog(.error, "AutoWood settings save failed: \(error.localizedDescription)") }
        }
    }

    func saveAutoMusicGameSettings(mustCanorusLevel: Bool? = nil, musicLevel: String? = nil) {
        guard let supervisor = betterGICoreSupervisor, let current = autoMusicGameSettings else { return }
        let next = BetterGICoreAutoMusicGameSettings(
            mustCanorusLevel: mustCanorusLevel ?? current.mustCanorusLevel,
            musicLevel: musicLevel ?? current.musicLevel,
            musicLevelOptions: current.musicLevelOptions)
        Task { [weak self] in
            do { self?.autoMusicGameSettings = try await supervisor.saveAutoMusicGameSettings(next) }
            catch { self?.addLog(.error, "AutoMusicGame settings save failed: \(error.localizedDescription)") }
        }
    }

    func saveAutoBossSettings(
        bossName: String? = nil, strategyName: String? = nil, teamName: String? = nil,
        specifyRunCount: Bool? = nil, runCount: Int? = nil,
        useTransientResin: Bool? = nil, useFragileResin: Bool? = nil,
        returnToStatueAfterEachRound: Bool? = nil,
        rewardRecognitionEnabled: Bool? = nil, reviveRetryCount: Int? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor, let current = autoBossSettings else { return }
        let next = BetterGICoreAutoBossSettings(
            bossName: bossName ?? current.bossName, bossOptions: current.bossOptions,
            strategyName: strategyName ?? current.strategyName,
            strategyOptions: current.strategyOptions, teamName: teamName ?? current.teamName,
            specifyRunCount: specifyRunCount ?? current.specifyRunCount,
            runCount: runCount ?? current.runCount,
            useTransientResin: useTransientResin ?? current.useTransientResin,
            useFragileResin: useFragileResin ?? current.useFragileResin,
            returnToStatueAfterEachRound:
                returnToStatueAfterEachRound ?? current.returnToStatueAfterEachRound,
            rewardRecognitionEnabled:
                rewardRecognitionEnabled ?? current.rewardRecognitionEnabled,
            reviveRetryCount: reviveRetryCount ?? current.reviveRetryCount)
        Task { [weak self] in
            do { self?.autoBossSettings = try await supervisor.saveAutoBossSettings(next) }
            catch { self?.addLog(.error, "AutoBoss settings save failed: \(error.localizedDescription)") }
        }
    }

    func saveAutoLeyLineOutcropSettings(
        leyLineOutcropType: String? = nil, country: String? = nil,
        strategyName: String? = nil, actionSchedulerByCd: String? = nil,
        seekEnemyEnabled: Bool? = nil, seekEnemyRotaryFactor: Int? = nil,
        seekEnemyIntervalSeconds: Int? = nil, kazuhaPickupEnabled: Bool? = nil,
        qinDoublePickUp: Bool? = nil, scanDropsAfterRewardEnabled: Bool? = nil,
        scanDropsAfterRewardSeconds: Int? = nil, isResinExhaustionMode: Bool? = nil,
        openModeCountMin: Bool? = nil, count: Int? = nil,
        useTransientResin: Bool? = nil, useFragileResin: Bool? = nil,
        team: String? = nil, friendshipTeam: String? = nil, timeout: Int? = nil,
        useAdventurerHandbook: Bool? = nil, isNotification: Bool? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor,
              let current = autoLeyLineOutcropSettings else { return }
        let next = BetterGICoreAutoLeyLineOutcropSettings(
            leyLineOutcropType: leyLineOutcropType ?? current.leyLineOutcropType,
            leyLineOutcropTypeOptions: current.leyLineOutcropTypeOptions,
            country: country ?? current.country, countryOptions: current.countryOptions,
            strategyName: strategyName ?? current.strategyName,
            strategyOptions: current.strategyOptions,
            actionSchedulerByCd: actionSchedulerByCd ?? current.actionSchedulerByCd,
            seekEnemyEnabled: seekEnemyEnabled ?? current.seekEnemyEnabled,
            seekEnemyRotaryFactor:
                seekEnemyRotaryFactor ?? current.seekEnemyRotaryFactor,
            seekEnemyIntervalSeconds:
                seekEnemyIntervalSeconds ?? current.seekEnemyIntervalSeconds,
            kazuhaPickupEnabled: kazuhaPickupEnabled ?? current.kazuhaPickupEnabled,
            qinDoublePickUp: qinDoublePickUp ?? current.qinDoublePickUp,
            scanDropsAfterRewardEnabled:
                scanDropsAfterRewardEnabled ?? current.scanDropsAfterRewardEnabled,
            scanDropsAfterRewardSeconds:
                scanDropsAfterRewardSeconds ?? current.scanDropsAfterRewardSeconds,
            isResinExhaustionMode:
                isResinExhaustionMode ?? current.isResinExhaustionMode,
            openModeCountMin: openModeCountMin ?? current.openModeCountMin,
            count: count ?? current.count,
            useTransientResin: useTransientResin ?? current.useTransientResin,
            useFragileResin: useFragileResin ?? current.useFragileResin,
            team: team ?? current.team,
            friendshipTeam: friendshipTeam ?? current.friendshipTeam,
            timeout: timeout ?? current.timeout,
            useAdventurerHandbook:
                useAdventurerHandbook ?? current.useAdventurerHandbook,
            isNotification: isNotification ?? current.isNotification)
        Task { [weak self] in
            do {
                self?.autoLeyLineOutcropSettings =
                    try await supervisor.saveAutoLeyLineOutcropSettings(next)
            } catch {
                self?.addLog(.error,
                    "AutoLeyLineOutcrop settings save failed: \(error.localizedDescription)")
            }
        }
    }

    func saveAutoStygianOnslaughtSettings(
        strategyName: String? = nil, bossNum: Int? = nil,
        fightTeamName: String? = nil, specifyResinUse: Bool? = nil,
        originalResinUseCount: Int? = nil, condensedResinUseCount: Int? = nil,
        transientResinUseCount: Int? = nil, fragileResinUseCount: Int? = nil,
        autoArtifactSalvage: Bool? = nil, maxArtifactStar: String? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor,
              let current = autoStygianOnslaughtSettings else { return }
        let next = BetterGICoreAutoStygianOnslaughtSettings(
            strategyName: strategyName ?? current.strategyName,
            strategyOptions: current.strategyOptions,
            bossNum: bossNum ?? current.bossNum,
            bossNumOptions: current.bossNumOptions,
            fightTeamName: fightTeamName ?? current.fightTeamName,
            specifyResinUse: specifyResinUse ?? current.specifyResinUse,
            originalResinUseCount: originalResinUseCount ?? current.originalResinUseCount,
            condensedResinUseCount: condensedResinUseCount ?? current.condensedResinUseCount,
            transientResinUseCount: transientResinUseCount ?? current.transientResinUseCount,
            fragileResinUseCount: fragileResinUseCount ?? current.fragileResinUseCount,
            autoArtifactSalvage: autoArtifactSalvage ?? current.autoArtifactSalvage,
            maxArtifactStar: maxArtifactStar ?? current.maxArtifactStar,
            maxArtifactStarOptions: current.maxArtifactStarOptions)
        Task { [weak self] in
            do {
                self?.autoStygianOnslaughtSettings =
                    try await supervisor.saveAutoStygianOnslaughtSettings(next)
            } catch {
                self?.addLog(.error,
                    "AutoStygianOnslaught settings save failed: \(error.localizedDescription)")
            }
        }
    }

    func saveAutoDomainSettings(
        strategyName: String? = nil, partyName: String? = nil, domainName: String? = nil,
        specifyResinUse: Bool? = nil, originalResinUseCount: Int? = nil,
        condensedResinUseCount: Int? = nil, transientResinUseCount: Int? = nil,
        fragileResinUseCount: Int? = nil, autoArtifactSalvage: Bool? = nil,
        maxArtifactStar: String? = nil, fightEndDelay: Double? = nil,
        shortMovement: Bool? = nil, walkToF: Bool? = nil,
        leftRightMoveTimes: Int? = nil, autoEat: Bool? = nil,
        rewardRecognitionEnabled: Bool? = nil, reviveRetryCount: Int? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor, let current = autoDomainSettings else { return }
        let next = BetterGICoreAutoDomainSettings(
            strategyName: strategyName ?? current.strategyName,
            strategyOptions: current.strategyOptions,
            partyName: partyName ?? current.partyName,
            domainName: domainName ?? current.domainName, domainOptions: current.domainOptions,
            specifyResinUse: specifyResinUse ?? current.specifyResinUse,
            originalResinUseCount: originalResinUseCount ?? current.originalResinUseCount,
            condensedResinUseCount: condensedResinUseCount ?? current.condensedResinUseCount,
            transientResinUseCount: transientResinUseCount ?? current.transientResinUseCount,
            fragileResinUseCount: fragileResinUseCount ?? current.fragileResinUseCount,
            autoArtifactSalvage: autoArtifactSalvage ?? current.autoArtifactSalvage,
            maxArtifactStar: maxArtifactStar ?? current.maxArtifactStar,
            maxArtifactStarOptions: current.maxArtifactStarOptions,
            fightEndDelay: fightEndDelay ?? current.fightEndDelay,
            shortMovement: shortMovement ?? current.shortMovement,
            walkToF: walkToF ?? current.walkToF,
            leftRightMoveTimes: leftRightMoveTimes ?? current.leftRightMoveTimes,
            autoEat: autoEat ?? current.autoEat,
            rewardRecognitionEnabled:
                rewardRecognitionEnabled ?? current.rewardRecognitionEnabled,
            reviveRetryCount: reviveRetryCount ?? current.reviveRetryCount)
        Task { [weak self] in
            do { self?.autoDomainSettings = try await supervisor.saveAutoDomainSettings(next) }
            catch { self?.addLog(.error, "AutoDomain settings save failed: \(error.localizedDescription)") }
        }
    }

    func saveAutoArtifactSalvageSettings(
        javaScript: String? = nil, artifactSetFilter: String? = nil,
        maxArtifactStar: String? = nil, maxNumToCheck: Int? = nil,
        recognitionFailurePolicy: String? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor,
              let current = autoArtifactSalvageSettings else { return }
        let next = BetterGICoreAutoArtifactSalvageSettings(
            javaScript: javaScript ?? current.javaScript,
            artifactSetFilter: artifactSetFilter ?? current.artifactSetFilter,
            maxArtifactStar: maxArtifactStar ?? current.maxArtifactStar,
            maxArtifactStarOptions: current.maxArtifactStarOptions,
            maxNumToCheck: maxNumToCheck ?? current.maxNumToCheck,
            recognitionFailurePolicy:
                recognitionFailurePolicy ?? current.recognitionFailurePolicy,
            recognitionFailurePolicyOptions: current.recognitionFailurePolicyOptions)
        Task { [weak self] in
            do {
                self?.autoArtifactSalvageSettings =
                    try await supervisor.saveAutoArtifactSalvageSettings(next)
            } catch {
                self?.addLog(.error,
                    "AutoArtifactSalvage settings save failed: \(error.localizedDescription)")
            }
        }
    }

    func saveAutoFightSettings(
        strategyName: String? = nil, actionSchedulerByCd: String? = nil,
        fightFinishDetectEnabled: Bool? = nil, fastCheckEnabled: Bool? = nil,
        fastCheckParams: String? = nil, rotateFindEnemyEnabled: Bool? = nil,
        rotaryFactor: Int? = nil, checkBeforeBurst: Bool? = nil,
        isFirstCheck: Bool? = nil, checkEndDelay: String? = nil,
        beforeDetectDelay: String? = nil, guardianAvatar: String? = nil,
        guardianCombatSkip: Bool? = nil, burstEnabled: Bool? = nil,
        guardianAvatarHold: Bool? = nil, pickDropsAfterFightEnabled: Bool? = nil,
        pickDropsAfterFightSeconds: Int? = nil, kazuhaPickupEnabled: Bool? = nil,
        qinDoublePickUp: Bool? = nil, expBasedPickupEnabled: Bool? = nil,
        timeout: Int? = nil, swimmingEnabled: Bool? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor, let current = autoFightSettings else { return }
        let next = BetterGICoreAutoFightSettings(
            strategyName: strategyName ?? current.strategyName,
            strategyOptions: current.strategyOptions,
            actionSchedulerByCd: actionSchedulerByCd ?? current.actionSchedulerByCd,
            fightFinishDetectEnabled:
                fightFinishDetectEnabled ?? current.fightFinishDetectEnabled,
            fastCheckEnabled: fastCheckEnabled ?? current.fastCheckEnabled,
            fastCheckParams: fastCheckParams ?? current.fastCheckParams,
            rotateFindEnemyEnabled: rotateFindEnemyEnabled ?? current.rotateFindEnemyEnabled,
            rotaryFactor: rotaryFactor ?? current.rotaryFactor,
            checkBeforeBurst: checkBeforeBurst ?? current.checkBeforeBurst,
            isFirstCheck: isFirstCheck ?? current.isFirstCheck,
            checkEndDelay: checkEndDelay ?? current.checkEndDelay,
            beforeDetectDelay: beforeDetectDelay ?? current.beforeDetectDelay,
            guardianAvatar: guardianAvatar ?? current.guardianAvatar,
            guardianAvatarOptions: current.guardianAvatarOptions,
            guardianCombatSkip: guardianCombatSkip ?? current.guardianCombatSkip,
            burstEnabled: burstEnabled ?? current.burstEnabled,
            guardianAvatarHold: guardianAvatarHold ?? current.guardianAvatarHold,
            pickDropsAfterFightEnabled:
                pickDropsAfterFightEnabled ?? current.pickDropsAfterFightEnabled,
            pickDropsAfterFightSeconds:
                pickDropsAfterFightSeconds ?? current.pickDropsAfterFightSeconds,
            kazuhaPickupEnabled: kazuhaPickupEnabled ?? current.kazuhaPickupEnabled,
            qinDoublePickUp: qinDoublePickUp ?? current.qinDoublePickUp,
            expBasedPickupEnabled: expBasedPickupEnabled ?? current.expBasedPickupEnabled,
            timeout: timeout ?? current.timeout,
            swimmingEnabled: swimmingEnabled ?? current.swimmingEnabled)
        Task { [weak self] in
            do { self?.autoFightSettings = try await supervisor.saveAutoFightSettings(next) }
            catch { self?.addLog(.error, "AutoFight settings save failed: \(error.localizedDescription)") }
        }
    }

    func toggleSoloTask(_ name: String, inputText: String? = nil) {
        guard let supervisor = betterGICoreSupervisor else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                if self.soloTaskStatus.name == name,
                   self.soloTaskStatus.state == "running",
                   let taskID = self.soloTaskStatus.taskID {
                    try await supervisor.stopSoloTask(taskID: taskID)
                } else {
                    self.soloTaskStatus = try await supervisor.startSoloTask(
                        name: name, inputText: inputText)
                }
                await self.pollSoloTaskStatus(supervisor)
            } catch {
                self.addLog(.error, "Core solo task \(name) failed: \(error.localizedDescription)")
            }
        }
    }

    private func pollSoloTaskStatus(_ supervisor: BetterGICoreProcessSupervisor) async {
        while true {
            do {
                soloTaskStatus = try await supervisor.soloTaskStatus()
            } catch {
                addLog(.error, "Core solo task status failed: \(error.localizedDescription)")
                return
            }
            guard soloTaskStatus.state == "running" || soloTaskStatus.state == "stopping" else {
                if let error = soloTaskStatus.error {
                    addLog(.error, "Core solo task failed: \(error)")
                }
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
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
        attemptAutoStartRuntime()
    }

    @discardableResult
    func refreshSelectedWindowGeometry() -> WindowInfo? {
        let windows = QuartzWindowEnumerator.enumerateApplicationWindows()
        if let refreshed = windows.first(where: { $0.id == selectedWindow.id }) {
            if refreshed != selectedWindow {
                selectedWindow = refreshed
            }
            if runtimeLifecycle == .running,
               runtimeGeometryPixelSize != refreshed.capturePixelSize {
                scheduleRuntimeGeometryRefresh(for: refreshed.capturePixelSize)
            }
            gameWindowStatus = refreshed.isLikelyGameWindow ? .detected : .missing
            return refreshed
        }

        if let replacement = QuartzWindowEnumerator.bestGameWindow(from: windows) {
            let previousWindowID = selectedWindow.isSynthetic ? nil : selectedWindow.id
            selectedWindow = replacement
            availableWindows = windows
            gameWindowStatus = .detected
            if runtimeLifecycle == .running,
               runtimeGeometryPixelSize != replacement.capturePixelSize {
                scheduleRuntimeGeometryRefresh(for: replacement.capturePixelSize)
            }
            if let previousWindowID {
                addLog(.info,
                    "Game window restarted; rebound WindowID \(previousWindowID) to \(replacement.id).")
            } else {
                addLog(.info, "Game window detected: \(replacement.displayName)")
            }
            return replacement
        }

        if !selectedWindow.isSynthetic {
            selectedWindow = .unavailable(title: "Game window unavailable")
            availableWindows = windows
            gameWindowStatus = .missing
            addLog(.warn, "Selected game window disappeared; waiting for a new Genshin window.")
        }
        return nil
    }

    private func scheduleRuntimeGeometryRefresh(for pixelSize: CGSize) {
        guard runtimeLifecycle == .running, betterGICoreSupervisor != nil,
              pendingRuntimeGeometryPixelSize != pixelSize else { return }
        pendingRuntimeGeometryPixelSize = pixelSize
        runtimeGeometryRefreshTask?.cancel()
        runtimeGeometryRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard let self, self.runtimeLifecycle == .running,
                      self.pendingRuntimeGeometryPixelSize == pixelSize,
                      let supervisor = self.betterGICoreSupervisor else { return }
                try await supervisor.refreshRuntimeGeometry()
                self.runtimeGeometryPixelSize = pixelSize
                self.pendingRuntimeGeometryPixelSize = nil
                self.addLog(.info,
                    "Game resolution changed to \(Int(pixelSize.width))x\(Int(pixelSize.height)); Core assets reloaded.")
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.pendingRuntimeGeometryPixelSize == pixelSize else { return }
                self.pendingRuntimeGeometryPixelSize = nil
                self.addLog(.error,
                    "Core geometry refresh failed for \(Int(pixelSize.width))x\(Int(pixelSize.height)): \(error.localizedDescription)")
            }
        }
    }

    private func cancelRuntimeGeometryRefresh() {
        runtimeGeometryRefreshTask?.cancel()
        runtimeGeometryRefreshTask = nil
        pendingRuntimeGeometryPixelSize = nil
        runtimeGeometryPixelSize = nil
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
        cancelRuntimeGeometryRefresh()
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
