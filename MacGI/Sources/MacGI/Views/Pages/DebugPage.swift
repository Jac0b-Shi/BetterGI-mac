import SwiftUI

struct DebugPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: BGISpacing.large) {
            HStack(alignment: .top, spacing: BGISpacing.large) {
                BGISectionCard("Mock Detection", subtitle: "调试入口集中在此页，不污染业务视图。", symbolName: "scope") {
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
                            Button("Simulate Pickup Match") { appState.simulatePickupMatch() }
                            Button("Simulate Pick / Interact") { appState.dispatchGameAction(.pickUpOrInteract) }
                            Button("Simulate Capture Lost") { appState.simulateCaptureLost() }
                            Button("Simulate Core Error") { appState.simulateCoreError() }
                        }
                    }
                }

                BGISectionCard("Runtime Boundary", subtitle: "Swift 捕获/输入边界 + Rust 纯逻辑决策边界。", symbolName: "externaldrive.connected.to.line.below") {
                    VStack(spacing: BGISpacing.medium) {
                        SettingRow(title: "Swift Shell", detail: "窗口、菜单、HUD、权限与用户配置。") {
                            BGIStatusBadge(text: "Active", tint: BGIColors.success)
                        }
                        SettingRow(title: "Rust Core", detail: appState.rustCoreStatusText) {
                            BGIStatusBadge(
                                text: appState.isRustCoreAvailable ? "Loaded" : "Fallback",
                                tint: appState.isRustCoreAvailable ? BGIColors.success : BGIColors.accent
                            )
                        }
                        SettingRow(title: "FFI Contract", detail: "已包含生命周期与 AutoPick/AutoSkip 决策入口。") {
                            BGIStatusBadge(text: "Active", tint: BGIColors.success)
                        }
                        SettingRow(title: "BGI Assets", detail: appState.bgiAssetStatusText) {
                            BGIStatusBadge(
                                text: appState.bgiAssetCoverage.missing.isEmpty ? "Ready" : "Missing",
                                tint: appState.bgiAssetCoverage.missing.isEmpty ? BGIColors.success : BGIColors.warning
                            )
                        }
                        SettingRow(title: "OCR Models", detail: appState.bgiModelAssetStatusText) {
                            BGIStatusBadge(
                                text: appState.bgiModelAssetCoverage.missing.isEmpty ? "Ready" : "Missing",
                                tint: appState.bgiModelAssetCoverage.missing.isEmpty ? BGIColors.success : BGIColors.warning
                            )
                        }
                        SettingRow(title: "OCR Runtime", detail: appState.paddleOCRRuntimeStatusText) {
                            BGIStatusBadge(
                                text: appState.isPaddleOCRRuntimeReady ? "Ready" : "Missing",
                                tint: appState.isPaddleOCRRuntimeReady ? BGIColors.success : BGIColors.warning
                            )
                        }
                        SettingRow(title: "Compute Preference", detail: "\(appState.computePreference.rawValue)") {
                            Picker("", selection: $appState.computePreference) {
                                Text("Automatic").tag(BGIComputePreference.automatic)
                                Text("Core ML: All (CPU+GPU+ANE)").tag(BGIComputePreference.coreMLAll)
                                Text("Core ML: CPU+GPU").tag(BGIComputePreference.coreMLCPUAndGPU)
                                Text("CPU Only").tag(BGIComputePreference.cpuOnly)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 280)
                        }
                        SettingRow(title: "EP Assignment", detail: appState.lastEpAssignment.summary) {
                            BGIStatusBadge(
                                text: appState.lastEpAssignment.finalBackend.displayName,
                                tint: {
                                    switch appState.lastEpAssignment.finalBackend {
                                    case .coreML: return BGIColors.success
                                    case .cpuFallbackFromCoreML: return BGIColors.warning
                                    case .cpuOnly: return BGIColors.accent
                                    case .failed: return BGIColors.danger
                                    }
                                }()
                            )
                        }
                        if !appState.lastEpAssignment.diagnostics.isEmpty {
                            SettingRow(title: "Session Diagnostics", detail: appState.lastEpAssignment.diagnostics.joined(separator: "\n")) {
                                EmptyView()
                            }
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
