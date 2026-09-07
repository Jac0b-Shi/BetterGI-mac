import SwiftUI

struct SettingsPage: View {
    @EnvironmentObject private var appState: AppState
    @State private var miyousheCookieDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "软件设置")

            if let settings = appState.commonSettings {
                BGISettingGroup(
                    icon: "globe",
                    title: "语言",
                    subtitle: "任务识别文本与界面语言配置；更改后重启生效，缺失资源回退简体中文。"
                ) { EmptyView() } content: {
                    BGISettingLine(title: "游戏语言", subtitle: "决定 OCR 与任务提示所使用的本地化资源。") {
                        Picker("", selection: Binding(
                            get: { settings.gameCultureInfoName },
                            set: { appState.saveCommonSettings(gameCultureInfoName: $0) })) {
                            ForEach(settings.cultureOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    BGISettingLine(title: "界面语言", subtitle: "与上游语言目录保持一致。") {
                        Picker("", selection: Binding(
                            get: { settings.uiCultureInfoName },
                            set: { appState.saveCommonSettings(uiCultureInfoName: $0) })) {
                            ForEach(settings.cultureOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                }

                BGISettingGroup(
                    icon: "photo",
                    title: "主窗口背景",
                    subtitle: "背景图片由 Core 复制到运行目录；原文件移动后仍可继续使用。"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.mainBackgroundEnabled },
                        set: { appState.saveCommonSettings(mainBackgroundEnabled: $0) }))
                        .labelsHidden()
                } content: {
                    BGISettingLine(title: "背景图片", subtitle: settings.mainBackgroundImagePath.isEmpty
                        ? "尚未选择图片" : settings.mainBackgroundImagePath) {
                        Button("选择并导入") { appState.selectMainBackgroundImage() }
                        Button("清除") { appState.clearMainBackgroundImage() }
                        .disabled(settings.mainBackgroundImagePath.isEmpty)
                    }
                    BGISettingLine(title: "显示方式", subtitle: "填充会裁剪边缘，适应会完整显示图片。") {
                        Picker("", selection: Binding(
                            get: { settings.mainBackgroundStretch },
                            set: { appState.saveCommonSettings(mainBackgroundStretch: $0) })) {
                            ForEach(settings.mainBackgroundStretchOptions, id: \.self) { option in
                                Text(option == "UniformToFill" ? "填充裁剪" :
                                    option == "Uniform" ? "完整适应" : "拉伸").tag(option)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    BGISettingLine(title: "背景不透明度", subtitle: "降低数值可提升前景文字可读性。") {
                        Slider(value: Binding(
                            get: { settings.mainBackgroundOpacity },
                            set: { appState.saveCommonSettings(mainBackgroundOpacity: $0) }), in: 0...1)
                            .frame(width: 180)
                        Text(String(format: "%.0f%%", settings.mainBackgroundOpacity * 100))
                            .frame(width: 48)
                    }
                }
            }

            BGISettingGroup(icon: "square.on.square", title: "启用遮罩窗口", subtitle: "重启后生效；macOS 版使用 NSPanel 作为游戏上方 HUD。") {
                Toggle("", isOn: Binding(get: { appState.isHUDVisible }, set: { _ in appState.toggleHUD() }))
                    .labelsHidden()
            } content: {
                BGISettingLine(title: "显示日志窗口", subtitle: "在遮罩内显示日志窗口，右下角持续展示最近运行日志。") {
                    Toggle("", isOn: $appState.showOverlayLogBox)
                        .labelsHidden()
                }
                BGISettingLine(
                    title: "HUD 最低日志等级",
                    subtitle: "低于该等级的日志不会显示在游戏叠加层中。"
                ) {
                    Picker("", selection: $appState.hudMinimumLogLevel) {
                        ForEach(LogLevel.allCases) { level in
                            Text(level.settingsTitle).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                BGISettingLine(title: "显示实时任务启用状态", subtitle: "在遮罩内显示实时任务启用状态。") {
                    Toggle("", isOn: $appState.showOverlayStatus)
                        .labelsHidden()
                }
                BGISettingLine(title: "启用拖拽调整位置大小", subtitle: "开启后可以拖拽调整日志、状态栏与指标栏位置，并调整大小。") {
                    Toggle("", isOn: $appState.overlayLayoutEditEnabled)
                        .labelsHidden()
                    Button("重置位置") {
                        appState.overlayLayoutEditEnabled = false
                    }
                }
                BGISettingLine(title: "显示遮罩指标栏", subtitle: "显示游戏帧率、处理耗时和硬件占用，指标项可单独选择。") {
                    Toggle("", isOn: $appState.showOverlayMetrics)
                        .labelsHidden()
                }
                BGISettingLine(title: "显示遮罩边框", subtitle: "围绕游戏窗口显示边框线，用于确认叠加层覆盖范围。") {
                    Toggle("", isOn: $appState.showOverlayBorder)
                        .labelsHidden()
                }
                BGISettingLine(title: "显示图像识别结果", subtitle: "实时显示各种图像识别的结果。") {
                    Toggle("", isOn: $appState.showOverlayRecognition)
                        .labelsHidden()
                }
                BGISettingLine(title: "启用UID遮盖", subtitle: "遮盖右下角 UID 区域。") {
                    Toggle("", isOn: Binding(
                        get: {
                            appState.commonSettings?.screenshotUidCoverEnabled
                                ?? appState.overlayUidCoverEnabled
                        },
                        set: { appState.saveCommonSettings(screenshotUidCoverEnabled: $0) }))
                        .labelsHidden()
                        .disabled(appState.commonSettings == nil)
                }
                BGISettingLine(title: "显示小地图方位", subtitle: "在小地图周围显示东南西北文字。") {
                    Toggle("", isOn: $appState.showOverlayDirections)
                        .labelsHidden()
                }
                BGISettingLine(title: "显示地图点位与路径", subtitle: "显示已选并投影到大地图和小地图的点位。") {
                    Toggle("", isOn: $appState.showOverlayMapPoints)
                        .labelsHidden()
                }
                BGISettingLine(title: "HUD 透明度", subtitle: "控制游戏窗口上方状态浮层背景透明度。") {
                    Slider(value: $appState.hudOpacity, in: 0.35...0.95)
                        .frame(width: 180)
                    Text(String(format: "%.0f%%", appState.hudOpacity * 100))
                        .font(BGIFonts.console)
                        .foregroundStyle(BGIColors.primaryText)
                        .frame(width: 48)
                }
                BGISettingLine(title: "HUD 最大日志行数", subtitle: "控制右下角 HUD 底部最近日志条数。") {
                    Stepper("\(appState.hudMaxLogLines)", value: $appState.hudMaxLogLines, in: 3...8)
                        .foregroundStyle(BGIColors.primaryText)
                }
            }

            BGISettingGroup(
                icon: "doc.text",
                title: "日志",
                subtitle: "控制 MacGI 本地运行日志文件的记录范围。"
            ) {
                EmptyView()
            } content: {
                BGISettingLine(
                    title: "文件日志最低等级",
                    subtitle: "低于该等级的日志不会写入本地运行日志文件。"
                ) {
                    Picker("", selection: $appState.fileMinimumLogLevel) {
                        ForEach(LogLevel.allCases) { level in
                            Text(level.settingsTitle).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }

            BGISettingGroup(icon: "gearshape", title: "通用", subtitle: "betterGI-mac 软件本体设置。") {
                EmptyView()
            } content: {
                BGISettingLine(
                    title: "启用保存截图功能（开发者）",
                    subtitle: "可以通过快捷键保存截图，文件保存在 log/screenshot"
                ) {
                    Toggle("", isOn: Binding(
                        get: { appState.commonSettings?.screenshotEnabled ?? false },
                        set: { appState.saveCommonSettings(screenshotEnabled: $0) }))
                        .labelsHidden()
                        .disabled(appState.commonSettings == nil)
                }
                if let settings = appState.commonSettings {
                    BGISettingLine(
                        title: "地图追踪优先使用的特征匹配方式",
                        subtitle: "影响所有地图追踪功能，重启后生效"
                    ) {
                        Picker(
                            "",
                            selection: Binding(
                                get: { settings.mapMatchingMethod },
                                set: {
                                    appState.saveCommonSettings(
                                        mapMatchingMethod: $0)
                                })
                        ) {
                            ForEach(
                                settings.mapMatchingMethodOptions,
                                id: \.self
                            ) {
                                Text($0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }
                BGISettingLine(title: "启动时显示 HUD", subtitle: "启动后自动显示右下角状态浮层。") {
                    Toggle("", isOn: $appState.showHUDOnStart)
                        .labelsHidden()
                }
                BGISettingLine(title: "重置界面状态", subtitle: "重置捕获、核心、输入、窗口状态。") {
                    Button {
                        appState.resetUIState()
                    } label: {
                        Label("重置", systemImage: "arrow.counterclockwise")
                    }
                }
            }

            if let settings = appState.commonSettings {
                BGISettingGroup(
                    icon: "arrow.triangle.2.circlepath",
                    title: "启动时自动更新已订阅的脚本",
                    subtitle: "启动时自动同步脚本仓库并更新所有已订阅的脚本。"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.autoUpdateSubscribedScripts },
                        set: {
                            appState.saveCommonSettings(
                                autoUpdateSubscribedScripts: $0)
                        }))
                        .labelsHidden()
                } content: {
                    BGISettingLine(
                        title: "命令行启动时也自动更新",
                        subtitle: "通过命令行参数启动配置组或任务进度时，先等待脚本更新完成再执行。"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { settings.autoUpdateBeforeCommandLineRun },
                            set: {
                                appState.saveCommonSettings(
                                    autoUpdateBeforeCommandLineRun: $0)
                            }))
                            .labelsHidden()
                    }
                }

                BGISettingGroup(
                    icon: "clock.arrow.circlepath",
                    title: "无人值守",
                    subtitle: "调度器连续运行、服务器时间与任务恢复策略。"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.autoRestartEnabled },
                        set: { appState.saveCommonSettings(autoRestartEnabled: $0) }))
                        .labelsHidden()
                } content: {
                    BGISettingLine(
                        title: "自动领取派遣城市",
                        subtitle: "路径追踪打开大地图前检测并领取探索派遣。"
                    ) {
                        Picker("", selection: Binding(
                            get: { settings.autoFetchDispatchCountry },
                            set: { appState.saveCommonSettings(autoFetchDispatchCountry: $0) })) {
                            ForEach(settings.autoFetchDispatchCountryOptions, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .frame(width: 150)
                    }
                    BGISettingLine(
                        title: "服务器时区",
                        subtitle: "用于每日重置时间和脚本服务器时间。"
                    ) {
                        Picker("", selection: Binding(
                            get: { settings.serverTimeZoneOffsetHours },
                            set: { appState.saveCommonSettings(serverTimeZoneOffsetHours: $0) })) {
                            ForEach(settings.serverTimeZoneOffsetOptions, id: \.self) { offset in
                                Text(serverTimeZoneTitle(offset)).tag(offset)
                            }
                        }
                        .frame(width: 160)
                    }
                    BGISettingLine(
                        title: "连续异常次数",
                        subtitle: "调度器达到该次数后自动重启 BetterGI。"
                    ) {
                        Stepper(
                            "\(settings.autoRestartFailureCount)",
                            value: Binding(
                                get: { settings.autoRestartFailureCount },
                                set: {
                                    appState.saveCommonSettings(
                                        autoRestartFailureCount: $0)
                                }),
                            in: 1...100)
                    }
                    BGISettingLine(
                        title: "同时重启游戏",
                        subtitle: "仅在联动启动与自动进入游戏均启用时生效。"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { settings.autoRestartGameTogether },
                            set: {
                                appState.saveCommonSettings(
                                    autoRestartGameTogether: $0)
                            }))
                            .labelsHidden()
                    }
                    BGISettingLine(
                        title: "战斗失败算异常",
                        subtitle: "锄地脚本实际战斗成功次数不足时判定任务失败。"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { settings.fightFailureExceptional },
                            set: {
                                appState.saveCommonSettings(
                                    fightFailureExceptional: $0)
                            }))
                            .labelsHidden()
                    }
                    BGISettingLine(
                        title: "路径未走完算异常",
                        subtitle: "路径追踪未完整执行时判定任务失败。"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { settings.pathingFailureExceptional },
                            set: {
                                appState.saveCommonSettings(
                                    pathingFailureExceptional: $0)
                            }))
                            .labelsHidden()
                    }
                }

                BGISettingGroup(
                    icon: "chart.bar.doc.horizontal",
                    title: "锄地规划",
                    subtitle: "按每日统计与上限跳过后续锄地任务。"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.farmingPlanEnabled },
                        set: { appState.saveCommonSettings(farmingPlanEnabled: $0) }))
                        .labelsHidden()
                } content: {
                    BGISettingLine(
                        title: "本地统计上限",
                        subtitle: "每日精英与小怪数量上限。"
                    ) {
                        Stepper(
                            "精英 \(settings.farmingDailyEliteCap)",
                            value: Binding(
                                get: { settings.farmingDailyEliteCap },
                                set: { appState.saveCommonSettings(farmingDailyEliteCap: $0) }),
                            in: 0...10000)
                        Stepper(
                            "小怪 \(settings.farmingDailyMobCap)",
                            value: Binding(
                                get: { settings.farmingDailyMobCap },
                                set: { appState.saveCommonSettings(farmingDailyMobCap: $0) }),
                            in: 0...50000)
                    }
                    BGISettingLine(
                        title: "结合米游社数据",
                        subtitle: "使用旅行札记校正统计，数据通常存在数小时延迟。"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { settings.miyousheDataEnabled },
                            set: { appState.saveCommonSettings(miyousheDataEnabled: $0) }))
                            .labelsHidden()
                    }
                    BGISettingLine(
                        title: "米游社统计上限",
                        subtitle: "存在旅行札记数据时使用这组每日上限。"
                    ) {
                        Stepper(
                            "精英 \(settings.miyousheDailyEliteCap)",
                            value: Binding(
                                get: { settings.miyousheDailyEliteCap },
                                set: { appState.saveCommonSettings(miyousheDailyEliteCap: $0) }),
                            in: 0...10000)
                        Stepper(
                            "小怪 \(settings.miyousheDailyMobCap)",
                            value: Binding(
                                get: { settings.miyousheDailyMobCap },
                                set: { appState.saveCommonSettings(miyousheDailyMobCap: $0) }),
                            in: 0...50000)
                    }
                    BGISettingLine(
                        title: "米游社 Cookie",
                        subtitle: "仅保存在本机，用于获取旅行札记。"
                    ) {
                        SecureField("Cookie", text: $miyousheCookieDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 240, maxWidth: 420)
                        Button("保存") {
                            appState.saveCommonSettings(
                                miyousheCookie: miyousheCookieDraft)
                        }
                        .disabled(miyousheCookieDraft == settings.miyousheCookie)
                    }
                    BGISettingLine(
                        title: "同步日志分析 Cookie",
                        subtitle: "与调度器日志分析配置共用 Cookie。"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { settings.miyousheLogSyncCookie },
                            set: { appState.saveCommonSettings(miyousheLogSyncCookie: $0) }))
                            .labelsHidden()
                    }
                }
            }
        }
        .onAppear {
            miyousheCookieDraft = appState.commonSettings?.miyousheCookie ?? ""
        }
        .onChange(of: appState.commonSettings?.miyousheCookie) { _, value in
            miyousheCookieDraft = value ?? ""
        }
    }

    private func serverTimeZoneTitle(_ offset: Int) -> String {
        switch offset {
        case 8: "其他 UTC+08"
        case 1: "欧服 UTC+01"
        case -5: "美服 UTC-05"
        default: "UTC\(offset >= 0 ? "+" : "")\(offset)"
        }
    }
}
