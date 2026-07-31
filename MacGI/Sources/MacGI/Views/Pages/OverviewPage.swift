import SwiftUI

struct OverviewPage: View {
    @EnvironmentObject private var appState: AppState
    @State private var permissionsExpanded = true
    @State private var showingWindowPicker = false

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
                    requestEnabled: appState.screenCaptureAuthorizationState == .notRequested,
                    request: appState.requestScreenCapturePermission
                )
                permissionLine(
                    title: "辅助功能",
                    granted: appState.accessibilityPermissionGranted,
                    requestMessage: nil,
                    requestEnabled: true,
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
                BGISettingLine(
                    title: "输入后端",
                    subtitle: appState.inputBackendSelection.subtitle
                ) {
                    Picker(
                        "输入后端",
                        selection: Binding(
                            get: { appState.inputBackendSelection },
                            set: { appState.setInputBackendSelection($0) })
                    ) {
                        ForEach(InputBackendSelection.allCases) { backend in
                            Text(backend.title).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(!appState.canChangeInputBackend)
                }
                BGISettingLine(title: "测试图像捕获", subtitle: "测试功能，测试几种截图模式的效果。") {
                    Text("使用真实运行帧")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                BGISettingLine(title: "手动选择窗口（无法找到原神窗口时使用）", subtitle: "原神已经启动的情况下，点击“启动”仍旧提示无法找到窗口时使用。") {
                    Button("选择捕获窗口") {
                        appState.refreshWindows()
                        showingWindowPicker = true
                    }
                }
                BGISettingLine(title: "原神失焦时隐藏 HUD", subtitle: "切换到其他应用时隐藏叠加层，返回原神后自动恢复。") {
                    Toggle("", isOn: $appState.hideHUDWhenGameUnfocused)
                        .labelsHidden()
                }
                BGISettingLine(
                    title: "后台遇到文字输入时暂停脚本",
                    subtitle: appState.backgroundTextInputPolicy.subtitle
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: {
                                appState.backgroundTextInputPolicy == .waitForForeground
                            },
                            set: {
                                appState.backgroundTextInputPolicy = $0
                                    ? .waitForForeground
                                    : .skipAndContinue
                            })
                    )
                    .labelsHidden()
                }
            }
        }
        .sheet(isPresented: $showingWindowPicker) {
            CaptureWindowPickerSheet(isPresented: $showingWindowPicker)
                .environmentObject(appState)
        }
    }

    private func permissionLine(
        title: String,
        granted: Bool,
        requestMessage: String?,
        requestEnabled: Bool,
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
                Button(requestEnabled ? "请求授权" : "已请求", action: request)
                    .buttonStyle(.bordered)
                    .disabled(!requestEnabled)
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

private struct CaptureWindowPickerSheet: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    @State private var pendingUnrecognizedWindow: WindowInfo?

    var body: some View {
        NavigationStack {
            Group {
                if appState.availableWindows.isEmpty {
                    ContentUnavailableView(
                        "没有可捕获窗口",
                        systemImage: "macwindow.badge.plus",
                        description: Text("请确认目标窗口已显示在桌面上，然后刷新列表。"))
                } else {
                    List(appState.availableWindows) { window in
                        Button {
                            if window.isLikelyGameWindow {
                                select(window)
                            } else {
                                pendingUnrecognizedWindow = window
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(window.displayName)
                                    Text("PID \(window.ownerPID) · \(Int(window.capturePixelSize.width))×\(Int(window.capturePixelSize.height))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if window.isLikelyGameWindow {
                                    Text("原神")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if window.id == appState.selectedWindow.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("选择捕获窗口")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isPresented = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.refreshWindows()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .alert(
            "这看起来不像是原神",
            isPresented: Binding(
                get: { pendingUnrecognizedWindow != nil },
                set: { if !$0 { pendingUnrecognizedWindow = nil } }
            ),
            presenting: pendingUnrecognizedWindow
        ) { window in
            Button("仍然选择") { select(window) }
            Button("取消", role: .cancel) { pendingUnrecognizedWindow = nil }
        } message: { window in
            Text("“\(window.displayName)”未被识别为原神窗口，确定要选择这个窗口吗？")
        }
        .frame(minWidth: 620, minHeight: 360)
    }

    private func select(_ window: WindowInfo) {
        appState.setSelectedWindow(window)
        pendingUnrecognizedWindow = nil
        isPresented = false
    }
}
