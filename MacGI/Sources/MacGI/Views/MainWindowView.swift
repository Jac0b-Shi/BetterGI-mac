import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            BGIHeaderBar()
            HStack(spacing: 0) {
                BGINavSidebar()
                ScrollView {
                    page
                        .padding(.horizontal, 44)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(BGIColors.appBackground)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BGIColors.appBackground)
        .preferredColorScheme(.dark)
        .sheet(isPresented: Binding(
            get: { appState.redeemCodeClipboardPrompt != nil },
            set: { if !$0 { appState.dismissRedeemCodeClipboardPrompt() } }
        )) {
            RedeemCodeClipboardPromptView()
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private var page: some View {
        switch appState.selectedPage {
        case .launch:
            OverviewPage()
        case .realtime:
            FeaturesPage()
        case .soloTask:
            SoloTasksPage()
        case .oneDragon:
            OneDragonWorkspaceView()
        case .scheduler:
            SchedulerPage()
        case .jsScript:
            JSScriptPage()
        case .mapTracking:
            MapTrackingPage()
        case .recordReplay:
            RecordReplayPage()
        case .macro:
            MacroPage()
        case .hotkey:
            HotkeyPage()
        case .keyBinding:
            KeyBindingPage()
        case .notification:
            NotificationPage()
        case .settings:
            SettingsPage()
        }
    }
}

private struct RedeemCodeClipboardPromptView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("自动使用兑换码")
                .font(.title3.weight(.semibold))
            Text("从剪切版中获取到下面的兑换码，是否自动使用？")
                .foregroundStyle(.secondary)
            TextEditor(text: $appState.redeemCodeClipboardDraft)
                .font(.body.monospaced())
                .frame(minWidth: 460, minHeight: 260)
                .overlay(Rectangle().stroke(BGIColors.border, lineWidth: 1))
            HStack {
                Spacer()
                Button("取消") {
                    appState.dismissRedeemCodeClipboardPrompt()
                }
                Button("自动使用") {
                    appState.acceptRedeemCodeClipboardPrompt()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 390)
        .background(BGIColors.appBackground)
    }
}
