import SwiftUI

private struct BGICommand: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    var action: () -> Void = {}
}

private struct BGIWorkflowShell<Sidebar: View, Content: View>: View {
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
            }
            Spacer(minLength: 0)
        }
    }
}

private struct BGIGroupSidebar: View {
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
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let selectedGroup = appState.schedulerGroups.first { $0.name == appState.selectedSchedulerGroupName }
            ?? appState.schedulerGroups.first
        BGIWorkflowShell(
            title: "调度器",
            subtitle: "原 BetterGI 的配置组、连续执行、任务表格和通用配置入口。\(appState.schedulerExecutionStatus) · \(appState.schedulerCatalogStatus)",
            commands: [
                BGICommand(title: "运行", symbol: "play.fill", action: { appState.runSchedulerGroups() }),
                BGICommand(title: "刷新", symbol: "arrow.clockwise", action: { appState.reloadSchedulerGroupsFromCore() }),
                BGICommand(title: "停止", symbol: "stop.fill", action: { appState.cancelSchedulerGroups() })
            ]
        ) {
            BGIGroupSidebar(
                title: "配置组",
                groups: appState.schedulerGroups.map(\.name),
                selected: selectedGroup?.name ?? "",
                onSelect: { appState.selectedSchedulerGroupName = $0 }
            )
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                BGISectionCard("配置组 - \(selectedGroup?.name ?? "未选择")", subtitle: "数据由 BetterGI C# Core 提供；在下方列表中右键可添加配置，拖拽可调整执行顺序。", symbolName: "cpu") {
                    VStack(spacing: 0) {
                        ForEach(selectedGroup?.projects ?? []) { project in
                            HStack {
                                Text("\(project.index)")
                                    .frame(width: 30, alignment: .leading)
                                Text(project.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(project.type == "Javascript" ? "JS脚本" : project.type)
                                    .frame(width: 80, alignment: .center)
                                Toggle("", isOn: .constant(project.status == "Enabled"))
                                .frame(width: 60)
                                .disabled(true)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }

                BGISectionCard("操作面板", subtitle: "连续执行、日志分析、更多功能。", symbolName: "square.grid.3x3") {
                    HStack(spacing: 12) {
                        Button("连续执行") { appState.runSchedulerGroups() }
                        Button("继续执行") { appState.runSchedulerGroups() }
                        Menu("更多功能") {
                            Button("从 Core 更新") { appState.reloadSchedulerGroupsFromCore() }
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - Config Group Settings Sheet

struct ScriptGroupConfigSheet: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var autoPick = true
    @State private var autoEat = false
    @State private var autoSkip = true
    @State private var autoFight = true
    @State private var partyName = ""
    @State private var guardianIndex = "4"
    @State private var guardianSkillInterval = "16.2"
    @State private var guardianLongPress = false
    @State private var mainAvatarIndex = "4"
    @State private var onlyTeleportRecover = false
    @State private var gadgetInterval = "0"
    @State private var skipDuring = ""
    @State private var hideOnRepeat = false
    @State private var autoRun = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("配置组设置").font(.title2).bold()
                Spacer()
                Button("完成") { dismiss() }
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Section {
                        Toggle("地图追踪行走配置（不启用则使用地图追踪内的条件配置）", isOn: .constant(true))
                    } header: { Text("地图追踪配置").font(.headline) }

                    Group {
                        Toggle("是否开启自动拾取", isOn: $autoPick)
                        Toggle("是否开启自动吃药", isOn: $autoEat)
                        Toggle("是否开启自动剧情跳过", isOn: $autoSkip)
                        Toggle("是否开启自动战斗", isOn: $autoFight)
                        Toggle("是否开启自动奔跑", isOn: $autoRun)
                    }

                    Group {
                        HStack {
                            Text("切换到队伍的名称（为空则不切换）")
                            Spacer()
                            TextField("队伍名称", text: $partyName).frame(width: 200)
                        }
                        Toggle("切换队伍前强制前往安全的神像区域", isOn: Binding(get: { true }, set: { _ in }))
                    }

                    Group {
                        HStack {
                            Text("【生存位】在队伍内的编号")
                            Spacer()
                            Picker("", selection: $guardianIndex) {
                                ForEach(["1","2","3","4"], id: \.self) { Text($0) }
                            }.frame(width: 80)
                        }
                        HStack {
                            Text("【生存位】释放元素战技的间隔（秒）")
                            Spacer()
                            TextField("16.2", text: $guardianSkillInterval).frame(width: 80)
                        }
                        Toggle("【生存位】元素战技是否长按", isOn: $guardianLongPress)
                            .toggleStyle(.switch)
                    }

                    Group {
                        HStack {
                            Text("【行走位】主要行走的角色在队伍内的编号")
                            Spacer()
                            Picker("", selection: $mainAvatarIndex) {
                                ForEach(["1","2","3","4"], id: \.self) { Text($0) }
                            }.frame(width: 80)
                        }
                    }

                    Group {
                        HStack {
                            Text("使用小道具的间隔时间（毫秒）填0为不使用")
                            Spacer()
                            TextField("0", text: $gadgetInterval).frame(width: 80)
                        }
                        Toggle("只在传送点时恢复", isOn: $onlyTeleportRecover)
                        HStack {
                            Text("不在某时执行（范围：0-23）")
                            Spacer()
                            TextField("", text: $skipDuring).frame(width: 60)
                        }
                        Toggle("不在连续任务中显示", isOn: $hideOnRepeat)
                    }
                }
                .padding()
            }
        }
        .frame(width: 700, height: 600)
    }
}

// MARK: - Project Editor Sheet

struct ScriptGroupProjectEditorSheet: View {
    let appState: AppState
    let projectIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Enabled"
    @State private var allowJSNotification = "Ask"
    @State private var allowJSHTTP = "Deny"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("脚本项目设置").font(.title2).bold()
                Spacer()
                Button("完成") { dismiss() }
            }
            .padding()
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("状态")
                    Spacer()
                    Picker("", selection: $status) {
                        Text("启用").tag("Enabled")
                        Text("禁用").tag("Disabled")
                    }.frame(width: 120)
                }

                Divider()

                Group {
                    Text("JS 通知权限").font(.headline)
                    Picker("", selection: $allowJSNotification) {
                        Text("询问").tag("Ask")
                        Text("允许").tag("Allow")
                        Text("拒绝").tag("Deny")
                    }.frame(width: 120)
                    Text("允许脚本发送系统通知").font(.caption).foregroundColor(.secondary)
                }

                Group {
                    Text("JS HTTP权限").font(.headline)
                    Text("允许脚本发送HTTP请求，可能会带来安全风险，请谨慎开启。").font(.caption).foregroundColor(.orange)
                    Picker("", selection: $allowJSHTTP) {
                        Text("拒绝").tag("Deny")
                        Text("允许").tag("Allow")
                    }.frame(width: 120)
                    Text("注意：脚本更新http_allowed_urls后，需手动重新启用权限。").font(.caption).foregroundColor(.orange)
                }
            }
            .padding()
            Spacer()
        }
        .frame(width: 400, height: 350)
    }
}

struct JSScriptPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "自定义 Javascript 脚本（实验功能）")
            HStack(spacing: 8) {
                BGIUnavailableAction("打开脚本目录", systemImage: "folder")
                BGIUnavailableAction("脚本仓库", systemImage: "archivebox")
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
    }
}

struct MapTrackingPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "地图追踪（实验功能）")
            HStack(spacing: 8) {
                BGIUnavailableAction("打开任务目录", systemImage: "folder")
                BGIUnavailableAction("脚本仓库", systemImage: "archivebox")
                BGIUnavailableAction("设置", systemImage: "gearshape")
                BGIUnavailableAction("开发者工具")
                Spacer()
            }

            BGISectionCard("路径任务", subtitle: "路径解析、定位、识别与执行均由 BetterGI C# Core 负责；此处尚未接入路径目录 DTO。", symbolName: "map") {
                BGIDataTable(
                    headers: ["名称", "文件", "执行任务"],
                    rows: [
                        ["枫丹晶蝶路线", "fontaine_crystalflies.json", "启动"],
                        ["璃月矿点路线", "liyue_ore.json", "启动"],
                        ["须弥材料路线", "sumeru_collect.json", "启动"]
                    ]
                )
            }

            BGIOriginalCard(icon: .fgi("\u{f279}"), title: "地图遮罩点位", subtitle: "Core draw-command sink 已接收状态；Swift 遮罩渲染尚不可用。") {
                BGIUnavailableToggle(isOn: true)
            } content: {
                BGISettingLine(title: "显示小地图方位", subtitle: "在小地图周围显示东南西北文字。") {
                    BGIUnavailableToggle(isOn: true)
                }
                BGISettingLine(title: "显示图像识别结果", subtitle: "实时显示各种图像识别的结果。") {
                    BGIUnavailableToggle(isOn: false)
                }
            }
        }
    }
}

struct RecordReplayPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "键鼠录制回放功能（实验功能）")
            HStack(spacing: 8) {
                BGIUnavailableAction("打开脚本目录", systemImage: "folder")
                BGIUnavailableAction("脚本仓库", systemImage: "archivebox")
                BGIUnavailableAction("开始录制", systemImage: "record.circle")
                BGIUnavailableAction("停止录制", systemImage: "stop.fill")
                Spacer()
            }

            BGISectionCard("录制脚本", subtitle: "原页面按名称、创建时间、操作展示，右键可改名或删除。", symbolName: "record.circle") {
                BGIDataTable(
                    headers: ["名称", "创建时间", "操作"],
                    rows: [
                        ["每日登录领取", "2026-06-29 17:30", "播放脚本"],
                        ["背包整理流程", "2026-06-28 21:12", "播放脚本"],
                        ["测试点击轨迹", "2026-06-27 10:05", "播放脚本"]
                    ]
                )
            }
        }
    }
}

struct MacroPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "辅助操控设置")

            BGIOriginalCard(icon: .symbol("applescript"), title: "一键宏（按角色）", subtitle: "触发后识别当前出战角色，并根据配置执行对应宏。") {
                BGIUnavailableToggle(isOn: false)
            } content: {
                BGISettingLine(title: "快捷键触发方式", subtitle: "按住时重复；触发：按下启动再按关闭。") {
                    BGIInlinePicker(value: "按住时重复", width: 140)
                }
                BGISettingLine(title: "宏配置", subtitle: "打开角色宏配置文件。") {
                    BGIUnavailableAction("前往设置")
                }
                BGISettingLine(title: "默认战斗宏编号", subtitle: "当角色 macroPriority 为 0 时使用，范围 1~5。") {
                    BGINumberField(value: "1", width: 70)
                }
            }

            BGIOriginalCard(icon: .symbol("cursorarrow.motionlines"), title: "那维莱特 - 转圈圈", subtitle: "快速水平平移鼠标，需要配置快捷键触发。") {
                BGIUnavailableAction("绑定快捷键")
            } content: {
                BGISettingLine(title: "移动鼠标距离", subtitle: "可为负数，绝对值越大移动越快。") {
                    BGINumberField(value: "120", width: 90)
                }
                BGISettingLine(title: "移动鼠标间隔（毫秒）", subtitle: "尽量设置大于 0 的数字。") {
                    BGINumberField(value: "8", width: 90)
                }
            }

            BGIOriginalCard(icon: .symbol("cursorarrow.click"), title: "快速强化圣遗物", subtitle: "快速跳过强化结果展示，需要配置快捷键触发。") {
                BGIUnavailableAction("绑定快捷键")
            } content: {
                BGISettingLine(title: "强化的额外等待时间（毫秒）", subtitle: "高延迟下无法跳过结果显示时延长此配置。") {
                    BGINumberField(value: "300", width: 90)
                }
            }

            BGIOriginalCard(icon: .symbol("keyboard"), title: "长按空格等于连续按下空格", subtitle: "用于解除冻结；水下场景不推荐启用。", expanded: false) {
                BGIUnavailableToggle(isOn: false)
            } content: {
                EmptyView()
            }
            BGIOriginalCard(icon: .symbol("keyboard"), title: "长按 F 等于连续按下 F", subtitle: "快速拾取大量掉落物。", expanded: false) {
                BGIUnavailableToggle(isOn: false)
            } content: {
                EmptyView()
            }
        }
    }
}

struct HotkeyPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "快捷键设置")
            Text("全局热键只支持组合键和功能键；键鼠监听支持任意键盘单键、鼠标侧键，功能启动后才生效。")
                .font(BGIFonts.body)
                .foregroundStyle(BGIColors.secondaryText)

            BGISectionCard("热键列表", subtitle: "点击类型按钮可以切换快捷键类型，长按需求的功能不能使用全局热键。", symbolName: "bolt") {
                BGIDataTable(
                    headers: ["功能", "快捷键类型", "配置快捷键"],
                    rows: [
                        ["启动/停止截图器", "全局热键", "⌘⇧S"],
                        ["停止任意独立任务", "键鼠监听", "F12"],
                        ["显示/隐藏 HUD", "全局热键", "⌘⇧H"],
                        ["一键战斗宏", "键鼠监听", "Mouse4"]
                    ]
                )
            }
        }
    }
}

struct NotificationPage: View {
    private let providers = [
        ("全局通知设置", "影响下方所有通知的设置", "bell"),
        ("启用 Webhook", "Webhook 相关设置", "cloud"),
        ("启用 WebSocket", "WebSocket 相关设置", "link"),
        ("启用 macOS 通知", "macOS 通知别与游戏界面重叠，否则易误点通知", "bell.badge"),
        ("启用飞书通知", "飞书通知相关设置", "paperplane"),
        ("启用 OneBot 通知", "OneBot 通知相关设置", "ellipsis.message"),
        ("启用企业微信通知", "企业微信通知相关设置", "bubble.left.and.bubble.right"),
        ("启用邮箱通知", "邮箱相关设置（账号密码完全保存在本地）", "envelope"),
        ("启用 Bark 通知", "Bark iOS 推送通知", "bell.circle"),
        ("启用 Telegram 通知", "Telegram 机器人相关设置", "paperplane.circle"),
        ("启用钉钉机器人通知", "钉钉机器人通知相关设置", "person.2.wave.2"),
        ("启用 Discord Webhook 通知", "Discord Webhook 通知相关设置", "bubble.left.and.text.bubble.right")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "通知设置")
            ForEach(providers, id: \.0) { provider in
                BGIOriginalCard(icon: .symbol(provider.2), title: provider.0, subtitle: provider.1, expanded: provider.0 == "全局通知设置") {
                    BGIUnavailableToggle(isOn: provider.0 == "全局通知设置")
                } content: {
                    BGISettingLine(title: "测试通知", subtitle: "发送测试通知，验证当前渠道配置。") {
                        BGIUnavailableAction("发送测试通知")
                    }
                    BGISettingLine(title: "通知模板", subtitle: "任务开始、任务结束、异常退出时的消息模板。") {
                        BGIInlinePicker(value: "默认", width: 110)
                    }
                }
            }
        }
    }
}
