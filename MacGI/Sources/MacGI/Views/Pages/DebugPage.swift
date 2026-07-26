import SwiftUI

struct DebugPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: BGISpacing.large) {
            HStack(alignment: .top, spacing: BGISpacing.large) {
                BGISectionCard("Platform Diagnostics", subtitle: "仅测试 macOS 捕获和输入边界，不执行 BetterGI 业务规则。", symbolName: "scope") {
                    VStack(spacing: BGISpacing.medium) {
                        SettingRow(title: "Confidence", detail: "模拟识别置信度。") {
                            Slider(value: $appState.debugConfidence, in: 0...1)
                                .frame(width: 180)
                            Text(String(format: "%.2f", appState.debugConfidence))
                                .font(BGIFonts.console)
                                .foregroundStyle(BGIColors.primaryText)
                                .frame(width: 42)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BGISpacing.small) {
                            Button("Simulate Pick / Interact") { appState.dispatchGameAction(.pickUpOrInteract) }
                        }
                    }
                }

                BGISectionCard("Runtime Boundary", subtitle: "Swift 捕获/输入边界 + BetterGI C# Core 业务边界。", symbolName: "externaldrive.connected.to.line.below") {
                    VStack(spacing: BGISpacing.medium) {
                        SettingRow(title: "Swift Shell", detail: "窗口、菜单、HUD、权限与用户配置。") {
                            BGIStatusBadge(text: "Active", tint: BGIColors.success)
                        }
                        SettingRow(title: "BetterGI Core", detail: appState.schedulerCatalogStatus) {
                            BGIStatusBadge(
                                text: appState.coreStatus == .ok ? "Connected" : "Unavailable",
                                tint: appState.coreStatus == .ok ? BGIColors.success : BGIColors.danger
                            )
                        }
                        SettingRow(title: "RPC Contract", detail: "目录、调度、捕获和输入均通过本机双向 RPC。") {
                            BGIStatusBadge(text: "Active", tint: BGIColors.success)
                        }
                        SettingRow(title: "Core vision runtime", detail: "模型、OCR 与识别状态由 C# Core 握手及验证门禁负责。") {
                            BGIStatusBadge(
                                text: appState.coreStatus == .ok ? "Core" : "Unavailable",
                                tint: appState.coreStatus == .ok ? BGIColors.success : BGIColors.warning
                            )
                        }
                    }
                }
            }

            BGISectionCard("State Dump", subtitle: "从 AppState 派生，方便检查页面与 HUD 是否一致。", symbolName: "curlybraces") {
                Text(appState.stateDump)
                    .font(BGIFonts.console)
                    .foregroundStyle(BGIColors.primaryText)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
                    .background(BGIColors.consoleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous))
            }
        }
    }
}
