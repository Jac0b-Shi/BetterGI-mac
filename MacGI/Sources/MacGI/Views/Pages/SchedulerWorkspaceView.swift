import SwiftUI

private enum SchedulerSheet: Identifiable {
    case common(Int)
    case custom(Int)
    case add(String)
    case groupSettings

    var id: String {
        switch self {
        case .common(let index): "common-\(index)"
        case .custom(let index): "custom-\(index)"
        case .add(let type): "add-\(type)"
        case .groupSettings: "group-settings"
        }
    }
}

struct SchedulerWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var sheet: SchedulerSheet?
    @State private var confirmingClear = false

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
                            onSelect: { appState.selectedSchedulerGroupName = $0 })
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
            case .groupSettings: SchedulerGroupSettingsSheet()
            }
        }
        .confirmationDialog("是否清空当前配置组的所有任务？", isPresented: $confirmingClear) {
            Button("清空", role: .destructive) {
                appState.performSchedulerCatalogMutation(.clear)
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
                Menu("更多功能") {
                    Button("清空", role: .destructive) { confirmingClear = true }
                    Button("日志分析") {
                        appState.addLog(.info, "日志分析尚未接入。")
                    }.disabled(true)
                    Button("打开脚本仓库") {
                        appState.addLog(.info, "脚本仓库尚未接入。")
                    }.disabled(true)
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
        enabled: true, autoPick: true, autoEat: false, autoSkip: true, autoFight: true, autoRun: true,
        partyName: "", visitStatue: false, mainAvatar: "", guardianAvatar: "", guardianInterval: "",
        guardianLongPress: false, gadgetInterval: 0, skipDuring: "", hideOnRepeat: false,
        enableShellConfig: false, shellDisable: false, shellTimeout: 60, shellNoWindow: true, shellOutput: true)
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("配置组设置").font(.title2).bold(); Spacer() }.padding(); Divider()
            ScrollView { VStack(alignment: .leading, spacing: 12) {
                GroupBox("地图追踪配置") { VStack(alignment: .leading) {
                    Toggle("启用地图追踪行走配置", isOn: $values.enabled)
                    Toggle("自动拾取", isOn: $values.autoPick); Toggle("自动吃药", isOn: $values.autoEat)
                    Toggle("自动剧情跳过", isOn: $values.autoSkip); Toggle("自动战斗", isOn: $values.autoFight); Toggle("自动奔跑", isOn: $values.autoRun)
                    TextField("切换到队伍的名称", text: $values.partyName); Toggle("切换队伍前前往七天神像", isOn: $values.visitStatue)
                    TextField("行走位编号", text: $values.mainAvatar); TextField("生存位编号", text: $values.guardianAvatar)
                    TextField("生存位元素战技间隔", text: $values.guardianInterval); Toggle("生存位元素战技长按", isOn: $values.guardianLongPress)
                    Stepper("使用小道具间隔：\(values.gadgetInterval) ms", value: $values.gadgetInterval, in: 0...600000, step: 100)
                    TextField("不在某时执行", text: $values.skipDuring); Toggle("连续执行时隐藏", isOn: $values.hideOnRepeat)
                }.padding(8) }
                GroupBox("Shell 执行配置") { VStack(alignment: .leading) {
                    Toggle("启用配置组 Shell 配置", isOn: $values.enableShellConfig); Toggle("禁用 Shell 任务", isOn: $values.shellDisable)
                    Stepper("最长等待：\(values.shellTimeout) 秒", value: $values.shellTimeout, in: 0...86400)
                    Toggle("隐藏命令执行窗口", isOn: $values.shellNoWindow); Toggle("输出写入日志", isOn: $values.shellOutput)
                }.padding(8) }
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
}
