import SwiftUI

struct BGICommand: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    var isEnabled = true
    var action: () -> Void = {}
}

struct BGIWorkflowShell<Sidebar: View, Content: View>: View {
    let title: String
    let subtitle: String
    let commands: [BGICommand]
    @ViewBuilder var sidebar: Sidebar
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                BGIPageTitle(title: title)
                Text(subtitle)
                    .font(BGIFonts.body)
                    .foregroundStyle(BGIColors.secondaryText)
            }

            commandBar

            HStack(alignment: .top, spacing: 14) {
                sidebar
                    .frame(width: 250)
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            ForEach(commands) { command in
                Button(action: command.action) {
                    Label(command.title, systemImage: command.symbol)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .disabled(!command.isEnabled)
            }
            Spacer(minLength: 0)
        }
    }
}

struct BGIGroupSidebar: View {
    let title: String
    let groups: [String]
    var selected: String
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(BGIFonts.bodyStrong)
                .foregroundStyle(BGIColors.primaryText)
                .padding(.horizontal, 12)
            VStack(spacing: 4) {
                ForEach(groups, id: \.self) { group in
                    Button {
                        onSelect(group)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: group == selected ? "folder.fill" : "folder")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 18)
                            Text(group)
                                .font(BGIFonts.bodyStrong)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(group == selected ? BGIColors.primaryText : BGIColors.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(group == selected ? BGIColors.cardElevated : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous))
                }
            }
        }
        .padding(10)
        .background(BGIColors.sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: BGIRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BGIRadius.medium, style: .continuous)
                .stroke(BGIColors.border, lineWidth: 1)
        )
    }
}

struct BGIOriginalCard<HeaderAction: View, Content: View>: View {
    let icon: BGIIcon
    let title: String
    let subtitle: String
    let expanded: Bool
    @ViewBuilder var headerAction: HeaderAction
    @ViewBuilder var content: Content

    init(
        icon: BGIIcon,
        title: String,
        subtitle: String,
        expanded: Bool = true,
        @ViewBuilder headerAction: () -> HeaderAction,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.expanded = expanded
        self.headerAction = headerAction()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: BGISpacing.large) {
                BGIIconView(icon: icon, size: 20)
                    .foregroundStyle(BGIColors.primaryText.opacity(0.86))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BGIColors.primaryText)
                    Text(subtitle)
                        .font(BGIFonts.body)
                        .foregroundStyle(BGIColors.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 20)
                headerAction
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BGIColors.secondaryText)
                    .frame(width: 18)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            if expanded {
                Divider().overlay(BGIColors.border)
                content
            }
        }
        .background(BGIColors.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous)
                .stroke(BGIColors.border, lineWidth: 1)
        )
    }
}

private struct BGIDataTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(headers, id: \.self) { header in
                    Text(header)
                        .font(BGIFonts.caption)
                        .foregroundStyle(BGIColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(BGIColors.consoleBackground.opacity(0.75))

            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 10) {
                    ForEach(rows[rowIndex].indices, id: \.self) { columnIndex in
                        Text(rows[rowIndex][columnIndex])
                            .font(BGIFonts.body)
                            .foregroundStyle(columnIndex == 0 ? BGIColors.primaryText : BGIColors.secondaryText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .overlay(Rectangle().fill(BGIColors.border).frame(height: 1), alignment: .top)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous)
                .stroke(BGIColors.border, lineWidth: 1)
        )
    }
}

struct BGIInlinePicker: View {
    let value: String
    let width: CGFloat

    var body: some View {
        Picker("", selection: .constant(value)) {
            Text(value).tag(value)
        }
        .labelsHidden()
        .frame(width: width)
    }
}

struct BGINumberField: View {
    let value: String
    let width: CGFloat

    var body: some View {
        TextField("", text: .constant(value))
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
    }
}

struct BGIUnavailableToggle: View {
    let isOn: Bool

    var body: some View {
        Toggle("", isOn: .constant(isOn))
            .labelsHidden()
            .disabled(true)
    }
}

struct BGIUnavailableAction: View {
    let title: String
    let systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        if let systemImage {
            Label("\(title)（不可用）", systemImage: systemImage)
                .foregroundStyle(.secondary)
        } else {
            Text("\(title)（不可用）")
                .foregroundStyle(.secondary)
        }
    }
}

struct OneDragonPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        BGIWorkflowShell(
            title: "一条龙",
            subtitle: "该页面仅保留 SwiftUI 布局；未接入 C# Core DTO 的配置项不可编辑或执行。",
            commands: [
                BGICommand(title: "启动", symbol: "play.fill"),
                BGICommand(title: "新增配置", symbol: "plus"),
                BGICommand(title: "编辑", symbol: "pencil"),
                BGICommand(title: "删除", symbol: "trash")
            ]
        ) {
            VStack(spacing: 10) {
                BGIGroupSidebar(title: "任务列表", groups: ["每日委托", "自动秘境", "自动首领讨伐", "自动地脉花", "领取奖励", "尘歌壶", "完成后操作"], selected: "自动秘境")
                BGIOriginalCard(icon: .fgi("\u{e411}"), title: "每日流程", subtitle: "右键添加或删除任务", expanded: false) {
                    BGIUnavailableToggle(isOn: true)
                } content: {
                    EmptyView()
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("配置")
                        .font(BGIFonts.bodyStrong)
                        .foregroundStyle(BGIColors.primaryText)
                    BGIInlinePicker(value: "默认", width: 140)
                    Spacer()
                }

                BGIOriginalCard(icon: .symbol("moon.stars"), title: "合成树脂", subtitle: "指定地区合成树脂，控制合成后保留的原粹树脂数量。") {
                    BGIUnavailableToggle(isOn: true)
                } content: {
                    BGISettingLine(title: "合成树脂合成台", subtitle: "指定地区合成树脂。") {
                        BGIInlinePicker(value: "枫丹", width: 120)
                    }
                    BGISettingLine(title: "合成后保留", subtitle: "原粹树脂数量。") {
                        BGINumberField(value: "40", width: 90)
                    }
                }

                BGIOriginalCard(icon: .fgi("\u{f073}"), title: "每日秘境刷取配置", subtitle: "前往指定秘境消耗树脂，并自动领取奖励。") {
                    BGIUnavailableToggle(isOn: true)
                } content: {
                    BGISettingLine(title: "进入秘境切换的队伍名称", subtitle: "注意是游戏内你设置的名称。") {
                        BGINumberField(value: "秘境队", width: 150)
                    }
                    BGISettingLine(title: "选择秘境", subtitle: "秘境名称、周日或限时、奖励序号。") {
                        BGIInlinePicker(value: "圣遗物", width: 130)
                    }
                }

                BGIOriginalCard(icon: .fgi("\u{f784}"), title: "每周秘境刷取配置", subtitle: "启用后，每日刷取配置将会失效。") {
                    BGIUnavailableToggle(isOn: false)
                } content: {
                    BGIDataTable(
                        headers: ["日期", "队伍", "秘境", "奖励"],
                        rows: [
                            ["默认", "秘境队", "深潮的余响", "圣遗物"],
                            ["周一", "留空使用默认队伍", "塞西莉亚苗圃", "武器材料"],
                            ["周日", "好感队", "任意秘境", "按需选择"]
                        ]
                    )
                    .padding(16)
                }

                BGIOriginalCard(icon: .fgi("\u{e629}"), title: "自动首领讨伐配置", subtitle: "自动传送、战斗并领取奖励。") {
                    Text("Core 暂未开放")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } content: {
                    BGISettingLine(title: "选择战斗策略", subtitle: "仅用于首领讨伐，不覆盖其他策略设置。") {
                        BGIInlinePicker(value: "默认策略", width: 150)
                    }
                    BGISettingLine(title: "选择首领", subtitle: "部分首领因机制问题未添加。") {
                        BGIInlinePicker(value: "无相系列", width: 150)
                    }
                    BGISettingLine(title: "指定讨伐次数", subtitle: "关闭时刷取至原粹树脂耗尽。") {
                        BGIUnavailableToggle(isOn: true)
                        BGINumberField(value: "4", width: 70)
                    }
                }

                BGIOriginalCard(icon: .fgi("\u{f2f1}"), title: "自动地脉花", subtitle: "跳过准备流程、树脂耗尽模式、运行日期配置。") {
                    BGIUnavailableToggle(isOn: true)
                } content: {
                    BGISettingLine(title: "运行日期配置", subtitle: "按星期设置类型与国家，留空时使用独立任务默认设置。") {
                        BGIInlinePicker(value: "每日", width: 110)
                    }
                    BGISettingLine(title: "刷取次数", subtitle: "填 0 则使用独立任务配置。") {
                        BGINumberField(value: "0", width: 70)
                    }
                }

                BGIOriginalCard(icon: .fgi("\u{f14e}"), title: "领取奖励", subtitle: "前往指定地区冒险者协会领取。", expanded: false) {
                    BGIInlinePicker(value: "枫丹", width: 110)
                } content: {
                    EmptyView()
                }

                BGIOriginalCard(icon: .fgi("\u{f07a}"), title: "尘歌壶配置", subtitle: "进壶方式、购买日期与商品。", expanded: false) {
                    BGIUnavailableToggle(isOn: true)
                } content: {
                    EmptyView()
                }

                BGIOriginalCard(icon: .fgi("\u{f11e}"), title: "任务完成后执行的操作", subtitle: "一条龙结束后操作。", expanded: false) {
                    BGIInlinePicker(value: "无", width: 110)
                } content: {
                    EmptyView()
                }
            }
        }
    }
}

struct SchedulerPage: View {
    var body: some View {
        SchedulerWorkspaceView()
    }
}

struct JSScriptPage: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingRepository = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "自定义 Javascript 脚本（实验功能）")
            HStack(spacing: 8) {
                Button { appState.openScriptProjectRootLocation() } label: {
                    Label("打开脚本目录", systemImage: "folder")
                }
                Button {
                    showingRepository = true
                } label: {
                    Label("脚本仓库", systemImage: "archivebox")
                }
                Button { appState.runSchedulerGroups() } label: {
                    Label("运行所选配置组", systemImage: "play.fill")
                }
                Button { appState.cancelSchedulerGroups() } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                Spacer()
            }

            BGISectionCard("脚本列表", subtitle: "上游页面按目录、名称、版本展示，并提供执行、打开目录、刷新、删除。", symbolName: "doc.text") {
                BGIDataTable(
                    headers: ["目录", "名称", "版本"],
                    rows: appState.scriptProjects.map { [$0.folderName, $0.name, $0.version] }
                )
            }

            BGIOriginalCard(icon: .symbol("play.rectangle"), title: "脚本执行链路", subtitle: appState.schedulerExecutionStatus) {
                Button("运行所选配置组") { appState.runSchedulerGroups() }
            } content: {
                BGISettingLine(title: "最近结果", subtitle: "通过 BetterGI C# Core 执行已安装脚本。") {
                    Text(appState.currentSchedulerProjectID ?? "无")
                        .foregroundStyle(BGIColors.mutedText)
                }
                if let schedulerError = appState.schedulerExecutionError {
                    Text(schedulerError)
                        .font(BGIFonts.caption)
                        .foregroundStyle(BGIColors.danger)
                        .textSelection(.enabled)
                }
            }
        }
        .sheet(isPresented: $showingRepository) {
            ScriptRepositorySheet()
        }
    }
}

struct RecordReplayPage: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingRepository = false
    @State private var renameCandidate: BetterGIKeyMouseScript?
    @State private var renameDraft = ""
    @State private var deleteCandidate: BetterGIKeyMouseScript?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "键鼠录制回放功能（实验功能）")
            HStack(spacing: 8) {
                Button {
                    appState.openKeyMouseScriptDirectory()
                } label: {
                    Label("打开脚本目录", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    showingRepository = true
                } label: {
                    Label("脚本仓库", systemImage: "archivebox")
                }
                .buttonStyle(.bordered)

                Button {
                    appState.startKeyMouseRecording()
                } label: {
                    Label("开始录制", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    appState.keyMouseRecordingState == "starting" ||
                    appState.keyMouseRecordingState == "recording" ||
                    appState.keyMouseRecordingState == "saving")

                Button {
                    appState.stopKeyMouseRecording()
                } label: {
                    Label("停止录制", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(
                    appState.keyMouseRecordingState != "starting" &&
                    appState.keyMouseRecordingState != "recording")

                Text(recordingStatusText)
                    .font(BGIFonts.caption)
                    .foregroundStyle(recordingStatusColor)
                Spacer()
            }

            BGISectionCard(
                "录制脚本",
                subtitle: "脚本按创建时间排列，可播放、停止、重命名或删除。",
                symbolName: "record.circle"
            ) {
                if appState.keyMouseScripts.isEmpty {
                    Text("键鼠脚本目录为空。")
                        .font(BGIFonts.body)
                        .foregroundStyle(BGIColors.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                } else {
                    VStack(spacing: 0) {
                        ForEach(appState.keyMouseScripts) { script in
                            keyMouseScriptRow(script)
                            if script.id != appState.keyMouseScripts.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .task {
            appState.refreshKeyMouseScripts()
        }
        .sheet(isPresented: $showingRepository) {
            ScriptRepositorySheet()
        }
        .alert("重命名键鼠脚本", isPresented: Binding(
            get: { renameCandidate != nil },
            set: { if !$0 { renameCandidate = nil } }
        )) {
            TextField("脚本名称", text: $renameDraft)
            Button("取消", role: .cancel) {
                renameCandidate = nil
            }
            Button("重命名") {
                if let renameCandidate {
                    appState.renameKeyMouseScript(id: renameCandidate.id, name: renameDraft)
                }
                renameCandidate = nil
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("删除键鼠脚本？", isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )) {
            Button("取消", role: .cancel) {
                deleteCandidate = nil
            }
            Button("删除", role: .destructive) {
                if let deleteCandidate {
                    appState.deleteKeyMouseScript(id: deleteCandidate.id)
                }
                deleteCandidate = nil
            }
        }
    }

    private var recordingStatusText: String {
        switch appState.keyMouseRecordingState {
        case "starting": "等待录制"
        case "recording": "正在录制"
        case "saving": "正在保存"
        case "failed": "录制失败"
        default: ""
        }
    }

    private var recordingStatusColor: Color {
        switch appState.keyMouseRecordingState {
        case "recording": BGIColors.danger
        case "failed": BGIColors.warning
        default: BGIColors.secondaryText
        }
    }

    private func keyMouseScriptRow(_ script: BetterGIKeyMouseScript) -> some View {
        let isPlaying = appState.keyMousePlaybackStatus.scriptID == script.id &&
            (appState.keyMousePlaybackStatus.state == "running" ||
             appState.keyMousePlaybackStatus.state == "stopping")
        return HStack(spacing: 12) {
            Image(systemName: "doc.badge.gearshape")
                .foregroundStyle(BGIColors.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(script.name)
                    .font(BGIFonts.bodyStrong)
                    .lineLimit(1)
                Text(script.createdAt)
                    .font(BGIFonts.caption)
                    .foregroundStyle(BGIColors.mutedText)
            }
            Spacer()
            Button {
                if isPlaying {
                    appState.stopKeyMousePlayback()
                } else {
                    appState.playKeyMouseScript(script.id)
                }
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .help(isPlaying ? "停止脚本" : "播放脚本")
            .disabled(
                appState.runtimeLifecycle != .running ||
                (appState.keyMousePlaybackStatus.state == "running" && !isPlaying))

            Menu {
                Button("重命名") {
                    renameCandidate = script
                    renameDraft = script.name.replacingOccurrences(
                        of: ".json", with: "", options: [.caseInsensitive, .anchored], range: nil)
                }
                Button("删除", role: .destructive) {
                    deleteCandidate = script
                }
                .disabled(isPlaying)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct MacroPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "辅助操控设置")

            BGIOriginalCard(
                icon: .symbol("keyboard"),
                title: "长按 \(appState.macroSettings?.jumpKey.displayName ?? "空格")等于连续按下",
                subtitle: "轻松解除冻结；水下存在需要长按空格的场景，不推荐长期启用。"
            ) {
                Toggle("", isOn: Binding(
                    get: {
                        appState.macroSettings?.spacePressHoldToContinuationEnabled ?? false
                    },
                    set: { appState.saveMacroSettings(spaceEnabled: $0) }
                ))
                .labelsHidden()
                .disabled(appState.macroSettings == nil)
            } content: {
                BGISettingLine(
                    title: "\(appState.macroSettings?.jumpKey.displayName ?? "空格")连发间隔",
                    subtitle: "长按超过 300 毫秒后按该间隔连续触发。"
                ) {
                    Stepper(
                        "\(appState.macroSettings?.spaceFireInterval ?? 100) ms",
                        value: Binding(
                            get: { appState.macroSettings?.spaceFireInterval ?? 100 },
                            set: { appState.saveMacroSettings(spaceInterval: $0) }
                        ),
                        in: 10...1000,
                        step: 10
                    )
                    .frame(width: 170)
                    .disabled(appState.macroSettings == nil)
                }
            }

            BGIOriginalCard(
                icon: .symbol("keyboard"),
                title: "长按 \(appState.macroSettings?.pickUpOrInteractKey.displayName ?? "F")等于连续按下",
                subtitle: "快速拾取大量掉落物。"
            ) {
                Toggle("", isOn: Binding(
                    get: {
                        appState.macroSettings?.fPressHoldToContinuationEnabled ?? false
                    },
                    set: { appState.saveMacroSettings(fEnabled: $0) }
                ))
                .labelsHidden()
                .disabled(appState.macroSettings == nil)
            } content: {
                BGISettingLine(
                    title: "\(appState.macroSettings?.pickUpOrInteractKey.displayName ?? "F")连发间隔",
                    subtitle: "长按超过 200 毫秒后按该间隔连续触发。"
                ) {
                    Stepper(
                        "\(appState.macroSettings?.fFireInterval ?? 100) ms",
                        value: Binding(
                            get: { appState.macroSettings?.fFireInterval ?? 100 },
                            set: { appState.saveMacroSettings(fInterval: $0) }
                        ),
                        in: 10...1000,
                        step: 10
                    )
                    .frame(width: 170)
                    .disabled(appState.macroSettings == nil)
                }
            }
        }
    }
}

struct HotkeyPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "快捷键设置")
            Text("全局热键只支持组合键和功能键；键鼠监听支持任意键盘单键、鼠标侧键，功能启动后才生效。")
                .font(BGIFonts.body)
                .foregroundStyle(BGIColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !appState.hotKeyStatusMessage.isEmpty {
                Text(appState.hotKeyStatusMessage)
                    .font(BGIFonts.caption)
                    .foregroundStyle(BGIColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.hotKeyBindings.isEmpty {
                BGISectionCard(
                    "快捷键尚未就绪",
                    subtitle: "BetterGI Core 启动后会加载可用的快捷键。",
                    symbolName: "keyboard"
                ) {
                    EmptyView()
                }
            } else {
                ForEach(Array(groupedBindings.enumerated()), id: \.offset) {
                    _, group in
                    BGISectionCard(
                        group.category,
                        symbolName: symbolName(for: group.category)
                    ) {
                        VStack(spacing: 0) {
                            ForEach(group.bindings) { binding in
                                hotKeyRow(binding)
                            }
                        }
                    }
                }
            }
        }
    }

    private var groupedBindings:
        [(category: String, bindings: [BetterGIHotKeyBinding])]
    {
        appState.hotKeyBindings.reduce(into: []) { groups, binding in
            if let index = groups.firstIndex(where: {
                $0.category == binding.category
            }) {
                groups[index].bindings.append(binding)
            } else {
                groups.append((
                    category: binding.category,
                    bindings: [binding]))
            }
        }
    }

    @ViewBuilder
    private func hotKeyRow(_ binding: BetterGIHotKeyBinding) -> some View {
        BGISettingLine(
            title: binding.functionName,
            subtitle: binding.isHold
                ? "键鼠监听 · 按住生效"
                : binding.hotKeyTypeName
        ) {
            HStack(spacing: 8) {
                Button {
                    appState.switchHotKeyType(binding)
                } label: {
                    Text(binding.hotKeyTypeName)
                        .frame(width: 74)
                }
                .buttonStyle(.bordered)
                .disabled(binding.isHold)
                .help(binding.isHold ? "按住型快捷键固定使用键鼠监听" : "切换快捷键类型")

                Button {
                    if appState.hotKeyCaptureID == binding.id {
                        appState.cancelHotKeyCapture()
                    } else {
                        appState.beginHotKeyCapture(binding)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName:
                            appState.hotKeyCaptureID == binding.id
                            ? "record.circle.fill"
                            : "keyboard")
                        Text(
                            appState.hotKeyCaptureID == binding.id
                            ? "按键中"
                            : binding.displayHotKey)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 86)
                }
                .buttonStyle(.borderedProminent)
                .tint(
                    appState.hotKeyCaptureID == binding.id
                    ? BGIColors.warning
                    : BGIColors.accent)

                Button {
                    appState.clearHotKey(binding)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .disabled(binding.hotKey.isEmpty)
                .help("清除快捷键")
            }
        }
    }

    private func symbolName(for category: String) -> String {
        switch category {
        case "系统控制": "gearshape"
        case "实时任务": "bolt"
        case "独立任务": "square.stack.3d.up"
        case "操控辅助": "gamecontroller"
        default: "keyboard"
        }
    }
}

struct NotificationPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "通知设置")

            BGIOriginalCard(
                icon: .symbol("bell"),
                title: "全局通知设置",
                subtitle: "影响脚本和通知渠道的全局权限"
            ) {
                EmptyView()
            } content: {
                BGISettingLine(
                    title: "允许 JS 脚本发送通知",
                    subtitle: "启用后，调度器中获准发送通知的脚本可以调用通知接口。"
                ) {
                    Toggle("", isOn: Binding(
                        get: { appState.notificationSettings?.jsNotificationEnabled ?? false },
                        set: { appState.saveNotificationSettings(jsNotificationEnabled: $0) }
                    ))
                    .labelsHidden()
                    .disabled(appState.notificationSettings == nil)
                }
            }

            BGIOriginalCard(
                icon: .symbol("bell.badge"),
                title: "macOS 通知",
                subtitle: "通过系统通知中心显示 BetterGI 消息"
            ) {
                Toggle("", isOn: Binding(
                    get: { appState.notificationSettings?.macOSNotificationEnabled ?? false },
                    set: { appState.saveNotificationSettings(macOSNotificationEnabled: $0) }
                ))
                .labelsHidden()
                .disabled(appState.notificationSettings == nil)
            } content: {
                BGISettingLine(
                    title: "测试通知",
                    subtitle: "通过当前配置发送一条系统通知。"
                ) {
                    HStack(spacing: 8) {
                        if !appState.notificationTestStatus.isEmpty {
                            Text(appState.notificationTestStatus)
                                .font(BGIFonts.caption)
                                .foregroundStyle(BGIColors.secondaryText)
                                .lineLimit(2)
                        }
                        Button {
                            appState.sendTestNotification()
                        } label: {
                            Label("发送", systemImage: "paperplane")
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            appState.notificationSettings?.macOSNotificationEnabled != true)
                    }
                }
            }
        }
    }
}
