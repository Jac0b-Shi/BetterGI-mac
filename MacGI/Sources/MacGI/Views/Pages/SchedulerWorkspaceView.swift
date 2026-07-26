import SwiftUI

private enum SchedulerSheet: Identifiable {
    case common(Int)
    case custom(Int)
    case add(String)
    case createGroup
    case renameGroup(String)
    case copyGroup(String)
    case continuousRun
    case continueRun
    case groupSettings
    case repository
    case logParse

    var id: String {
        switch self {
        case .common(let index): "common-\(index)"
        case .custom(let index): "custom-\(index)"
        case .add(let type): "add-\(type)"
        case .createGroup: "create-group"
        case .renameGroup(let name): "rename-group-\(name)"
        case .copyGroup(let name): "copy-group-\(name)"
        case .continuousRun: "continuous-run"
        case .continueRun: "continue-run"
        case .groupSettings: "group-settings"
        case .repository: "repository"
        case .logParse: "log-parse"
        }
    }
}

private struct SchedulerGroupDeletion: Identifiable {
    let name: String
    var id: String { name }
}

struct SchedulerWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var sheet: SchedulerSheet?
    @State private var confirmingClear = false
    @State private var groupDeletion: SchedulerGroupDeletion?

    var body: some View {
        let selectedGroup = appState.selectedSchedulerGroup
        BGIWorkflowShell(
            title: "调度器",
            subtitle: "BetterGI 配置组、脚本项目和连续执行。\(appState.schedulerExecutionStatus) · \(appState.schedulerCatalogStatus)",
            commands: [
                BGICommand(title: "运行", symbol: "play.fill", isEnabled: appState.canRunScheduler,
                           action: { appState.runSchedulerGroups() }),
                BGICommand(title: "刷新", symbol: "arrow.clockwise",
                           action: { appState.reloadSchedulerGroupsFromCore() }),
                BGICommand(title: "停止", symbol: "stop.fill",
                           action: { appState.cancelSchedulerGroups() })
            ]
        ) {
            BGIGroupSidebar(title: "配置组", groups: appState.schedulerGroups.map(\.name),
                            selected: selectedGroup?.name ?? "",
                            onSelect: { appState.selectedSchedulerGroupName = $0 },
                            onAdd: { sheet = .createGroup },
                            onRename: { sheet = .renameGroup($0) },
                            onCopy: { sheet = .copyGroup($0) },
                            onDelete: { groupDeletion = SchedulerGroupDeletion(name: $0) })
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                operationPanel
                projectList(selectedGroup)
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .common(let index): SchedulerProjectCommonSettingsSheet(projectIndex: index)
            case .custom(let index): SchedulerProjectCustomSettingsSheet(projectIndex: index)
            case .add(let type): SchedulerAddProjectsSheet(type: type)
            case .createGroup: SchedulerGroupNameSheet(mode: .create)
            case .renameGroup(let name): SchedulerGroupNameSheet(mode: .rename(name))
            case .copyGroup(let name): SchedulerGroupNameSheet(mode: .copy(name))
            case .continuousRun: SchedulerContinuousRunSheet()
            case .continueRun: SchedulerContinueRunSheet()
            case .groupSettings: SchedulerGroupSettingsSheet()
            case .repository: ScriptRepositorySheet()
            case .logParse: SchedulerLogParseSheet()
            }
        }
        .confirmationDialog("是否清空当前配置组的所有任务？", isPresented: $confirmingClear) {
            Button("清空", role: .destructive) {
                appState.performSchedulerCatalogMutation(.clear)
            }
        }
        .confirmationDialog(
            "是否删除配置组“\(groupDeletion?.name ?? "")”？",
            isPresented: Binding(
                get: { groupDeletion != nil },
                set: { if !$0 { groupDeletion = nil } }
            )
        ) {
            if let groupDeletion {
                Button("删除组", role: .destructive) {
                    let name = groupDeletion.name
                    self.groupDeletion = nil
                    Task {
                        do {
                            try await appState.deleteSchedulerGroup(name: name)
                        } catch {
                            appState.addLog(
                                .error,
                                "Delete scheduler group failed: \(error.localizedDescription)"
                            )
                        }
                    }
                }
            }
        }
    }

    private func projectList(_ group: BetterGIScriptGroupSummary?) -> some View {
        BGISectionCard("配置组 - \(group?.name ?? "未选择")", subtitle: "右键项目可修改配置、设置下次起点、打开目录或移除。", symbolName: "cpu") {
            VStack(spacing: 0) {
                ForEach(group?.projects ?? []) { project in
                    HStack(spacing: 10) {
                        Image(systemName: project.nextFlag ? "flag.fill" : "line.3.horizontal")
                            .foregroundStyle(project.nextFlag ? BGIColors.warning : BGIColors.mutedText)
                            .frame(width: 20)
                        Text("\(project.index)").frame(width: 30, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name).lineLimit(1)
                            if !project.folderName.isEmpty {
                                Text(project.folderName).font(BGIFonts.caption).foregroundStyle(BGIColors.mutedText).lineLimit(1)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(typeDescription(project.type)).frame(width: 80)
                        Toggle("", isOn: Binding(
                            get: { project.status == "Enabled" },
                            set: { appState.setSchedulerProjectEnabled(projectIndex: project.index, enabled: $0) }))
                            .labelsHidden().disabled(appState.currentSchedulerProjectID != nil)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .contextMenu { projectMenu(project) }
                    Divider()
                }
                if group?.projects.isEmpty != false {
                    Text("当前配置组没有任务，请从“添加”菜单加入项目。")
                        .foregroundStyle(BGIColors.mutedText).padding(.vertical, 18)
                }
            }
            .contextMenu { addMenuItems() }
        }
    }

    @ViewBuilder private func projectMenu(_ project: BetterGIScriptGroupProjectSummary) -> some View {
        addMenuItems()
        Divider()
        Button("下一次任务从此处执行") {
            appState.performSchedulerCatalogMutation(.setNext(projectIndex: project.index))
        }
        Button("修改通用配置") { sheet = .common(project.index) }
        if project.type == "Javascript" {
            Button("修改 JS 脚本自定义配置") { sheet = .custom(project.index) }
                .disabled(!project.hasCustomSettings)
        }
        Button("打开所在目录") { appState.openSchedulerProjectLocation(projectIndex: project.index) }
            .disabled(project.type == "Shell")
        Divider()
        Button("移除", role: .destructive) {
            appState.performSchedulerCatalogMutation(.remove(projectIndex: project.index, sameFolder: false))
        }
        if project.type == "Pathing" {
            Button("根据文件夹移除", role: .destructive) {
                appState.performSchedulerCatalogMutation(.remove(projectIndex: project.index, sameFolder: true))
            }
        }
    }

    @ViewBuilder private func addMenuItems() -> some View {
        Button("添加 JS 脚本") { sheet = .add("Javascript") }
        Button("添加地图追踪任务") { sheet = .add("Pathing") }
        Button("添加键鼠脚本") { sheet = .add("KeyMouse") }
        Button("添加 Shell") { sheet = .add("Shell") }
    }

    private var operationPanel: some View {
        BGISectionCard("任务操作", subtitle: appState.schedulerRunReadiness, symbolName: "square.grid.3x3") {
            HStack(spacing: 10) {
                Menu("添加", systemImage: "plus") { addMenuItems() }
                Button("连续执行", systemImage: "forward.end.fill") {
                    sheet = .continuousRun
                }
                .disabled(appState.currentSchedulerProjectID != nil)
                Button("继续执行", systemImage: "clock.arrow.circlepath") {
                    sheet = .continueRun
                }
                .disabled(appState.currentSchedulerProjectID != nil)
                Menu("更多功能") {
                    Button("清空", role: .destructive) { confirmingClear = true }
                    Button("日志分析") {
                        sheet = .logParse
                    }
                    .disabled(appState.selectedSchedulerGroup == nil)
                    Button("打开脚本仓库") {
                        sheet = .repository
                    }
                    Button("根据文件夹更新") {
                        appState.performSchedulerCatalogMutation(.updatePathingFolders)
                    }
                    Button("任务倒序排列") {
                        appState.performSchedulerCatalogMutation(.reverse)
                    }
                    Button("导出根据控制文件修改任务") {
                        appState.exportMergedSchedulerPathing()
                    }
                }
                Button("设置", systemImage: "gearshape") { sheet = .groupSettings }
                Spacer()
            }
        }
    }

    private func typeDescription(_ type: String) -> String {
        ["Javascript": "JS脚本", "Pathing": "地图追踪", "KeyMouse": "键鼠脚本", "Shell": "Shell"][type] ?? type
    }
}

private struct SchedulerLogParseSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var settings: BetterGILogParseSettings?
    @State private var error: String?
    @State private var status: String?
    @State private var generating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("日志分析").font(.title2).bold()
            if let settings {
                Form {
                    LabeledContent("配置组") {
                        Text(settings.groupName)
                    }
                    Picker(
                        "分析范围",
                        selection: valueBinding(\.rangeValue)
                    ) {
                        ForEach(settings.rangeOptions) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    Picker(
                        "日志天数",
                        selection: valueBinding(\.dayRangeValue)
                    ) {
                        ForEach(settings.dayRangeOptions) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    Toggle(
                        "合并相邻同名配置组",
                        isOn: valueBinding(\.mergerStatsSwitch))
                    Toggle(
                        "异常情况统计",
                        isOn: valueBinding(\.faultStatsSwitch))
                    Toggle(
                        "统计锄地摩拉怪物数",
                        isOn: valueBinding(\.hoeingStatsSwitch))
                    Toggle(
                        "生成锄地规划数据",
                        isOn: valueBinding(\.generateFarmingPlanData))
                    HStack {
                        SecureField(
                            "米游社 Cookie",
                            text: valueBinding(\.cookie))
                        Button {
                            openCookieHelp()
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("锄地统计说明")
                    }
                    LabeledContent("锄地延时（秒）") {
                        TextField(
                            "0",
                            text: valueBinding(\.hoeingDelay))
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .formStyle(.grouped)
            } else if error == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if generating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在准备数据并生成日志分析...")
                }
                .foregroundStyle(BGIColors.mutedText)
            } else if let status {
                Text(status)
                    .foregroundStyle(BGIColors.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error)
                    .foregroundStyle(BGIColors.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .disabled(generating)
                Button("生成") { generate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(settings == nil || generating)
            }
        }
        .padding(22)
        .frame(width: 620, height: 650)
        .task { await load() }
    }

    private func valueBinding<Value>(
        _ keyPath: WritableKeyPath<BetterGILogParseSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                guard let settings else {
                    preconditionFailure("Log-parse settings are unavailable.")
                }
                return settings[keyPath: keyPath]
            },
            set: { settings?[keyPath: keyPath] = $0 })
    }

    private func load() async {
        error = nil
        do {
            settings = try await appState.loadLogParseSettings()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openCookieHelp() {
        Task {
            do {
                try await appState.openLogParseCookieHelp()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func generate() {
        guard let settings else { return }
        generating = true
        error = nil
        status = nil
        Task {
            do {
                let result = try await appState.generateLogParse(settings)
                status = "已生成 \(result.configGroupCount) 个配置组的日志分析。"
            } catch {
                self.error = error.localizedDescription
            }
            generating = false
        }
    }
}

private struct SchedulerContinueRunSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var progressItems: [BetterGISchedulerProgressSummary] = []
    @State private var selectedName: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("继续执行").font(.title2).bold()
            if progressItems.isEmpty, error == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(progressItems) { progress in
                    Button {
                        selectedName = progress.name
                    } label: {
                        HStack {
                            Image(systemName:
                                selectedName == progress.name
                                    ? "checkmark.circle.fill"
                                    : "circle")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(progress.displayName)
                                    .lineLimit(2)
                                Text(progress.scriptGroupNames.joined(separator: "、"))
                                    .font(BGIFonts.caption)
                                    .foregroundStyle(BGIColors.mutedText)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let error {
                Text(error)
                    .foregroundStyle(BGIColors.danger)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("确认执行") {
                    guard let selectedName,
                          let progress = progressItems.first(where: {
                              $0.name == selectedName
                          })
                    else { return }
                    appState.continueSchedulerProgress(
                        name: selectedName,
                        displayName: progress.displayName
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedName == nil)
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
        .task {
            do {
                progressItems = try await appState.loadSchedulerProgress()
                selectedName = progressItems.first?.name
                if progressItems.isEmpty {
                    error = "没有可继续执行的进度记录。"
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct SchedulerContinuousRunSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedNames: Set<String> = []
    @State private var loop = false

    private var groups: [BetterGIScriptGroupSummary] {
        appState.schedulerGroups.filter { !$0.hideOnRepeat }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("连续执行").font(.title2).bold()
            Toggle("循环", isOn: $loop)
            HStack {
                Button("全选") {
                    selectedNames = Set(groups.map(\.name))
                }
                Button("清除") {
                    selectedNames.removeAll()
                }
                Spacer()
            }
            List(groups) { group in
                Toggle(
                    group.name,
                    isOn: Binding(
                        get: { selectedNames.contains(group.name) },
                        set: { selected in
                            if selected {
                                selectedNames.insert(group.name)
                            } else {
                                selectedNames.remove(group.name)
                            }
                        }
                    )
                )
                .toggleStyle(.checkbox)
            }
            if groups.isEmpty {
                Text("没有可用于连续执行的配置组。")
                    .foregroundStyle(BGIColors.mutedText)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("确认执行") {
                    let orderedNames = groups
                        .map(\.name)
                        .filter(selectedNames.contains)
                    appState.runContinuousSchedulerGroups(
                        names: orderedNames,
                        loop: loop
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedNames.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
    }
}

private enum SchedulerGroupNameMode {
    case create
    case rename(String)
    case copy(String)

    var title: String {
        switch self {
        case .create: "新增配置组"
        case .rename: "重命名配置组"
        case .copy: "复制配置组"
        }
    }

    var initialName: String {
        switch self {
        case .create: ""
        case .rename(let name), .copy(let name): name
        }
    }
}

private struct SchedulerGroupNameSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let mode: SchedulerGroupNameMode
    @State private var name: String
    @State private var error: String?
    @State private var saving = false

    init(mode: SchedulerGroupNameMode) {
        self.mode = mode
        _name = State(initialValue: mode.initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title).font(.title2).bold()
            TextField("配置组名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            if let error {
                Text(error)
                    .foregroundStyle(BGIColors.danger)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("确定", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        error = nil
        Task {
            do {
                switch mode {
                case .create:
                    try await appState.createSchedulerGroup(name: name)
                case .rename(let sourceName):
                    try await appState.renameSchedulerGroup(
                        sourceName: sourceName,
                        targetName: name
                    )
                case .copy(let sourceName):
                    try await appState.copySchedulerGroup(
                        sourceName: sourceName,
                        targetName: name
                    )
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

private struct SchedulerProjectCommonSettingsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let projectIndex: Int
    @State private var settings: BetterGIProjectCommonSettings?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("修改通用设置").font(.title2).bold()
            if let value = settings {
                Picker("状态", selection: Binding(get: { value.status }, set: { settings?.status = $0 })) {
                    Text("启用").tag("Enabled"); Text("禁用").tag("Disabled")
                }
                if value.isJavascript {
                    Toggle("允许 JS 发送通知", isOn: Binding(get: { value.allowJsNotification }, set: { settings?.allowJsNotification = $0 }))
                    Toggle("允许 JS HTTP 请求", isOn: Binding(get: { value.allowJsHTTP }, set: { settings?.allowJsHTTP = $0 }))
                    if value.httpAllowedURLs.isEmpty {
                        Text("当前脚本无需使用 HTTP 资源。")
                    } else {
                        Text("脚本声明的 HTTP 地址").font(.headline)
                        ForEach(value.httpAllowedURLs, id: \.self) { Text($0).font(BGIFonts.console).textSelection(.enabled) }
                        Text("脚本更新 http_allowed_urls 后权限会自动失效。")
                            .font(BGIFonts.caption).foregroundStyle(BGIColors.warning)
                    }
                }
                Spacer()
            } else if let error {
                Text(error).foregroundStyle(BGIColors.danger).textSelection(.enabled)
                Button("重试") { Task { await load() } }
                Spacer()
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    if let settings { save(settings) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(settings == nil)
            }
        }
        .padding(24).frame(width: 520, height: 420)
        .task { await load() }
    }

    private func load() async {
        error = nil
        do { settings = try await appState.loadProjectCommonSettings(projectIndex) }
        catch { self.error = error.localizedDescription }
    }
    private func save(_ value: BetterGIProjectCommonSettings) {
        Task { do { try await appState.saveProjectCommonSettings(value); dismiss() }
            catch { self.error = error.localizedDescription } }
    }
}

private struct SchedulerProjectCustomSettingsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let projectIndex: Int
    @State private var settings: BetterGIProjectCustomSettings?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("修改 JS 脚本自定义设置").font(.title2).bold(); Spacer() }.padding()
            Divider()
            if let settings {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(settings.schema) { settingControl($0) }
                    }.padding()
                }
            } else if let error {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).foregroundStyle(BGIColors.danger).textSelection(.enabled)
                    Button("重试") { Task { await load() } }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(settings == nil)
            }
            .padding()
        }
        .frame(width: 620, height: 600).task { await load() }
    }

    @ViewBuilder private func settingControl(_ item: BetterGISettingItem) -> some View {
        if item.type == "separator" { Divider() }
        else {
            VStack(alignment: .leading, spacing: 6) {
                if !item.label.isEmpty { Text(item.label) }
                switch item.type {
                case "input-text": TextField("", text: stringBinding(item.name))
                case "select": Picker("", selection: stringBinding(item.name)) {
                    ForEach(item.options, id: \.self) { Text($0).tag($0) }
                }.labelsHidden()
                case "checkbox": Toggle("", isOn: boolBinding(item.name)).labelsHidden()
                case "multi-checkbox":
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(item.options, id: \.self) { option in
                            Toggle(option, isOn: multiBinding(item.name, option)).toggleStyle(.checkbox)
                        }
                    }
                case "cascade-select": Picker("", selection: stringBinding(item.name)) {
                    ForEach(item.cascadeOptions.keys.sorted(), id: \.self) { group in
                        Section(group) { ForEach(item.cascadeOptions[group] ?? [], id: \.self) { Text($0).tag($0) } }
                    }
                }.labelsHidden()
                default: Text("不支持的设置类型：\(item.type)").foregroundStyle(BGIColors.danger)
                }
            }
        }
    }

    private func stringBinding(_ name: String) -> Binding<String> { Binding(
        get: { if case .string(let value) = settings?.values[name] { value } else { "" } },
        set: { settings?.values[name] = .string($0) }) }
    private func boolBinding(_ name: String) -> Binding<Bool> { Binding(
        get: { if case .bool(let value) = settings?.values[name] { value } else { false } },
        set: { settings?.values[name] = .bool($0) }) }
    private func multiBinding(_ name: String, _ option: String) -> Binding<Bool> { Binding(
        get: { if case .strings(let values) = settings?.values[name] { values.contains(option) } else { false } },
        set: { enabled in
            var values: [String] = []
            if case .strings(let current) = settings?.values[name] { values = current }
            if enabled && !values.contains(option) { values.append(option) }
            if !enabled { values.removeAll { $0 == option } }
            settings?.values[name] = .strings(values)
        }) }
    private func load() async {
        error = nil
        do { settings = try await appState.loadProjectCustomSettings(projectIndex) }
        catch { self.error = error.localizedDescription }
    }
    private func save() { guard let settings else { return }; Task { do { try await appState.saveProjectCustomSettings(settings); dismiss() } catch { self.error = error.localizedDescription } } }
}

private struct SchedulerAddProjectsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let type: String
    @State private var candidates: [BetterGIAddCandidate] = []
    @State private var selected: Set<String> = []
    @State private var search = ""
    @State private var shellCommand = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2).bold()
            if type == "Shell" {
                Text("执行 Shell 存在极大风险，请勿输入不理解的命令。游戏执行期间可能失去焦点。")
                    .foregroundStyle(BGIColors.warning)
                TextEditor(text: $shellCommand).font(BGIFonts.console).frame(minHeight: 180)
            } else {
                TextField("搜索", text: $search)
                List(filtered) { candidate in
                    Toggle(isOn: Binding(get: { selected.contains(candidate.id) }, set: { value in
                        if value { selected.insert(candidate.id) } else { selected.remove(candidate.id) }
                    })) {
                        VStack(alignment: .leading) { Text(candidate.name); Text(candidate.id).font(BGIFonts.caption).foregroundStyle(BGIColors.mutedText) }
                    }.toggleStyle(.checkbox)
                }
            }
            if let error { Text(error).foregroundStyle(BGIColors.danger) }
            HStack { Spacer(); Button("取消") { dismiss() }; Button("添加") { add() }
                    .disabled(type == "Shell" ? shellCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : selected.isEmpty) }
        }
        .padding(20).frame(width: 620, height: 560).task { await load() }
    }

    private var title: String { ["Javascript": "添加 JS 脚本", "Pathing": "添加地图追踪任务", "KeyMouse": "添加键鼠脚本", "Shell": "添加 Shell"][type] ?? "添加" }
    private var filtered: [BetterGIAddCandidate] { search.isEmpty ? candidates : candidates.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) } }
    private func load() async { guard type != "Shell" else { return }; do { candidates = try await appState.loadSchedulerAddCandidates(type: type) } catch { self.error = error.localizedDescription } }
    private func add() { appState.addSchedulerProjects(type: type, candidateIDs: Array(selected), shellCommand: shellCommand); dismiss() }
}

private struct SchedulerGroupSettingsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var values = BetterGIGroupConfigSettings(
        enabled: true,
        autoPick: true,
        autoEat: false,
        autoSkip: true,
        autoFight: true,
        autoRun: true,
        defaultAtkBoostingDishName: "",
        defaultAdventurersDishName: "",
        defaultDefBoostingDishName: "",
        fightStrategyName: "根据队伍自动选择",
        fightActionSchedulerByCd: "",
        fightFinishDetectEnabled: true,
        fightFastCheckEnabled: false,
        fightFastCheckParams: "",
        fightRotateFindEnemyEnabled: false,
        fightRotaryFactor: 12,
        fightCheckBeforeBurst: false,
        fightIsFirstCheck: false,
        fightCheckEndDelay: "0.4;钟离,1.4;",
        fightBeforeDetectDelay: "0.4",
        fightGuardianAvatar: "",
        fightGuardianCombatSkip: false,
        fightBurstEnabled: false,
        fightGuardianAvatarHold: false,
        fightPickDropsAfterFightEnabled: false,
        fightPickDropsAfterFightSeconds: 15,
        fightKazuhaPickupEnabled: true,
        fightQinDoublePickUp: false,
        fightExpBasedPickupEnabled: false,
        fightBattleThresholdForLoot: nil,
        fightOnlyPickEliteDropsMode: "Closed",
        fightKazuhaPartyName: "",
        fightTimeout: 120,
        fightSwimmingEnabled: true,
        partyName: "",
        visitStatue: false,
        mainAvatar: "",
        guardianAvatar: "",
        guardianInterval: "",
        guardianLongPress: false,
        gadgetInterval: 0,
        recoverTiming: "AnyWaypoint",
        skipDuring: "",
        hideOnRepeat: false,
        hurryOnAvatar: "",
        travelMode: "精准靠近",
        distance: 45,
        approachStopDistance: 25,
        switchToWalkEnabled: false,
        mwkJumpFlyEnabled: true,
        mwkJumpFlyIntervalSeconds: 1,
        taskCycleEnabled: false,
        taskCycleBoundaryTime: 0,
        taskCycleUsesServerTime: false,
        taskCycle: 1,
        taskCycleIndex: 1,
        completionSkipEnabled: false,
        completionSkipPolicy: "GroupPhysicalPathSkipPolicy",
        completionBoundaryTime: 4,
        completionUsesServerTime: false,
        completionLastRunGapSeconds: -1,
        completionReferencePoint: "EndTime",
        priorityEnabled: false,
        priorityGroupNames: "",
        priorityMaxRetryCount: 1,
        avatarIndexOptions: ["", "1", "2", "3", "4"],
        hurryOnAvatarOptions: ["", "自动"],
        travelModeOptions: ["精准靠近", "连续赶路"],
        fightStrategyOptions: ["根据队伍自动选择"],
        onlyPickEliteDropsModeOptions: [],
        recoverTimingOptions: [],
        completionSkipPolicyOptions: [],
        completionReferencePointOptions: [],
        enableShellConfig: false,
        shellDisable: false,
        shellTimeout: 60,
        shellNoWindow: true,
        shellOutput: true)
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("配置组设置").font(.title2).bold(); Spacer() }.padding(); Divider()
            ScrollView { VStack(alignment: .leading, spacing: 12) {
                pathingSettings
                fightSettings
                foodSettings
                travelSettings
                cycleSettings
                completionSettings
                prioritySettings
                shellSettings
                if let error { Text(error).foregroundStyle(BGIColors.danger) }
            }.padding() }
            Divider(); HStack { Spacer(); Button("取消") { dismiss() }; Button("保存") { save() }.keyboardShortcut(.defaultAction) }.padding()
        }.frame(width: 700, height: 680).task { await load() }
    }

    private func load() async {
        do {
            values = try await appState.loadSelectedGroupConfig()
        } catch { self.error = error.localizedDescription }
    }
    private func save() { Task { do {
        try await appState.saveSelectedGroupConfig(values); dismiss()
    } catch { self.error = error.localizedDescription } } }

    private var pathingSettings: some View {
        GroupBox("地图追踪行走配置") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("启用地图追踪行走配置", isOn: $values.enabled)
                Toggle("自动拾取", isOn: $values.autoPick)
                Toggle("自动吃药", isOn: $values.autoEat)
                Toggle("自动进入剧情", isOn: $values.autoSkip)
                Toggle("自动战斗", isOn: $values.autoFight)
                Toggle("自动冲刺", isOn: $values.autoRun)
                TextField("切换到队伍的名称", text: $values.partyName)
                Toggle("切换队伍前前往七天神像", isOn: $values.visitStatue)
                optionPicker(
                    "行走位编号",
                    selection: $values.mainAvatar,
                    options: values.avatarIndexOptions)
                optionPicker(
                    "生存位编号",
                    selection: $values.guardianAvatar,
                    options: values.avatarIndexOptions)
                TextField("生存位元素战技间隔（秒）", text: $values.guardianInterval)
                Toggle("生存位元素战技长按", isOn: $values.guardianLongPress)
                Stepper(
                    "使用小道具间隔：\(values.gadgetInterval) 毫秒",
                    value: $values.gadgetInterval,
                    in: 0...3_600_000,
                    step: 100)
                namedOptionPicker(
                    "低血量回复时机",
                    selection: $values.recoverTiming,
                    options: values.recoverTimingOptions)
                TextField("不在某时执行", text: $values.skipDuring)
                Toggle("不在连续任务中显示", isOn: $values.hideOnRepeat)
            }
            .padding(8)
        }
    }

    private var fightSettings: some View {
        GroupBox("自动战斗配置") {
            VStack(alignment: .leading, spacing: 10) {
                optionPicker(
                    "战斗策略",
                    selection: $values.fightStrategyName,
                    options: values.fightStrategyOptions)
                TextField(
                    "根据技能 CD 优化出招人员",
                    text: $values.fightActionSchedulerByCd)

                DisclosureGroup("自动检测战斗结束") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            "启用战斗结束检测",
                            isOn: $values.fightFinishDetectEnabled)
                        Toggle(
                            "更快检查结束战斗",
                            isOn: $values.fightFastCheckEnabled)
                        if values.fightFastCheckEnabled {
                            TextField(
                                "检查参数，例如 5;白术;钟离;",
                                text: $values.fightFastCheckParams)
                        }
                        Toggle(
                            "旋转寻找敌人位置",
                            isOn: $values.fightRotateFindEnemyEnabled)
                        if values.fightRotateFindEnemyEnabled {
                            Stepper(
                                "旋转速度：\(values.fightRotaryFactor)",
                                value: $values.fightRotaryFactor,
                                in: 1...13)
                            Toggle(
                                "释放元素爆发前检查",
                                isOn: $values.fightCheckBeforeBurst)
                            Toggle(
                                "开战时尝试面向敌人",
                                isOn: $values.fightIsFirstCheck)
                        }
                        TextField(
                            "检查战斗结束延时",
                            text: $values.fightCheckEndDelay)
                        TextField(
                            "按键触发后检查延时",
                            text: $values.fightBeforeDetectDelay)
                    }
                    .padding(.top, 8)
                }

                DisclosureGroup("盾奶位角色优先释放技能") {
                    VStack(alignment: .leading, spacing: 10) {
                        optionPicker(
                            "盾奶位角色位置",
                            selection: $values.fightGuardianAvatar,
                            options: values.avatarIndexOptions)
                        if !values.fightGuardianAvatar.isEmpty {
                            Toggle(
                                "禁用该角色的 E 战斗策略",
                                isOn: $values.fightGuardianCombatSkip)
                            Toggle(
                                "自动释放 Q 爆发",
                                isOn: $values.fightBurstEnabled)
                            Toggle(
                                "盾奶位 E 长按",
                                isOn: $values.fightGuardianAvatarHold)
                        }
                    }
                    .padding(.top, 8)
                }

                DisclosureGroup("战后拾取") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            "扫描掉落物光柱",
                            isOn: $values.fightPickDropsAfterFightEnabled)
                        if values.fightPickDropsAfterFightEnabled {
                            Stepper(
                                "扫描时长：\(values.fightPickDropsAfterFightSeconds) 秒",
                                value: $values.fightPickDropsAfterFightSeconds,
                                in: 0...300)
                        }
                        Toggle(
                            "聚集材料动作",
                            isOn: $values.fightKazuhaPickupEnabled)
                        if values.fightKazuhaPickupEnabled {
                            Toggle(
                                "琴二次拾取",
                                isOn: $values.fightQinDoublePickUp)
                            Toggle(
                                "基于经验值判断拾取",
                                isOn: $values.fightExpBasedPickupEnabled)
                            TextField(
                                "万叶拾取队伍名",
                                text: $values.fightKazuhaPartyName)
                        }
                        TextField(
                            "拾取战斗人次阈值（留空禁用）",
                            text: Binding(
                                get: {
                                    values.fightBattleThresholdForLoot.map(String.init)
                                        ?? ""
                                },
                                set: {
                                    values.fightBattleThresholdForLoot = Int($0)
                                }))
                        namedOptionPicker(
                            "只拾取精英掉落模式",
                            selection: $values.fightOnlyPickEliteDropsMode,
                            options: values.onlyPickEliteDropsModeOptions)
                    }
                    .padding(.top, 8)
                }

                Stepper(
                    "自动战斗超时：\(values.fightTimeout) 秒",
                    value: $values.fightTimeout,
                    in: 1...3600)
                Toggle(
                    "游泳检测",
                    isOn: $values.fightSwimmingEnabled)
            }
            .padding(8)
            .disabled(!values.autoFight)
        }
    }

    private var foodSettings: some View {
        GroupBox("自动吃食物配置") {
            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    "默认攻击类料理名称",
                    text: $values.defaultAtkBoostingDishName)
                TextField(
                    "默认冒险类料理名称",
                    text: $values.defaultAdventurersDishName)
                TextField(
                    "默认防御类料理名称",
                    text: $values.defaultDefBoostingDishName)
            }
            .padding(8)
        }
    }

    private var travelSettings: some View {
        GroupBox("自动赶路设置") {
            VStack(alignment: .leading, spacing: 10) {
                optionPicker(
                    "赶路角色",
                    selection: $values.hurryOnAvatar,
                    options: values.hurryOnAvatarOptions)
                optionPicker(
                    "赶路模式",
                    selection: $values.travelMode,
                    options: values.travelModeOptions)
                Stepper(
                    "赶路启用距离：\(values.distance)",
                    value: $values.distance,
                    in: 0...500)
                Stepper(
                    "接近停车距离：\(values.approachStopDistance)",
                    value: $values.approachStopDistance,
                    in: 0...max(values.distance, 0))
                Toggle("接近时切人步行", isOn: $values.switchToWalkEnabled)
                Toggle("启用跳飞赶路", isOn: $values.mwkJumpFlyEnabled)
                HStack {
                    Text("跳飞/跳跃间隔（秒）")
                    Spacer()
                    TextField(
                        "",
                        value: $values.mwkJumpFlyIntervalSeconds,
                        format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }
            .padding(8)
        }
    }

    private var cycleSettings: some View {
        GroupBox("执行周期配置") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("启用执行周期配置", isOn: $values.taskCycleEnabled)
                Stepper(
                    "分界时间：\(values.taskCycleBoundaryTime)",
                    value: $values.taskCycleBoundaryTime,
                    in: 0...23)
                Toggle(
                    "分界时间参考服务器时区",
                    isOn: $values.taskCycleUsesServerTime)
                Stepper(
                    "周期：\(values.taskCycle)",
                    value: $values.taskCycle,
                    in: 1...365)
                Stepper(
                    "执行序号：\(values.taskCycleIndex)",
                    value: $values.taskCycleIndex,
                    in: 1...max(values.taskCycle, 1))
            }
            .padding(8)
        }
    }

    private var completionSettings: some View {
        GroupBox("跳过执行配置") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("启用跳过执行", isOn: $values.completionSkipEnabled)
                namedOptionPicker(
                    "跳过执行策略",
                    selection: $values.completionSkipPolicy,
                    options: values.completionSkipPolicyOptions)
                Stepper(
                    "分界时间：\(values.completionBoundaryTime)",
                    value: $values.completionBoundaryTime,
                    in: -1...24)
                Toggle(
                    "分界时间参考服务器时区",
                    isOn: $values.completionUsesServerTime)
                Stepper(
                    "和上次运行的间隔秒数：\(values.completionLastRunGapSeconds)",
                    value: $values.completionLastRunGapSeconds,
                    in: -1...31_536_000)
                namedOptionPicker(
                    "间隔时间计算参照",
                    selection: $values.completionReferencePoint,
                    options: values.completionReferencePointOptions)
            }
            .padding(8)
        }
    }

    private var prioritySettings: some View {
        GroupBox("优先执行其他配置组") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("启用优先执行", isOn: $values.priorityEnabled)
                TextField("配置组名称，多个用逗号分隔", text: $values.priorityGroupNames)
                Stepper(
                    "额外执行次数：\(values.priorityMaxRetryCount)",
                    value: $values.priorityMaxRetryCount,
                    in: 0...100)
            }
            .padding(8)
        }
    }

    private var shellSettings: some View {
        GroupBox("Shell 执行配置") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("启用配置组 Shell 配置", isOn: $values.enableShellConfig)
                Toggle("禁用 Shell 任务", isOn: $values.shellDisable)
                Stepper(
                    "最长等待：\(values.shellTimeout) 秒",
                    value: $values.shellTimeout,
                    in: 0...86_400)
                Toggle("隐藏命令执行窗口", isOn: $values.shellNoWindow)
                Toggle("输出写入日志", isOn: $values.shellOutput)
            }
            .padding(8)
        }
    }

    private func optionPicker(
        _ title: String,
        selection: Binding<String>,
        options: [String]
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.isEmpty ? "未指定" : option).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }
    }

    private func namedOptionPicker(
        _ title: String,
        selection: Binding<String>,
        options: [BetterGICoreNamedOption]
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.displayName).tag(option.value)
                }
            }
            .labelsHidden()
            .frame(width: 240)
        }
    }
}
