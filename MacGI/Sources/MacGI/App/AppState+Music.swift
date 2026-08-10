import Foundation

extension AppState {
    var selectedMusicTrack: BetterGIMusicTrack? {
        guard let selectedMusicTrackIndex else { return nil }
        return musicState.tracks.first { $0.index == selectedMusicTrackIndex }
    }

    var canStartMusicPlayback: Bool {
        runtimeLifecycle == .running
            && musicState.playback.state == .stopped
            && selectedMusicTrack?.isValid == true
            && !musicLoading
    }

    func loadMusicStateFromCore() async {
        guard let supervisor = betterGICoreSupervisor else {
            musicStatus = "Core unavailable"
            return
        }
        do {
            applyMusicState(try await supervisor.musicState())
        } catch {
            musicStatus = "读取自动演奏状态失败：\(error.localizedDescription)"
        }
    }

    func scanMusicFolder(_ rootFolder: String) {
        guard let supervisor = betterGICoreSupervisor else {
            musicStatus = "BetterGI Core 尚未就绪。"
            return
        }
        musicLoading = true
        musicStatus = "正在扫描曲谱目录..."
        Task { [weak self] in
            guard let self else { return }
            do {
                let state = try await supervisor.scanMusic(rootFolder: rootFolder)
                self.applyMusicState(state)
                self.selectedMusicTrackIndex = state.tracks.first?.index
                self.addLog(.info, "自动演奏已载入 \(state.tracks.count) 首曲谱。")
            } catch {
                self.musicStatus = "扫描曲谱失败：\(error.localizedDescription)"
                self.addLog(.error, self.musicStatus)
            }
            self.musicLoading = false
        }
    }

    func selectMusicTrack(_ index: Int) {
        selectedMusicTrackIndex = index
    }

    func startSelectedMusic() {
        guard runtimeLifecycle == .running else {
            musicStatus = "请先启动运行时并选中原神窗口。"
            return
        }
        guard let supervisor = betterGICoreSupervisor,
              let index = selectedMusicTrackIndex else {
            musicStatus = "请选择可播放曲目。"
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                self.applyMusicState(try await supervisor.playMusic(
                    index: index,
                    speed: self.musicSpeed,
                    playbackMode: self.musicPlaybackMode))
                self.addLog(.info, "自动演奏已开始。")
            } catch {
                self.musicStatus = "开始演奏失败：\(error.localizedDescription)"
                self.addLog(.error, self.musicStatus)
            }
        }
    }

    func pauseOrResumeMusic() {
        let method = musicState.playback.state == .paused
            ? "music.resume" : "music.pause"
        runMusicCommand(method)
    }

    func stopMusic() {
        runMusicCommand("music.stop")
    }

    func nextMusic() {
        runMusicCommand("music.next")
    }

    func previousMusic() {
        runMusicCommand("music.previous")
    }

    func seekMusic(to positionMilliseconds: Double) {
        guard let supervisor = betterGICoreSupervisor,
              musicState.playback.state != .stopped else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                self.applyMusicState(try await supervisor.seekMusic(
                    positionMilliseconds: positionMilliseconds))
            } catch {
                self.musicStatus = "跳转播放位置失败：\(error.localizedDescription)"
            }
        }
    }

    func setMusicSpeed(_ speed: Double) {
        musicSpeed = min(max(speed, 0.5), 2)
        guard let supervisor = betterGICoreSupervisor,
              musicState.playback.state != .stopped else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                self.applyMusicState(try await supervisor.setMusicSpeed(self.musicSpeed))
            } catch {
                self.musicStatus = "调整演奏速度失败：\(error.localizedDescription)"
            }
        }
    }

    func setMusicPlaybackMode(_ mode: BetterGIMusicPlaybackMode) {
        musicPlaybackMode = mode
        guard let supervisor = betterGICoreSupervisor else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                self.applyMusicState(try await supervisor.setMusicPlaybackMode(mode))
            } catch {
                self.musicStatus = "切换播放模式失败：\(error.localizedDescription)"
            }
        }
    }

    func configureMusicTrack(
        index: Int,
        outputProfileName: String,
        transpose: Int,
        disabledTrackIndexes: [Int]
    ) {
        guard let supervisor = betterGICoreSupervisor else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                self.applyMusicState(try await supervisor.configureMusicTrack(
                    index: index,
                    outputProfileName: outputProfileName,
                    transpose: transpose,
                    disabledTrackIndexes: disabledTrackIndexes))
            } catch {
                self.musicStatus = "保存曲目映射失败：\(error.localizedDescription)"
            }
        }
    }

    private func runMusicCommand(_ method: String) {
        guard let supervisor = betterGICoreSupervisor else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                self.applyMusicState(try await supervisor.musicCommand(method))
            } catch {
                self.musicStatus = "自动演奏控制失败：\(error.localizedDescription)"
                self.addLog(.error, self.musicStatus)
            }
        }
    }

    private func applyMusicState(_ state: BetterGIMusicState) {
        musicState = state
        musicPlaybackMode = state.playbackMode
        if state.playback.state != .stopped {
            musicSpeed = state.playback.speed
            if state.playback.queueIndex >= 0 {
                selectedMusicTrackIndex = state.playback.queueIndex
            }
            musicStatus = state.playback.state == .paused
                ? "已暂停：\(state.playback.trackName)"
                : "正在演奏：\(state.playback.trackName)"
            startMusicPlaybackPolling()
        } else {
            musicPlaybackPollTask?.cancel()
            musicPlaybackPollTask = nil
            musicStatus = state.rootFolder.isEmpty
                ? "请选择曲谱目录。"
                : "已载入 \(state.tracks.count) 首曲谱。"
        }
    }

    private func startMusicPlaybackPolling() {
        guard musicPlaybackPollTask == nil else { return }
        musicPlaybackPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled,
                      let self,
                      let supervisor = self.betterGICoreSupervisor else { return }
                do {
                    self.applyMusicState(try await supervisor.musicState())
                } catch {
                    self.musicStatus = "同步演奏状态失败：\(error.localizedDescription)"
                    self.musicPlaybackPollTask = nil
                    return
                }
            }
        }
    }
}
