import SwiftUI

struct SettingsPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "软件设置")

            BGISettingGroup(icon: "globe", title: "软件UI语言", subtitle: "UI Language") {
                Text("暂不可更改")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: .constant("简体中文")) {
                    Text("简体中文").tag("简体中文")
                    Text("English").tag("English")
                }
                .frame(width: 160)
                .disabled(true)
            } content: {
                BGISettingLine(title: "原神游戏语言", subtitle: "Game Language") {
                    Picker("", selection: .constant("简体中文")) {
                        Text("简体中文").tag("简体中文")
                        Text("English").tag("English")
                    }
                    .frame(width: 160)
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
                    Toggle("", isOn: $appState.overlayUidCoverEnabled)
                        .labelsHidden()
                }
                BGISettingLine(title: "显示小地图方位", subtitle: "在小地图周围显示东南西北文字。") {
                    Toggle("", isOn: $appState.showOverlayDirections)
                        .labelsHidden()
                }
                BGISettingLine(title: "显示地图点位与路径", subtitle: "显示 Core 识别并投影到大地图和小地图的已选点位。") {
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

            BGIOriginalCard(icon: .symbol("camera"), title: "启用保存截图功能（开发者）", subtitle: "截图功能主要用于错误排查、训练素材快速获取等开发相关功能。") {
                Toggle("", isOn: .constant(false))
                    .labelsHidden()
            } content: {
                BGISettingLine(title: "截图快捷键", subtitle: "绑定保存截图的快捷键。") {
                    BGIUnavailableAction("绑定快捷键")
                }
                BGISettingLine(title: "截图遮盖UID", subtitle: "生成的截图会遮盖右下角 UID 区域。") {
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                }
            }

            BGIOriginalCard(icon: .symbol("arrow.triangle.2.circlepath"), title: "启动时自动更新已订阅的脚本", subtitle: "启动时自动同步脚本仓库并更新所有已订阅的脚本。") {
                Toggle("", isOn: .constant(true))
                    .labelsHidden()
            } content: {
                BGISettingLine(title: "命令行启动时也自动更新", subtitle: "通过命令行参数启动配置组/一条龙时，先等待脚本更新完成再执行。") {
                    Toggle("", isOn: .constant(false))
                        .labelsHidden()
                }
            }

            BGIOriginalCard(icon: .fgi("\u{f3c5}"), title: "大地图地图传送设置", subtitle: "用于地图追踪、自动秘境、一条龙等功能中传送功能的配置。") {
                Toggle("", isOn: .constant(true))
                    .labelsHidden()
            } content: {
                BGISettingLine(title: "地图移动过程中是否缩放地图", subtitle: "建议开启，关闭可能在运行部分脚本时发生错误。") {
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                }
                BGISettingLine(title: "单次鼠标移动的最大距离", subtitle: "过大可能会导致鼠标移动出窗口。") {
                    BGINumberField(value: "500", width: 90)
                }
                BGISettingLine(title: "地图缩小的距离", subtitle: "大于这个距离会缩小地图以加快传送。") {
                    BGINumberField(value: "900", width: 90)
                }
                BGISettingLine(title: "地图放大的距离", subtitle: "小于这个距离会放大地图以提高移动精度。") {
                    BGINumberField(value: "300", width: 90)
                }
                BGISettingLine(title: "鼠标移动的时间间隔（毫秒）", subtitle: "数字越小移动越快，如果移动地图时卡顿请提高。") {
                    BGINumberField(value: "8", width: 90)
                }
            }

            BGIOriginalCard(icon: .fgi("\u{f0fa}"), title: "七天神像设置", subtitle: "用于指定回血的七天神像。") {
                EmptyView()
            } content: {
                BGISettingLine(title: "是否就近七天神像恢复血量", subtitle: "启用后自动选择最近的七天神像，忽略下方指定位置。") {
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                }
                BGISettingLine(title: "传送到七天神像之后是否需要移动后回血", subtitle: "启用后将自动向七天神像方向移动。") {
                    Toggle("", isOn: .constant(false))
                        .labelsHidden()
                }
                BGISettingLine(title: "七天神像国家", subtitle: "选择七天神像所在国家。") {
                    BGIInlinePicker(value: "枫丹", width: 120)
                }
                BGISettingLine(title: "七天神像区域", subtitle: "选择七天神像所在区域。") {
                    BGIInlinePicker(value: "枫丹廷区", width: 140)
                }
                BGISettingLine(title: "回血等待间隔（秒）", subtitle: "传送到七天神像之后等待多久恢复血量。") {
                    BGINumberField(value: "8.0", width: 90)
                }
            }

            BGIOriginalCard(icon: .fgi("\u{f141}"), title: "其他设置", subtitle: "设定一些其他功能的配置，失去焦点自动恢复等。") {
                EmptyView()
            } content: {
                BGISettingLine(title: "游戏失去焦点时候，强制恢复激活游戏窗口", subtitle: "适用于调度器任务和部分独立任务，切出游戏前建议先暂停任务。") {
                    Toggle("", isOn: .constant(false))
                        .labelsHidden()
                }
                BGISettingLine(title: "调度器路径追踪任务大地图传送过程中自动领取委托", subtitle: "打开大地图准备传送时自动检测并领取派遣任务。") {
                    BGIInlinePicker(value: "关闭", width: 110)
                }
                BGISettingLine(title: "服务器时区设置", subtitle: "用于计算服务器时间的每日重置，JS 脚本也可使用。") {
                    BGIInlinePicker(value: "Asia/Shanghai", width: 150)
                }
                BGISettingLine(title: "调度器异常重启配置", subtitle: "任务异常累计到阈值后自动重启 BGI 以恢复功能。") {
                    Toggle("", isOn: .constant(false))
                        .labelsHidden()
                    BGINumberField(value: "3", width: 70)
                }
                BGISettingLine(title: "OCR 配置", subtitle: "PaddleOCR 模型选择，面向进阶用户。") {
                    BGIInlinePicker(value: "默认模型", width: 130)
                }
            }

            BGISettingGroup(icon: "gearshape", title: "通用", subtitle: "betterGI-mac 软件本体设置。") {
                EmptyView()
            } content: {
                BGISettingLine(title: "开机启动", subtitle: "后续接 SMAppService。") {
                    Toggle("", isOn: $appState.launchAtLogin)
                        .labelsHidden()
                }
                BGISettingLine(title: "启动时显示 HUD", subtitle: "启动后自动显示右下角状态浮层。") {
                    Toggle("", isOn: $appState.showHUDOnStart)
                        .labelsHidden()
                }
                BGISettingLine(title: "主窗口置顶", subtitle: "后续映射到 NSWindow level。") {
                    Toggle("", isOn: $appState.keepWindowOnTop)
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

            BGIOriginalCard(icon: .symbol("arrow.down.circle"), title: "版本更新", subtitle: "检查软件是否有新版本可用。") {
                BGIUnavailableAction("检查更新")
            } content: {
                BGISettingLine(title: "检查是否存在最新测试版", subtitle: "测试版非常不稳定，请谨慎选择更新。") {
                    BGIUnavailableAction("检查更新")
                }
                BGISettingLine(title: "直接从 Github 获取最新测试版", subtitle: "打开项目发布页。") {
                    BGIUnavailableAction("访问 Github")
                }
            }

            BGIOriginalCard(icon: .symbol("info.circle"), title: "关于 BetterGI", subtitle: "查看项目、文档、许可证与素材来源。", expanded: false) {
                BGIUnavailableAction("查看")
            } content: {
                EmptyView()
            }
        }
    }
}
