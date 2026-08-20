import AppKit
import SwiftUI

private enum MusicMappingModeOption: String, CaseIterable, Identifiable {
    case followDefault
    case melodicOctaveFold = "MelodicOctaveFold"
    case exact = "Exact"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followDefault: "跟随乐器默认"
        case .melodicOctaveFold: "八度折叠"
        case .exact: "超出音域丢弃"
        }
    }
}

struct MusicPage: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var selectedProfileName = ""
    @State private var transpose = 0
    @State private var mappingModeOption: MusicMappingModeOption = .followDefault
    @State private var disabledMidiTrackIndexes: Set<Int> = []
    @State private var seekPosition = 0.0
    @State private var isSeeking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                BGIPageTitle(title: "自动演奏")
                Spacer()
                BGIStatusBadge(
                    text: playbackStatusTitle,
                    tint: playbackStatusTint)
            }

            commandBar

            HStack(alignment: .top, spacing: 14) {
                trackCatalog
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                trackSettings
                    .frame(width: 330, alignment: .topLeading)
            }

            playbackPanel
        }
        .task {
            await appState.loadMusicStateFromCore()
            selectInitialTrack()
        }
        .onChange(of: appState.selectedMusicTrackIndex) { _, _ in
            loadSelectedTrackSettings()
        }
        .onChange(of: appState.musicState.playback.positionMilliseconds) { _, value in
            if !isSeeking {
                seekPosition = value
            }
        }
        .onChange(of: appState.musicState.tracks) { _, _ in
            selectInitialTrack()
        }
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            Button {
                chooseMusicFolder()
            } label: {
                Label("选择曲谱目录", systemImage: "folder")
            }
            Button {
                guard !appState.musicState.rootFolder.isEmpty else { return }
                appState.scanMusicFolder(appState.musicState.rootFolder)
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(appState.musicState.rootFolder.isEmpty || appState.musicLoading)
            if !appState.musicState.folderHistory.isEmpty {
                Menu {
                    ForEach(appState.musicState.folderHistory, id: \.self) { folder in
                        Button(folder) {
                            appState.scanMusicFolder(folder)
                        }
                    }
                } label: {
                    Label("最近", systemImage: "clock")
                }
            }

            TextField("搜索曲名、作者或路径", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            Spacer()
            if appState.musicLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(appState.musicStatus)
                .font(BGIFonts.caption)
                .foregroundStyle(BGIColors.secondaryText)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
    }

    private var trackCatalog: some View {
        BGISectionCard(
            "曲目",
            subtitle: appState.musicState.rootFolder.isEmpty
                ? nil : appState.musicState.rootFolder,
            symbolName: "music.note.list"
        ) {
            LazyVStack(spacing: 0) {
                ForEach(filteredTracks) { track in
                    trackRow(track)
                    Divider()
                }
                if filteredTracks.isEmpty {
                    Text(appState.musicState.rootFolder.isEmpty
                         ? "尚未选择曲谱目录。" : "没有匹配的可用曲谱。")
                        .font(BGIFonts.body)
                        .foregroundStyle(BGIColors.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
            }
        }
    }

    private func trackRow(_ track: BetterGIMusicTrack) -> some View {
        HStack(spacing: 10) {
                Image(systemName: track.isValid ? "music.note" : "exclamationmark.triangle")
                    .foregroundStyle(track.isValid ? BGIColors.accent : BGIColors.danger)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(BGIFonts.bodyStrong)
                        .foregroundStyle(BGIColors.primaryText)
                        .lineLimit(1)
                    Text(trackSubtitle(track))
                        .font(BGIFonts.caption)
                        .foregroundStyle(BGIColors.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(formatDuration(track.durationMilliseconds))
                    .font(BGIFonts.console)
                    .foregroundStyle(BGIColors.mutedText)
                Button {
                    appState.selectMusicTrack(track.index)
                    appState.startSelectedMusic()
                } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("播放")
                .disabled(!track.isValid
                          || appState.runtimeLifecycle != .running
                          || appState.musicState.playback.state != .stopped)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .background(appState.selectedMusicTrackIndex == track.index
                    ? BGIColors.cardElevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: BGIRadius.small))
        .onTapGesture {
            appState.selectMusicTrack(track.index)
        }
    }

    private var trackSettings: some View {
        BGISectionCard(
            appState.selectedMusicTrack?.title ?? "曲目设置",
            subtitle: appState.selectedMusicTrack?.formatName,
            symbolName: "slider.horizontal.3"
        ) {
            if let track = appState.selectedMusicTrack {
                VStack(alignment: .leading, spacing: 12) {
                    metadataLine("作者", track.author)
                    metadataLine("乐器", track.instrument)
                    metadataLine("音符", "\(track.noteCount)")
                    metadataLine("可演奏", String(format: "%.1f%%", track.playableRatio * 100))
                    if let error = track.error, !error.isEmpty {
                        Text(error)
                            .font(BGIFonts.caption)
                            .foregroundStyle(BGIColors.danger)
                    }
                    Divider()
                    Picker("输出乐器", selection: $selectedProfileName) {
                        ForEach(appState.musicState.profiles) { profile in
                            Text(profile.name).tag(profile.name)
                        }
                    }
                    Picker("音域处理", selection: $mappingModeOption) {
                        ForEach(MusicMappingModeOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Stepper("移调：\(transpose)", value: $transpose, in: -36...36)

                    if !track.midiTracks.isEmpty {
                        Divider()
                        Text("MIDI 轨道")
                            .font(BGIFonts.bodyStrong)
                        ForEach(track.midiTracks) { midiTrack in
                            Toggle(isOn: midiTrackBinding(midiTrack.index)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(midiTrack.name)
                                        .lineLimit(1)
                                    Text("\(midiTrack.noteCount) 个音符")
                                        .font(BGIFonts.caption)
                                        .foregroundStyle(BGIColors.mutedText)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }

                    Button {
                        appState.configureMusicTrack(
                            index: track.index,
                            outputProfileName: selectedProfileName,
                            transpose: transpose,
                            disabledTrackIndexes: disabledMidiTrackIndexes.sorted(),
                            mappingModeOverride: mappingModeOption == .followDefault
                                ? nil : mappingModeOption.rawValue)
                    } label: {
                        Label("保存映射", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedProfileName.isEmpty
                              || appState.musicState.playback.state != .stopped)
                }
            } else {
                Text("选择曲目后可调整输出乐器、移调和 MIDI 轨道。")
                    .font(BGIFonts.body)
                    .foregroundStyle(BGIColors.mutedText)
            }
        }
    }

    private var playbackPanel: some View {
        BGISectionCard(
            appState.musicState.playback.trackName.isEmpty
                ? "播放控制" : appState.musicState.playback.trackName,
            symbolName: "waveform"
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Text(formatDuration(seekPosition))
                        .font(BGIFonts.console)
                        .frame(width: 48, alignment: .trailing)
                    Slider(
                        value: $seekPosition,
                        in: 0...max(1, appState.musicState.playback.durationMilliseconds),
                        onEditingChanged: { editing in
                            isSeeking = editing
                            if !editing {
                                appState.seekMusic(to: seekPosition)
                            }
                        })
                        .disabled(appState.musicState.playback.state == .stopped)
                    Text(formatDuration(appState.musicState.playback.durationMilliseconds))
                        .font(BGIFonts.console)
                        .frame(width: 48, alignment: .leading)
                }

                HStack(spacing: 14) {
                    playbackButton("backward.end.fill", help: "上一首") {
                        appState.previousMusic()
                    }
                    playbackButton(
                        appState.musicState.playback.state == .paused
                            ? "play.fill" : "pause.fill",
                        help: appState.musicState.playback.state == .paused ? "继续" : "暂停"
                    ) {
                        appState.pauseOrResumeMusic()
                    }
                    .disabled(appState.musicState.playback.state == .stopped)
                    playbackButton("stop.fill", help: "停止") {
                        appState.stopMusic()
                    }
                    .disabled(appState.musicState.playback.state == .stopped)
                    playbackButton("forward.end.fill", help: "下一首") {
                        appState.nextMusic()
                    }

                    Divider().frame(height: 24)

                    Text(String(format: "%.2fx", appState.musicSpeed))
                        .font(BGIFonts.console)
                        .frame(width: 48)
                    Slider(
                        value: Binding(
                            get: { appState.musicSpeed },
                            set: { appState.setMusicSpeed($0) }),
                        in: 0.1...10,
                        step: 0.05)
                        .frame(width: 150)

                    Picker("播放模式", selection: Binding(
                        get: { appState.musicPlaybackMode },
                        set: { appState.setMusicPlaybackMode($0) })) {
                        ForEach(BetterGIMusicPlaybackMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)

                    Spacer()
                    Button {
                        appState.startSelectedMusic()
                    } label: {
                        Label("开始演奏", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.canStartMusicPlayback)
                }

                HStack(spacing: 12) {
                    Toggle("自定义 BPM", isOn: Binding(
                        get: { appState.musicUseCustomBpm },
                        set: { appState.musicUseCustomBpm = $0 }))
                        .toggleStyle(.checkbox)
                    TextField(
                        "BPM",
                        value: Binding(
                            get: { appState.musicCustomBpm },
                            set: { appState.musicCustomBpm = $0 }),
                        format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .disabled(!appState.musicUseCustomBpm)
                        .help("用自定义 BPM 覆盖曲谱基准速度，仅在开启自定义 BPM 时生效")

                    Divider().frame(height: 18)

                    Toggle("自动换乐器", isOn: Binding(
                        get: { appState.musicAutoSwitchInstrument },
                        set: { appState.musicAutoSwitchInstrument = $0 }))
                        .toggleStyle(.checkbox)
                    Text("需要 macOS 运行时")
                        .font(BGIFonts.caption)
                        .foregroundStyle(BGIColors.mutedText)

                    Spacer()
                }
            }
        }
    }

    private func playbackButton(
        _ systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.bordered)
        .help(help)
    }

    private func metadataLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(BGIColors.mutedText)
                .frame(width: 48, alignment: .leading)
            Text(value.isEmpty ? "-" : value)
                .foregroundStyle(BGIColors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(BGIFonts.body)
    }

    private func midiTrackBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { !disabledMidiTrackIndexes.contains(index) },
            set: { enabled in
                if enabled {
                    disabledMidiTrackIndexes.remove(index)
                } else {
                    disabledMidiTrackIndexes.insert(index)
                }
            })
    }

    private var filteredTracks: [BetterGIMusicTrack] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appState.musicState.tracks }
        return appState.musicState.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.author.localizedCaseInsensitiveContains(query)
                || $0.relativePath.localizedCaseInsensitiveContains(query)
        }
    }

    private var playbackStatusTitle: String {
        switch appState.musicState.playback.state {
        case .stopped: "已停止"
        case .playing: "演奏中"
        case .paused: "已暂停"
        }
    }

    private var playbackStatusTint: Color {
        switch appState.musicState.playback.state {
        case .stopped: BGIColors.muted
        case .playing: BGIColors.success
        case .paused: BGIColors.warning
        }
    }

    private func chooseMusicFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        if !appState.musicState.rootFolder.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: appState.musicState.rootFolder)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.scanMusicFolder(url.path)
    }

    private func selectInitialTrack() {
        if let selected = appState.selectedMusicTrackIndex,
           appState.musicState.tracks.contains(where: { $0.index == selected }) {
            loadSelectedTrackSettings()
            return
        }
        appState.selectedMusicTrackIndex = appState.musicState.tracks.first?.index
        loadSelectedTrackSettings()
    }

    private func loadSelectedTrackSettings() {
        guard let track = appState.selectedMusicTrack else {
            selectedProfileName = ""
            transpose = 0
            mappingModeOption = .followDefault
            disabledMidiTrackIndexes = []
            return
        }
        selectedProfileName = track.outputProfileName.isEmpty
            ? appState.musicState.profiles.first?.name ?? ""
            : track.outputProfileName
        transpose = track.transpose
        mappingModeOption = track.mappingModeOverride
            .flatMap(MusicMappingModeOption.init(rawValue:)) ?? .followDefault
        disabledMidiTrackIndexes = Set(
            track.midiTracks.filter { !$0.isEnabled }.map(\.index))
    }

    private func trackSubtitle(_ track: BetterGIMusicTrack) -> String {
        [track.author, track.formatName, track.relativePath]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func formatDuration(_ milliseconds: Double) -> String {
        let seconds = max(0, Int(milliseconds / 1_000))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
