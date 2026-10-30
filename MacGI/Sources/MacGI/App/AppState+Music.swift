import Foundation
import AppKit

extension AppState {
    var selectedMusicTrack: BetterGIMusicTrack? {
        guard let selectedMusicTrackIndex else { return nil }
        return musicState.tracks.first { $0.index == selectedMusicTrackIndex }
    }

    var canStartMusicPlayback: Bool {
        runtimeLifecycle == .running
            && !musicState.guided.active
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
            let state = try await supervisor.musicState()
            if state.rootFolder.isEmpty,
               let recentFolder = state.folderHistory.first,
               FileManager.default.fileExists(atPath: recentFolder) {
                applyMusicState(try await supervisor.scanMusic(rootFolder: recentFolder))
            } else {
                applyMusicState(state)
            }
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
        if musicGuidedMode { startSelectedGuidedMusic(); return }
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
                let startPosition = self.selectedMusicTrack?.fullPath
                    == self.musicState.savedTrackFullPath
                    ? self.musicState.savedPositionMilliseconds
                    : 0
                self.applyMusicState(try await supervisor.playMusic(
                    index: index,
                    speed: self.musicSpeed,
                    playbackMode: self.musicPlaybackMode,
                    startPositionMilliseconds: startPosition,
                    customBpm: self.musicUseCustomBpm ? self.musicCustomBpm : nil,
                    autoSwitchInstrument: self.musicAutoSwitchInstrument))
                self.addLog(.info, "自动演奏已开始。")
            } catch {
                self.musicStatus = "开始演奏失败：\(error.localizedDescription)"
                self.addLog(.error, self.musicStatus)
            }
        }
    }

    func startSelectedGuidedMusic() {
        guard canStartMusicPlayback, let supervisor = betterGICoreSupervisor, let index = selectedMusicTrackIndex else { return }
        musicLoading = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.musicLoading = false }
            do {
                self.musicGuidedKeyMonitor.isGameFrontmost = { [weak self] in
                    guard let self else { return false }
                    return self.runtimeLifecycle == .running && ForegroundWindowGuard.isTargetFrontmost(self.selectedWindow)
                }
                try self.musicGuidedKeyMonitor.start()
                let state = try await supervisor.startGuidedMusic(index: index, windowID: self.selectedWindow.id,
                    segmentSize: self.musicGuidedSegmentSize, strictOrder: self.musicGuidedStrictOrder, autoDetect: self.musicGuidedAutoDetect, overlayEnabled: self.musicGuidedOverlayEnabled)
                self.musicGuidedKeyMonitor.onExit = { [weak self] in self?.stopMusic() }
                self.musicGuidedKeyMonitor.onRedetect = { [weak self] in self?.redetectGuidedMusic() }
                self.musicGuidedKeyMonitor.onKey = { [weak self] key, down, modifiers in
                    guard let self, let session = state.guided.session else { return }
                    let previous = self.musicGuidedKeyTask
                    self.musicGuidedKeyTask = Task { [weak self] in
                        await previous?.value
                        do { try await supervisor.guidedMusicKey(session: session, key: key, down: down, modifiers: modifiers) }
                        catch {
                            guard self?.musicState.guided.session == session else { return }
                            self?.stopMusic(); self?.addLog(.error, error.localizedDescription)
                        }
                    }
                }
                if self.musicGuidedOverlayEnabled { self.isHUDVisible = true }
                self.applyMusicState(state)
            } catch {
                self.musicGuidedKeyMonitor.stop()
                self.musicStatus = "无法开始跟弹：\(error.localizedDescription)"
            }
        }
    }

    func redetectGuidedMusic() {
        guard let supervisor = betterGICoreSupervisor, let session = musicState.guided.session, musicState.guided.active else { return }
        musicGuidedEditRevision &+= 1
        let revision = musicGuidedEditRevision
        Task { [weak self] in
            do {
                let state = try await supervisor.redetectGuidedMusic(session: session)
                guard self?.musicState.guided.session == session, self?.musicState.guided.active == true,
                      self?.musicGuidedEditRevision == revision else { return }
                self?.applyMusicState(state)
            } catch { self?.addLog(.error, "跟弹键位识别失败：\(error.localizedDescription)") }
        }
    }
    func updateGuidedMusicLayout(_ layout: BetterGIMusicGuidedLayout) {
        guard let supervisor = betterGICoreSupervisor, let session = musicState.guided.session, musicState.guided.active else { return }
        var layout = layout
        layout.manualCalibrated = true
        musicState.guided.keyLayout = layout
        musicGuidedEditRevision &+= 1
        let revision = musicGuidedEditRevision
        Task { [weak self] in
            do {
                let state = try await supervisor.updateGuidedMusicLayout(session: session, layout: layout)
                guard self?.musicState.guided.session == session, self?.musicState.guided.active == true,
                      self?.musicGuidedEditRevision == revision else { return }
                self?.applyMusicState(state)
            } catch { self?.addLog(.error, "跟弹键位调整失败：\(error.localizedDescription)") }
        }
    }

    func pauseOrResumeMusic() {
        let method = musicState.playback.state == .paused
            ? "music.resume" : "music.pause"
        runMusicCommand(method)
    }

    func stopMusic() {
        musicGuidedKeyMonitor.stop()
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
        musicSpeed = min(max(speed, 0.1), 10)
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
        disabledTrackIndexes: [Int],
        mappingModeOverride: String?
    ) {
        guard let supervisor = betterGICoreSupervisor else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                self.applyMusicState(try await supervisor.configureMusicTrack(
                    index: index,
                    outputProfileName: outputProfileName,
                    transpose: transpose,
                    disabledTrackIndexes: disabledTrackIndexes,
                    mappingModeOverride: mappingModeOverride))
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
        let selectedFullPath = selectedMusicTrack?.fullPath
        musicState = state
        musicPlaybackMode = state.playbackMode
        if state.guided.active {
            musicStatus = "跟弹：第 \(state.guided.segmentIndex + 1)/\(state.guided.segmentCount) 段，已弹 \(state.guided.progress) 次，错误 \(state.guided.errors) 次。请切回游戏手动演奏，Esc 停止。"
            startMusicPlaybackPolling()
        } else if state.playback.state != .stopped {
            musicSpeed = state.playback.speed
            if state.playback.queueIndex >= 0 {
                selectedMusicTrackIndex = state.playback.queueIndex
            }
            musicStatus = state.playback.state == .paused
                ? "已暂停：\(state.playback.trackName)"
                : "正在演奏：\(state.playback.trackName)"
            startMusicPlaybackPolling()
        } else {
            musicGuidedKeyMonitor.stop()
            if let error = state.guided.error { addLog(.error, error) }
            musicPlaybackPollTask?.cancel()
            musicPlaybackPollTask = nil
            musicStatus = state.rootFolder.isEmpty
                ? "请选择曲谱目录。"
                : "已载入 \(state.tracks.count) 首曲谱。"
            if let selectedFullPath,
               let track = state.tracks.first(where: { $0.fullPath == selectedFullPath }) {
                selectedMusicTrackIndex = track.index
            } else if let track = state.tracks.first(
                where: { $0.fullPath == state.savedTrackFullPath }) {
                selectedMusicTrackIndex = track.index
            } else {
                selectedMusicTrackIndex = state.tracks.first(where: \.isValid)?.index
            }
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
