import SwiftUI

private enum OneDragonConfigDialog {
    case create
    case rename
}

private struct OneDragonDay: Identifiable {
    let id: String
    let title: String
    let domainPrefix: String
    let leyLinePrefix: String
}

struct OneDragonWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var configDialog: OneDragonConfigDialog?
    @State private var configNameDraft = ""
    @State private var confirmingDelete = false

    private let days = [
        OneDragonDay(id: "Monday", title: "周一", domainPrefix: "Monday", leyLinePrefix: "LeyLineMonday"),
        OneDragonDay(id: "Tuesday", title: "周二", domainPrefix: "Tuesday", leyLinePrefix: "LeyLineTuesday"),
        OneDragonDay(id: "Wednesday", title: "周三", domainPrefix: "Wednesday", leyLinePrefix: "LeyLineWednesday"),
        OneDragonDay(id: "Thursday", title: "周四", domainPrefix: "Thursday", leyLinePrefix: "LeyLineThursday"),
        OneDragonDay(id: "Friday", title: "周五", domainPrefix: "Friday", leyLinePrefix: "LeyLineFriday"),
        OneDragonDay(id: "Saturday", title: "周六", domainPrefix: "Saturday", leyLinePrefix: "LeyLineSaturday"),
        OneDragonDay(id: "Sunday", title: "周日", domainPrefix: "Sunday", leyLinePrefix: "LeyLineSunday"),
    ]

    var body: some View {
        BGIWorkflowShell(
            title: "一条龙",
            subtitle: "按配置顺序执行日常任务与配置组。\(statusText) · \(appState.oneDragonCatalogStatus)",
            commands: [
                BGICommand(
                    title: "运行",
                    symbol: "play.fill",
                    isEnabled: appState.canRunOneDragon,
                    action: appState.runOneDragon),
                BGICommand(
                    title: "刷新",
                    symbol: "arrow.clockwise",
                    action: appState.reloadOneDragonConfigsFromCore),
                BGICommand(
                    title: "停止",
                    symbol: "stop.fill",
                    isEnabled: appState.oneDragonStatus.taskID != nil,
                    action: appState.stopOneDragon),
            ]
        ) {
            BGIGroupSidebar(
                title: "配置",
                groups: appState.oneDragonConfigs.map(\.name),
                selected: appState.selectedOneDragonConfigName,
                onSelect: appState.selectOneDragonConfig)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                configOperations
                taskList
                if appState.oneDragonDocument != nil {
                    settings
                }
            }
        }
        .alert(
            configDialog == .create ? "新建配置" : "重命名配置",
            isPresented: Binding(
                get: { configDialog != nil },
                set: { if !$0 { configDialog = nil } })
        ) {
            TextField("配置名称", text: $configNameDraft)
            Button("取消", role: .cancel) {
                configDialog = nil
            }
            Button("确定") {
                if configDialog == .create {
                    appState.createOneDragonConfig(name: configNameDraft)
                } else {
                    appState.renameSelectedOneDragonConfig(to: configNameDraft)
                }
                configDialog = nil
            }
            .disabled(configNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(
            "删除配置“\(appState.selectedOneDragonConfigName)”？",
            isPresented: $confirmingDelete
        ) {
            Button("删除", role: .destructive) {
                appState.deleteSelectedOneDragonConfig()
            }
        }
        .task {
            if appState.oneDragonConfigs.isEmpty {
                appState.reloadOneDragonConfigsFromCore()
            }
        }
    }

    private var statusText: String {
        if let error = appState.oneDragonStatus.error, !error.isEmpty {
            return "\(appState.oneDragonStatus.state)：\(error)"
        }
        return appState.oneDragonStatus.state
    }

    private var configOperations: some View {
        BGISectionCard(
            "配置操作",
            subtitle: appState.oneDragonRunReadiness,
            symbolName: "slider.horizontal.3"
        ) {
            HStack(spacing: 8) {
                Button {
                    configNameDraft = ""
                    configDialog = .create
                } label: {
                    Label("新建", systemImage: "plus")
                }
                Button {
                    configNameDraft = appState.selectedOneDragonConfigName
                    configDialog = .rename
                } label: {
                    Label("重命名", systemImage: "pencil")
                }
                .disabled(appState.oneDragonDocument == nil)
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(
                    appState.oneDragonDocument == nil ||
                        appState.oneDragonStatus.taskID != nil)
                Spacer()
                Button {
                    appState.saveOneDragonConfig()
                } label: {
                    Label("保存配置", systemImage: "square.and.arrow.down")
                }
                .disabled(
                    appState.oneDragonDocument == nil ||
                        appState.oneDragonStatus.taskID != nil)
            }
        }
    }

    private var taskList: some View {
        BGISectionCard(
            "任务列表",
            subtitle: "启用、排序或设置下一次执行起点。",
            symbolName: "list.bullet.rectangle"
        ) {
            VStack(spacing: 0) {
                HStack {
                    Text("任务").font(BGIFonts.bodyStrong)
                    Spacer()
                    Menu {
                        Section("内置任务") {
                            ForEach(
                                appState.oneDragonDocument?.builtInTaskNames ?? [],
                                id: \.self
                            ) { name in
                                Button(name) {
                                    appState.addOneDragonTask(name)
                                }
                            }
                        }
                        Section("配置组") {
                            ForEach(appState.schedulerGroups) { group in
                                Button(group.name) {
                                    appState.addOneDragonTask(group.name)
                                }
                            }
                        }
                    } label: {
                        Label("添加任务", systemImage: "plus")
                    }
                    .disabled(appState.oneDragonStatus.taskID != nil)
                }
                .padding(.bottom, 8)

                ForEach(Array((appState.oneDragonDocument?.tasks ?? []).enumerated()), id: \.element.id) {
                    index,
                    task in
                    HStack(spacing: 10) {
                        Image(systemName: task.isResumeStep ? "flag.fill" : "circle.fill")
                            .font(.system(size: task.isResumeStep ? 13 : 8))
                            .foregroundStyle(
                                task.isResumeStep ? BGIColors.accent : BGIColors.mutedText)
                            .frame(width: 18)
                        Text(task.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { task.isEnabled },
                                set: {
                                    appState.setOneDragonTaskEnabled(
                                        id: task.id,
                                        enabled: $0)
                                }))
                            .labelsHidden()
                            .disabled(appState.oneDragonStatus.taskID != nil)
                        Button {
                            appState.moveOneDragonTask(id: task.id, offset: -1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .help("上移")
                        .disabled(index == 0 || appState.oneDragonStatus.taskID != nil)
                        Button {
                            appState.moveOneDragonTask(id: task.id, offset: 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .help("下移")
                        .disabled(
                            index == (appState.oneDragonDocument?.tasks.count ?? 1) - 1 ||
                                appState.oneDragonStatus.taskID != nil)
                        Menu {
                            Button("从此执行") {
                                appState.setOneDragonResumeTask(id: task.id)
                            }
                            if task.isResumeStep {
                                Button("清除起点") {
                                    appState.setOneDragonResumeTask(id: nil)
                                }
                            }
                            Divider()
                            Button("删除", role: .destructive) {
                                appState.removeOneDragonTask(id: task.id)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 28)
                        .disabled(appState.oneDragonStatus.taskID != nil)
                    }
                    .padding(.vertical, 7)
                    Divider()
                }

                if appState.oneDragonDocument?.tasks.isEmpty != false {
                    Text("当前配置没有任务。")
                        .foregroundStyle(BGIColors.mutedText)
                        .padding(.vertical, 18)
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            resinAndRewards
            domainSettings
            bossSettings
            leyLineSettings
            sereniteaSettings
            completionSettings
        }
    }

    private var resinAndRewards: some View {
        BGISectionCard("合成树脂与奖励", subtitle: "合成台、冒险家协会和好感队伍。", symbolName: "moon.stars") {
            VStack(alignment: .leading, spacing: 10) {
                textField("合成台国家", key: "CraftingBenchCountry")
                Stepper(
                    "保留原粹树脂：\(appState.oneDragonIntValue("MinResinToKeep"))",
                    value: intBinding("MinResinToKeep"),
                    in: 0 ... 200)
                textField("冒险家协会国家", key: "AdventurersGuildCountry")
                textField("领取每日奖励的好感队伍", key: "DailyRewardPartyName")
            }
        }
    }

    private var domainSettings: some View {
        BGISectionCard("自动秘境", subtitle: "默认配置与按星期覆盖配置。", symbolName: "building.columns") {
            VStack(alignment: .leading, spacing: 10) {
                textField("默认队伍", key: "PartyName")
                textField("默认秘境", key: "DomainName")
                Toggle("按星期使用不同配置", isOn: boolBinding("WeeklyDomainEnabled"))
                textField("普通周日奖励选项", key: "SundayEverySelectedValue")
                textField("每周秘境周日奖励选项", key: "SundayWeeklySelectedValue")
                if appState.oneDragonBoolValue("WeeklyDomainEnabled") {
                    Divider()
                    ForEach(days) { day in
                        DisclosureGroup(day.title) {
                            VStack(alignment: .leading, spacing: 8) {
                                textField("队伍", key: "\(day.domainPrefix)PartyName")
                                textField("秘境", key: "\(day.domainPrefix)DomainName")
                                textField("周日奖励选项", key: "\(day.domainPrefix)SelectedValue")
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }

    private var bossSettings: some View {
        BGISectionCard("自动首领讨伐", subtitle: "首领、战斗策略、队伍与树脂使用。", symbolName: "shield.lefthalf.filled") {
            VStack(alignment: .leading, spacing: 10) {
                textField("首领名称", key: "AutoBossName")
                textField("战斗策略", key: "AutoBossStrategyName")
                textField("队伍名称", key: "AutoBossTeamName")
                Toggle("指定运行次数", isOn: boolBinding("AutoBossSpecifyRunCount"))
                if appState.oneDragonBoolValue("AutoBossSpecifyRunCount") {
                    Stepper(
                        "运行次数：\(appState.oneDragonIntValue("AutoBossRunCount", default: 1))",
                        value: intBinding("AutoBossRunCount", default: 1),
                        in: 1 ... 999)
                    Toggle("使用须臾树脂", isOn: boolBinding("AutoBossUseTransientResin"))
                    Toggle("使用脆弱树脂", isOn: boolBinding("AutoBossUseFragileResin"))
                }
                Stepper(
                    "复苏重试次数：\(appState.oneDragonIntValue("AutoBossReviveRetryCount", default: 3))",
                    value: intBinding("AutoBossReviveRetryCount", default: 3),
                    in: 0 ... 20)
                Toggle(
                    "每轮结束后返回七天神像",
                    isOn: boolBinding("AutoBossReturnToStatueAfterEachRound"))
                Toggle(
                    "启用奖励识别",
                    isOn: boolBinding("AutoBossRewardRecognitionEnabled"))
            }
        }
    }

    private var leyLineSettings: some View {
        BGISectionCard("自动地脉花", subtitle: "运行日期、次数与每日类型覆盖。", symbolName: "camera.macro") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("一条龙模式", isOn: boolBinding("LeyLineOneDragonMode"))
                Stepper(
                    "运行次数：\(appState.oneDragonIntValue("LeyLineRunCount"))",
                    value: intBinding("LeyLineRunCount"),
                    in: 0 ... 999)
                Toggle(
                    "树脂耗尽模式",
                    isOn: boolBinding("LeyLineResinExhaustionMode"))
                Toggle(
                    "耗尽模式下取较小次数",
                    isOn: boolBinding("LeyLineOpenModeCountMin"))
                Divider()
                ForEach(days) { day in
                    DisclosureGroup(day.title) {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(
                                "当天运行",
                                isOn: boolBinding("LeyLineRun\(day.id)"))
                            textField("地脉类型", key: "\(day.leyLinePrefix)Type")
                            textField("国家", key: "\(day.leyLinePrefix)Country")
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private var sereniteaSettings: some View {
        BGISectionCard("尘歌壶", subtitle: "传送方式与洞天购买选择。", symbolName: "house") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("传送方式", selection: stringBinding("SereniteaPotTpType", default: "地图传送")) {
                    Text("地图传送").tag("地图传送")
                    Text("尘歌壶道具").tag("尘歌壶道具")
                }
                TextField(
                    "购买物品，以逗号分隔",
                    text: Binding(
                        get: {
                            appState.oneDragonStringsValue(
                                "SecretTreasureObjects").joined(separator: ",")
                        },
                        set: { value in
                            appState.setOneDragonConfigValue(
                                "SecretTreasureObjects",
                                .strings(value.split(separator: ",").map {
                                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                }.filter { !$0.isEmpty }))
                        }))
            }
        }
    }

    private var completionSettings: some View {
        BGISectionCard("完成后操作", subtitle: "全部任务结束后执行。", symbolName: "power") {
            Picker(
                "操作",
                selection: stringBinding("CompletionAction")
            ) {
                Text("无").tag("")
                Text("关闭游戏").tag("关闭游戏")
                Text("关闭软件").tag("关闭软件")
                Text("关闭游戏和软件").tag("关闭游戏和软件")
                Text("关机").tag("关机")
            }
        }
    }

    private func textField(_ title: String, key: String) -> some View {
        HStack {
            Text(title)
                .frame(width: 180, alignment: .leading)
            TextField("", text: stringBinding(key))
        }
    }

    private func stringBinding(
        _ key: String,
        default defaultValue: String = ""
    ) -> Binding<String> {
        Binding(
            get: { appState.oneDragonStringValue(key, default: defaultValue) },
            set: { appState.setOneDragonConfigValue(key, .string($0)) })
    }

    private func boolBinding(
        _ key: String,
        default defaultValue: Bool = false
    ) -> Binding<Bool> {
        Binding(
            get: { appState.oneDragonBoolValue(key, default: defaultValue) },
            set: { appState.setOneDragonConfigValue(key, .bool($0)) })
    }

    private func intBinding(
        _ key: String,
        default defaultValue: Int = 0
    ) -> Binding<Int> {
        Binding(
            get: { appState.oneDragonIntValue(key, default: defaultValue) },
            set: {
                appState.setOneDragonConfigValue(
                    key,
                    .integer(Int64($0)))
            })
    }
}
