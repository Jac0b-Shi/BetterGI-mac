import SwiftUI

struct InputPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: BGISpacing.large) {
            HStack(alignment: .top, spacing: BGISpacing.large) {
                BGISectionCard("Safety Gate", subtitle: "输入安全门控 — dry-run / emergency stop / 速率限制。", symbolName: "lock.shield") {
                    VStack(spacing: BGISpacing.medium) {
                        SafetyToggle(
                            title: "Dry-Run Mode",
                            detail: "ON: 记录日志但不发送真实按键。OFF: 允许发送 CGEvent（需辅助功能权限）。",
                            isOn: Binding(
                                get: { appState.safetyGate.dryRun },
                                set: { appState.safetyGate.dryRun = $0 }
                            ),
                            warning: appState.safetyGate.dryRun ? nil : "⚠️ 真实输入将发送到游戏窗口"
                        )
                        SafetyToggle(
                            title: "Real Input Enabled",
                            detail: "最终开关。Dry-Run OFF + 此项 ON 才会真正模拟输入。",
                            isOn: Binding(
                                get: { appState.safetyGate.realInputEnabled },
                                set: { appState.safetyGate.realInputEnabled = $0 }
                            ),
                            warning: nil
                        )
                        SafetyToggle(
                            title: "Core Runtime Input",
                            detail: "允许 BetterGI C# Core 的触发器与脚本发送输入；仍受 Dry-Run、真实输入、前台窗口及紧急停止约束。",
                            isOn: Binding(
                                get: { appState.allowRuntimeRealInput },
                                set: { appState.allowRuntimeRealInput = $0 }
                            ),
                            warning: appState.allowRuntimeRealInput ? "⚠️ Core 自动化已获输入授权" : nil
                        )
                        SafetyToggle(
                            title: "Emergency Stop",
                            detail: "立即停止所有输入和自动化循环。",
                            isOn: Binding(
                                get: { appState.safetyGate.emergencyStop },
                                set: { appState.safetyGate.emergencyStop = $0 }
                            ),
                            warning: appState.safetyGate.emergencyStop ? "🛑 紧急停止 — 所有输入已冻结" : nil
                        )
                        Divider()
                            .foregroundStyle(BGIColors.border)
                        HStack {
                            Text("Rate Limit")
                                .font(BGIFonts.bodyStrong)
                            Spacer()
                            Text(String(format: "%.0f ms", appState.safetyGate.rateLimit * 1000))
                                .font(BGIFonts.console)
                                .foregroundStyle(BGIColors.accent)
                        }
                        HStack {
                            Text("Dispatched")
                                .font(BGIFonts.bodyStrong)
                            Spacer()
                            Text("\(appState.safetyGate.dispatchCount)")
                                .font(BGIFonts.console)
                                .foregroundStyle(appState.safetyGate.dispatchCount > 0 ? BGIColors.success : BGIColors.mutedText)
                        }
                        HStack {
                            Text("Dry-Run")
                                .font(BGIFonts.bodyStrong)
                            Spacer()
                            Text("\(appState.safetyGate.dryRunCount)")
                                .font(BGIFonts.console)
                                .foregroundStyle(appState.safetyGate.dryRunCount > 0 ? BGIColors.accent : BGIColors.mutedText)
                        }
                        HStack {
                            Text("Blocked")
                                .font(BGIFonts.bodyStrong)
                            Spacer()
                            Text("\(appState.safetyGate.blockedActionCount)")
                                .font(BGIFonts.console)
                                .foregroundStyle(appState.safetyGate.blockedActionCount > 0 ? BGIColors.warning : BGIColors.mutedText)
                        }
                    }
                }

                BGISectionCard("Test Actions", subtitle: "当前阶段只写入 Action Log。前缀: ○=dry-run, →=dispatched, ✕=blocked。", symbolName: "keyboard") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BGISpacing.small) {
                        ForEach(["Press F", "Press ESC", "Click Center", "Release All Keys"], id: \.self) { action in
                            Button {
                                appState.testInputAction(action)
                            } label: {
                                Text(action)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }

            BGISectionCard("Action Log", subtitle: "事件前缀: →(dispatched) ○(dry-run) ✕(blocked)。", symbolName: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appState.inputActionLog, id: \.self) { line in
                        Text(line)
                            .font(BGIFonts.console)
                            .foregroundStyle(BGIColors.primaryText.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .frame(minHeight: 220, alignment: .topLeading)
                .background(BGIColors.consoleBackground)
                .clipShape(RoundedRectangle(cornerRadius: BGIRadius.small, style: .continuous))
            }
        }
    }
}

private struct SafetyToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    let warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(BGIFonts.bodyStrong)
            }
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(BGIColors.secondaryText)
            if let warning {
                Text(warning)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BGIColors.warning)
            }
        }
    }
}
