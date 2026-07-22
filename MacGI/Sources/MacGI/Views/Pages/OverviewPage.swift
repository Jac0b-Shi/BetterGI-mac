import SwiftUI

struct OverviewPage: View {
    @EnvironmentObject private var appState: AppState
    @State private var permissionsExpanded = true

    private var allPermissionsGranted: Bool {
        appState.screenCapturePermissionGranted && appState.accessibilityPermissionGranted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            launchBanner

            BGISettingGroup(
                icon: "lock.shield",
                title: "macOS 权限",
                subtitle: allPermissionsGranted ? "已授权" : "运行截图器和真实输入前必须由用户明确授权。",
                isExpanded: $permissionsExpanded
            ) {
                Button {
                    appState.refreshPermissionStatus()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            } content: {
                permissionLine(
                    title: "屏幕录制",
                    granted: appState.screenCapturePermissionGranted,
                    requestMessage: appState.screenCapturePermissionRequestMessage,
                    request: appState.requestScreenCapturePermission
                )
                permissionLine(
                    title: "辅助功能",
                    granted: appState.accessibilityPermissionGranted,
                    requestMessage: nil,
                    request: appState.requestAccessibilityPermission
                )
            }
            .onAppear {
                permissionsExpanded = !allPermissionsGranted
            }
            .onChange(of: allPermissionsGranted) { _, granted in
                permissionsExpanded = !granted
            }

            BGISettingGroup(icon: "play", title: "BetterGI 截图器，启动！", subtitle: "截图器启动后才能使用各项功能，点击展开启动相关配置。") {
                Button {
                    appState.toggleRuntime()
                } label: {
                    Label(
                        appState.runtimeLifecycle == .running ? "停止" : "启动",
                        systemImage: appState.runtimeLifecycle == .running ? "stop.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.runtimeLifecycle.isTransitioning)
            } content: {
                BGISettingLine(title: "运行时状态", subtitle: appState.runtimeLifecycleMessage) {
                    Text(appState.runtimeLifecycle.rawValue.capitalized)
                        .foregroundStyle(appState.runtimeLifecycle == .failed ? .red : .secondary)
                }
                BGISettingLine(title: "截图后端", subtitle: "macOS 平台回调使用 ScreenCaptureKit 捕获目标窗口。") {
                    Text("ScreenCaptureKit")
                        .foregroundStyle(.secondary)
                }
                BGISettingLine(title: "触发器间隔（毫秒）", subtitle: "默认50ms，普通用户不建议调整这个值，具体调整方式见文档。") {
                    TextField("", text: .constant("50"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                }
                BGISettingLine(title: "AI推理设备设置", subtitle: "修改后需要重启程序生效。") {
                    Picker("", selection: .constant("Cpu")) {
                        Text("Cpu").tag("Cpu")
                        Text("Gpu").tag("Gpu")
                    }
                    .frame(width: 98)
                    Text("由 Core 管理")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                BGISettingLine(title: "测试图像捕获", subtitle: "测试功能，测试几种截图模式的效果。") {
                    Text("使用真实运行帧")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                BGISettingLine(title: "手动选择窗口（无法找到原神窗口时使用）", subtitle: "原神已经启动的情况下，点击“启动”仍旧提示无法找到窗口时使用。") {
                    Button("选择捕获窗口") {
                        appState.refreshWindows()
                    }
                }
            }

            BGISettingGroup(icon: "link", title: "同时启动原神", subtitle: "启动截图器时，如果原神未启动，则自动启动原神。") {
                Toggle("", isOn: .constant(true))
                    .labelsHidden()
            } content: {
                BGISettingLine(title: "原神安装位置（不支持云原神的联动启动）", subtitle: "/Applications/Genshin Impact.app") {
                    Text("暂不可更改")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                BGISettingLine(title: "启动参数", subtitle: "如果你不知道什么是启动参数请不要填写。") {
                    TextField("", text: .constant(""))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
                BGISettingLine(title: "自动进入游戏", subtitle: "原神启动后自动进入游戏（自动开门、领取月卡）。") {
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                }
            }
        }
    }

    private func permissionLine(
        title: String,
        granted: Bool,
        requestMessage: String?,
        request: @escaping () -> Void
    ) -> some View {
        BGISettingLine(
            title: title,
            subtitle: granted
                ? "已授权"
                : requestMessage ?? "未授权；授权后 macOS 可能要求重新打开应用。"
        ) {
            if granted {
                Label("已授权", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("请求授权", action: request)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var launchBanner: some View {
        ZStack(alignment: .bottomLeading) {
            BGIBundledImage(resource: "bettergi-banner", fileExtension: "jpg", contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 214)
                .clipped()
            LinearGradient(
                colors: [
                    Color.black.opacity(0.58),
                    Color.black.opacity(0.28),
                    Color.black.opacity(0.04)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            VStack(alignment: .leading, spacing: 5) {
                Text("BetterGI")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(BGIColors.primaryText)
                Text("更好的原神，免费且开源")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BGIColors.primaryText.opacity(0.86))
                Text("点击查看文档与教程")
                    .font(BGIFonts.bodyStrong)
                    .foregroundStyle(BGIColors.secondaryText)
            }
            .padding(.leading, 54)
            .padding(.bottom, 28)
        }
        .frame(height: 214)
        .overlay(
            RoundedRectangle(cornerRadius: BGIRadius.medium, style: .continuous)
                .stroke(BGIColors.border, lineWidth: 1)
        )
    }
}
