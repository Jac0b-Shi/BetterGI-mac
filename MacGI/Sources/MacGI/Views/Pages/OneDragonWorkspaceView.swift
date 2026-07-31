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
                optionPicker(
                    "合成台国家",
                    key: "CraftingBenchCountry",
                    options: oneDragonOptions.craftingBenchCountries)
                Stepper(
                    "保留原粹树脂：\(appState.oneDragonIntValue("MinResinToKeep"))",
                    value: intBinding("MinResinToKeep"),
                    in: 0 ... 200)
                optionPicker(
                    "冒险家协会国家",
                    key: "AdventurersGuildCountry",
                    options: oneDragonOptions.adventurersGuildCountries)
                textField("领取每日奖励的好感队伍", key: "DailyRewardPartyName")
            }
        }
    }

    private var domainSettings: some View {
        BGISectionCard("自动秘境", subtitle: "默认配置与按星期覆盖配置。", symbolName: "building.columns") {
            VStack(alignment: .leading, spacing: 10) {
                textField("默认队伍", key: "PartyName")
                optionPicker(
                    "默认秘境",
                    key: "DomainName",
                    options: oneDragonOptions.domainNames,
                    emptyLabel: "留空")
                Toggle("按星期使用不同配置", isOn: boolBinding("WeeklyDomainEnabled"))
                optionPicker(
                    "普通周日奖励选项",
                    key: "SundayEverySelectedValue",
                    options: oneDragonOptions.sundayRewardOptions,
                    emptyLabel: "留空")
                optionPicker(
                    "每周秘境周日奖励选项",
                    key: "SundayWeeklySelectedValue",
                    options: oneDragonOptions.sundayRewardOptions,
                    emptyLabel: "留空")
                if appState.oneDragonBoolValue("WeeklyDomainEnabled") {
                    Divider()
                    ForEach(days) { day in
                        DisclosureGroup(day.title) {
                            VStack(alignment: .leading, spacing: 8) {
                                textField("队伍", key: "\(day.domainPrefix)PartyName")
                                optionPicker(
                                    "秘境",
                                    key: "\(day.domainPrefix)DomainName",
                                    options: oneDragonOptions.domainNames,
                                    emptyLabel: "使用默认秘境")
                                optionPicker(
                                    "周日奖励选项",
                                    key: "\(day.domainPrefix)SelectedValue",
                                    options: oneDragonOptions.sundayRewardOptions,
                                    emptyLabel: "使用全局选项")
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                Divider()
                domainRewardSettings
            }
        }
    }

    @ViewBuilder
    private var domainRewardSettings: some View {
        if let settings = appState.autoDomainSettings {
            DisclosureGroup("领奖树脂与圣遗物分解") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "按配置数量使用树脂",
                        isOn: Binding(
                            get: { settings.specifyResinUse },
                            set: { appState.saveAutoDomainSettings(specifyResinUse: $0) }))
                    if settings.specifyResinUse {
                        domainResinCount(
                            "原粹树脂刷取次数",
                            value: Binding(
                                get: { settings.originalResinUseCount },
                                set: {
                                    appState.saveAutoDomainSettings(
                                        originalResinUseCount: $0)
                                }))
                        domainResinCount(
                            "浓缩树脂刷取次数",
                            value: Binding(
                                get: { settings.condensedResinUseCount },
                                set: {
                                    appState.saveAutoDomainSettings(
                                        condensedResinUseCount: $0)
                                }))
                        domainResinCount(
                            "须臾树脂刷取次数",
                            value: Binding(
                                get: { settings.transientResinUseCount },
                                set: {
                                    appState.saveAutoDomainSettings(
                                        transientResinUseCount: $0)
                                }))
                        domainResinCount(
                            "脆弱树脂刷取次数",
                            value: Binding(
                                get: { settings.fragileResinUseCount },
                                set: {
                                    appState.saveAutoDomainSettings(
                                        fragileResinUseCount: $0)
                                }))
                    } else {
                        Text("先使用浓缩树脂，再使用原粹树脂，其余树脂不使用。")
                            .font(BGIFonts.caption)
                            .foregroundStyle(BGIColors.secondaryText)
                    }
                    HStack(spacing: 12) {
                        Toggle(
                            "结束后自动分解圣遗物",
                            isOn: Binding(
                                get: { settings.autoArtifactSalvage },
                                set: {
                                    appState.saveAutoDomainSettings(
                                        autoArtifactSalvage: $0)
                                }))
                        Spacer()
                        Picker(
                            "最高星级",
                            selection: Binding(
                                get: { settings.maxArtifactStar },
                                set: {
                                    appState.saveAutoDomainSettings(
                                        maxArtifactStar: $0)
                                })
                        ) {
                            ForEach(settings.maxArtifactStarOptions, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .frame(width: 150)
                        .disabled(!settings.autoArtifactSalvage)
                    }
                    Toggle(
                        "启用奖励识别",
                        isOn: Binding(
                            get: { settings.rewardRecognitionEnabled },
                            set: {
                                appState.saveAutoDomainSettings(
                                    rewardRecognitionEnabled: $0)
                            }))
                    Text("每轮领取后识别奖励名称与数量，任务结束时打印汇总。")
                        .font(BGIFonts.caption)
                        .foregroundStyle(BGIColors.secondaryText)
                }
                .padding(.top, 8)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在读取秘境领奖设置")
                    .font(BGIFonts.caption)
                    .foregroundStyle(BGIColors.secondaryText)
            }
        }
    }

    private func domainResinCount(
        _ title: String,
        value: Binding<Int>
    ) -> some View {
        Stepper(
            "\(title)：\(value.wrappedValue)",
            value: value,
            in: 0 ... 999)
    }

    private var bossSettings: some View {
        BGISectionCard("自动首领讨伐", subtitle: "首领、战斗策略、队伍与树脂使用。", symbolName: "shield.lefthalf.filled") {
            VStack(alignment: .leading, spacing: 10) {
                optionPicker(
                    "首领名称",
                    key: "AutoBossName",
                    options: oneDragonOptions.bossNames,
                    emptyLabel: "未选择")
                optionPicker(
                    "战斗策略",
                    key: "AutoBossStrategyName",
                    options: oneDragonOptions.fightStrategies)
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
                Stepper(
                    "战斗超时：\(appState.oneDragonIntValue("AutoBossTimeout", default: 240)) 秒",
                    value: intBinding("AutoBossTimeout", default: 240),
                    in: 1 ... 3_600)
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
                            optionPicker(
                                "地脉类型",
                                key: "\(day.leyLinePrefix)Type",
                                options: oneDragonOptions.leyLineTypes,
                                emptyLabel: "使用独立任务配置")
                            optionPicker(
                                "国家",
                                key: "\(day.leyLinePrefix)Country",
                                options: oneDragonOptions.leyLineCountries,
                                emptyLabel: "使用独立任务配置")
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
                optionPicker(
                    "传送方式",
                    key: "SereniteaPotTpType",
                    options: oneDragonOptions.sereniteaPotTpTypes,
                    default: "地图传送")
                Text("洞天购买商品")
                    .font(BGIFonts.caption)
                    .foregroundStyle(BGIColors.secondaryText)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(oneDragonOptions.secretTreasureObjects, id: \.self) { item in
                        Toggle(
                            item,
                            isOn: secretTreasureBinding(item))
                            .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    private var completionSettings: some View {
        BGISectionCard("完成后操作", subtitle: "全部任务结束后执行。", symbolName: "power") {
            Picker(
                "操作",
                selection: stringBinding("CompletionAction")
            ) {
                ForEach(
                    optionsPreservingCurrentValue(
                        oneDragonOptions.completionActions,
                        key: "CompletionAction"),
                    id: \.self
                ) { option in
                    Text(option.isEmpty ? "未设置（等同无）" : option).tag(option)
                }
            }
        }
    }

    private var oneDragonOptions: BetterGIOneDragonConfigOptions {
        appState.oneDragonDocument?.options ?? .empty
    }

    private func textField(_ title: String, key: String) -> some View {
        HStack {
            Text(title)
                .frame(width: 180, alignment: .leading)
            TextField("", text: stringBinding(key))
        }
    }

    private func optionPicker(
        _ title: String,
        key: String,
        options: [String],
        default defaultValue: String = "",
        emptyLabel: String = "留空"
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: 180, alignment: .leading)
            Picker(
                "",
                selection: stringBinding(key, default: defaultValue)
            ) {
                ForEach(
                    optionsPreservingCurrentValue(
                        options,
                        key: key,
                        default: defaultValue),
                    id: \.self
                ) { option in
                    Text(option.isEmpty ? emptyLabel : option).tag(option)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func optionsPreservingCurrentValue(
        _ options: [String],
        key: String,
        default defaultValue: String = ""
    ) -> [String] {
        let current = appState.oneDragonStringValue(key, default: defaultValue)
        guard !options.contains(current) else { return options }
        return [current] + options
    }

    private func secretTreasureBinding(_ item: String) -> Binding<Bool> {
        Binding(
            get: {
                appState.oneDragonStringsValue("SecretTreasureObjects")
                    .contains(item)
            },
            set: { selected in
                var values = appState.oneDragonStringsValue("SecretTreasureObjects")
                if selected {
                    if !values.contains(item) {
                        values.append(item)
                    }
                } else {
                    values.removeAll { $0 == item }
                }
                appState.setOneDragonConfigValue(
                    "SecretTreasureObjects",
                    .strings(values))
            })
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
