import SwiftUI

struct CapturePage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: BGISpacing.large) {
            HStack(alignment: .top, spacing: BGISpacing.large) {
                BGISectionCard("Game Window", subtitle: "WindowInfo → CGWindowID / PID / frame / scaleFactor。", symbolName: "macwindow") {
                    VStack(spacing: BGISpacing.medium) {
                        Picker("", selection: Binding(
                            get: { appState.selectedWindow.id },
                            set: { appState.selectWindow(byID: $0) }
                        )) {
                            ForEach(appState.availableWindows, id: \.id) { window in
                                Text(window.displayName).tag(window.id)
                            }
                        }
                        .frame(width: 260)
                        .labelsHidden()

                        // Window details
                        VStack(alignment: .leading, spacing: 4) {
                            WindowDetailRow("PID", "\(appState.selectedWindow.ownerPID)")
                            WindowDetailRow("Frame", appState.selectedWindow.frame.debugDescription)
                            WindowDetailRow("Scale", "\(appState.selectedWindow.scaleFactor)×")
                            WindowDetailRow("Layer", "\(appState.selectedWindow.layer)")
                            WindowDetailRow("On-Screen", appState.selectedWindow.isOnScreen ? "Yes" : "No")
                            WindowDetailRow("Is Game?", appState.selectedWindow.isLikelyGameWindow ? "Yes" : "No")
                        }
                        .font(BGIFonts.console)
                        .foregroundStyle(BGIColors.secondaryText)

                        HStack {
                            Button {
                                appState.refreshWindows()
                            } label: {
                                Label("Refresh Windows", systemImage: "arrow.clockwise")
                            }
                            Spacer()
                            BGIStatusBadge(
                                text: appState.isWindowValid ? "Valid" : appState.gameWindowStatus.label,
                                tint: appState.isWindowValid ? BGIColors.success : appState.gameWindowStatus.tint
                            )
                        }
                    }
                }

                BGISectionCard("Capture Status", subtitle: "CapturedFrame 提供尺寸/格式/时间戳。", symbolName: "viewfinder") {
                    VStack(spacing: BGISpacing.medium) {
                        SettingRow(title: "FPS", detail: "Capture session frame rate.") {
                            Text("\(appState.captureFPS)")
                                .font(BGIFonts.console)
                                .foregroundStyle(BGIColors.primaryText)
                        }
                        SettingRow(title: "Frame Size", detail: "CapturedFrame.sizeDescription") {
                            Text(appState.frameSize)
                                .font(BGIFonts.console)
                                .foregroundStyle(BGIColors.primaryText)
                        }
                        SettingRow(title: "Pixel Format", detail: "CapturedFrame.pixelFormatName") {
                            Text(appState.pixelFormat)
                                .font(BGIFonts.console)
                                .foregroundStyle(BGIColors.primaryText)
                        }
                        SettingRow(title: "Last Frame", detail: "Most recent capture timestamp.") {
                            Text(appState.lastCapturedFrame?.timestamp.formatted(date: .omitted, time: .standard) ?? "—")
                                .font(BGIFonts.console)
                                .foregroundStyle(BGIColors.primaryText)
                        }
                    }
                }
            }

            BGISectionCard("Last Captured Frame", subtitle: "nil = no capture session active。", symbolName: "rectangle.dashed") {
                VStack(alignment: .leading, spacing: BGISpacing.medium) {
                    ZStack {
                        RoundedRectangle(cornerRadius: BGIRadius.medium, style: .continuous)
                            .fill(BGIColors.consoleBackground)
                        if appState.lastCapturedFrame != nil {
                            VStack(spacing: 10) {
                                Image(systemName: "photo")
                                    .font(.system(size: 42, weight: .light))
                                    .foregroundStyle(BGIColors.mutedText)
                                Text("Frame #\(appState.lastCapturedFrame!.frameIndex)")
                                    .font(BGIFonts.bodyStrong)
                                    .foregroundStyle(BGIColors.secondaryText)
                                Text("\(appState.frameSize) · \(appState.pixelFormat)")
                                    .font(BGIFonts.console)
                                    .foregroundStyle(BGIColors.mutedText)
                            }
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "photo")
                                    .font(.system(size: 42, weight: .light))
                                    .foregroundStyle(BGIColors.mutedText)
                                Text("Mock Capture Frame")
                                    .font(BGIFonts.bodyStrong)
                                    .foregroundStyle(BGIColors.secondaryText)
                                Text("\(appState.frameSize) · \(appState.pixelFormat)")
                                    .font(BGIFonts.console)
                                    .foregroundStyle(BGIColors.mutedText)
                            }
                        }
                    }
                    .frame(height: 260)
                    Button {
                        appState.saveDebugFrameMock()
                    } label: {
                        Label("Save Debug Frame", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
    }
}

/// Compact key-value row for WindowInfo details.
private struct WindowDetailRow: View {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .foregroundStyle(BGIColors.mutedText)
            Text(value)
                .foregroundStyle(BGIColors.primaryText)
        }
    }
}
