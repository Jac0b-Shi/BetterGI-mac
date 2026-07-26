import SwiftUI

struct AutoSkipTriggerSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if let settings = appState.autoSkipTriggerSettings {
            Group {
                toggleLine(
                    "快速跳过对话文本",
                    "如果要听完整的主线语音，可以关闭此功能",
                    settings.quicklySkipConversationsEnabled
                ) { appState.saveAutoSkipTriggerSettings(quicklySkipConversationsEnabled: $0) }

                toggleLine(
                    "自定义优先对话选项",
                    "优先级高于选择选项优先级",
                    settings.customPriorityOptionsEnabled
                ) { appState.saveAutoSkipTriggerSettings(customPriorityOptionsEnabled: $0) }

                if settings.customPriorityOptionsEnabled {
                    BGISettingLine(
                        title: "自定义优先选项文本",
                        subtitle: "多个选项用中英文分号分隔，或者每行一个"
                    ) {
                        VStack(alignment: .trailing, spacing: 8) {
                            TextEditor(text: $appState.autoSkipCustomPriorityOptionsDraft)
                                .frame(width: 360, height: 100)
                                .overlay(Rectangle().stroke(BGIColors.border, lineWidth: 1))
                            Button("保存优先选项") {
                                appState.saveAutoSkipCustomPriorityOptions()
                            }
                        }
                    }
                }

                BGISettingLine(
                    title: "选择选项优先级",
                    subtitle: "进入对话后，对话选项的选择方式"
                ) {
                    Picker("", selection: Binding(
                        get: { settings.clickChatOption },
                        set: { appState.saveAutoSkipTriggerSettings(clickChatOption: $0) })) {
                        ForEach(settings.clickChatOptionOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                numberLine(
                    "选择对话选项前的延迟（毫秒）",
                    "方便在自动剧情时看清楚选项",
                    settings.afterChooseOptionSleepDelay
                ) { appState.saveAutoSkipTriggerSettings(afterChooseOptionSleepDelay: $0) }

                toggleLine(
                    "听完语音后再选择对话选项",
                    "检测游戏进程中的人声；无法读取声音时使用固定延迟",
                    settings.autoWaitDialogueOptionVoiceEnabled
                ) { appState.saveAutoSkipTriggerSettings(autoWaitDialogueOptionVoiceEnabled: $0) }

                if settings.autoWaitDialogueOptionVoiceEnabled {
                    numberLine(
                        "语音结束检测最大等待（秒）",
                        "最长 600 秒，超时后继续选择以避免卡住剧情",
                        settings.dialogueOptionVoiceMaxWaitSeconds
                    ) { appState.saveAutoSkipTriggerSettings(dialogueOptionVoiceMaxWaitSeconds: $0) }
                }

                numberLine(
                    "点击对话框确认按钮之前的延迟（毫秒）",
                    "方便在自动剧情时看完全部对话框文字",
                    settings.beforeClickConfirmDelay
                ) { appState.saveAutoSkipTriggerSettings(beforeClickConfirmDelay: $0) }

                toggleLine(
                    "自动提交物品",
                    "对话过程中出现提交物品界面时自动提交，支持多个物品",
                    settings.submitGoodsEnabled
                ) { appState.saveAutoSkipTriggerSettings(submitGoodsEnabled: $0) }

                toggleLine(
                    "自动关闭弹出页",
                    "关闭对话过程中出现的弹出页面，可能会误关地图或相机",
                    settings.closePopupPagedEnabled
                ) { appState.saveAutoSkipTriggerSettings(closePopupPagedEnabled: $0) }

                toggleLine(
                    "凯瑟琳 - 自动领取『每日委托』奖励",
                    "与凯瑟琳对话时自动领取每日委托奖励",
                    settings.autoGetDailyRewardsEnabled
                ) { appState.saveAutoSkipTriggerSettings(autoGetDailyRewardsEnabled: $0) }

                toggleLine(
                    "凯瑟琳 - 自动重新派遣",
                    "自动领取已完成探索的奖励，并重新派遣",
                    settings.autoReExploreEnabled
                ) { appState.saveAutoSkipTriggerSettings(autoReExploreEnabled: $0) }
            }
        }
    }

    private func toggleLine(
        _ title: String,
        _ subtitle: String,
        _ value: Bool,
        save: @escaping (Bool) -> Void
    ) -> some View {
        BGISettingLine(title: title, subtitle: subtitle) {
            Toggle("", isOn: Binding(get: { value }, set: { save($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func numberLine(
        _ title: String,
        _ subtitle: String,
        _ value: Int,
        save: @escaping (Int) -> Void
    ) -> some View {
        BGISettingLine(title: title, subtitle: subtitle) {
            TextField("", value: Binding(get: { value }, set: { save($0) }), format: .number)
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct AutoHangoutTriggerSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if let settings = appState.autoSkipTriggerSettings {
            toggleLine(
                "存在跳过按钮时自动点击",
                "邀约过程中左上角存在跳过按钮时候，自动点击跳过",
                settings.autoHangoutPressSkipEnabled
            ) { appState.saveAutoSkipTriggerSettings(autoHangoutPressSkipEnabled: $0) }

            BGISettingLine(
                title: "选择邀约分支（不支持气泡联想选择）",
                subtitle: "会按照选择分支的关键词进行选项选择"
            ) {
                Picker("", selection: Binding(
                    get: { settings.autoHangoutEndChoose },
                    set: { appState.saveAutoSkipTriggerSettings(autoHangoutEndChoose: $0) })) {
                    Text("不指定邀约分支").tag("")
                    ForEach(settings.autoHangoutEndChooseOptions, id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 260)
            }

            numberLine(
                "选择邀约选项前的延迟（毫秒）",
                "方便在自动邀约的情况下，依旧能够看清楚选项",
                settings.autoHangoutChooseOptionSleepDelay
            ) { appState.saveAutoSkipTriggerSettings(autoHangoutChooseOptionSleepDelay: $0) }
        }
    }

    private func toggleLine(
        _ title: String,
        _ subtitle: String,
        _ value: Bool,
        save: @escaping (Bool) -> Void
    ) -> some View {
        BGISettingLine(title: title, subtitle: subtitle) {
            Toggle("", isOn: Binding(get: { value }, set: { save($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func numberLine(
        _ title: String,
        _ subtitle: String,
        _ value: Int,
        save: @escaping (Int) -> Void
    ) -> some View {
        BGISettingLine(title: title, subtitle: subtitle) {
            TextField("", value: Binding(get: { value }, set: { save($0) }), format: .number)
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
        }
    }
}
