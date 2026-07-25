import SwiftUI

struct SettingsPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BGIPageTitle(title: "软件设置")

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
        }
    }
}
