import SwiftUI

struct LogsPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: BGISpacing.large) {
            BGISectionCard("日志控制", subtitle: "主窗口与 HUD 共用 recentLogs。", symbolName: "line.3.horizontal.decrease.circle") {
                HStack(spacing: BGISpacing.medium) {
                    Picker("Level", selection: $appState.logLevelFilter) {
                        ForEach(LogLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .frame(width: 120)

                    TextField("Search", text: $appState.logSearchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)

                    Button {
                        appState.addTestLog()
                    } label: {
                        Label("Add Test Log", systemImage: "plus.message")
                    }

                    Button {
                        appState.clearLogs()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }

                    Button {
                        appState.exportLogsMock()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }

                    Spacer()
                }
            }

            BGISectionCard("日志列表", subtitle: "等宽字体控制台风格，接近 BetterGI 遮罩日志。", symbolName: "terminal") {
                BGILogConsole(entries: appState.filteredLogs)
                    .frame(minHeight: 460)
            }
        }
    }
}
