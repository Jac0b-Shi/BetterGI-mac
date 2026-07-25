import SwiftUI

struct BGICommand: Identifiable {
    let title: String
    let symbol: String
    var isEnabled = true
    let action: () -> Void

    var id: String { "\(symbol)|\(title)" }
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
    let onSelect: (String) -> Void
    var onAdd: (() -> Void)? = nil
    var onRename: ((String) -> Void)? = nil
    var onCopy: ((String) -> Void)? = nil
    var onDelete: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(BGIFonts.bodyStrong)
                    .foregroundStyle(BGIColors.primaryText)
                Spacer()
                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("新增配置组")
                }
            }
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
                    .contextMenu {
                        if let onAdd {
                            Button("新增组", action: onAdd)
                        }
                        if let onRename {
                            Button("重命名") { onRename(group) }
                        }
                        if let onCopy {
                            Button("复制组") { onCopy(group) }
                        }
                        if let onDelete {
                            Divider()
                            Button("删除组", role: .destructive) { onDelete(group) }
                        }
                    }
                }
            }
            if groups.isEmpty, let onAdd {
                Button("新增配置组", systemImage: "plus", action: onAdd)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
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

            BGISectionCard("脚本列表", subtitle: "按目录、名称和版本展示，并提供执行、打开目录、刷新与删除。", symbolName: "doc.text") {
                BGIDataTable(
                    headers: ["目录", "名称", "版本"],
                    rows: appState.scriptProjects.map { [$0.folderName, $0.name, $0.version] }
                )
            }

            BGIOriginalCard(icon: .symbol("play.rectangle"), title: "脚本执行链路", subtitle: appState.schedulerExecutionStatus) {
                Button("运行所选配置组") { appState.runSchedulerGroups() }
            } content: {
                BGISettingLine(title: "最近结果", subtitle: "执行已安装脚本后的状态。") {
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
                icon: .symbol("doc.text"),
                title: "一键宏（按角色）",
                subtitle: "触发后会识别当前出战角色，并根据配置执行对应的宏"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: {
                            appState.macroSettings?
                                .combatMacroEnabled ?? false
                        },
                        set: {
                            appState.saveMacroSettings(
                                combatMacroEnabled: $0)
                        })
                )
                .labelsHidden()
                .disabled(appState.macroSettings == nil)
            } content: {
                VStack(spacing: 0) {
                    BGISettingLine(
                        title: "快捷键触发方式",
                        subtitle: "按住时重复：按住时重复执行；触发：按下启动再按关闭"
                    ) {
                        Picker(
                            "",
                            selection: Binding(
                                get: {
                                    appState.macroSettings?
                                        .combatMacroHotkeyMode ?? ""
                                },
                                set: {
                                    appState.saveMacroSettings(
                                        combatMacroHotkeyMode: $0)
                                })
                        ) {
                            ForEach(
                                appState.macroSettings?
                                    .combatMacroHotkeyModeOptions ?? [],
                                id: \.self
                            ) {
                                Text($0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        .disabled(appState.macroSettings == nil)
                    }

                    Divider()

                    BGISettingLine(
                        title: "宏配置",
                        subtitle: "配置每个角色执行的宏，比如：胡桃A重跳"
                    ) {
                        HStack(spacing: 10) {
                            Link(
                                "点击查看说明",
                                destination: URL(
                                    string: "https://www.bettergi.com/feats/macro/onem.html"
                                )!)
                            Button("前往设置") {
                                appState.openAvatarMacroConfiguration()
                            }
                            .disabled(appState.macroSettings == nil)
                        }
                    }

                    Divider()

                    BGISettingLine(
                        title: "默认战斗宏编号",
                        subtitle: "当角色的 macroPriority 设置为0时，使用此默认宏编号（1~5）"
                    ) {
                        Stepper(
                            "\(appState.macroSettings?.combatMacroPriority ?? 1)",
                            value: Binding(
                                get: {
                                    appState.macroSettings?
                                        .combatMacroPriority ?? 1
                                },
                                set: {
                                    appState.saveMacroSettings(
                                        combatMacroPriority: $0)
                                }),
                            in: 1...5)
                        .frame(width: 180)
                        .disabled(appState.macroSettings == nil)
                    }

                    Divider()

                    BGISettingLine(
                        title: "角色个性化宏编号设置",
                        subtitle: "上方宏配置支持为每个角色单独设置宏编号。在角色宏配置中设置 macroPriority 字段（1-5），设置为0则使用上面的默认战斗宏编号。"
                    ) {
                        EmptyView()
                    }
                }
            }

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

            BGIOriginalCard(
                icon: .symbol("cursorarrow.motionlines"),
                title: "那维莱特 - 转圈圈",
                subtitle: "按住已绑定快捷键时持续水平平移鼠标。"
            ) {
                hotKeyBindingButton
            } content: {
                VStack(spacing: 0) {
                    BGISettingLine(
                        title: "移动鼠标距离",
                        subtitle: "可以为负数，绝对值越大移动越快。"
                    ) {
                        Stepper(
                            "\(appState.macroSettings?.runaroundMouseXInterval ?? 500)",
                            value: Binding(
                                get: {
                                    appState.macroSettings?
                                        .runaroundMouseXInterval ?? 500
                                },
                                set: {
                                    appState.saveMacroSettings(
                                        runaroundMouseXInterval: $0)
                                }),
                            in: -10_000...10_000,
                            step: 10)
                        .frame(width: 170)
                        .disabled(appState.macroSettings == nil)
                    }

                    Divider()

                    BGISettingLine(
                        title: "移动鼠标间隔",
                        subtitle: "每次水平移动之间的等待时间。"
                    ) {
                        Stepper(
                            "\(appState.macroSettings?.runaroundInterval ?? 10) ms",
                            value: Binding(
                                get: {
                                    appState.macroSettings?
                                        .runaroundInterval ?? 10
                                },
                                set: {
                                    appState.saveMacroSettings(
                                        runaroundInterval: $0)
                                }),
                            in: 1...1000)
                        .frame(width: 170)
                        .disabled(appState.macroSettings == nil)
                    }
                }
            }

            BGIOriginalCard(
                icon: .symbol("sparkles"),
                title: "快速强化圣遗物",
                subtitle: "快速跳过强化结果展示，需要配置快捷键进行触发。"
            ) {
                hotKeyBindingButton
            } content: {
                BGISettingLine(
                    title: "强化的额外等待时间",
                    subtitle: "高延迟下无法跳过强化结果显示时，可延长该等待时间。"
                ) {
                    Stepper(
                        "\(appState.macroSettings?.enhanceWaitDelay ?? 0) ms",
                        value: Binding(
                            get: {
                                appState.macroSettings?.enhanceWaitDelay ?? 0
                            },
                            set: {
                                appState.saveMacroSettings(
                                    enhanceWaitDelay: $0)
                            }),
                        in: 0...1000,
                        step: 10)
                    .frame(width: 170)
                    .disabled(appState.macroSettings == nil)
                }
            }

            BGIOriginalCard(
                icon: .symbol("cart"),
                title: "快速购买",
                subtitle: "在物品购买或兑换页使用，从选中物品处开始，按住快捷键持续购买。"
            ) {
                hotKeyBindingButton
            } content: {
                Text("请在快捷键设置中绑定“按下快速购买商店物品”。")
                    .font(BGIFonts.body)
                    .foregroundStyle(BGIColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BGIOriginalCard(
                icon: .symbol("house"),
                title: "一键进出尘歌壶",
                subtitle: "一键自动打开背包，放置尘歌壶并进入。"
            ) {
                hotKeyBindingButton
            } content: {
                Text("请在快捷键设置中绑定“按下快速进出尘歌壶”。")
                    .font(BGIFonts.body)
                    .foregroundStyle(BGIColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BGIOriginalCard(
                icon: .symbol("checkmark.circle"),
                title: "一键确认/取消",
                subtitle: "绑定快捷键到原神的确认或取消按钮。"
            ) {
                hotKeyBindingButton
            } content: {
                Text("分别绑定“快捷点击原神内确认按钮”和“快捷点击原神内取消按钮”。")
                    .font(BGIFonts.body)
                    .foregroundStyle(BGIColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BGIOriginalCard(
                icon: .symbol("gift"),
                title: "一键领取奖励",
                subtitle: "识别当前页面的领取按钮或礼物图标并点击，需要配置快捷键进行触发"
            ) {
                hotKeyBindingButton
            } content: {
                VStack(spacing: 0) {
                    BGISettingLine(
                        title: "模式选择",
                        subtitle: "点按一次会领取当前页面可见图标；按住持续会在松开快捷键时立即停止"
                    ) {
                        Picker(
                            "",
                            selection: Binding(
                                get: {
                                    appState.macroSettings?
                                        .oneKeyClaimRewardHotkeyMode ?? ""
                                },
                                set: {
                                    appState.saveMacroSettings(
                                        oneKeyClaimRewardHotkeyMode: $0)
                                })
                        ) {
                            ForEach(
                                appState.macroSettings?
                                    .oneKeyClaimRewardHotkeyModeOptions ?? [],
                                id: \.self
                            ) {
                                Text($0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                        .disabled(appState.macroSettings == nil)
                    }

                    Divider()

                    BGISettingLine(
                        title: "未找到领取图标时滚轮下滑",
                        subtitle: "仅在按住持续模式下可用。"
                    ) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    appState.macroSettings?
                                        .oneKeyClaimRewardScrollDownEnabled
                                        ?? false
                                },
                                set: {
                                    appState.saveMacroSettings(
                                        oneKeyClaimRewardScrollDownEnabled: $0)
                                })
                        )
                        .labelsHidden()
                        .disabled(
                            appState.macroSettings == nil ||
                            appState.macroSettings?
                                .oneKeyClaimRewardHotkeyMode !=
                                appState.macroSettings?
                                    .oneKeyClaimRewardHoldMode)
                    }

                    Divider()

                    BGISettingLine(
                        title: "滚轮下滑幅度",
                        subtitle: "数值越大，每次未找到领取图标时向下滚动越多"
                    ) {
                        Stepper(
                            "\(appState.macroSettings?.oneKeyClaimRewardScrollDownAmount ?? 2)",
                            value: Binding(
                                get: {
                                    appState.macroSettings?
                                        .oneKeyClaimRewardScrollDownAmount ?? 2
                                },
                                set: {
                                    appState.saveMacroSettings(
                                        oneKeyClaimRewardScrollDownAmount: $0)
                                }),
                            in: 1...1000)
                        .frame(width: 170)
                        .disabled(
                            appState.macroSettings == nil ||
                            appState.macroSettings?
                                .oneKeyClaimRewardHotkeyMode !=
                                appState.macroSettings?
                                    .oneKeyClaimRewardHoldMode ||
                            appState.macroSettings?
                                .oneKeyClaimRewardScrollDownEnabled != true)
                    }
                }
            }
        }
    }

    private var hotKeyBindingButton: some View {
        Button {
            appState.selectedPage = .hotkey
        } label: {
            Label("绑定", systemImage: "keyboard")
        }
        .buttonStyle(.bordered)
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
                    subtitle: "程序启动后会加载可用的快捷键。",
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

struct KeyBindingPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "按键绑定设置")

            if let settings = appState.keyBindingSettings {
                BGISectionCard(
                    "全局按键映射",
                    subtitle: "应用于脚本、战斗策略和地图追踪中的游戏动作",
                    symbolName: "keyboard"
                ) {
                    BGISettingLine(
                        title: "启用全局按键映射",
                        subtitle: "关闭时仅内置功能使用以下按键绑定"
                    ) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    settings.globalKeyMappingEnabled
                                },
                                set: {
                                    appState.setGlobalKeyMappingEnabled($0)
                                }))
                        .labelsHidden()
                    }
                }

                ForEach(Array(groupedBindings.enumerated()), id: \.offset) {
                    _, group in
                    BGISectionCard(
                        group.category,
                        symbolName:
                            group.category == "操作"
                            ? "gamecontroller"
                            : "rectangle.grid.2x2"
                    ) {
                        VStack(spacing: 0) {
                            ForEach(group.bindings) { binding in
                                bindingRow(binding, settings: settings)
                            }
                        }
                    }
                }
            } else {
                BGISectionCard(
                    "按键绑定尚未就绪",
                    subtitle: "程序启动后会加载游戏键位。",
                    symbolName: "keyboard"
                ) {
                    EmptyView()
                }
            }
        }
    }

    private var groupedBindings:
        [(category: String, bindings: [BetterGIKeyBinding])]
    {
        (appState.keyBindingSettings?.bindings ?? []).reduce(
            into: []
        ) { groups, binding in
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
    private func bindingRow(
        _ binding: BetterGIKeyBinding,
        settings: BetterGIKeyBindingSettings
    ) -> some View {
        BGISettingLine(
            title: binding.actionName,
            subtitle: binding.supported
                ? binding.displayValue
                : "当前键值无法由 macOS 输入桥投递"
        ) {
            Picker(
                binding.actionName,
                selection: Binding(
                    get: { binding.value },
                    set: {
                        appState.setGameKeyBinding(
                            binding,
                            value: $0)
                    })
            ) {
                if !binding.supported {
                    Text(binding.displayValue)
                        .tag(binding.value)
                }
                ForEach(settings.options) { option in
                    Text(option.displayName)
                        .tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150)
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
                VStack(spacing: 0) {
                    BGISettingLine(
                        title: "通知时包含截图",
                        subtitle: "启用后，支持图片的通知渠道会附带当前游戏画面。"
                    ) {
                        Toggle("", isOn: Binding(
                            get: {
                                appState.notificationSettings?
                                    .includeScreenShot ?? true
                            },
                            set: {
                                appState.saveNotificationSettings(
                                    includeScreenShot: $0)
                            }
                        ))
                        .labelsHidden()
                        .disabled(appState.notificationSettings == nil)
                    }

                    Divider()

                    BGISettingLine(
                        title: "允许 JS 脚本发送通知",
                        subtitle: "启用后，调度器中获准发送通知的脚本可以调用通知接口。"
                    ) {
                        Toggle("", isOn: Binding(
                            get: {
                                appState.notificationSettings?
                                    .jsNotificationEnabled ?? false
                            },
                            set: {
                                appState.saveNotificationSettings(
                                    jsNotificationEnabled: $0)
                            }
                        ))
                        .labelsHidden()
                        .disabled(appState.notificationSettings == nil)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("需要通知的事件")
                                        .font(BGIFonts.body)
                                    Link(
                                        "打开文档",
                                        destination: URL(
                                            string: "https://www.bettergi.com/dev/webhook.html#%E4%BA%8B%E4%BB%B6%E5%88%97%E8%A1%A8"
                                        )!)
                                        .font(BGIFonts.caption)
                                }
                                Text(eventSelectionSummary)
                                    .font(BGIFonts.caption)
                                    .foregroundStyle(BGIColors.secondaryText)
                            }
                            Spacer()
                            Button("全选") {
                                appState.setAllNotificationEvents(selected: true)
                            }
                            .buttonStyle(.bordered)
                            Button("取消选择") {
                                appState.setAllNotificationEvents(selected: false)
                            }
                            .buttonStyle(.bordered)
                        }

                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .adaptive(minimum: 180),
                                    alignment: .leading)
                            ],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(
                                appState.notificationSettings?.events ?? []
                            ) { event in
                                Toggle(
                                    event.displayName,
                                    isOn: Binding(
                                        get: { event.selected },
                                        set: {
                                            appState.setNotificationEvent(
                                                event.code,
                                                selected: $0)
                                        }))
                                    .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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
                            appState.sendTestNotification(channel: "native")
                        } label: {
                            Label("发送", systemImage: "paperplane")
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            appState.notificationSettings?.macOSNotificationEnabled != true)
                    }
                }
            }

            ForEach(appState.notificationSettings?.channels ?? []) { channel in
                NotificationChannelCard(channel: channel)
            }
        }
    }

    private var eventSelectionSummary: String {
        guard let events = appState.notificationSettings?.events else {
            return "程序启动后加载事件列表"
        }
        let selectedCount = events.filter(\.selected).count
        return selectedCount == 0
            ? "未选择时按全部通知处理"
            : "已选择 \(selectedCount) / \(events.count) 个事件"
    }
}

private struct NotificationChannelCard: View {
    @EnvironmentObject private var appState: AppState
    let channel: BetterGINotificationChannel

    var body: some View {
        BGIOriginalCard(
            icon: .symbol(iconName),
            title: channel.title,
            subtitle: channel.subtitle
        ) {
            Toggle(
                "",
                isOn: Binding(
                    get: { channel.enabled },
                    set: {
                        appState.saveNotificationChannel(
                            channelID: channel.id,
                            enabled: $0)
                    }))
                .labelsHidden()
        } content: {
            VStack(spacing: 0) {
                ForEach(Array(channel.fields.enumerated()), id: \.element.id) {
                    index, field in
                    if index > 0 {
                        Divider()
                    }
                    BGISettingLine(
                        title: field.label,
                        subtitle: field.placeholder
                    ) {
                        fieldControl(field)
                    }
                }

                if !channel.fields.isEmpty {
                    Divider()
                }
                BGISettingLine(
                    title: "测试通知",
                    subtitle: "使用当前已保存配置发送一条测试通知。"
                ) {
                    HStack(spacing: 8) {
                        if !appState.notificationTestStatus.isEmpty {
                            Text(appState.notificationTestStatus)
                                .font(BGIFonts.caption)
                                .foregroundStyle(BGIColors.secondaryText)
                                .lineLimit(3)
                        }
                        Button {
                            appState.sendTestNotification(channel: channel.id)
                        } label: {
                            Label("发送", systemImage: "paperplane")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!channel.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fieldControl(_ field: BetterGINotificationField) -> some View {
        switch field.value {
        case .boolean(let value):
            Toggle(
                "",
                isOn: Binding(
                    get: { value },
                    set: {
                        save(field, value: .boolean($0))
                    }))
                .labelsHidden()
        case .integer(let value):
            TextField(
                field.placeholder,
                value: Binding(
                    get: { value },
                    set: {
                        save(field, value: .integer($0))
                    }),
                format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        case .string(let value):
            if field.kind == "select" {
                Picker(
                    field.label,
                    selection: Binding(
                        get: { value },
                        set: {
                            save(field, value: .string($0))
                        })
                ) {
                    ForEach(field.options, id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 150)
            } else if field.kind == "secret" {
                SecureField(
                    field.placeholder,
                    text: Binding(
                        get: { value },
                        set: {
                            save(field, value: .string($0))
                        }))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 240)
            } else {
                TextField(
                    field.placeholder,
                    text: Binding(
                        get: { value },
                        set: {
                            save(field, value: .string($0))
                        }))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 240)
            }
        }
    }

    private func save(
        _ field: BetterGINotificationField,
        value: BetterGINotificationFieldValue
    ) {
        appState.saveNotificationChannel(
            channelID: channel.id,
            fieldID: field.id,
            value: value)
    }

    private var iconName: String {
        switch channel.id {
        case "email": "envelope"
        case "telegram": "paperplane"
        case "websocket": "network"
        case "bark": "bell.badge"
        case "discord": "bubble.left.and.bubble.right"
        default: "link"
        }
    }
}
