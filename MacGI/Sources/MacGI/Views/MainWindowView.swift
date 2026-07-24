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
