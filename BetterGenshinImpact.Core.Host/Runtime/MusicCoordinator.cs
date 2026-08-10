using BetterGenshinImpact.GameTask.Music.Model;
using BetterGenshinImpact.GameTask.Music.Service;
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
    private string _rootFolder = string.Empty;
    private MusicPlaybackMode _playbackMode = MusicPlaybackMode.Sequential;
    private CancellationTokenSource? _playbackCancellation;
    private Task? _playbackTask;
    private int _disposed;

    public MusicCoordinator(
        ForegroundInputCoordinator input,
        CancellationToken hostCancellationToken,
        ILoggerFactory loggerFactory)
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
            loggerFactory.CreateLogger<MusicPlaybackService>());
        _playbackService.SnapshotChanged += OnSnapshotChanged;
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
            if (_playbackService.Snapshot.State != MusicPlaybackState.Stopped)
            {
                throw new InvalidOperationException("播放期间不能切换曲谱目录。");
            }

            _queue = await _libraryService.ScanAsync(rootFolder, _hostCancellationToken);
            foreach (var score in _queue.Where(score => score.IsValid))
            {
                _timelineBuilder.Build(
                    score,
                    _profileService.Find(score.OutputProfileName),
                    score.Transpose);
            }
            _rootFolder = rootFolder;
            _libraryService.Watch(rootFolder);
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
            playback = ToSnapshot(_playbackService.Snapshot),
        };
    }

    public async Task<object> PlayAsync(
        int index,
        double speed,
        MusicPlaybackMode playbackMode,
        double startPositionMilliseconds)
    {
        ThrowIfDisposed();
        await _mutationLock.WaitAsync(_hostCancellationToken);
        try
        {
            if (_queue.Count == 0)
            {
                throw new InvalidOperationException("曲库为空，请先选择并扫描曲谱目录。");
            }

            if (index < 0 || index >= _queue.Count)
            {
                throw new ArgumentOutOfRangeException(nameof(index));
            }

            if (_playbackService.Snapshot.State != MusicPlaybackState.Stopped)
            {
                throw new InvalidOperationException("已有曲目正在播放。");
            }

            _playbackMode = playbackMode;
            _playbackCancellation?.Dispose();
            _playbackCancellation = CancellationTokenSource.CreateLinkedTokenSource(
                _hostCancellationToken);
            using (_input.UseCancellationToken(_playbackCancellation.Token))
            {
                _playbackTask = _playbackService.RunPlaylistAsync(
                    _queue,
                    index,
                    new MusicPlaybackOptions
                    {
                        InputMode = MusicInputMode.ForegroundSendInput,
                        PlaybackMode = playbackMode,
                        Speed = speed,
                        StartPosition = TimeSpan.FromMilliseconds(
                            Math.Max(0, startPositionMilliseconds)),
                    },
                    _playbackCancellation.Token);
            }
            _ = ObservePlaybackAsync(_playbackTask);
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
        _playbackService.Stop();
        _playbackCancellation?.Cancel();
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

        SavePlaybackState();
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
        IReadOnlyCollection<int> disabledTrackIndexes)
    {
        await _mutationLock.WaitAsync(_hostCancellationToken);
        try
        {
            if (_playbackService.Snapshot.State != MusicPlaybackState.Stopped)
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
            foreach (var track in score.Tracks)
            {
                track.IsEnabled = !disabledTrackIndexes.Contains(track.Index);
            }

            _timelineBuilder.Build(score, profile, score.Transpose);

            _stateStore.State.Items[score.RelativePath] = new MusicItemPreference
            {
                OutputProfileName = score.OutputProfileName,
                Transpose = score.Transpose,
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
        _playbackService.Stop();
        _playbackCancellation?.Cancel();
        _playbackCancellation?.Dispose();
        _libraryService.Dispose();
        _stateStore.Save();
        _mutationLock.Dispose();
    }

    private async Task ObservePlaybackAsync(Task task)
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
            SavePlaybackState();
        }
    }

    private void OnSnapshotChanged(object? sender, PlaybackSnapshot snapshot)
    {
        if (snapshot.QueueIndex >= 0 && snapshot.QueueIndex < _queue.Count)
        {
            _stateStore.State.CurrentTrackFullPath = _queue[snapshot.QueueIndex].FullPath;
        }

        _stateStore.State.CurrentPositionMilliseconds = snapshot.Position.TotalMilliseconds;
    }

    private void SavePlaybackState()
    {
        var snapshot = _playbackService.Snapshot;
        OnSnapshotChanged(this, snapshot);
        _stateStore.Save();
    }

    private static object ToTrack(PerformanceScore score, int index)
    {
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

    private static object ToSnapshot(PlaybackSnapshot snapshot)
    {
        return new
        {
            state = snapshot.State.ToString(),
            positionMilliseconds = snapshot.Position.TotalMilliseconds,
            durationMilliseconds = snapshot.Duration.TotalMilliseconds,
            speed = snapshot.Speed,
            trackName = snapshot.TrackName,
            queueIndex = snapshot.QueueIndex,
        };
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref _disposed) != 0, this);
    }
}
