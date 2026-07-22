import SwiftUI

struct FeaturesPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "实时触发的自动化任务设置")
            ForEach(appState.features) { feature in
                if feature.settingsAvailable {
                    BGIExpandableTaskCard(
                        icon: feature.icon, title: feature.name, subtitle: feature.detail
                    ) {
                        featureToggle(feature)
                    } content: {
                        triggerSettings(for: feature.id)
                    }
                } else {
                    BGITaskCard(icon: feature.icon, title: feature.name, subtitle: feature.detail) {
                        featureToggle(feature)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func featureToggle(_ feature: MacGIFeature) -> some View {
        Toggle("", isOn: Binding(
            get: { appState.featureEnabled(feature.id) },
            set: { appState.setFeature(feature.id, enabled: $0) }))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!appState.canControlFeature(feature.id))
    }

    @ViewBuilder
    private func triggerSettings(for name: String) -> some View {
        switch name {
        case "AutoPick": autoPickSettings
        case "AutoFish":
            BGISettingLine(
                title: "全自动钓鱼已迁移至独立任务下",
                subtitle: "请到独立任务页配合快捷键使用"
            ) { EmptyView() }
        case "AutoEat": autoEatSettings
        case "QuickTeleport": quickTeleportSettings
        case "MapMask": mapMaskSettings
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var autoPickSettings: some View {
        if let settings = appState.autoPickTriggerSettings {
            BGISettingLine(
                title: "极速拾取模式",
                subtitle: "打开后不再识别具体拾取内容，黑名单与白名单不会生效"
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.fastModeEnabled },
                    set: { appState.saveAutoPickTriggerConfiguration(fastModeEnabled: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(
                title: "选择自动拾取文字识别引擎",
                subtitle: "Paddle可识别所有文字,速度慢,消耗少;Yap可识别部分文字,快且准,消耗大"
            ) {
                Picker("", selection: Binding(
                    get: { settings.ocrEngine },
                    set: { appState.saveAutoPickTriggerConfiguration(ocrEngine: $0) })) {
                    ForEach(settings.ocrEngineOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 100)
            }
            BGISettingLine(title: "黑名单", subtitle: "排除 NPC 对话、各类交互选项、不需要拾取的物品等") {
                Toggle("", isOn: Binding(
                    get: { settings.blackListEnabled },
                    set: { appState.saveAutoPickTriggerConfiguration(blackListEnabled: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(title: "精确匹配黑名单", subtitle: "每行一条记录") {
                TextEditor(text: $appState.autoPickExactBlackListDraft)
                    .font(.body.monospaced()).frame(width: 360, height: 100)
                    .overlay(Rectangle().stroke(BGIColors.border, lineWidth: 1))
            }
            BGISettingLine(title: "模糊匹配黑名单", subtitle: "每行一条记录") {
                VStack(alignment: .trailing, spacing: 8) {
                    TextEditor(text: $appState.autoPickFuzzyBlackListDraft)
                        .font(.body.monospaced()).frame(width: 360, height: 100)
                        .overlay(Rectangle().stroke(BGIColors.border, lineWidth: 1))
                    Button("保存黑名单") { appState.saveAutoPickBlackLists() }
                }
            }
            BGISettingLine(title: "白名单", subtitle: "需要主动按下 F 交互的内容，请配合黑名单使用") {
                Toggle("", isOn: Binding(
                    get: { settings.whiteListEnabled },
                    set: { appState.saveAutoPickTriggerConfiguration(whiteListEnabled: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(title: "白名单配置", subtitle: "每行一条记录") {
                VStack(alignment: .trailing, spacing: 8) {
                    TextEditor(text: $appState.autoPickWhiteListDraft)
                        .font(.body.monospaced()).frame(width: 360, height: 100)
                        .overlay(Rectangle().stroke(BGIColors.border, lineWidth: 1))
                    Button("保存白名单") { appState.saveAutoPickWhiteList() }
                }
            }
            BGISettingLine(title: "自定义拾取按键", subtitle: "默认为 F，自带了 E 和 G 按键，需要改成其他键的请阅读文档") {
                Picker("", selection: Binding(
                    get: { settings.pickKey },
                    set: { appState.saveAutoPickTriggerConfiguration(pickKey: $0) })) {
                    ForEach(settings.pickKeyOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 80)
            }
        }
    }

    @ViewBuilder
    private var autoEatSettings: some View {
        if let settings = appState.autoEatTriggerSettings {
            BGISettingLine(title: "触发时间间隔（毫秒）", subtitle: "多少时间检查一次是否红血或需要复活") {
                TextField("", value: Binding(
                    get: { settings.checkInterval },
                    set: { appState.saveAutoEatTriggerSettings(checkInterval: $0) }), format: .number)
                    .frame(width: 90).multilineTextAlignment(.trailing)
            }
            BGISettingLine(title: "吃药时间间隔（毫秒）", subtitle: "防止频繁吃药") {
                TextField("", value: Binding(
                    get: { settings.eatInterval },
                    set: { appState.saveAutoEatTriggerSettings(eatInterval: $0) }), format: .number)
                    .frame(width: 90).multilineTextAlignment(.trailing)
            }
        }
    }

    @ViewBuilder
    private var quickTeleportSettings: some View {
        if let settings = appState.quickTeleportTriggerSettings {
            BGISettingLine(title: "点击候选列表传送点的间隔时间（毫秒）", subtitle: "需要根据文字识别耗时配置，太低会导致点击失败") {
                TextField("", value: Binding(
                    get: { settings.teleportListClickDelay },
                    set: { appState.saveQuickTeleportTriggerSettings(teleportListClickDelay: $0) }), format: .number)
                    .frame(width: 90).multilineTextAlignment(.trailing)
            }
            BGISettingLine(title: "等待右侧传送弹出界面的时间（毫秒）", subtitle: "不建议低于 80ms，太低会导致传送按钮识别不到") {
                TextField("", value: Binding(
                    get: { settings.waitTeleportPanelDelay },
                    set: { appState.saveQuickTeleportTriggerSettings(waitTeleportPanelDelay: $0) }), format: .number)
                    .frame(width: 90).multilineTextAlignment(.trailing)
            }
            BGISettingLine(title: "启用快捷键传送", subtitle: "按下手动触发快速传送快捷键后才进行快速传送") {
                Toggle("", isOn: Binding(
                    get: { settings.hotkeyTpEnabled },
                    set: { appState.saveQuickTeleportTriggerSettings(hotkeyTpEnabled: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var mapMaskSettings: some View {
        if let settings = appState.mapMaskTriggerSettings {
            BGISettingLine(title: "启用小地图遮罩", subtitle: "在小地图上显示已选择的点位") {
                Toggle("", isOn: Binding(
                    get: { settings.miniMapMaskEnabled },
                    set: { appState.saveMapMaskTriggerSettings(miniMapMaskEnabled: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
        }
    }
}

struct SoloTasksPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "独立任务设置")
            ForEach(appState.soloTasks) { task in
                if task.settingsAvailable {
                    BGIExpandableTaskCard(
                        icon: icon(for: task.name), title: task.displayName,
                        subtitle: task.unavailableReason ?? detail(for: task.name)
                    ) {
                        taskAction(task)
                    } content: {
                        settingsContent(for: task)
                    }
                } else {
                    BGITaskCard(icon: icon(for: task.name), title: task.displayName,
                                subtitle: task.unavailableReason ?? detail(for: task.name)) {
                        taskAction(task)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func settingsContent(for task: BetterGICoreSoloTask) -> some View {
        if task.inputKind == "multilineText" {
            BGISettingLine(
                title: task.inputTitle ?? "输入",
                subtitle: task.inputPlaceholder ?? ""
            ) {
                TextEditor(text: Binding(
                    get: { appState.soloTaskInputDrafts[task.name, default: ""] },
                    set: { appState.soloTaskInputDrafts[task.name] = $0 }))
                    .font(.body.monospaced())
                    .frame(width: 360, height: 120)
                    .overlay(Rectangle().stroke(BGIColors.border, lineWidth: 1))
            }
        }
        switch task.name {
        case "AutoGeniusInvokation": autoGeniusInvokationSettings
        case "AutoFishing": autoFishingSettings
        case "AutoCook": autoCookSettings
        case "AutoWood": autoWoodSettings
        case "AutoMusicGame", "AutoAlbum": autoMusicGameSettings
        case "AutoBoss": autoBossSettings
        case "AutoLeyLineOutcrop": autoLeyLineOutcropSettings
        case "AutoStygianOnslaught": autoStygianOnslaughtSettings
        case "AutoDomain": autoDomainSettings
        case "AutoArtifactSalvage": autoArtifactSalvageSettings
        case "AutoFight": autoFightSettings
        case "AutoRedeemCode": EmptyView()
        default:
            BGISettingLine(title: "设置", subtitle: "Core 未返回该任务的设置模型") {
                BGIStatusBadge(text: "不可用", tint: BGIColors.muted)
            }
        }
    }

    @ViewBuilder
    private var autoGeniusInvokationSettings: some View {
        if let settings = appState.autoGeniusInvokationSettings {
            BGISettingLine(title: "选择卡组", subtitle: "选择你想要使用的卡组与策略") {
                Picker("", selection: Binding(
                    get: { settings.strategyName },
                    set: { appState.saveAutoGeniusInvokationSettings(strategyName: $0) })) {
                    Text("请选择策略").tag("")
                    ForEach(settings.strategyOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 220)
            }
            BGISettingLine(
                title: "设置延时（毫秒）",
                subtitle: "如果频繁出现操作速度过快，操作动画未播放完毕的情况可以添加延时"
            ) {
                Stepper(value: Binding(
                    get: { settings.sleepDelay },
                    set: { appState.saveAutoGeniusInvokationSettings(sleepDelay: $0) }),
                    in: 0...5000) {
                    Text("\(settings.sleepDelay)").frame(minWidth: 52)
                }
            }
        } else { settingsLoading }
    }

    @ViewBuilder
    private var autoFishingSettings: some View {
        if let settings = appState.autoFishingSettings {
            BGISettingLine(
                title: "上钩等待超时时间",
                subtitle: "超过这个时间将自动提竿，并重新识别鱼饵进行抛竿"
            ) {
                Stepper(value: Binding(
                    get: { settings.autoThrowRodTimeOut },
                    set: { appState.saveAutoFishingSettings(autoThrowRodTimeOut: $0) }),
                    in: 5...60) {
                    Text("\(settings.autoThrowRodTimeOut) 秒").frame(minWidth: 60)
                }
            }
            BGISettingLine(title: "整个任务超时时间", subtitle: "超过这个时间将强制结束任务；0 表示不限制") {
                Stepper(value: Binding(
                    get: { settings.wholeProcessTimeoutSeconds },
                    set: { appState.saveAutoFishingSettings(wholeProcessTimeoutSeconds: $0) }),
                    in: 0...1800) {
                    Text("\(settings.wholeProcessTimeoutSeconds) 秒").frame(minWidth: 72)
                }
            }
            BGISettingLine(title: "昼夜策略", subtitle: "选择全天、白天、夜晚，或不调整游戏时间") {
                Picker("", selection: Binding(
                    get: { settings.fishingTimePolicy },
                    set: { appState.saveAutoFishingSettings(fishingTimePolicy: $0) })) {
                    ForEach(settings.fishingTimePolicyOptions) { option in
                        Text(option.displayName).tag(option.value)
                    }
                }
                .labelsHidden().frame(width: 110)
            }
            BGISettingLine(
                title: "关键帧保存截图（开发者）",
                subtitle: "在流程关键时刻保存截图，会产生大量文件，非调试时请关闭"
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.saveScreenshotOnKeyTick },
                    set: { appState.saveAutoFishingSettings(saveScreenshotOnKeyTick: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(
                title: "Torch 库文件",
                subtitle: "上游字段仅接受 Windows torch DLL；macOS 当前使用 ONNX/CPU 回退"
            ) {
                Text(settings.torchDllSupported ? settings.torchDllFullPath : "macOS 不支持")
                    .foregroundStyle(.secondary)
            }
        } else { settingsLoading }
    }

    @ViewBuilder
    private func taskAction(_ task: BetterGICoreSoloTask) -> some View {
        if task.available {
            Button {
                appState.toggleSoloTask(
                    task.name,
                    inputText: task.inputKind == nil
                        ? nil
                        : appState.soloTaskInputDrafts[task.name, default: ""])
            } label: {
                Image(systemName: isRunning(task.name) ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.soloTaskStatus.state == "stopping")
            .help(isRunning(task.name) ? "停止" : "启动")
        } else {
            Text("Core 暂未开放")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var autoCookSettings: some View {
        if let settings = appState.autoCookSettings {
            BGISettingLine(title: "检测间隔（毫秒）", subtitle: "每次截图检测的时间间隔，最小 1ms") {
                Stepper(
                    value: Binding(
                        get: { settings.checkIntervalMs },
                        set: { appState.saveAutoCookSettings(checkIntervalMs: $0) }
                    ),
                    in: 1...1000
                ) {
                    Text("\(settings.checkIntervalMs)")
                        .frame(minWidth: 42, alignment: .trailing)
                }
            }
            BGISettingLine(
                title: "自动结束烹饪任务",
                subtitle: "开启后检测到“自动烹饪”按钮会点击并结束当前任务"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { settings.stopTaskWhenRecoverButtonDetected },
                        set: { appState.saveAutoCookSettings(stopWhenDetected: $0) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
        } else {
            BGISettingLine(title: "设置", subtitle: "正在从 BetterGI C# Core 读取") {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var autoWoodSettings: some View {
        if let settings = appState.autoWoodSettings {
            BGISettingLine(title: "使用进出千星奇域刷新树木CD", subtitle: "需要确保已解锁并进入过千星奇域") {
                Toggle("", isOn: Binding(
                    get: { settings.useWonderlandRefresh },
                    set: { appState.saveAutoWoodSettings(useWonderlandRefresh: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(title: "循环次数", subtitle: "输入 0 则为无限循环直到手动终止") {
                TextField("", value: Binding(
                    get: { settings.roundNum },
                    set: { appState.saveAutoWoodSettings(roundNum: $0) }), format: .number)
                    .frame(width: 90).multilineTextAlignment(.trailing)
            }
            BGISettingLine(title: "启用OCR伐木数量限制（需1080P以上分辨率）", subtitle: "达到上限后自动停止伐木") {
                Toggle("", isOn: Binding(
                    get: { settings.woodCountOcrEnabled },
                    set: { appState.saveAutoWoodSettings(woodCountOcrEnabled: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(title: "伐木数量上限", subtitle: "原神每日每种木材最多2000，输入 0 等同不设上限") {
                TextField("", value: Binding(
                    get: { settings.dailyMaxCount },
                    set: { appState.saveAutoWoodSettings(dailyMaxCount: $0) }), format: .number)
                    .frame(width: 90).multilineTextAlignment(.trailing)
            }
            BGISettingLine(title: "使用小道具后的额外延迟（毫秒）", subtitle: "用于观察使用小道具后获得木材的提示") {
                TextField("", value: Binding(
                    get: { settings.afterZSleepDelay },
                    set: { appState.saveAutoWoodSettings(afterZSleepDelay: $0) }), format: .number)
                    .frame(width: 90).multilineTextAlignment(.trailing)
            }
        } else { settingsLoading }
    }

    @ViewBuilder
    private var autoMusicGameSettings: some View {
        if let settings = appState.autoMusicGameSettings {
            BGISettingLine(
                title: "【专辑】 自动演奏未达成【大音天籁】的乐曲",
                subtitle: "关闭时奖励已领取就跳过；开启时达成大音天籁才跳过"
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.mustCanorusLevel },
                    set: { appState.saveAutoMusicGameSettings(mustCanorusLevel: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(title: "【专辑】 自动演奏的目标难度", subtitle: "传说或大师可获取全部奖励；所有会演奏全部难度") {
                Picker("", selection: Binding(
                    get: { settings.musicLevel },
                    set: { appState.saveAutoMusicGameSettings(musicLevel: $0) })) {
                    ForEach(settings.musicLevelOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 120)
            }
        } else { settingsLoading }
    }

    @ViewBuilder
    private var autoBossSettings: some View {
        if let settings = appState.autoBossSettings {
            BGISettingLine(title: "选择战斗策略", subtitle: "仅用于首领讨伐，不覆盖其他策略设置") {
                Picker("", selection: Binding(
                    get: { settings.strategyName },
                    set: { appState.saveAutoBossSettings(strategyName: $0) })) {
                    ForEach(settings.strategyOptions, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 220)
            }
            BGISettingLine(title: "选择首领", subtitle: "部分首领因机制问题未添加") {
                Picker("", selection: Binding(
                    get: { settings.bossName },
                    set: { appState.saveAutoBossSettings(bossName: $0) })) {
                    Text("未选择").tag("")
                    ForEach(settings.bossOptions, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 220)
            }
            BGISettingLine(title: "切换队伍", subtitle: "留空则不更换队伍") {
                TextField("例如：首领队", text: Binding(
                    get: { settings.teamName },
                    set: { appState.saveAutoBossSettings(teamName: $0) }))
                    .frame(width: 200)
            }
            BGISettingLine(title: "指定讨伐次数", subtitle: "关闭时刷取至原粹树脂耗尽") {
                Toggle("", isOn: Binding(
                    get: { settings.specifyRunCount },
                    set: { appState.saveAutoBossSettings(specifyRunCount: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            if settings.specifyRunCount {
                BGISettingLine(title: "讨伐次数", subtitle: "按成功领取奖励次数停止") {
                    Stepper(value: Binding(
                        get: { settings.runCount },
                        set: { appState.saveAutoBossSettings(runCount: $0) }), in: 1...999) {
                        Text("\(settings.runCount)").frame(minWidth: 36, alignment: .trailing)
                    }
                }
                BGISettingLine(title: "原粹不足时使用须臾树脂补充", subtitle: "仅在指定讨伐次数时生效") {
                    Toggle("", isOn: Binding(
                        get: { settings.useTransientResin },
                        set: { appState.saveAutoBossSettings(useTransientResin: $0) }))
                        .toggleStyle(.switch).labelsHidden()
                }
                BGISettingLine(title: "原粹不足时使用脆弱树脂补充", subtitle: "仅在指定讨伐次数时生效") {
                    Toggle("", isOn: Binding(
                        get: { settings.useFragileResin },
                        set: { appState.saveAutoBossSettings(useFragileResin: $0) }))
                        .toggleStyle(.switch).labelsHidden()
                }
            }
            BGISettingLine(title: "每轮讨伐后返回七天神像", subtitle: "每次领奖后先回血，再重新前往首领") {
                Toggle("", isOn: Binding(
                    get: { settings.returnToStatueAfterEachRound },
                    set: { appState.saveAutoBossSettings(returnToStatueAfterEachRound: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(title: "启用奖励识别", subtitle: "每轮领取后识别奖励名称与数量，任务结束打印汇总") {
                Toggle("", isOn: Binding(
                    get: { settings.rewardRecognitionEnabled },
                    set: { appState.saveAutoBossSettings(rewardRecognitionEnabled: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(title: "角色死亡后重试次数", subtitle: "复活后重新讨伐当前首领") {
                Stepper(value: Binding(
                    get: { settings.reviveRetryCount },
                    set: { appState.saveAutoBossSettings(reviveRetryCount: $0) }), in: 0...99) {
                    Text("\(settings.reviveRetryCount)").frame(minWidth: 30, alignment: .trailing)
                }
            }
        } else { settingsLoading }
    }

    @ViewBuilder
    private var autoDomainSettings: some View {
        if let settings = appState.autoDomainSettings {
            BGISettingLine(title: "选择战斗策略", subtitle: "用于战斗") {
                Picker("", selection: Binding(
                    get: { settings.strategyName },
                    set: { appState.saveAutoDomainSettings(strategyName: $0) })) {
                    ForEach(settings.strategyOptions, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 220)
            }
            BGISettingLine(title: "自动切换到指定队伍", subtitle: "注意队伍名称是游戏内手动设置的名称") {
                TextField("队伍名称", text: Binding(
                    get: { settings.partyName },
                    set: { appState.saveAutoDomainSettings(partyName: $0) }))
                    .frame(width: 200)
            }
            BGISettingLine(title: "指定要前往的秘境", subtitle: "自动传送到刷取的秘境") {
                Picker("", selection: Binding(
                    get: { settings.domainName },
                    set: { appState.saveAutoDomainSettings(domainName: $0) })) {
                    Text("未选择").tag("")
                    ForEach(settings.domainOptions, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 220)
            }
            BGISettingLine(title: "指定每种树脂刷取次数", subtitle: "关闭时优先使用浓缩树脂，然后使用原粹树脂") {
                Toggle("", isOn: Binding(
                    get: { settings.specifyResinUse },
                    set: { appState.saveAutoDomainSettings(specifyResinUse: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            if settings.specifyResinUse {
                domainCountLine("原粹树脂刷取次数", value: Binding(
                    get: { settings.originalResinUseCount },
                    set: { appState.saveAutoDomainSettings(originalResinUseCount: $0) }))
                domainCountLine("浓缩树脂刷取次数", value: Binding(
                    get: { settings.condensedResinUseCount },
                    set: { appState.saveAutoDomainSettings(condensedResinUseCount: $0) }))
                domainCountLine("须臾树脂刷取次数", value: Binding(
                    get: { settings.transientResinUseCount },
                    set: { appState.saveAutoDomainSettings(transientResinUseCount: $0) }))
                domainCountLine("脆弱树脂刷取次数", value: Binding(
                    get: { settings.fragileResinUseCount },
                    set: { appState.saveAutoDomainSettings(fragileResinUseCount: $0) }))
            }
            BGISettingLine(title: "结束后自动分解圣遗物", subtitle: "选择需要快速分解圣遗物的最高星级") {
                HStack(spacing: 12) {
                    Picker("", selection: Binding(
                        get: { settings.maxArtifactStar },
                        set: { appState.saveAutoDomainSettings(maxArtifactStar: $0) })) {
                        ForEach(settings.maxArtifactStarOptions, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 70)
                    Toggle("", isOn: Binding(
                        get: { settings.autoArtifactSalvage },
                        set: { appState.saveAutoDomainSettings(autoArtifactSalvage: $0) }))
                        .toggleStyle(.switch).labelsHidden()
                }
            }
            BGISettingLine(title: "战斗完成后等待时间（秒）", subtitle: "寻找石化古树前等待角色技能完全结束") {
                TextField("", value: Binding(
                    get: { settings.fightEndDelay },
                    set: { appState.saveAutoDomainSettings(fightEndDelay: $0) }), format: .number)
                    .frame(width: 90).multilineTextAlignment(.trailing)
            }
            BGISettingLine(title: "寻找古树时使用小步伐行走", subtitle: "仅用于识别较慢的计算机") {
                Toggle("", isOn: Binding(
                    get: { settings.shortMovement },
                    set: { appState.saveAutoDomainSettings(shortMovement: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(title: "步行前往开启秘境和领取奖励", subtitle: "用于 F 点击不到的情况") {
                Toggle("", isOn: Binding(
                    get: { settings.walkToF },
                    set: { appState.saveAutoDomainSettings(walkToF: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(title: "寻找古树时左右移动次数", subtitle: "正常用户不建议修改") {
                TextField("", value: Binding(
                    get: { settings.leftRightMoveTimes },
                    set: { appState.saveAutoDomainSettings(leftRightMoveTimes: $0) }), format: .number)
                    .frame(width: 90).multilineTextAlignment(.trailing)
            }
            BGISettingLine(title: "自动吃药", subtitle: "装备便携营养袋后，红血时自动按 Z 键吃药") {
                Toggle("", isOn: Binding(
                    get: { settings.autoEat },
                    set: { appState.saveAutoDomainSettings(autoEat: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(title: "启用奖励识别", subtitle: "每轮领取后识别奖励名称与数量，任务结束打印汇总") {
                Toggle("", isOn: Binding(
                    get: { settings.rewardRecognitionEnabled },
                    set: { appState.saveAutoDomainSettings(rewardRecognitionEnabled: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(title: "角色死亡后重试次数", subtitle: "秘境战斗中发生角色死亡时重试") {
                TextField("", value: Binding(
                    get: { settings.reviveRetryCount },
                    set: { appState.saveAutoDomainSettings(reviveRetryCount: $0) }), format: .number)
                    .frame(width: 90).multilineTextAlignment(.trailing)
            }
        } else { settingsLoading }
    }

    @ViewBuilder
    private var autoLeyLineOutcropSettings: some View {
        if let settings = appState.autoLeyLineOutcropSettings {
            BGISettingLine(title: "地脉花类型", subtitle: "启示之花（经验书）或藏金之花（摩拉）") {
                Picker("", selection: Binding(
                    get: { settings.leyLineOutcropType },
                    set: { appState.saveAutoLeyLineOutcropSettings(leyLineOutcropType: $0) })) {
                    ForEach(settings.leyLineOutcropTypeOptions, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 150)
            }
            BGISettingLine(title: "国家", subtitle: "按国家选择刷取对应的地脉花") {
                Picker("", selection: Binding(
                    get: { settings.country },
                    set: { appState.saveAutoLeyLineOutcropSettings(country: $0) })) {
                    ForEach(settings.countryOptions, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 130)
            }
            BGISettingLine(title: "选择战斗策略", subtitle: "用于地脉花战斗") {
                Picker("", selection: Binding(
                    get: { settings.strategyName },
                    set: { appState.saveAutoLeyLineOutcropSettings(strategyName: $0) })) {
                    Text("跟随自动战斗配置").tag("")
                    ForEach(settings.strategyOptions, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 220)
            }
            CoreTextSettingLine(
                title: "根据技能 CD 优化出招人员",
                subtitle: "填写角色名或角色名与 CD，多个配置以分号分隔",
                value: settings.actionSchedulerByCd,
                onSave: { appState.saveAutoLeyLineOutcropSettings(actionSchedulerByCd: $0) })
            leyLineToggle("旋转寻找敌人位置", "战斗时按设置间隔靠近或旋转寻找敌人",
                value: Binding(get: { settings.seekEnemyEnabled },
                    set: { appState.saveAutoLeyLineOutcropSettings(seekEnemyEnabled: $0) }))
            if settings.seekEnemyEnabled {
                BGISettingLine(title: "旋转寻找敌人速度", subtitle: "上游建议单次旋转约 360 度") {
                    Slider(value: Binding(
                        get: { Double(settings.seekEnemyRotaryFactor) },
                        set: { appState.saveAutoLeyLineOutcropSettings(
                            seekEnemyRotaryFactor: Int($0.rounded())) }), in: 1...13, step: 1)
                        .frame(width: 180)
                }
                BGISettingLine(title: "寻敌间隔（秒）", subtitle: "最小 1 秒") {
                    Stepper(value: Binding(
                        get: { settings.seekEnemyIntervalSeconds },
                        set: { appState.saveAutoLeyLineOutcropSettings(
                            seekEnemyIntervalSeconds: $0) }), in: 1...60) {
                        Text("\(settings.seekEnemyIntervalSeconds)").frame(minWidth: 36)
                    }
                }
            }
            leyLineToggle("聚集材料动作", "战斗结束后使用万叶或琴长 E 聚集材料",
                value: Binding(get: { settings.kazuhaPickupEnabled },
                    set: { appState.saveAutoLeyLineOutcropSettings(kazuhaPickupEnabled: $0) }))
            if settings.kazuhaPickupEnabled {
                leyLineToggle("琴二次拾取", "首次拾取为空时再次执行拾取",
                    value: Binding(get: { settings.qinDoublePickUp },
                        set: { appState.saveAutoLeyLineOutcropSettings(qinDoublePickUp: $0) }))
            }
            leyLineToggle("领取奖励后扫描掉落物光柱", "短时间扫描周围掉落物并靠近拾取",
                value: Binding(get: { settings.scanDropsAfterRewardEnabled },
                    set: { appState.saveAutoLeyLineOutcropSettings(
                        scanDropsAfterRewardEnabled: $0) }))
            if settings.scanDropsAfterRewardEnabled {
                BGISettingLine(title: "领奖后扫描时长（秒）", subtitle: "0 表示不扫描") {
                    Stepper(value: Binding(
                        get: { settings.scanDropsAfterRewardSeconds },
                        set: { appState.saveAutoLeyLineOutcropSettings(
                            scanDropsAfterRewardSeconds: $0) }), in: 0...60) {
                        Text("\(settings.scanDropsAfterRewardSeconds)").frame(minWidth: 36)
                    }
                }
            }
            leyLineToggle("树脂耗尽模式", "按当前树脂与库存自动计算可刷次数",
                value: Binding(get: { settings.isResinExhaustionMode },
                    set: { appState.saveAutoLeyLineOutcropSettings(
                        isResinExhaustionMode: $0) }))
            leyLineToggle("刷取次数取小值", "与手动次数取最小值，避免超过树脂可用次数",
                value: Binding(get: { settings.openModeCountMin },
                    set: { appState.saveAutoLeyLineOutcropSettings(openModeCountMin: $0) }))
            BGISettingLine(title: "刷取次数", subtitle: "树脂耗尽模式关闭或统计失败时使用") {
                Stepper(value: Binding(get: { settings.count },
                    set: { appState.saveAutoLeyLineOutcropSettings(count: $0) }), in: 1...999) {
                    Text("\(settings.count)").frame(minWidth: 36)
                }
            }
            leyLineToggle("使用须臾树脂", "原粹与浓缩耗尽后允许继续刷取",
                value: Binding(get: { settings.useTransientResin },
                    set: { appState.saveAutoLeyLineOutcropSettings(useTransientResin: $0) }))
            leyLineToggle("使用脆弱树脂", "原粹与浓缩耗尽后允许继续刷取",
                value: Binding(get: { settings.useFragileResin },
                    set: { appState.saveAutoLeyLineOutcropSettings(useFragileResin: $0) }))
            CoreTextSettingLine(title: "战斗队伍名称", subtitle: "留空则不切换；配置好感队时必须填写",
                value: settings.team,
                onSave: { appState.saveAutoLeyLineOutcropSettings(team: $0) })
            CoreTextSettingLine(title: "好感队名称", subtitle: "领取奖励前切换；留空则不切换",
                value: settings.friendshipTeam,
                onSave: { appState.saveAutoLeyLineOutcropSettings(friendshipTeam: $0) })
            BGISettingLine(title: "战斗超时时间（秒）", subtitle: "到达指定时间后自动停止战斗") {
                Stepper(value: Binding(get: { settings.timeout },
                    set: { appState.saveAutoLeyLineOutcropSettings(timeout: $0) }), in: 1...9999) {
                    Text("\(settings.timeout)").frame(minWidth: 48)
                }
            }
            leyLineToggle("不使用冒险之证寻路", "改用内置路线定位地脉花",
                value: Binding(get: { settings.useAdventurerHandbook },
                    set: { appState.saveAutoLeyLineOutcropSettings(useAdventurerHandbook: $0) }))
            leyLineToggle("发送通知", "任务完成或失败时通过通知系统发送提醒",
                value: Binding(get: { settings.isNotification },
                    set: { appState.saveAutoLeyLineOutcropSettings(isNotification: $0) }))
        } else { settingsLoading }
    }

    @ViewBuilder
    private var autoStygianOnslaughtSettings: some View {
        if let settings = appState.autoStygianOnslaughtSettings {
            BGISettingLine(title: "选择战斗策略", subtitle: "用于战斗") {
                Picker("", selection: Binding(
                    get: { settings.strategyName },
                    set: { appState.saveAutoStygianOnslaughtSettings(strategyName: $0) })) {
                    Text("跟随自动战斗配置").tag("")
                    ForEach(settings.strategyOptions, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 220)
            }
            BGISettingLine(title: "指定刷取的战场", subtitle: "从上到下战场一、二、三") {
                Picker("", selection: Binding(
                    get: { settings.bossNum },
                    set: { appState.saveAutoStygianOnslaughtSettings(bossNum: $0) })) {
                    ForEach(settings.bossNumOptions, id: \.self) { Text("\($0)").tag($0) }
                }.labelsHidden().frame(width: 90)
            }
            CoreTextSettingLine(
                title: "指定战斗队伍",
                subtitle: "输入预设队伍的名称，留空则不更换队伍",
                value: settings.fightTeamName,
                onSave: { appState.saveAutoStygianOnslaughtSettings(fightTeamName: $0) })
            BGISettingLine(
                title: "刷取至树脂耗尽",
                subtitle: "优先使用浓缩树脂，然后使用原粹树脂，其余树脂不使用"
            ) {
                Toggle("", isOn: Binding(
                    get: { !settings.specifyResinUse },
                    set: { appState.saveAutoStygianOnslaughtSettings(specifyResinUse: !$0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            BGISettingLine(title: "指定每种树脂刷取次数", subtitle: "开启后会根据配置的次数使用对应的树脂") {
                Toggle("", isOn: Binding(
                    get: { settings.specifyResinUse },
                    set: { appState.saveAutoStygianOnslaughtSettings(specifyResinUse: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            if settings.specifyResinUse {
                stygianResinCountLine("原粹树脂刷取次数", value: Binding(
                    get: { settings.originalResinUseCount },
                    set: { appState.saveAutoStygianOnslaughtSettings(originalResinUseCount: $0) }))
                stygianResinCountLine("浓缩树脂刷取次数", value: Binding(
                    get: { settings.condensedResinUseCount },
                    set: { appState.saveAutoStygianOnslaughtSettings(condensedResinUseCount: $0) }))
                stygianResinCountLine("须臾树脂刷取次数", value: Binding(
                    get: { settings.transientResinUseCount },
                    set: { appState.saveAutoStygianOnslaughtSettings(transientResinUseCount: $0) }))
                stygianResinCountLine("脆弱树脂刷取次数", value: Binding(
                    get: { settings.fragileResinUseCount },
                    set: { appState.saveAutoStygianOnslaughtSettings(fragileResinUseCount: $0) }))
            }
            BGISettingLine(title: "结束后自动分解圣遗物", subtitle: "需要快速分解圣遗物的最高星级") {
                HStack(spacing: 10) {
                    Picker("", selection: Binding(
                        get: { settings.maxArtifactStar },
                        set: { appState.saveAutoStygianOnslaughtSettings(maxArtifactStar: $0) })) {
                        ForEach(settings.maxArtifactStarOptions, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 80)
                    Toggle("", isOn: Binding(
                        get: { settings.autoArtifactSalvage },
                        set: { appState.saveAutoStygianOnslaughtSettings(autoArtifactSalvage: $0) }))
                        .toggleStyle(.switch).labelsHidden()
                }
            }
        } else { settingsLoading }
    }

    private func stygianResinCountLine(_ title: String, value: Binding<Int>) -> some View {
        BGISettingLine(title: title, subtitle: "最小 0 次") {
            TextField("", value: value, format: .number)
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
        }
    }

    private func leyLineToggle(
        _ title: String, _ subtitle: String, value: Binding<Bool>
    ) -> some View {
        BGISettingLine(title: title, subtitle: subtitle) {
            Toggle("", isOn: value).toggleStyle(.switch).labelsHidden()
        }
    }

    @ViewBuilder
    private var autoArtifactSalvageSettings: some View {
        if let settings = appState.autoArtifactSalvageSettings {
            AutoArtifactSalvageSettingsEditor(settings: settings)
        } else { settingsLoading }
    }

    @ViewBuilder
    private var autoFightSettings: some View {
        if let settings = appState.autoFightSettings {
            BGISettingLine(title: "选择战斗策略", subtitle: "用于战斗") {
                Picker("", selection: Binding(
                    get: { settings.strategyName },
                    set: { appState.saveAutoFightSettings(strategyName: $0) })) {
                    ForEach(settings.strategyOptions, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 220)
            }
            CoreTextSettingLine(
                title: "根据技能 CD 优化出招人员",
                subtitle: "填写角色名或角色名与 CD，多种使用分号分隔",
                value: settings.actionSchedulerByCd,
                onSave: { appState.saveAutoFightSettings(actionSchedulerByCd: $0) })

            fightSectionTitle("自动检测战斗结束")
            fightToggleLine("启用战斗结束检测", "检测到战斗结束时停止自动战斗",
                value: Binding(get: { settings.fightFinishDetectEnabled },
                    set: { appState.saveAutoFightSettings(fightFinishDetectEnabled: $0) }))
            fightToggleLine("更快检查结束战斗", "按时间或指定角色完成一轮操作后检查",
                value: Binding(get: { settings.fastCheckEnabled },
                    set: { appState.saveAutoFightSettings(fastCheckEnabled: $0) }))
            if settings.fastCheckEnabled {
                CoreTextSettingLine(
                    title: "更快检查结束战斗参数",
                    subtitle: "例如：5;白术;钟离;",
                    value: settings.fastCheckParams,
                    onSave: { appState.saveAutoFightSettings(fastCheckParams: $0) })
            }
            fightToggleLine("旋转寻找敌人位置", "打开队伍界面检测前先判断是否需要靠近或旋转",
                value: Binding(get: { settings.rotateFindEnemyEnabled },
                    set: { appState.saveAutoFightSettings(rotateFindEnemyEnabled: $0) }))
            if settings.rotateFindEnemyEnabled {
                BGISettingLine(title: "旋转速度", subtitle: "上游范围 1-13，建议单次约 360°") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { Double(settings.rotaryFactor) },
                            set: { appState.saveAutoFightSettings(rotaryFactor: Int($0.rounded())) }),
                            in: 1...13, step: 1).frame(width: 150)
                        Text("\(settings.rotaryFactor)").frame(width: 24)
                    }
                }
                fightToggleLine("Q 前检测", "释放元素爆发前检查战斗是否结束",
                    value: Binding(get: { settings.checkBeforeBurst },
                        set: { appState.saveAutoFightSettings(checkBeforeBurst: $0) }))
                fightToggleLine("尝试面敌", "开战寻敌时尝试面向敌人",
                    value: Binding(get: { settings.isFirstCheck },
                        set: { appState.saveAutoFightSettings(isFirstCheck: $0) }))
            }
            CoreTextSettingLine(
                title: "检查战斗结束的延时",
                subtitle: "可为默认秒数或角色与秒数组合",
                value: settings.checkEndDelay,
                onSave: { appState.saveAutoFightSettings(checkEndDelay: $0) })
            CoreTextSettingLine(
                title: "按键触发后检查延时",
                subtitle: "按下切换队伍后检查屏幕色块前的延时",
                value: settings.beforeDetectDelay,
                onSave: { appState.saveAutoFightSettings(beforeDetectDelay: $0) })

            fightSectionTitle("盾奶位角色优先释放技能")
            BGISettingLine(title: "盾奶位角色在队伍中的位置", subtitle: "空选关闭实时盾奶技能检测") {
                Picker("", selection: Binding(
                    get: { settings.guardianAvatar },
                    set: { appState.saveAutoFightSettings(guardianAvatar: $0) })) {
                    ForEach(settings.guardianAvatarOptions, id: \.self) {
                        Text($0.isEmpty ? "关闭" : $0).tag($0)
                    }
                }.labelsHidden().frame(width: 90)
            }
            if !settings.guardianAvatar.isEmpty {
                fightToggleLine("禁用该角色的 E 战斗策略", "自动释放盾奶位 E 技能",
                    value: Binding(get: { settings.guardianCombatSkip },
                        set: { appState.saveAutoFightSettings(guardianCombatSkip: $0) }))
                fightToggleLine("自动释放 Q 爆发", "盾奶位可用时自动释放元素爆发",
                    value: Binding(get: { settings.burstEnabled },
                        set: { appState.saveAutoFightSettings(burstEnabled: $0) }))
                fightToggleLine("盾奶位 E 长按", "关闭为短按，开启为长按",
                    value: Binding(get: { settings.guardianAvatarHold },
                        set: { appState.saveAutoFightSettings(guardianAvatarHold: $0) }))
            }

            fightSectionTitle("战后拾取")
            fightToggleLine("扫描掉落物光柱", "战斗结束后旋转视角寻找掉落物并靠近",
                value: Binding(get: { settings.pickDropsAfterFightEnabled },
                    set: { appState.saveAutoFightSettings(pickDropsAfterFightEnabled: $0) }))
            if settings.pickDropsAfterFightEnabled {
                BGISettingLine(title: "扫描掉落物光柱时长", subtitle: "单位为秒；0 表示不扫描") {
                    Stepper(value: Binding(
                        get: { settings.pickDropsAfterFightSeconds },
                        set: { appState.saveAutoFightSettings(pickDropsAfterFightSeconds: $0) }),
                        in: 0...300) {
                        Text("\(settings.pickDropsAfterFightSeconds)").frame(minWidth: 38)
                    }
                }
            }
            fightToggleLine("聚集材料动作", "战斗结束后使用万叶或琴长 E 聚集材料",
                value: Binding(get: { settings.kazuhaPickupEnabled },
                    set: { appState.saveAutoFightSettings(kazuhaPickupEnabled: $0) }))
            if settings.kazuhaPickupEnabled {
                fightToggleLine("琴二次拾取", "首次拾取为空时再次执行拾取",
                    value: Binding(get: { settings.qinDoublePickUp },
                        set: { appState.saveAutoFightSettings(qinDoublePickUp: $0) }))
                fightToggleLine("基于经验值判断拾取", "未检测到精英怪经验值时跳过拾取",
                    value: Binding(get: { settings.expBasedPickupEnabled },
                        set: { appState.saveAutoFightSettings(expBasedPickupEnabled: $0) }))
            }
            BGISettingLine(title: "自动战斗超时（秒）", subtitle: "到达指定时间后自动停止战斗") {
                Stepper(value: Binding(
                    get: { settings.timeout },
                    set: { appState.saveAutoFightSettings(timeout: $0) }), in: 1...3600) {
                    Text("\(settings.timeout)").frame(minWidth: 48)
                }
            }
            fightToggleLine("游泳检测", "自动战斗中检测游泳，先回战斗节点，失败则去七天神像",
                value: Binding(get: { settings.swimmingEnabled },
                    set: { appState.saveAutoFightSettings(swimmingEnabled: $0) }))
        } else { settingsLoading }
    }

    private func fightSectionTitle(_ title: String) -> some View {
        Text(title).font(.headline).foregroundStyle(BGIColors.primaryText).padding(.top, 6)
    }

    private func fightToggleLine(
        _ title: String, _ subtitle: String, value: Binding<Bool>
    ) -> some View {
        BGISettingLine(title: title, subtitle: subtitle) {
            Toggle("", isOn: value)
                .toggleStyle(.switch).labelsHidden()
        }
    }

    private func domainCountLine(_ title: String, value: Binding<Int>) -> some View {
        BGISettingLine(title: title, subtitle: "最小 0 次") {
            Stepper(value: value, in: 0...999) {
                Text("\(value.wrappedValue)").frame(minWidth: 36, alignment: .trailing)
            }
        }
    }

    private var settingsLoading: some View {
        BGISettingLine(title: "设置", subtitle: "正在从 BetterGI C# Core 读取") {
            ProgressView().controlSize(.small)
        }
    }

    private func isRunning(_ name: String) -> Bool {
        appState.soloTaskStatus.name == name &&
            ["running", "stopping"].contains(appState.soloTaskStatus.state)
    }

    private func icon(for name: String) -> BGIIcon {
        switch name {
        case "AutoFishing": .fgi("\u{e3a8}")
        case "AutoRedeemCode": .symbol("barcode.viewfinder")
        default: .symbol("gearshape.2")
        }
    }

    private func detail(for name: String) -> String {
        switch name {
        case "AutoFishing":
            "在出现钓鱼交互提示的位置启动；识别、抛竿和收杆均由共享 C# 任务执行。"
        case "AutoRedeemCode":
            "输入兑换码后，由 BetterGI C# Core 打开设置并逐条兑换。"
        default:
            "BetterGI C# Core 独立任务。"
        }
    }
}

private struct AutoArtifactSalvageSettingsEditor: View {
    @EnvironmentObject private var appState: AppState
    let settings: BetterGICoreAutoArtifactSalvageSettings
    @State private var javaScript: String
    @State private var artifactSetFilter: String

    init(settings: BetterGICoreAutoArtifactSalvageSettings) {
        self.settings = settings
        _javaScript = State(initialValue: settings.javaScript)
        _artifactSetFilter = State(initialValue: settings.artifactSetFilter)
    }

    var body: some View {
        BGISettingLine(title: "JavaScript", subtitle: "只要满足脚本条件的五星圣遗物都会被选中") {
            Button("保存脚本") {
                appState.saveAutoArtifactSalvageSettings(
                    javaScript: javaScript, artifactSetFilter: artifactSetFilter)
            }
            .buttonStyle(.bordered)
        }
        TextEditor(text: $javaScript)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 130)
            .padding(8)
            .background(BGIColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        BGISettingLine(
            title: "按套装筛选",
            subtitle: "一般填写套装内生之花名，可填入多个名称；留空则不用"
        ) {
            TextField("套装名称", text: $artifactSetFilter)
                .frame(width: 260)
                .onSubmit {
                    appState.saveAutoArtifactSalvageSettings(
                        javaScript: javaScript, artifactSetFilter: artifactSetFilter)
                }
        }
        BGISettingLine(title: "需要快速分解圣遗物的最高星级", subtitle: "先会进行一次快速分解选择") {
            Picker("", selection: Binding(
                get: { settings.maxArtifactStar },
                set: { appState.saveAutoArtifactSalvageSettings(maxArtifactStar: $0) })) {
                ForEach(settings.maxArtifactStarOptions, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: 80)
        }
        BGISettingLine(title: "最大检查数量", subtitle: "达到最大检查数量后也会停止") {
            Stepper(value: Binding(
                get: { settings.maxNumToCheck },
                set: { appState.saveAutoArtifactSalvageSettings(maxNumToCheck: $0) }),
                    in: 1...9999) {
                Text("\(settings.maxNumToCheck)").frame(minWidth: 48, alignment: .trailing)
            }
        }
        BGISettingLine(title: "识别失败策略", subtitle: "识别单个圣遗物面板信息失败时，是跳过还是终止") {
            Picker("", selection: Binding(
                get: { settings.recognitionFailurePolicy },
                set: { appState.saveAutoArtifactSalvageSettings(recognitionFailurePolicy: $0) })) {
                ForEach(settings.recognitionFailurePolicyOptions) { option in
                    Text(option.displayName).tag(option.value)
                }
            }
            .labelsHidden().frame(width: 100)
        }
    }
}

private struct CoreTextSettingLine: View {
    let title: String
    let subtitle: String
    let onSave: (String) -> Void
    @State private var draft: String
    @FocusState private var focused: Bool

    init(title: String, subtitle: String, value: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.onSave = onSave
        _draft = State(initialValue: value)
    }

    var body: some View {
        BGISettingLine(title: title, subtitle: subtitle) {
            TextField("", text: $draft)
                .frame(width: 260)
                .focused($focused)
                .onSubmit { onSave(draft) }
                .onChange(of: focused) { wasFocused, isFocused in
                    if wasFocused && !isFocused { onSave(draft) }
                }
        }
    }
}
