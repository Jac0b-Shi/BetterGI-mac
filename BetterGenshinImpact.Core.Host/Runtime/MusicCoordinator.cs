using BetterGenshinImpact.GameTask.Music.Model;
using BetterGenshinImpact.GameTask.Music.Service;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.GameTask;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MusicCoordinator : IDisposable
{
    private readonly CancellationToken _hostCancellationToken;
    private readonly ILogger<MusicCoordinator> _logger;
    private readonly ForegroundInputCoordinator _input;
    private readonly MusicStateStore _stateStore;
    private readonly InstrumentProfileService _profileService;
    private readonly MusicLibraryService _libraryService;
    private readonly MusicTimelineBuilder _timelineBuilder;
    private readonly MusicPlaybackService _playbackService;
    private readonly SemaphoreSlim _mutationLock = new(1, 1);
    private IReadOnlyList<PerformanceScore> _queue = [];
    private IReadOnlyList<PerformanceScore> _playableQueue = [];
    private IReadOnlyList<int> _playableCatalogIndexes = [];
    private string _rootFolder = string.Empty;
    private MusicPlaybackMode _playbackMode = MusicPlaybackMode.Sequential;
    private CancellationTokenSource? _playbackCancellation;
    private Task? _playbackTask;
    private int _startingCatalogIndex = -1;
    private double _startingSpeed = 1;
    private int _sessionStarting;
    private int _sessionGeneration;
    private int _disposed;

    public MusicCoordinator(
        ForegroundInputCoordinator input,
        CancellationToken hostCancellationToken,
        ILoggerFactory loggerFactory,
        IMusicInstrumentSwitcher? instrumentSwitcher = null)
    {
        _hostCancellationToken = hostCancellationToken;
        _input = input;
        _logger = loggerFactory.CreateLogger<MusicCoordinator>();
        _stateStore = new MusicStateStore(loggerFactory.CreateLogger<MusicStateStore>());
        _profileService = new InstrumentProfileService(
            loggerFactory.CreateLogger<InstrumentProfileService>());
        var parser = new MusicScoreParser();
        _libraryService = new MusicLibraryService(
            parser,
            _stateStore,
            loggerFactory.CreateLogger<MusicLibraryService>());
        _timelineBuilder = new MusicTimelineBuilder(_profileService);
        var transport = new MacMusicKeyInputTransport(input, hostCancellationToken);
        _playbackService = new MusicPlaybackService(
            _timelineBuilder,
            _profileService,
            [transport],
            loggerFactory.CreateLogger<MusicPlaybackService>(),
            new MacMusicPlaybackGate(input, hostCancellationToken),
            instrumentSwitcher);
        _playbackService.SnapshotChanged += OnSnapshotChanged;
        _playbackService.PlaybackEnded += OnPlaybackEnded;
    }

    public async Task<object> ScanAsync(string rootFolder)
    {
        ThrowIfDisposed();
        rootFolder = Path.GetFullPath(rootFolder);
        if (!Directory.Exists(rootFolder))
        {
            throw new DirectoryNotFoundException($"曲谱目录不存在：{rootFolder}");
        }

        await _mutationLock.WaitAsync(_hostCancellationToken);
        try
        {
            if (_playbackService.Snapshot.State != MusicPlaybackState.Stopped ||
                Volatile.Read(ref _sessionStarting) != 0)
            {
                throw new InvalidOperationException("播放期间不能切换曲谱目录。");
            }

            _queue = await _libraryService.ScanAsync(rootFolder, _hostCancellationToken);
            _playableCatalogIndexes = _queue
                .Select((score, index) => (score, index))
                .Where(entry => entry.score.IsValid)
                .Select(entry => entry.index)
                .ToArray();
            _playableQueue = _playableCatalogIndexes.Select(index => _queue[index]).ToArray();
            foreach (var score in _queue.Where(score => score.IsValid))
            {
                _timelineBuilder.Build(
                    score,
                    _profileService.Find(score.OutputProfileName),
                    score.Transpose);
            }
            _rootFolder = rootFolder;
            var history = _stateStore.State.MusicFolderHistory;
            history.RemoveAll(path => string.Equals(path, rootFolder, StringComparison.Ordinal));
            history.Insert(0, rootFolder);
            if (history.Count > 10)
            {
                history.RemoveRange(10, history.Count - 10);
            }

            _stateStore.Save();
            return State();
        }
        finally
        {
            _mutationLock.Release();
        }
    }

    public object State()
    {
        ThrowIfDisposed();
        return new
        {
            rootFolder = _rootFolder,
            folderHistory = _stateStore.State.MusicFolderHistory.ToArray(),
            playbackMode = _playbackMode.ToString(),
            profiles = _profileService.Profiles.Select(profile => new
            {
                name = profile.Name,
                mappingMode = profile.MappingMode.ToString(),
            }).ToArray(),
            tracks = _queue.Select(ToTrack).ToArray(),
            savedTrackFullPath = _stateStore.State.CurrentTrackFullPath,
            savedPositionMilliseconds = _stateStore.State.CurrentPositionMilliseconds,
            playback = ToSnapshotForCatalog(_playbackService.Snapshot),
        };
    }

    public async Task<object> PlayAsync(
        int index,
        double speed,
        MusicPlaybackMode playbackMode,
        double startPositionMilliseconds,
        double? customBpm = null,
        bool autoSwitchInstrument = false)
    {
        ThrowIfDisposed();
        await _mutationLock.WaitAsync(_hostCancellationToken);
        try
        {
            if (_playableQueue.Count == 0)
            {
                throw new InvalidOperationException("曲库中没有可播放的有效曲谱。");
            }

            if (index < 0 || index >= _queue.Count)
            {
                throw new ArgumentOutOfRangeException(nameof(index));
            }

            if (_playbackService.Snapshot.State != MusicPlaybackState.Stopped ||
                Volatile.Read(ref _sessionStarting) != 0)
            {
                throw new InvalidOperationException("已有曲目正在播放。");
            }

            var playableIndex = FindPlayableIndex(_playableCatalogIndexes, index);
            if (playableIndex < 0)
            {
                throw new InvalidOperationException("所选曲谱解析失败，无法播放。");
            }

            var score = _queue[index];
            var profile = _profileService.Find(score.OutputProfileName);
            var effectiveTimeline = _timelineBuilder.Build(
                score,
                profile,
                score.Transpose);
            var startPosition = NormalizeStartPosition(
                startPositionMilliseconds,
                effectiveTimeline.Duration);

            _playbackCancellation?.Dispose();
            _playbackCancellation = CancellationTokenSource.CreateLinkedTokenSource(
                _hostCancellationToken);
            _startingCatalogIndex = index;
            _startingSpeed = Math.Clamp(speed, 0.1, 10.0);
            var sessionGeneration = Interlocked.Increment(ref _sessionGeneration);
            var previousPlaybackMode = _playbackMode;
            var previousTrackFullPath = _stateStore.State.CurrentTrackFullPath;
            var previousPositionMilliseconds =
                _stateStore.State.CurrentPositionMilliseconds;
            _playbackMode = playbackMode;
            _stateStore.State.CurrentTrackFullPath = _queue[index].FullPath;
            _stateStore.State.CurrentPositionMilliseconds = startPosition;
            Volatile.Write(ref _sessionStarting, 1);
            try
            {
                var sessionCancellation = _playbackCancellation;
                _playbackTask = new TaskRunner().StartThread(
                    async () =>
                    {
                        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
                            sessionCancellation.Token,
                            CancellationContext.Instance.Cts.Token);
                        using (_input.UseCancellationToken(linked.Token))
                        {
                            var playback = _playbackService.RunPlaylistAsync(
                                _playableQueue,
                                playableIndex,
                                new MusicPlaybackOptions
                                {
                                    InputMode = MusicInputMode.ForegroundSendInput,
                                    PlaybackMode = playbackMode,
                                    Speed = speed,
                                    CustomBpm = customBpm is > 0 ? customBpm : null,
                                    AutoSwitchInstrument = autoSwitchInstrument,
                                    StartPosition = TimeSpan.FromMilliseconds(startPosition),
                                },
                                linked.Token);
                            if (Volatile.Read(ref _sessionGeneration) == sessionGeneration)
                            {
                                Volatile.Write(ref _sessionStarting, 0);
                            }
                            await playback;
                        }
                    },
                    sessionCancellation.Token,
                    waitForInputDuringInitialization: false);
            }
            catch
            {
                Volatile.Write(ref _sessionStarting, 0);
                _startingCatalogIndex = -1;
                _playbackMode = previousPlaybackMode;
                _stateStore.State.CurrentTrackFullPath = previousTrackFullPath;
                _stateStore.State.CurrentPositionMilliseconds =
                    previousPositionMilliseconds;
                _playbackCancellation.Dispose();
                _playbackCancellation = null;
                throw;
            }
            _ = ObservePlaybackAsync(_playbackTask, sessionGeneration);
            return State();
        }
        finally
        {
            _mutationLock.Release();
        }
    }

    public object Pause()
    {
        _playbackService.Pause();
        SavePlaybackState();
        return State();
    }

    public object Resume()
    {
        _playbackService.Resume();
        return State();
    }

    public async Task<object> StopAsync()
    {
        var hadActiveSession =
            _playbackService.Snapshot.State != MusicPlaybackState.Stopped ||
            Volatile.Read(ref _sessionStarting) != 0;
        _playbackCancellation?.Cancel();
        Volatile.Write(ref _sessionStarting, 0);
        _playbackService.Stop();
        var task = _playbackTask;
        if (task is not null)
        {
            try
            {
                await task;
            }
            catch (OperationCanceledException)
            {
            }
        }

        if (hadActiveSession)
        {
            _stateStore.State.CurrentPositionMilliseconds = 0;
        }
        _stateStore.Save();
        return State();
    }

    public object Next()
    {
        _playbackService.Next();
        return State();
    }

    public object Previous()
    {
        _playbackService.Previous();
        return State();
    }

    public object Seek(double positionMilliseconds)
    {
        _playbackService.Seek(TimeSpan.FromMilliseconds(Math.Max(0, positionMilliseconds)));
        SavePlaybackState();
        return State();
    }

    public object SetSpeed(double speed)
    {
        _playbackService.SetSpeed(speed);
        return State();
    }

    public object SetPlaybackMode(MusicPlaybackMode mode)
    {
        _playbackMode = mode;
        _playbackService.SetPlaybackMode(mode);
        return State();
    }

    public async Task<object> ConfigureTrackAsync(
        int index,
        string? outputProfileName,
        int transpose,
        IReadOnlyCollection<int> disabledTrackIndexes,
        InstrumentMappingMode? mappingModeOverride)
    {
        await _mutationLock.WaitAsync(_hostCancellationToken);
        try
        {
            if (_playbackService.Snapshot.State != MusicPlaybackState.Stopped ||
                Volatile.Read(ref _sessionStarting) != 0)
            {
                throw new InvalidOperationException("播放期间不能修改曲目映射。");
            }

            if (index < 0 || index >= _queue.Count)
            {
                throw new ArgumentOutOfRangeException(nameof(index));
            }

            var score = _queue[index];
            var profile = _profileService.Find(outputProfileName);
            score.OutputProfileName = profile.Name;
            score.Transpose = Math.Clamp(transpose, -36, 36);
            score.MappingModeOverride = mappingModeOverride;
            foreach (var track in score.Tracks)
            {
                track.IsEnabled = !disabledTrackIndexes.Contains(track.Index);
            }

            _timelineBuilder.Build(score, profile, score.Transpose);

            _stateStore.State.Items[score.RelativePath] = new MusicItemPreference
            {
                OutputProfileName = score.OutputProfileName,
                Transpose = score.Transpose,
                MappingModeOverride = mappingModeOverride,
                DisabledTrackIndexes = score.Tracks
                    .Where(track => !track.IsEnabled)
                    .Select(track => track.Index)
                    .ToList(),
            };
            _stateStore.Save();
            return State();
        }
        finally
        {
            _mutationLock.Release();
        }
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0)
        {
            return;
        }

        _playbackService.SnapshotChanged -= OnSnapshotChanged;
        _playbackService.PlaybackEnded -= OnPlaybackEnded;
        _playbackCancellation?.Cancel();
        Volatile.Write(ref _sessionStarting, 0);
        _playbackService.Stop();
        _playbackCancellation?.Dispose();
        _libraryService.Dispose();
        _stateStore.Save();
        _mutationLock.Dispose();
    }

    private async Task ObservePlaybackAsync(Task task, int sessionGeneration)
    {
        try
        {
            await task;
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "自动演奏播放失败");
        }
        finally
        {
            if (Volatile.Read(ref _sessionGeneration) == sessionGeneration)
            {
                Volatile.Write(ref _sessionStarting, 0);
                _startingCatalogIndex = -1;
            }
            SavePlaybackState();
        }
    }

    private void OnSnapshotChanged(object? sender, PlaybackSnapshot snapshot)
    {
        var catalogIndex = ToCatalogIndex(snapshot.QueueIndex);
        if (catalogIndex >= 0 && catalogIndex < _queue.Count)
        {
            _stateStore.State.CurrentTrackFullPath = _queue[catalogIndex].FullPath;
            _stateStore.State.CurrentPositionMilliseconds = snapshot.Position.TotalMilliseconds;
        }
    }

    private void OnPlaybackEnded(object? sender, MusicPlaybackEndedEventArgs args)
    {
        if (!ApplyPlaybackCompletion(
                _stateStore.State,
                _queue,
                _playableCatalogIndexes,
                args))
        {
            return;
        }
        _stateStore.Save();
    }

    internal static bool ApplyPlaybackCompletion(
        MusicLibraryState state,
        IReadOnlyList<PerformanceScore> queue,
        IReadOnlyList<int> playableCatalogIndexes,
        MusicPlaybackEndedEventArgs args)
    {
        if (args.Reason == MusicPlaybackCompletionReason.Cancelled)
        {
            return false;
        }

        var catalogIndex = MapPlayableIndex(playableCatalogIndexes, args.QueueIndex);
        if (catalogIndex >= 0 && catalogIndex < queue.Count)
        {
            state.CurrentTrackFullPath = queue[catalogIndex].FullPath;
        }
        state.CurrentPositionMilliseconds = 0;
        return true;
    }

    internal static double NormalizeStartPosition(
        double requestedMilliseconds,
        TimeSpan duration)
    {
        var requested = Math.Max(0, requestedMilliseconds);
        if (duration <= TimeSpan.Zero)
        {
            return 0;
        }

        var restartThreshold = Math.Max(0, duration.TotalMilliseconds - 50);
        return requested >= restartThreshold ? 0 : requested;
    }

    private void SavePlaybackState()
    {
        var snapshot = _playbackService.Snapshot;
        OnSnapshotChanged(this, snapshot);
        _stateStore.Save();
    }

    private object ToTrack(PerformanceScore score, int index)
    {
        var profile = _profileService.Find(score.OutputProfileName);
        return new
        {
            index,
            fullPath = score.FullPath,
            relativePath = score.RelativePath,
            title = score.DisplayTitle,
            author = score.Author,
            instrument = score.Instrument,
            description = score.Description,
            composer = score.Composer,
            arranger = score.Arranger,
            format = score.Format.ToString(),
            formatName = score.FormatName,
            durationMilliseconds = score.Duration.TotalMilliseconds,
            noteCount = score.NoteCount,
            playableRatio = score.PlayableRatio,
            isValid = score.IsValid,
            error = score.Error,
            outputProfileName = score.OutputProfileName,
            transpose = score.Transpose,
            mappingModeOverride = score.MappingModeOverride?.ToString(),
            mappingMode = (score.MappingModeOverride ?? profile.MappingMode).ToString(),
            midiTracks = score.Tracks.Select(track => new
            {
                index = track.Index,
                name = track.Name,
                noteCount = track.NoteCount,
                minNoteNumber = track.MinNoteNumber,
                maxNoteNumber = track.MaxNoteNumber,
                isEnabled = track.IsEnabled,
                playableRatio = track.PlayableRatio,
            }).ToArray(),
        };
    }

    private object ToSnapshotForCatalog(PlaybackSnapshot snapshot)
    {
        if (snapshot.State == MusicPlaybackState.Stopped &&
            Volatile.Read(ref _sessionStarting) != 0 &&
            _startingCatalogIndex >= 0 &&
            _startingCatalogIndex < _queue.Count)
        {
            var score = _queue[_startingCatalogIndex];
            return new
            {
                state = MusicPlaybackState.Playing.ToString(),
                positionMilliseconds = 0d,
                durationMilliseconds = score.Duration.TotalMilliseconds,
                speed = _startingSpeed,
                trackName = score.DisplayTitle,
                queueIndex = _startingCatalogIndex,
            };
        }

        return new
        {
            state = snapshot.State.ToString(),
            positionMilliseconds = snapshot.Position.TotalMilliseconds,
            durationMilliseconds = snapshot.Duration.TotalMilliseconds,
            speed = snapshot.Speed,
            trackName = snapshot.TrackName,
            queueIndex = MapPlayableIndex(_playableCatalogIndexes, snapshot.QueueIndex),
        };
    }

    internal static int MapPlayableIndex(
        IReadOnlyList<int> playableCatalogIndexes,
        int playableIndex) =>
        playableIndex >= 0 && playableIndex < playableCatalogIndexes.Count
            ? playableCatalogIndexes[playableIndex]
            : -1;

    internal static int FindPlayableIndex(
        IReadOnlyList<int> playableCatalogIndexes,
        int catalogIndex)
    {
        for (var index = 0; index < playableCatalogIndexes.Count; index++)
        {
            if (playableCatalogIndexes[index] == catalogIndex)
            {
                return index;
            }
        }

        return -1;
    }

    private int ToCatalogIndex(int playableIndex) =>
        MapPlayableIndex(_playableCatalogIndexes, playableIndex);

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref _disposed) != 0, this);
    }
}
