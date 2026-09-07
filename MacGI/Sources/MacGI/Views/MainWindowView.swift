import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            BGIColors.appBackground
            mainBackground
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
                    .background(backgroundIsVisible ? Color.clear : BGIColors.appBackground)
                    .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: Binding(
            get: { appState.scriptSubscriptionClipboardPrompt },
            set: { if $0 == nil { appState.dismissScriptSubscriptionClipboardPrompt() } }
        )) { prompt in
            ScriptSubscriptionClipboardPromptView(prompt: prompt)
                .environmentObject(appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.redeemCodeClipboardPrompt != nil },
            set: { if !$0 { appState.dismissRedeemCodeClipboardPrompt() } }
        )) {
            RedeemCodeClipboardPromptView()
                .environmentObject(appState)
        }
    }

    private var backgroundIsVisible: Bool {
        guard let settings = appState.commonSettings else { return false }
        return settings.mainBackgroundEnabled &&
            !settings.mainBackgroundImagePath.isEmpty &&
            FileManager.default.isReadableFile(atPath: settings.mainBackgroundImagePath)
    }

    @ViewBuilder
    private var mainBackground: some View {
        if backgroundIsVisible,
           let settings = appState.commonSettings,
           let image = NSImage(contentsOfFile: settings.mainBackgroundImagePath) {
            switch settings.mainBackgroundStretch {
            case "Uniform":
                Image(nsImage: image).resizable().scaledToFit()
                    .opacity(settings.mainBackgroundOpacity)
            case "Fill":
                Image(nsImage: image).resizable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(settings.mainBackgroundOpacity)
            default:
                Image(nsImage: image).resizable().scaledToFill()
                    .opacity(settings.mainBackgroundOpacity)
            }
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
        case .music:
            MusicPage()
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

private struct ScriptSubscriptionClipboardPromptView: View {
    @EnvironmentObject private var appState: AppState
    let prompt: ScriptSubscriptionClipboardPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("脚本订阅")
                .font(.title3.weight(.semibold))
            Text("检测到剪贴板中的脚本订阅链接。是否导入并覆盖对应文件或文件夹？")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(prompt.paths, id: \.self) { path in
                        Text(path)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
            .frame(minWidth: 460, minHeight: 180)
            .background(BGIColors.cardBackground)
            .overlay(Rectangle().stroke(BGIColors.border, lineWidth: 1))
            HStack {
                Spacer()
                Button("关闭") {
                    appState.dismissScriptSubscriptionClipboardPrompt()
                }
                Button("确认导入") {
                    appState.acceptScriptSubscriptionClipboardPrompt()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 320)
        .background(BGIColors.appBackground)
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
