import AppKit
import Darwin
import Foundation
import SwiftUI
import UserNotifications

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

enum LogLevel: String, CaseIterable, Identifiable, Sendable {
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
    var canSetEnabled: Bool
    var settingsAvailable: Bool
    var autoHangoutEventEnabled: Bool?
}

struct LogEntry: Identifiable, Equatable, Sendable {
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

@MainActor
final class AppState: ObservableObject {
    @Published var selectedPage: NavigationPage = .launch
    @Published var appStatus: AppStatus = .idle
    @Published var gameWindowStatus: RuntimeStatus = .missing
    @Published var captureStatus: RuntimeStatus = .missing
    @Published var inputStatus: RuntimeStatus = .missing
    @Published var coreStatus: RuntimeStatus = .starting
    @Published private(set) var screenCapturePermissionGranted = false
    @Published private(set) var screenCaptureAuthorizationState: ScreenCaptureAuthorizationState = .checking
    @Published private(set) var accessibilityPermissionGranted = false
    @Published private(set) var screenCapturePermissionRequestMessage: String?
    @Published private(set) var runtimeLifecycleMessage = "运行时尚未启动。"
    @Published var runtimeLifecycle: RuntimeLifecycle = .stopped {
        didSet {
            recomputeHUDPresentation()
            refreshHotKeyMonitor()
        }
    }
    @Published var isHUDVisible = false {
        didSet { recomputeHUDPresentation() }
    }
    @Published private(set) var isGameWindowFrontmost = false
    @Published private(set) var isHUDPresented = false
    @Published var hideHUDWhenGameUnfocused = true {
        didSet {
            userDefaults.set(hideHUDWhenGameUnfocused, forKey: Self.hideHUDWhenGameUnfocusedKey)
            recomputeHUDPresentation()
        }
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
    @Published var overlayLayoutEditEnabled = false {
        didSet { recomputeHUDPresentation() }
    }
    let coreOverlayStore = CoreOverlayStore()
    @Published var launchAtLogin = false
    @Published var showHUDOnStart = true
    @Published var keepWindowOnTop = false
    @Published var debugPageEnabled = true
    @Published var debugConfidence = 0.86
    @Published var dispatcherIntervalMs = 50
    @Published private(set) var allowRuntimeRealInput: Bool
    let dryRunLaunchEnabled: Bool
    @Published var schedulerGroups: [BetterGIScriptGroupSummary] = []
    @Published var scriptProjects: [BetterGIScriptProjectSummary] = []
    @Published var schedulerCatalogIssues: [CoreCatalogIssue] = []
    @Published var schedulerCatalogStatus = "Core unavailable"
    @Published var selectedSchedulerGroupName = ""
    @Published var schedulerExecutionStatus = "Idle"
    @Published var schedulerExecutionError: String?
    @Published var currentSchedulerProjectID: String?
    @Published private(set) var pathingEntries: [BetterGIPathingEntry] = []
    @Published private(set) var pathingCatalogStatus = "Core unavailable"

    // MARK: Window & capture (typed — not strings)

    /// Currently selected game window.
    @Published var selectedWindow: WindowInfo = .unavailable() {
        didSet {
            updateGameWindowFocus(frontmostPID: frontmostApplicationPID)
            refreshAuxiliaryControlMonitor()
            refreshHotKeyMonitor()
        }
    }

    /// Available game windows from the tracker.
    @Published var availableWindows: [WindowInfo] = []

    /// Most recently captured frame (nil if no capture session).
    @Published var lastCapturedFrame: CapturedFrame?

    /// Most recent captured image frame for OCR/template matching.
    @Published var lastCaptureImageFrame: CaptureImageFrame?

    /// Key bindings mirrored from BetterGI `KeyBindingsConfig`.
    @Published var keyBindings: KeyBindingsConfig = .bgiDefault


    /// Input safety gate (dry-run, emergency stop, rate limiting).
    let safetyGate: InputSafetyGate

    private let frameProvider = ScreenCaptureKitFrameProvider()
    private let inputDispatcher: any InputDispatching
    private let isTargetWindowFrontmost: (WindowInfo) -> Bool
    private let runtimeResourceStore: BGIRuntimeResourceStore
    private let runtimeLogWriter: RuntimeLogFileWriter
    private let userDefaults: UserDefaults
    let latestFrameStore = LatestFrameStore()
    private var runtimeFrameIndex: UInt64 = 0
    private var schedulerExecutionTask: Task<Void, Never>?
    private var betterGICoreSupervisor: BetterGICoreProcessSupervisor?
    private var coreStartupTask: Task<Void, Never>?
    private var coreStartupInFlight = false
    private var autoStartRuntimePending: Bool
    private var autoStartSchedulerGroupNames: [String]
    private var runtimeLaunchReady = false
    private var runtimeGeometryPixelSize: CGSize?
    private var pendingRuntimeGeometryPixelSize: CGSize?
    private var runtimeGeometryRefreshTask: Task<Void, Never>?
    private var runtimeTargetProcessID: pid_t?
    private var mapMaskSelectionSaveTask: Task<Void, Never>?
    private let keyMouseEventRecorder = MacKeyMouseEventRecorder()
    private var keyMouseRecordingStartTask: Task<Void, Never>?
    private var keyMousePlaybackPollTask: Task<Void, Never>?
    private var notificationSettingsSaveRevision = 0
    private var macroSettingsSaveRevision = 0
    private var hotKeySettingsSaveRevision = 0
    private var hotKeyMonitorErrorLogged = false
    private lazy var auxiliaryControlMonitor = MacAuxiliaryControlMonitor {
        [weak self] key, isDown in
        MainActor.assumeIsolated {
            self?.handleAuxiliaryControlKey(key, isDown: isDown)
        }
    }
    private lazy var hotKeyMonitor = MacHotKeyMonitor(
        handler: { [weak self] binding in
            MainActor.assumeIsolated {
                self?.handleHotKey(binding)
            }
        },
        captureHandler: { [weak self] id, value, error in
            MainActor.assumeIsolated {
                self?.completeHotKeyCapture(
                    id: id, value: value, error: error)
            }
        })
    private var fContinuationTask: Task<Void, Never>?
    private var spaceContinuationTask: Task<Void, Never>?
    private var confirmedMapMaskSelectedLabelIDs: Set<String> = []
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
    @Published private(set) var keyMouseScripts: [BetterGIKeyMouseScript] = []
    @Published private(set) var keyMouseRecordingState = "idle"
    @Published private(set) var keyMousePlaybackStatus = BetterGIKeyMousePlaybackStatus(
        taskID: nil, scriptID: nil, state: "idle", error: nil)
    @Published private(set) var notificationSettings: BetterGINotificationSettings?
    @Published private(set) var notificationTestStatus = ""
    @Published private(set) var macroSettings: BetterGIMacroSettings?
    @Published private(set) var hotKeyBindings: [BetterGIHotKeyBinding] = []
    @Published private(set) var hotKeyCaptureID: String?
    @Published private(set) var hotKeyStatusMessage = ""
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
    @Published private(set) var autoSkipTriggerSettings: BetterGICoreAutoSkipTriggerSettings?
    @Published var autoPickExactBlackListDraft = ""
    @Published var autoPickFuzzyBlackListDraft = ""
    @Published var autoPickWhiteListDraft = ""
    @Published var autoSkipCustomPriorityOptionsDraft = ""
    @Published private(set) var quickTeleportTriggerSettings: BetterGICoreQuickTeleportTriggerSettings?
    @Published private(set) var mapMaskTriggerSettings: BetterGICoreMapMaskTriggerSettings?
    @Published private(set) var skillCdTriggerSettings: BetterGICoreSkillCdTriggerSettings?
    @Published var skillCdRulesDraft: [BetterGICoreSkillCdRule] = []
    @Published var skillCdTextNormalColorDraft = ""
    @Published var skillCdBackgroundNormalColorDraft = ""
    @Published var skillCdTextReadyColorDraft = ""
    @Published var skillCdBackgroundReadyColorDraft = ""
    @Published private(set) var mapMaskPickerSettings: BetterGICoreMapMaskPickerSettings?
    @Published private(set) var mapMaskLabelCategories: [BetterGICoreMapMaskLabel] = []
    @Published private(set) var mapMaskSelectedLabelIDs: Set<String> = []
    @Published private(set) var mapMaskCatalogLoading = false
    @Published private(set) var mapMaskCatalogLoaded = false
    @Published private(set) var isMapMaskPickerOpen = false
    @Published var recentLogs: [LogEntry] = []

    var onHUDPresentationChanged: ((Bool) -> Void)?
    private var frontmostApplicationPID: pid_t?
    private let screenCapturePermissionCoordinator: ScreenCapturePermissionCoordinator

    init(
        resourceStore: BGIRuntimeResourceStore = .defaultStore(),
        inputDispatcher: any InputDispatching = CGEventInputDispatcher(),
        isTargetWindowFrontmost: @escaping (WindowInfo) -> Bool = ForegroundWindowGuard.isTargetFrontmost,
        launchArguments: [String] = ProcessInfo.processInfo.arguments,
        userDefaults: UserDefaults = .standard,
        screenCapturePermissionCoordinator: ScreenCapturePermissionCoordinator? = nil
    ) {
        self.screenCapturePermissionCoordinator =
            screenCapturePermissionCoordinator ?? ScreenCapturePermissionCoordinator()
        self.userDefaults = userDefaults
        dryRunLaunchEnabled = launchArguments.contains("--dry-run")
        safetyGate = InputSafetyGate(
            dryRun: dryRunLaunchEnabled,
            realInputEnabled: !dryRunLaunchEnabled)
        allowRuntimeRealInput = !dryRunLaunchEnabled
        runtimeResourceStore = resourceStore
        runtimeLogWriter = RuntimeLogFileWriter(directory: resourceStore.logURL)
        self.inputDispatcher = inputDispatcher
        self.isTargetWindowFrontmost = isTargetWindowFrontmost
        let storedFocusHiding = userDefaults.object(forKey: Self.hideHUDWhenGameUnfocusedKey)
            as? Bool ?? true
        hideHUDWhenGameUnfocused = launchArguments.contains("--disable-hud-focus-hiding")
            ? false
            : storedFocusHiding
        autoStartSchedulerGroupNames = Self.startGroupNames(from: launchArguments)
        autoStartRuntimePending = launchArguments.contains("--start-runtime")
            || !autoStartSchedulerGroupNames.isEmpty
        addLog(.info, "betterGI-mac Swift UI initialized")
        if dryRunLaunchEnabled {
            addLog(.info, "Dry-Run enabled by --dry-run; real input is disabled")
        }
        if !hideHUDWhenGameUnfocused {
            addLog(.info, "HUD focus hiding is disabled for this launch")
        }
        addLog(.info, "Waiting for BetterGI C# Core Host")
        refreshPermissionStatus()
        refreshWindows()
    }

    func beginCoreStartup() {
        guard coreStartupTask == nil, !coreStartupInFlight, betterGICoreSupervisor == nil else { return }
        runtimeLaunchReady = true
        NSLog("BetterGI Core startup scheduled")
        coreStartupTask = Task {
            await startBetterGICore()
        }
        attemptAutoStartRuntime()
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

    func openScriptProjectRootLocation() {
        guard let supervisor = betterGICoreSupervisor else {
            addLog(.error, "Open script directory failed: BetterGI Core is unavailable.")
            return
        }
        Task { [weak self] in
            do {
                let path = try await supervisor.scriptProjectRootLocation()
                guard NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
                    throw BetterGICoreRPCError.socket("Finder could not open the script directory.")
                }
            } catch {
                self?.addLog(.error, "Open script directory failed: \(error.localizedDescription)")
            }
        }
    }

    func loadScriptRepositoryState() async throws -> BetterGIScriptRepositoryState {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        return try await supervisor.scriptRepositoryState()
    }

    func updateScriptRepository(channel: String, url: String) async throws -> BetterGIScriptRepositoryUpdateResult {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        let result = try await supervisor.updateScriptRepository(channel: channel, url: url)
        addLog(.info, result.status == "alreadyUpToDate" ? "脚本仓库已是最新。" : "脚本仓库更新完成。")
        return result
    }

    func resetScriptRepository() async throws {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        try await supervisor.resetScriptRepository()
        addLog(.info, "脚本仓库已重置。")
    }

    func scriptRepositoryRepoJSON() async throws -> String {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        return try await supervisor.scriptRepositoryRepoJSON()
    }

    func scriptRepositorySubscribedPathsJSON() async throws -> String {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        return try await supervisor.scriptRepositorySubscribedPathsJSON()
    }

    func scriptRepositoryFile(path: String) async throws -> String {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        return try await supervisor.scriptRepositoryFile(path: path)
    }

    func resetScriptRepositoryUpdateFlag(path: String) async throws -> Bool {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        return try await supervisor.resetScriptRepositoryUpdateFlag(path: path)
    }

    func clearScriptRepositoryUpdateFlags() async throws -> Bool {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        return try await supervisor.clearScriptRepositoryUpdateFlags()
    }

    func scriptRepositoryGuideStatus() async throws -> Bool {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        return try await supervisor.scriptRepositoryGuideStatus()
    }

    func setScriptRepositoryGuideStatus(_ status: Bool) async throws -> Bool {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        return try await supervisor.setScriptRepositoryGuideStatus(status)
    }

    func importScriptRepositoryURI(_ uri: String) async throws -> Int {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        let count = try await supervisor.importScriptRepositoryURI(uri)
        await loadSchedulerGroupsFromCore()
        addLog(.info, "已从脚本仓库安装 \(count) 个项目。")
        return count
    }

    func refreshKeyMouseScripts() {
        Task { [weak self] in
            await self?.loadKeyMouseScriptsFromCore()
        }
    }

    private func loadKeyMouseScriptsFromCore() async {
        guard let supervisor = betterGICoreSupervisor else {
            keyMouseScripts = []
            return
        }
        do {
            keyMouseScripts = try await supervisor.listKeyMouseScripts()
            keyMousePlaybackStatus = try await supervisor.keyMousePlaybackStatus()
        } catch {
            keyMouseScripts = []
            addLog(.error, "Key/mouse script catalog failed: \(error.localizedDescription)")
        }
    }

    func startKeyMouseRecording() {
        guard runtimeLifecycle == .running else {
            addLog(.error, "请先启动运行时再录制键鼠脚本。")
            return
        }
        guard keyMouseRecordingState == "idle" || keyMouseRecordingState == "failed" else {
            addLog(.warn, "键鼠录制已处于 \(keyMouseRecordingState) 状态。")
            return
        }
        keyMouseRecordingStartTask?.cancel()
        keyMouseRecordingState = "starting"
        addLog(.info, "3 秒后启动键鼠录制。")
        keyMouseRecordingStartTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
                guard let self else { return }
                guard self.runtimeLifecycle == .running else {
                    throw BetterGICoreRPCError.protocolViolation("运行时已停止。")
                }
                guard self.isTargetWindowFrontmost(self.selectedWindow) else {
                    throw BetterGICoreRPCError.protocolViolation(
                        "原神窗口未处于前台，录制未启动。")
                }
                let recordingHotKey = self.hotKeyBindings.first {
                    $0.action == "recording.toggle"
                }.flatMap {
                    MacHotKeySignature.parse($0.hotKey)
                }
                try self.keyMouseEventRecorder.start(
                    targetWindow: self.selectedWindow,
                    ignoring: recordingHotKey)
                self.keyMouseRecordingState = "recording"
                self.addLog(.info, "键鼠录制已启动。")
            } catch is CancellationError {
                self?.keyMouseRecordingState = "idle"
            } catch {
                self?.keyMouseRecordingState = "failed"
                self?.addLog(.error, "键鼠录制启动失败：\(error.localizedDescription)")
            }
        }
    }

    func stopKeyMouseRecording() {
        if keyMouseRecordingState == "starting" {
            keyMouseRecordingStartTask?.cancel()
            keyMouseRecordingStartTask = nil
            keyMouseRecordingState = "idle"
            addLog(.info, "已取消键鼠录制启动。")
            return
        }
        guard keyMouseRecordingState == "recording",
              let supervisor = betterGICoreSupervisor
        else {
            addLog(.warn, "当前没有正在运行的键鼠录制。")
            return
        }
        do {
            let recording = try keyMouseEventRecorder.stop()
            keyMouseRecordingState = "saving"
            Task { [weak self] in
                do {
                    try await supervisor.saveKeyMouseRecording(recording)
                    self?.keyMouseRecordingState = "idle"
                    self?.addLog(.info, "键鼠录制已保存，共 \(recording.events.count) 个原始事件。")
                    await self?.loadKeyMouseScriptsFromCore()
                } catch {
                    self?.keyMouseRecordingState = "failed"
                    self?.addLog(.error, "键鼠录制保存失败：\(error.localizedDescription)")
                }
            }
        } catch {
            keyMouseRecordingState = "failed"
            addLog(.error, "键鼠录制停止失败：\(error.localizedDescription)")
        }
    }

    func playKeyMouseScript(_ id: String) {
        guard runtimeLifecycle == .running, let supervisor = betterGICoreSupervisor else {
            addLog(.error, "请先启动运行时再播放键鼠脚本。")
            return
        }
        keyMousePlaybackPollTask?.cancel()
        keyMousePlaybackPollTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.keyMousePlaybackStatus = try await supervisor.playKeyMouseScript(id: id)
                while self.keyMousePlaybackStatus.state == "running" ||
                        self.keyMousePlaybackStatus.state == "stopping" {
                    try await Task.sleep(for: .milliseconds(250))
                    self.keyMousePlaybackStatus = try await supervisor.keyMousePlaybackStatus()
                }
                if let error = self.keyMousePlaybackStatus.error {
                    self.addLog(.error, "键鼠脚本播放失败：\(error)")
                }
            } catch is CancellationError {
                return
            } catch {
                self.addLog(.error, "键鼠脚本播放失败：\(error.localizedDescription)")
            }
        }
    }

    func stopKeyMousePlayback() {
        guard let supervisor = betterGICoreSupervisor else { return }
        Task { [weak self] in
            do {
                self?.keyMousePlaybackStatus = try await supervisor.stopKeyMouseScript()
            } catch {
                self?.addLog(.error, "停止键鼠脚本失败：\(error.localizedDescription)")
            }
        }
    }

    func renameKeyMouseScript(id: String, name: String) {
        guard let supervisor = betterGICoreSupervisor else { return }
        Task { [weak self] in
            do {
                try await supervisor.renameKeyMouseScript(id: id, name: name)
                await self?.loadKeyMouseScriptsFromCore()
            } catch {
                self?.addLog(.error, "键鼠脚本重命名失败：\(error.localizedDescription)")
            }
        }
    }

    func deleteKeyMouseScript(id: String) {
        guard let supervisor = betterGICoreSupervisor else { return }
        Task { [weak self] in
            do {
                try await supervisor.deleteKeyMouseScript(id: id)
                await self?.loadKeyMouseScriptsFromCore()
            } catch {
                self?.addLog(.error, "删除键鼠脚本失败：\(error.localizedDescription)")
            }
        }
    }

    func openKeyMouseScriptDirectory() {
        guard let supervisor = betterGICoreSupervisor else { return }
        Task { [weak self] in
            do {
                let path = try await supervisor.keyMouseScriptRootLocation()
                guard NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
                    throw BetterGICoreRPCError.socket("Finder 无法打开键鼠脚本目录。")
                }
            } catch {
                self?.addLog(.error, "打开键鼠脚本目录失败：\(error.localizedDescription)")
            }
        }
    }

    private func loadNotificationSettingsFromCore() async {
        guard let supervisor = betterGICoreSupervisor else {
            notificationSettings = nil
            return
        }
        do {
            notificationSettings = try await supervisor.notificationSettings()
        } catch {
            notificationSettings = nil
            addLog(.error, "通知设置加载失败：\(error.localizedDescription)")
        }
    }

    func saveNotificationSettings(
        jsNotificationEnabled: Bool? = nil,
        macOSNotificationEnabled: Bool? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor,
              let current = notificationSettings
        else {
            addLog(.error, "通知设置保存失败：BetterGI Core 尚未就绪。")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let nativeEnabled = macOSNotificationEnabled ?? current.macOSNotificationEnabled
            if nativeEnabled && !current.macOSNotificationEnabled {
                do {
                    let granted = try await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound])
                    guard granted else {
                        throw BetterGICoreRPCError.protocolViolation("macOS 通知权限未授权。")
                    }
                } catch {
                    self.notificationTestStatus = error.localizedDescription
                    self.addLog(.error, "macOS 通知授权失败：\(error.localizedDescription)")
                    return
                }
            }
            let next = BetterGINotificationSettings(
                jsNotificationEnabled:
                    jsNotificationEnabled ?? current.jsNotificationEnabled,
                macOSNotificationEnabled: nativeEnabled)
            self.notificationSettingsSaveRevision += 1
            let revision = self.notificationSettingsSaveRevision
            self.notificationSettings = next
            do {
                let saved = try await supervisor.saveNotificationSettings(next)
                if revision == self.notificationSettingsSaveRevision {
                    self.notificationSettings = saved
                    self.notificationTestStatus = ""
                }
            } catch {
                if revision == self.notificationSettingsSaveRevision {
                    await self.loadNotificationSettingsFromCore()
                }
                self.addLog(.error, "通知设置保存失败：\(error.localizedDescription)")
            }
        }
    }

    func sendTestNotification() {
        guard let supervisor = betterGICoreSupervisor else { return }
        notificationTestStatus = "正在发送"
        Task { [weak self] in
            do {
                try await supervisor.testNotification()
                self?.notificationTestStatus = "发送成功"
            } catch {
                self?.notificationTestStatus = error.localizedDescription
                self?.addLog(.error, "测试通知失败：\(error.localizedDescription)")
            }
        }
    }

    private func loadMacroSettingsFromCore() async {
        guard let supervisor = betterGICoreSupervisor else {
            macroSettings = nil
            return
        }
        do {
            macroSettings = try await supervisor.macroSettings()
            refreshAuxiliaryControlMonitor()
        } catch {
            macroSettings = nil
            addLog(.error, "辅助操控设置加载失败：\(error.localizedDescription)")
        }
    }

    private func loadHotKeySettingsFromCore() async {
        guard let supervisor = betterGICoreSupervisor else {
            hotKeyBindings = []
            hotKeyMonitor.stop()
            return
        }
        do {
            hotKeyBindings = try await supervisor.hotKeyBindings()
            hotKeyStatusMessage = ""
            refreshHotKeyMonitor()
        } catch {
            hotKeyBindings = []
            hotKeyMonitor.stop()
            addLog(.error, "快捷键设置加载失败：\(error.localizedDescription)")
        }
    }

    func beginHotKeyCapture(_ binding: BetterGIHotKeyBinding) {
        do {
            try hotKeyMonitor.beginCapture(
                id: binding.id, hotKeyType: binding.hotKeyType)
            hotKeyCaptureID = binding.id
            hotKeyStatusMessage = "请按下新的快捷键；Delete、Backspace 或 Escape 清除。"
        } catch {
            hotKeyCaptureID = nil
            hotKeyStatusMessage = error.localizedDescription
            addLog(.error, "快捷键录入启动失败：\(error.localizedDescription)")
        }
    }

    func cancelHotKeyCapture() {
        hotKeyMonitor.cancelCapture()
        hotKeyCaptureID = nil
        hotKeyStatusMessage = ""
    }

    func clearHotKey(_ binding: BetterGIHotKeyBinding) {
        saveHotKeyBinding(binding, hotKey: "", hotKeyType: binding.hotKeyType)
    }

    func switchHotKeyType(_ binding: BetterGIHotKeyBinding) {
        guard !binding.isHold else { return }
        let nextType = binding.hotKeyType == "GlobalRegister"
            ? "KeyboardMonitor"
            : "GlobalRegister"
        saveHotKeyBinding(binding, hotKey: "", hotKeyType: nextType)
    }

    private func completeHotKeyCapture(
        id: String,
        value: String?,
        error: String?
    ) {
        guard hotKeyCaptureID == id,
              let binding = hotKeyBindings.first(where: { $0.id == id })
        else {
            return
        }
        if let error {
            hotKeyStatusMessage = error
            return
        }
        guard let value else { return }
        hotKeyCaptureID = nil
        hotKeyStatusMessage = ""
        saveHotKeyBinding(
            binding, hotKey: value, hotKeyType: binding.hotKeyType)
    }

    private func saveHotKeyBinding(
        _ binding: BetterGIHotKeyBinding,
        hotKey: String,
        hotKeyType: String
    ) {
        guard let supervisor = betterGICoreSupervisor else {
            addLog(.error, "快捷键设置保存失败：BetterGI Core 尚未就绪。")
            return
        }
        hotKeySettingsSaveRevision += 1
        let revision = hotKeySettingsSaveRevision
        hotKeyBindings = hotKeyBindings.map { item in
            if item.id == binding.id {
                return BetterGIHotKeyBinding(
                    id: item.id, category: item.category,
                    functionName: item.functionName, hotKey: hotKey,
                    hotKeyType: hotKeyType, action: item.action,
                    executionOwner: item.executionOwner,
                    isHold: item.isHold,
                    dispatchOnPress: item.dispatchOnPress)
            }
            if !hotKey.isEmpty,
               item.hotKey.caseInsensitiveCompare(hotKey) == .orderedSame {
                return BetterGIHotKeyBinding(
                    id: item.id, category: item.category,
                    functionName: item.functionName, hotKey: "",
                    hotKeyType: item.hotKeyType, action: item.action,
                    executionOwner: item.executionOwner,
                    isHold: item.isHold,
                    dispatchOnPress: item.dispatchOnPress)
            }
            return item
        }
        refreshHotKeyMonitor()
        Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await supervisor.saveHotKeyBinding(
                    id: binding.id, hotKey: hotKey, hotKeyType: hotKeyType)
                if revision == self.hotKeySettingsSaveRevision {
                    self.hotKeyBindings = saved
                    self.refreshHotKeyMonitor()
                }
            } catch {
                if revision == self.hotKeySettingsSaveRevision {
                    await self.loadHotKeySettingsFromCore()
                }
                self.addLog(.error, "快捷键设置保存失败：\(error.localizedDescription)")
            }
        }
    }

    private func refreshHotKeyMonitor() {
        do {
            try hotKeyMonitor.update(
                bindings: hotKeyBindings,
                targetProcessID:
                    isWindowValid && !selectedWindow.isSynthetic
                    ? selectedWindow.ownerPID
                    : nil,
                runtimeActive: runtimeLifecycle == .running)
            hotKeyMonitorErrorLogged = false
        } catch {
            if !hotKeyMonitorErrorLogged {
                addLog(.error, "快捷键监听启动失败：\(error.localizedDescription)")
                hotKeyMonitorErrorLogged = true
            }
        }
    }

    private func handleHotKey(_ binding: BetterGIHotKeyBinding) {
        if binding.executionOwner == "core" {
            guard let supervisor = betterGICoreSupervisor else { return }
            Task { [weak self] in
                do {
                    let state = try await supervisor.invokeHotKey(id: binding.id)
                    self?.hotKeyStatusMessage =
                        state.map { "\(binding.functionName)：\($0)" } ?? binding.functionName
                    await self?.loadTriggerStatesFromCore()
                    await self?.loadSoloTasksFromCore()
                } catch {
                    self?.addLog(
                        .error,
                        "快捷键「\(binding.functionName)」执行失败：\(error.localizedDescription)")
                }
            }
            return
        }

        switch binding.action {
        case "runtime.toggle":
            toggleRuntime()
        case "overlay.log.toggle":
            showOverlayLogBox.toggle()
            showOverlayStatus = showOverlayLogBox
            showOverlayMetrics = showOverlayLogBox
        case "recording.toggle":
            if keyMouseRecordingState == "recording" ||
                keyMouseRecordingState == "starting" {
                stopKeyMouseRecording()
            } else {
                startKeyMouseRecording()
            }
        default:
            addLog(
                .error,
                "快捷键「\(binding.functionName)」没有可用的平台动作。")
        }
    }

    func saveMacroSettings(
        fEnabled: Bool? = nil,
        fInterval: Int? = nil,
        spaceEnabled: Bool? = nil,
        spaceInterval: Int? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor, let current = macroSettings else {
            addLog(.error, "辅助操控设置保存失败：BetterGI Core 尚未就绪。")
            return
        }
        let next = BetterGIMacroSettings(
            fPressHoldToContinuationEnabled:
                fEnabled ?? current.fPressHoldToContinuationEnabled,
            fFireInterval: fInterval ?? current.fFireInterval,
            spacePressHoldToContinuationEnabled:
                spaceEnabled ?? current.spacePressHoldToContinuationEnabled,
            spaceFireInterval: spaceInterval ?? current.spaceFireInterval,
            pickUpOrInteractKey: current.pickUpOrInteractKey,
            jumpKey: current.jumpKey)
        macroSettingsSaveRevision += 1
        let revision = macroSettingsSaveRevision
        macroSettings = next
        refreshAuxiliaryControlMonitor()
        Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await supervisor.saveMacroSettings(next)
                if revision == self.macroSettingsSaveRevision {
                    self.macroSettings = saved
                    self.refreshAuxiliaryControlMonitor()
                }
            } catch {
                if revision == self.macroSettingsSaveRevision {
                    await self.loadMacroSettingsFromCore()
                }
                self.addLog(.error, "辅助操控设置保存失败：\(error.localizedDescription)")
            }
        }
    }

    private func refreshAuxiliaryControlMonitor() {
        guard runtimeLifecycle == .running,
              let settings = macroSettings,
              settings.fPressHoldToContinuationEnabled ||
                settings.spacePressHoldToContinuationEnabled,
              isWindowValid,
              !selectedWindow.isSynthetic
        else {
            stopAuxiliaryControlMonitor()
            return
        }
        do {
            try auxiliaryControlMonitor.start(targetProcessID: selectedWindow.ownerPID)
        } catch {
            addLog(.error, "辅助操控键盘监听启动失败：\(error.localizedDescription)")
        }
    }

    private func stopAuxiliaryControlMonitor() {
        auxiliaryControlMonitor.stop()
        fContinuationTask?.cancel()
        fContinuationTask = nil
        spaceContinuationTask?.cancel()
        spaceContinuationTask = nil
    }

    private func handleAuxiliaryControlKey(_ key: KeyCode, isDown: Bool) {
        guard let settings = macroSettings else { return }
        if key == settings.pickUpOrInteractKey &&
            settings.fPressHoldToContinuationEnabled {
            if isDown {
                if fContinuationTask == nil {
                    fContinuationTask = continuationTask(
                        key: settings.pickUpOrInteractKey,
                        thresholdMilliseconds: 200,
                        intervalMilliseconds: settings.fFireInterval,
                        clear: { [weak self] in self?.fContinuationTask = nil })
                }
            } else {
                fContinuationTask?.cancel()
                fContinuationTask = nil
            }
        }
        if key == settings.jumpKey &&
            settings.spacePressHoldToContinuationEnabled {
            if isDown {
                if spaceContinuationTask == nil {
                    spaceContinuationTask = continuationTask(
                        key: settings.jumpKey,
                        thresholdMilliseconds: 300,
                        intervalMilliseconds: settings.spaceFireInterval,
                        clear: { [weak self] in self?.spaceContinuationTask = nil })
                }
            } else {
                spaceContinuationTask?.cancel()
                spaceContinuationTask = nil
            }
        }
    }

    private func continuationTask(
        key: KeyCode,
        thresholdMilliseconds: Int,
        intervalMilliseconds: Int,
        clear: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            defer { clear() }
            do {
                try await Task.sleep(for: .milliseconds(thresholdMilliseconds))
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(intervalMilliseconds))
                    guard let self,
                          self.runtimeLifecycle == .running,
                          self.isTargetWindowFrontmost(self.selectedWindow)
                    else {
                        return
                    }
                    _ = self.dispatchInput(
                        .keyPress(key: key),
                        source: .runtimeTrigger)
                }
            } catch {
                return
            }
        }
    }

    func exportMergedSchedulerPathing() {
        guard let supervisor = betterGICoreSupervisor, let group = selectedSchedulerGroup else { return }
        Task { [weak self] in
            do {
                let result = try await supervisor.exportMergedPathing(groupName: group.name)
                guard result.count > 0 else {
                    self?.addLog(.info, "当前配置组没有可导出的地图追踪任务。")
                    return
                }
                guard NSWorkspace.shared.open(URL(fileURLWithPath: result.path)) else {
                    throw BetterGICoreRPCError.socket("Finder could not open the export directory.")
                }
                self?.addLog(.info, "已导出 \(result.count) 个地图追踪任务。")
            } catch {
                self?.addLog(.error, "Export merged pathing failed: \(error.localizedDescription)")
            }
        }
    }

    func applyCoreOverlayCommand(_ parameters: [String: Any]) throws {
        let previousBigMapState = coreOverlayStore.state.isInBigMapUI
        try coreOverlayStore.apply(parameters: parameters)
        if parameters["operation"] as? String == "setMapPointData" {
            NSLog("BetterGI MapMask received point data: %d", coreOverlayStore.state.mapPoints.count)
        }
        if previousBigMapState != coreOverlayStore.state.isInBigMapUI {
            NSLog("BetterGI MapMask big-map state: %@", coreOverlayStore.state.isInBigMapUI.description)
        }
        if !coreOverlayStore.state.isInBigMapUI {
            isMapMaskPickerOpen = false
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
            await loadPathingEntriesFromCore()
            await loadKeyMouseScriptsFromCore()
            await loadNotificationSettingsFromCore()
            await loadMacroSettingsFromCore()
            await loadHotKeySettingsFromCore()
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
                self.runtimeTargetProcessID = self.selectedWindow.ownerPID
                self.runtimeLifecycle = .running
                self.runtimeLifecycleMessage = "运行时已启动，截图器正在持续捕获。"
                self.appStatus = .running
                self.refreshAuxiliaryControlMonitor()
                self.addLog(.info, "BetterGI runtime started with a verified ScreenCaptureKit frame.")
                self.attemptAutoStartSchedulerGroups()
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
        applyScreenCaptureAuthorizationState(screenCapturePermissionCoordinator.refresh())
        accessibilityPermissionGranted = MacGIPermissionRequester.accessibilityGranted
    }

    func updateGameWindowFocus(frontmostPID: pid_t?) {
        frontmostApplicationPID = frontmostPID
        let gameIsFrontmost = isWindowValid
            && !selectedWindow.isSynthetic
            && frontmostPID == selectedWindow.ownerPID
        if isGameWindowFrontmost != gameIsFrontmost {
            isGameWindowFrontmost = gameIsFrontmost
        }
        recomputeHUDPresentation()
    }

    func refreshGameWindowFocus() {
        updateGameWindowFocus(
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    private func recomputeHUDPresentation() {
        let shouldPresent = HUDPresentationPolicy.shouldPresent(
            hudRequested: isHUDVisible,
            runtimeLifecycle: runtimeLifecycle,
            windowValid: isWindowValid && !selectedWindow.isSynthetic,
            hideWhenUnfocused: hideHUDWhenGameUnfocused,
            gameFrontmost: isGameWindowFrontmost,
            layoutEditing: overlayLayoutEditEnabled,
            macGIFrontmost: frontmostApplicationPID == ProcessInfo.processInfo.processIdentifier)
        guard shouldPresent != isHUDPresented else { return }
        isHUDPresented = shouldPresent
        onHUDPresentationChanged?(shouldPresent)
    }

    private static let hideHUDWhenGameUnfocusedKey = "hud.hideWhenGameUnfocused"

    func requestScreenCapturePermission() {
        let state = screenCapturePermissionCoordinator.requestOnce(
            source: "AppState.requestScreenCapturePermission")
        applyScreenCaptureAuthorizationState(state)
        switch state {
        case .granted:
            addLog(.info, "macOS Screen Recording permission is already granted.")
        case .restartRequired:
            addLog(.info, "macOS Screen Recording permission changed; reopen BetterGI before capture.")
        case .settingsRequired:
            addLog(.info, "Submitted the only Screen Recording permission request for this launch.")
        case .checking, .notRequested, .requesting:
            break
        }
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

    private func applyScreenCaptureAuthorizationState(
        _ state: ScreenCaptureAuthorizationState
    ) {
        screenCaptureAuthorizationState = state
        screenCapturePermissionGranted = state.permitsCapture
        screenCapturePermissionRequestMessage = switch state {
        case .checking:
            "正在检查屏幕录制权限。"
        case .notRequested:
            nil
        case .requesting:
            "正在等待 macOS 屏幕录制授权。"
        case .settingsRequired:
            "本次启动已发出授权请求；完成授权后请退出并重新打开 BetterGI。"
        case .restartRequired:
            "屏幕录制权限已更改；请退出并重新打开 BetterGI 后再启动运行时。"
        case .granted:
            nil
        }
    }

    private func attemptAutoStartRuntime() {
        guard autoStartRuntimePending,
              runtimeLaunchReady,
              screenCapturePermissionGranted,
              accessibilityPermissionGranted,
              isWindowValid,
              !selectedWindow.isSynthetic,
              runtimeLifecycle == .stopped else { return }
        autoStartRuntimePending = false
        let source = autoStartSchedulerGroupNames.isEmpty ? "--start-runtime" : "--startGroups"
        addLog(.info, "\(source) accepted; starting BetterGI runtime when Core is ready.")
        startRuntime()
    }

    private func attemptAutoStartSchedulerGroups() {
        guard !autoStartSchedulerGroupNames.isEmpty,
              coreStatus == .ok,
              runtimeLifecycle == .running,
              !schedulerGroups.isEmpty,
              currentSchedulerProjectID == nil else { return }

        let requested = autoStartSchedulerGroupNames
        autoStartSchedulerGroupNames = []
        let knownNames = Set(schedulerGroups.map(\.name))
        let available = requested.filter(knownNames.contains)
        for name in requested where !knownNames.contains(name) {
            addLog(.warn, "--startGroups ignored unknown script group: \(name)")
        }
        guard !available.isEmpty else {
            addLog(.error, "--startGroups did not contain an available script group.")
            return
        }
        selectedSchedulerGroupName = available[0]
        startSchedulerGroups(names: available, continuous: true)
    }

    func stopRuntime() {
        stopRuntime(
            completionMessage: "运行时已停止。",
            completionLog: "BetterGI runtime stopped.")
    }

    private func stopRuntime(
        completionMessage: String,
        completionLog: String
    ) {
        guard runtimeLifecycle == .running else { return }
        if keyMouseEventRecorder.isRecording {
            _ = try? keyMouseEventRecorder.stop()
            keyMouseRecordingState = "idle"
            addLog(.warn, "运行时停止，当前未保存的键鼠录制已丢弃。")
        }
        keyMouseRecordingStartTask?.cancel()
        keyMouseRecordingStartTask = nil
        stopAuxiliaryControlMonitor()
        releaseAllRuntimeInputs()
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
                self.runtimeTargetProcessID = nil
                self.runtimeLifecycle = .stopped
                self.runtimeLifecycleMessage = completionMessage
                self.appStatus = .idle
                self.addLog(.info, completionLog)
            } catch {
                self.runtimeTargetProcessID = nil
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
            attemptAutoStartSchedulerGroups()
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

    func reloadPathingEntriesFromCore() {
        Task { [weak self] in
            await self?.loadPathingEntriesFromCore()
        }
    }

    private func loadPathingEntriesFromCore() async {
        guard let supervisor = betterGICoreSupervisor else {
            pathingEntries = []
            pathingCatalogStatus = "Core unavailable"
            return
        }
        do {
            pathingEntries = try await supervisor.listPathingEntries()
            pathingCatalogStatus = "已加载 \(pathingEntries.filter { !$0.isDirectory }.count) 条路线"
            addLog(.info, "Pathing catalog loaded \(pathingEntries.count) entries through BetterGI Core")
        } catch {
            pathingEntries = []
            pathingCatalogStatus = "加载失败"
            addLog(.error, "BetterGI Core pathing catalog load failed: \(error.localizedDescription)")
        }
    }

    func loadPathingDetail(id: String) async throws -> BetterGIPathingDetail {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        return try await supervisor.pathingDetail(id: id)
    }

    func loadPathingSettings() async throws -> BetterGIPathingSettings {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        return try await supervisor.pathingSettings()
    }

    func savePathingSettings(
        _ settings: BetterGIPathingSettings
    ) async throws -> BetterGIPathingSettings {
        guard let supervisor = betterGICoreSupervisor else {
            throw BetterGICoreRPCError.socket("BetterGI Core is unavailable.")
        }
        let saved = try await supervisor.savePathingSettings(settings)
        addLog(.info, "Core saved map pathing settings.")
        return saved
    }

    func openPathingRootLocation() {
        guard let supervisor = betterGICoreSupervisor else {
            addLog(.error, "Open pathing directory failed: BetterGI Core is unavailable.")
            return
        }
        Task { [weak self] in
            do {
                let path = try await supervisor.pathingRootLocation()
                guard NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
                    throw BetterGICoreRPCError.socket(
                        "Finder could not open the map pathing directory.")
                }
            } catch {
                self?.addLog(.error, "Open pathing directory failed: \(error.localizedDescription)")
            }
        }
    }

    func deletePathingEntry(id: String) {
        guard currentSchedulerProjectID == nil else {
            addLog(.error, "Cannot delete a pathing entry while a task is running.")
            return
        }
        guard let supervisor = betterGICoreSupervisor else {
            addLog(.error, "Delete pathing entry failed: BetterGI Core is unavailable.")
            return
        }
        Task { [weak self] in
            do {
                try await supervisor.deletePathingEntry(id: id)
                await self?.loadPathingEntriesFromCore()
                self?.addLog(.info, "Core deleted pathing entry \(id).")
            } catch {
                self?.addLog(.error, "Delete pathing entry failed: \(error.localizedDescription)")
            }
        }
    }

    func runPathingEntry(id: String) {
        guard currentSchedulerProjectID == nil else {
            addLog(.error, "Cannot run pathing: another task is already active.")
            return
        }
        guard let supervisor = betterGICoreSupervisor, coreStatus == .ok else {
            addLog(.error, "Cannot run pathing: BetterGI Core is not ready.")
            return
        }
        guard runtimeLifecycle == .running else {
            addLog(.error, "Cannot run pathing: start the BetterGI runtime first.")
            return
        }
        guard isWindowValid, !selectedWindow.isSynthetic else {
            addLog(.error, "Cannot run pathing: no real on-screen game window is selected.")
            return
        }
        schedulerExecutionTask?.cancel()
        schedulerExecutionStatus = "Starting"
        schedulerExecutionError = nil
        schedulerExecutionTask = Task { [weak self] in
            do {
                let taskID = try await supervisor.runPathingEntry(id: id)
                guard !Task.isCancelled, let self else { return }
                self.handleCoreSchedulerRunAccepted(
                    taskID: taskID,
                    groupName: "地图追踪:\(id)")
            } catch {
                self?.schedulerExecutionStatus = "Failed"
                self?.schedulerExecutionError = error.localizedDescription
                self?.currentSchedulerProjectID = nil
                self?.appStatus = .error
                self?.addLog(.error, "Core pathing start failed: \(error.localizedDescription)")
            }
        }
    }

    private func setCoreCatalogUnavailable(_ error: Error) {
        schedulerGroups = []
        scriptProjects = []
        pathingEntries = []
        pathingCatalogStatus = "Core unavailable"
        selectedSchedulerGroupName = ""
        schedulerCatalogStatus = "Core unavailable"
        schedulerCatalogIssues = [
            CoreCatalogIssue(path: "Core/catalog", message: error.localizedDescription)
        ]
        hotKeyBindings = []
        hotKeyMonitor.stop()
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
            RuntimeMetric(title: "HUD", value: isHUDPresented ? "Visible" : "Hidden", status: isHUDPresented ? .ok : .missing)
        ]
    }

    var overlayStatusItems: [OverlayStatusItem] {
        let definitions = [
            ("AutoPick", "拾取", "\u{f256}"),
            ("AutoSkip", "剧情", "\u{f075}"),
            ("AutoHangout", "邀约", "\u{e5c8}"),
            ("AutoFish", "钓鱼", "\u{f578}"),
            ("QuickTeleport", "传送", "\u{f3c5}")
        ]
        return definitions.map { id, name, glyph in
            let enabled = id == "AutoHangout"
                ? (features.first(where: { $0.id == "AutoSkip" })?.autoHangoutEventEnabled ?? false)
                : (features.first(where: { $0.id == id })?.isEnabled ?? false)
            return OverlayStatusItem(id: id, glyph: glyph, name: name, isEnabled: enabled)
        }
    }

    var overlayMetricDisplayItems: [OverlayDisplayMetric] {
        [
            OverlayDisplayMetric(id: "game-fps", name: "游戏帧率", value: "\(captureFPS)"),
            OverlayDisplayMetric(id: "core-status", name: "Core", value: coreStatus.label),
            OverlayDisplayMetric(id: "scheduler-status", name: "调度器", value: schedulerExecutionStatus)
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
          "hudRequested": \(isHUDVisible),
          "hudPresented": \(isHUDPresented),
          "gameWindowFrontmost": \(isGameWindowFrontmost),
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
        addLog(.info, "HUD display \(isHUDVisible ? "enabled" : "disabled")")
    }

    func addTestLog() {
        addLog(.info, "Core=\(coreStatus.label), scheduler=\(schedulerExecutionStatus), group=\(selectedSchedulerGroupName)")
    }

    func addLog(_ level: LogLevel, _ message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        recentLogs.insert(entry, at: 0)
        if recentLogs.count > 160 {
            recentLogs.removeLast(recentLogs.count - 160)
        }
        runtimeLogWriter.append(entry)
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
        guard betterGICoreSupervisor != nil, coreStatus == .ok else {
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
        startSchedulerGroups(names: [selectedSchedulerGroupName], continuous: false)
    }

    private func startSchedulerGroups(names: [String], continuous: Bool) {
        guard let supervisor = betterGICoreSupervisor, !names.isEmpty else { return }
        schedulerExecutionTask?.cancel()
        let displayName = names.joined(separator: ",")
        schedulerExecutionStatus = "Starting"
        schedulerExecutionError = nil
        schedulerExecutionTask = Task { [weak self] in
            do {
                let taskID = continuous
                    ? try await supervisor.runSchedulerGroups(names: names)
                    : try await supervisor.runSchedulerGroup(name: names[0])
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.handleCoreSchedulerRunAccepted(taskID: taskID, groupName: displayName)
            } catch {
                self?.schedulerExecutionStatus = "Failed"
                self?.schedulerExecutionError = error.localizedDescription
                self?.currentSchedulerProjectID = nil
                self?.appStatus = .error
                self?.addLog(.error, "Core scheduler start failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated static func startGroupNames(from arguments: [String]) -> [String] {
        guard arguments.count > 1,
              arguments[1].trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("--startGroups") == .orderedSame
        else { return [] }
        return arguments.dropFirst(2)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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
        if dryRunLaunchEnabled { return "Dry-Run：不会发送真实输入" }
        return "已就绪"
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
        betterGICoreSupervisor != nil
            && features.contains(where: { $0.id == id && $0.canSetEnabled })
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
                    canSetEnabled: state.canSetEnabled,
                    settingsAvailable: state.settingsAvailable,
                    autoHangoutEventEnabled: state.autoHangoutEventEnabled
                )
            }
            let autoPickSettings = try await supervisor.autoPickTriggerSettings()
            autoPickTriggerSettings = autoPickSettings
            autoPickExactBlackListDraft = autoPickSettings.exactBlackList
            autoPickFuzzyBlackListDraft = autoPickSettings.fuzzyBlackList
            autoPickWhiteListDraft = autoPickSettings.whiteList
            let autoSkipSettings = try await supervisor.autoSkipTriggerSettings()
            autoSkipTriggerSettings = autoSkipSettings
            autoSkipCustomPriorityOptionsDraft = autoSkipSettings.customPriorityOptions
            autoEatTriggerSettings = try await supervisor.autoEatTriggerSettings()
            quickTeleportTriggerSettings = try await supervisor.quickTeleportTriggerSettings()
            mapMaskTriggerSettings = try await supervisor.mapMaskTriggerSettings()
            let skillCdSettings = try await supervisor.skillCdTriggerSettings()
            skillCdTriggerSettings = skillCdSettings
            applySkillCdDrafts(skillCdSettings)
        } catch {
            features = []
            autoPickTriggerSettings = nil
            autoSkipTriggerSettings = nil
            autoEatTriggerSettings = nil
            quickTeleportTriggerSettings = nil
            mapMaskTriggerSettings = nil
            skillCdTriggerSettings = nil
            mapMaskPickerSettings = nil
            mapMaskLabelCategories = []
            mapMaskSelectedLabelIDs = []
            mapMaskCatalogLoaded = false
            addLog(.error, "BetterGI Core trigger catalog failed: \(error.localizedDescription)")
        }
    }

    func saveAutoPickTriggerConfiguration(
        ocrEngine: String? = nil,
        fastModeEnabled: Bool? = nil,
        blackListEnabled: Bool? = nil,
        whiteListEnabled: Bool? = nil,
        pickKey: String? = nil
    ) {
        guard let current = autoPickTriggerSettings else { return }
        saveAutoPickTriggerSettings(.init(
            ocrEngine: ocrEngine ?? current.ocrEngine,
            ocrEngineOptions: current.ocrEngineOptions,
            fastModeEnabled: fastModeEnabled ?? current.fastModeEnabled,
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
            fastModeEnabled: current.fastModeEnabled,
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
            fastModeEnabled: current.fastModeEnabled,
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

    func saveAutoSkipTriggerSettings(
        quicklySkipConversationsEnabled: Bool? = nil,
        afterChooseOptionSleepDelay: Int? = nil,
        autoWaitDialogueOptionVoiceEnabled: Bool? = nil,
        dialogueOptionVoiceMaxWaitSeconds: Int? = nil,
        beforeClickConfirmDelay: Int? = nil,
        autoGetDailyRewardsEnabled: Bool? = nil,
        autoReExploreEnabled: Bool? = nil,
        clickChatOption: String? = nil,
        customPriorityOptionsEnabled: Bool? = nil,
        customPriorityOptions: String? = nil,
        autoHangoutEventEnabled: Bool? = nil,
        autoHangoutEndChoose: String? = nil,
        autoHangoutChooseOptionSleepDelay: Int? = nil,
        autoHangoutPressSkipEnabled: Bool? = nil,
        submitGoodsEnabled: Bool? = nil,
        closePopupPagedEnabled: Bool? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor, let current = autoSkipTriggerSettings else { return }
        let next = BetterGICoreAutoSkipTriggerSettings(
            quicklySkipConversationsEnabled:
                quicklySkipConversationsEnabled ?? current.quicklySkipConversationsEnabled,
            afterChooseOptionSleepDelay:
                afterChooseOptionSleepDelay ?? current.afterChooseOptionSleepDelay,
            autoWaitDialogueOptionVoiceEnabled:
                autoWaitDialogueOptionVoiceEnabled ?? current.autoWaitDialogueOptionVoiceEnabled,
            dialogueOptionVoiceMaxWaitSeconds:
                dialogueOptionVoiceMaxWaitSeconds ?? current.dialogueOptionVoiceMaxWaitSeconds,
            beforeClickConfirmDelay: beforeClickConfirmDelay ?? current.beforeClickConfirmDelay,
            autoGetDailyRewardsEnabled:
                autoGetDailyRewardsEnabled ?? current.autoGetDailyRewardsEnabled,
            autoReExploreEnabled: autoReExploreEnabled ?? current.autoReExploreEnabled,
            clickChatOption: clickChatOption ?? current.clickChatOption,
            clickChatOptionOptions: current.clickChatOptionOptions,
            customPriorityOptionsEnabled:
                customPriorityOptionsEnabled ?? current.customPriorityOptionsEnabled,
            customPriorityOptions: customPriorityOptions ?? current.customPriorityOptions,
            autoHangoutEventEnabled: autoHangoutEventEnabled ?? current.autoHangoutEventEnabled,
            autoHangoutEndChoose: autoHangoutEndChoose ?? current.autoHangoutEndChoose,
            autoHangoutEndChooseOptions: current.autoHangoutEndChooseOptions,
            autoHangoutChooseOptionSleepDelay:
                autoHangoutChooseOptionSleepDelay ?? current.autoHangoutChooseOptionSleepDelay,
            autoHangoutPressSkipEnabled:
                autoHangoutPressSkipEnabled ?? current.autoHangoutPressSkipEnabled,
            submitGoodsEnabled: submitGoodsEnabled ?? current.submitGoodsEnabled,
            closePopupPagedEnabled: closePopupPagedEnabled ?? current.closePopupPagedEnabled)
        Task { [weak self] in
            do {
                self?.autoSkipTriggerSettings = try await supervisor.saveAutoSkipTriggerSettings(next)
            } catch {
                self?.addLog(.error, "Core failed to save AutoSkip settings: \(error.localizedDescription)")
            }
        }
    }

    func saveAutoSkipCustomPriorityOptions() {
        let draft = autoSkipCustomPriorityOptionsDraft
        saveAutoSkipTriggerSettings(customPriorityOptions: draft)
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

    func saveMapMaskTriggerSettings(
        miniMapMaskEnabled: Bool
    ) {
        guard let supervisor = betterGICoreSupervisor, mapMaskTriggerSettings != nil else { return }
        let next = BetterGICoreMapMaskTriggerSettings(
            miniMapMaskEnabled: miniMapMaskEnabled)
        Task { [weak self] in
            do {
                self?.mapMaskTriggerSettings = try await supervisor.saveMapMaskTriggerSettings(next)
            } catch {
                self?.addLog(.error, "Core failed to save MapMask settings: \(error.localizedDescription)")
            }
        }
    }

    func saveSkillCdTriggerSettings(
        customCdList: [BetterGICoreSkillCdRule]? = nil,
        triggerOnSkillUse: Bool? = nil,
        hideWhenZero: Bool? = nil,
        pX: Double? = nil,
        pY: Double? = nil,
        gap: Double? = nil,
        scale: Double? = nil,
        textNormalColor: String? = nil,
        backgroundNormalColor: String? = nil,
        textReadyColor: String? = nil,
        backgroundReadyColor: String? = nil,
        refreshDrafts: Bool = false
    ) {
        guard let supervisor = betterGICoreSupervisor, let current = skillCdTriggerSettings else { return }
        let next = BetterGICoreSkillCdTriggerSettings(
            customCdList: customCdList ?? current.customCdList,
            triggerOnSkillUse: triggerOnSkillUse ?? current.triggerOnSkillUse,
            hideWhenZero: hideWhenZero ?? current.hideWhenZero,
            pX: pX ?? current.pX,
            pY: pY ?? current.pY,
            gap: gap ?? current.gap,
            scale: scale ?? current.scale,
            textNormalColor: textNormalColor ?? current.textNormalColor,
            backgroundNormalColor: backgroundNormalColor ?? current.backgroundNormalColor,
            textReadyColor: textReadyColor ?? current.textReadyColor,
            backgroundReadyColor: backgroundReadyColor ?? current.backgroundReadyColor)
        Task { [weak self] in
            do {
                let saved = try await supervisor.saveSkillCdTriggerSettings(next)
                self?.skillCdTriggerSettings = saved
                if refreshDrafts { self?.applySkillCdDrafts(saved) }
            } catch {
                self?.addLog(.error, "Core failed to save SkillCd settings: \(error.localizedDescription)")
            }
        }
    }

    func addSkillCdRule() {
        skillCdRulesDraft.append(.init(roleName: "", cdValueText: ""))
    }

    func removeSkillCdRule(at index: Int) {
        guard skillCdRulesDraft.indices.contains(index) else { return }
        skillCdRulesDraft.remove(at: index)
    }

    func saveSkillCdRules() {
        saveSkillCdTriggerSettings(customCdList: skillCdRulesDraft, refreshDrafts: true)
    }

    func saveSkillCdColors() {
        saveSkillCdTriggerSettings(
            textNormalColor: skillCdTextNormalColorDraft,
            backgroundNormalColor: skillCdBackgroundNormalColorDraft,
            textReadyColor: skillCdTextReadyColorDraft,
            backgroundReadyColor: skillCdBackgroundReadyColorDraft,
            refreshDrafts: true)
    }

    private func applySkillCdDrafts(_ settings: BetterGICoreSkillCdTriggerSettings) {
        skillCdRulesDraft = settings.customCdList.isEmpty
            ? [.init(roleName: "", cdValueText: "")]
            : settings.customCdList
        skillCdTextNormalColorDraft = settings.textNormalColor
        skillCdBackgroundNormalColorDraft = settings.backgroundNormalColor
        skillCdTextReadyColorDraft = settings.textReadyColor
        skillCdBackgroundReadyColorDraft = settings.backgroundReadyColor
    }

    func toggleMapMaskPicker() {
        guard coreOverlayStore.state.isInBigMapUI else {
            isMapMaskPickerOpen = false
            return
        }
        isMapMaskPickerOpen.toggle()
        if isMapMaskPickerOpen {
            Task { [weak self] in await self?.ensureMapMaskCatalogLoaded() }
        }
    }

    func closeMapMaskPicker() {
        isMapMaskPickerOpen = false
    }

    func saveMapMaskPickerSettings(
        mapPointApiProvider: String? = nil,
        hoYoLabLanguage: String? = nil
    ) {
        guard let supervisor = betterGICoreSupervisor, let current = mapMaskPickerSettings else { return }
        let next = BetterGICoreMapMaskPickerSettings(
            mapPointApiProvider: mapPointApiProvider ?? current.mapPointApiProvider,
            mapPointApiProviderOptions: current.mapPointApiProviderOptions,
            hoYoLabLanguage: hoYoLabLanguage ?? current.hoYoLabLanguage,
            hoYoLabLanguageOptions: current.hoYoLabLanguageOptions)
        Task { [weak self] in
            do {
                self?.mapMaskPickerSettings = try await supervisor.saveMapMaskPickerSettings(next)
                self?.mapMaskCatalogLoaded = false
                await self?.loadMapMaskCatalogFromCore()
            } catch {
                self?.addLog(.error, "Core failed to save MapMask picker settings: \(error.localizedDescription)")
            }
        }
    }

    func setMapMaskLabel(_ id: String, selected: Bool) {
        guard let supervisor = betterGICoreSupervisor else { return }
        if selected {
            mapMaskSelectedLabelIDs.insert(id)
        } else {
            mapMaskSelectedLabelIDs.remove(id)
        }
        guard mapMaskSelectionSaveTask == nil else { return }
        mapMaskSelectionSaveTask = Task { [weak self] in
            await self?.flushMapMaskSelection(to: supervisor)
        }
    }

    private func flushMapMaskSelection(to supervisor: BetterGICoreProcessSupervisor) async {
        while !Task.isCancelled {
            let requested = mapMaskSelectedLabelIDs
            do {
                let saved = try await supervisor.saveMapMaskPointSelection(requested)
                confirmedMapMaskSelectedLabelIDs = saved
                if mapMaskSelectedLabelIDs == requested {
                    mapMaskSelectedLabelIDs = saved
                    mapMaskSelectionSaveTask = nil
                    return
                }
            } catch {
                addLog(.error, "Core failed to save MapMask selection: \(error.localizedDescription)")
                if mapMaskSelectedLabelIDs == requested {
                    mapMaskSelectedLabelIDs = confirmedMapMaskSelectedLabelIDs
                    mapMaskSelectionSaveTask = nil
                    return
                }
            }
        }
        mapMaskSelectionSaveTask = nil
    }

    func ensureMapMaskCatalogLoaded() async {
        guard !mapMaskCatalogLoaded, !mapMaskCatalogLoading else { return }
        await loadMapMaskCatalogFromCore()
    }

    private func loadMapMaskCatalogFromCore() async {
        guard let supervisor = betterGICoreSupervisor else { return }
        mapMaskCatalogLoading = true
        defer { mapMaskCatalogLoading = false }
        do {
            if mapMaskPickerSettings == nil {
                mapMaskPickerSettings = try await supervisor.mapMaskPickerSettings()
            }
            mapMaskLabelCategories = try await supervisor.mapMaskPointCatalog()
            mapMaskSelectedLabelIDs = try await supervisor.mapMaskPointSelection()
            confirmedMapMaskSelectedLabelIDs = mapMaskSelectedLabelIDs
            mapMaskCatalogLoaded = true
        } catch {
            mapMaskLabelCategories = []
            mapMaskSelectedLabelIDs = []
            confirmedMapMaskSelectedLabelIDs = []
            mapMaskCatalogLoaded = false
            addLog(.error, "Core failed to load MapMask catalog: \(error.localizedDescription)")
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
                saveScreenshotOnKeyTick ?? current.saveScreenshotOnKeyTick)
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
            if stopRuntimeIfGameProcessExited() {
                availableWindows = []
                selectedWindow = .unavailable(title: "Game process exited")
                gameWindowStatus = .missing
                return
            }
            availableWindows = []
            selectedWindow = .unavailable(title: "No game window selected")
            gameWindowStatus = .missing
            addLog(.warn, "Quartz window list contains no selectable game window")
            return
        }

        availableWindows = windows
        if runtimeLifecycle == .running, let targetPID = runtimeTargetProcessID {
            if let preserved = windows.first(where: {
                $0.id == selectedWindow.id && $0.ownerPID == targetPID
            }) {
                selectedWindow = preserved
            } else if !Self.isProcessAlive(targetPID) {
                gameWindowStatus = .missing
                stopRuntimeAfterGameExit()
                selectedWindow = .unavailable(title: "Game process exited")
                return
            } else if let replacement = QuartzWindowEnumerator.bestGameWindow(
                from: windows.filter { $0.ownerPID == targetPID })
            {
                selectedWindow = replacement
            } else {
                gameWindowStatus = .missing
                return
            }
        } else if let preserved = windows.first(where: { $0.id == selectedWindow.id }) {
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

        if runtimeLifecycle == .running, let targetPID = runtimeTargetProcessID {
            if !Self.isProcessAlive(targetPID) {
                availableWindows = windows
                gameWindowStatus = .missing
                stopRuntimeAfterGameExit()
                selectedWindow = .unavailable(title: "Game process exited")
                return nil
            }
            if let replacement = QuartzWindowEnumerator.bestGameWindow(
                from: windows.filter { $0.ownerPID == targetPID })
            {
                let previousWindowID = selectedWindow.isSynthetic ? nil : selectedWindow.id
                selectedWindow = replacement
                availableWindows = windows
                gameWindowStatus = .detected
                if runtimeGeometryPixelSize != replacement.capturePixelSize {
                    scheduleRuntimeGeometryRefresh(for: replacement.capturePixelSize)
                }
                if let previousWindowID {
                    addLog(.info,
                        "Game window recreated in the active process; rebound WindowID \(previousWindowID) to \(replacement.id).")
                }
                return replacement
            }
            availableWindows = windows
            gameWindowStatus = .missing
            return nil
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

    func gameApplicationDidTerminate(processID: pid_t) {
        guard GameRuntimeLifecyclePolicy.shouldStopAfterTermination(
            runtimeLifecycle: runtimeLifecycle,
            targetProcessID: runtimeTargetProcessID,
            terminatedProcessID: processID
        ) else { return }
        gameWindowStatus = .missing
        stopRuntimeAfterGameExit()
        selectedWindow = .unavailable(title: "Game process exited")
    }

    private func stopRuntimeIfGameProcessExited() -> Bool {
        let targetProcessAlive = runtimeTargetProcessID.map(Self.isProcessAlive) ?? false
        guard GameRuntimeLifecyclePolicy.shouldStopWhenWindowUnavailable(
            runtimeLifecycle: runtimeLifecycle,
            targetProcessID: runtimeTargetProcessID,
            targetProcessAlive: targetProcessAlive
        ) else { return false }
        stopRuntimeAfterGameExit()
        return true
    }

    private func stopRuntimeAfterGameExit() {
        guard runtimeLifecycle == .running else { return }
        addLog(.info, "游戏已退出，BetterGI 自动停止截图器。")
        stopRuntime(
            completionMessage: "游戏已退出，运行时已自动停止。",
            completionLog: "Game process exited; BetterGI runtime stopped automatically.")
    }

    private static func isProcessAlive(_ processID: pid_t) -> Bool {
        guard processID > 0 else { return false }
        if Darwin.kill(processID, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private func releaseAllRuntimeInputs() {
        guard !safetyGate.dryRun, safetyGate.realInputEnabled else { return }
        do {
            let report = try inputDispatcher.perform(
                .releaseAll,
                targetWindow: selectedWindow)
            addLog(
                .debug,
                "Released runtime inputs during shutdown: \(report.eventCount) events.")
        } catch {
            addLog(
                .error,
                "Failed to release runtime inputs during shutdown: \(error.localizedDescription)")
        }
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
        let isReleaseAll = action == .releaseAll
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
                ? runtimeLifecycle == .running || (isReleaseAll && runtimeLifecycle == .stopping)
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
        runtimeTargetProcessID = nil
        schedulerExecutionStatus = "Idle"
        currentSchedulerProjectID = nil
        safetyGate.resetCounters()
        addLog(.info, "UI state reset")
    }
}
