using BetterGenshinImpact.GameTask.Music.Model;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.GameTask.Music.Service;

public sealed class MusicPlaybackService(
    IMusicTimelineBuilder timelineBuilder,
    IInstrumentProfileService profileService,
    IEnumerable<IKeyInputTransport> transports,
    ILogger<MusicPlaybackService>? logger = null,
    IMusicPlaybackGate? playbackGate = null) : IMusicPlaybackService
{
    private readonly ILogger<MusicPlaybackService> _logger =
        logger ?? NullLogger<MusicPlaybackService>.Instance;
    private readonly object _syncRoot = new();
    private readonly Dictionary<MusicInputMode, IKeyInputTransport> _transports =
        transports.ToDictionary(x => x.Mode);
    private readonly IMusicPlaybackGate _playbackGate =
        playbackGate ?? AlwaysAvailableMusicPlaybackGate.Instance;

    private PlaybackSnapshot _snapshot = new();
    private IKeyInputTransport? _transport;
    private PerformanceTimeline _timeline = PerformanceTimeline.Empty;
    private CancellationTokenSource? _controlCancellationTokenSource;
    private TaskCompletionSource _resumeSource = CreateCompletedSource();
    private MusicPlaybackState _state = MusicPlaybackState.Stopped;
    private MusicPlaybackMode _playbackMode;
    private double _speed = 1.0;
    private TimeSpan _anchorPosition;
    private long _anchorTimestamp;
    private string _trackName = string.Empty;
    private int _queueIndex = -1;
    private bool _stopRequested;
    private int _skipDirection;
    private bool _needsHeldKeyRebuild;
    private bool _restartFromAnchorPosition;

    public event EventHandler<PlaybackSnapshot>? SnapshotChanged;

    public event EventHandler<MusicPlaybackEndedEventArgs>? PlaybackEnded;

    public PlaybackSnapshot Snapshot
    {
        get
        {
            lock (_syncRoot)
            {
                return CreateSnapshotLocked();
            }
        }
    }

    public async Task RunPlaylistAsync(
        IReadOnlyList<PerformanceScore> queue,
        int startIndex,
        MusicPlaybackOptions options,
        CancellationToken cancellationToken)
    {
        if (queue.Count == 0)
        {
            return;
        }

        lock (_syncRoot)
        {
            if (_state != MusicPlaybackState.Stopped)
            {
                return;
            }

            _transport = _transports[options.InputMode];
            _playbackMode = options.PlaybackMode;
            _speed = Math.Clamp(options.Speed, 0.5, 2.0);
            _stopRequested = false;
            _skipDirection = 0;
        }

        var currentIndex = Math.Clamp(startIndex, 0, queue.Count - 1);
        var isFirstTrack = true;
        var completionReason = MusicPlaybackCompletionReason.Cancelled;
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var score = queue[currentIndex];
                var profile = profileService.Find(score.OutputProfileName);
                var timeline = timelineBuilder.Build(score, profile, score.Transpose);
                var startPosition = isFirstTrack ? options.StartPosition : TimeSpan.Zero;
                isFirstTrack = false;
                PrepareTrack(timeline, score.DisplayTitle, currentIndex, startPosition);

                var result = await PlayTimelineAsync(cancellationToken);
                _transport?.ReleaseAll();
                lock (_syncRoot)
                {
                    if (_stopRequested)
                    {
                        completionReason = MusicPlaybackCompletionReason.ExplicitStop;
                        break;
                    }
                }
                if (result == TrackResult.Stop)
                {
                    completionReason = MusicPlaybackCompletionReason.ExplicitStop;
                    break;
                }

                if (result == TrackResult.Previous)
                {
                    currentIndex = currentIndex == 0 ? queue.Count - 1 : currentIndex - 1;
                    continue;
                }

                if (result == TrackResult.Next)
                {
                    currentIndex = currentIndex == queue.Count - 1 ? 0 : currentIndex + 1;
                    continue;
                }

                currentIndex = _playbackMode switch
                {
                    MusicPlaybackMode.SingleLoop => currentIndex,
                    MusicPlaybackMode.Shuffle when queue.Count > 1 => GetRandomIndex(queue.Count, currentIndex),
                    MusicPlaybackMode.Shuffle => currentIndex,
                    MusicPlaybackMode.Sequential when currentIndex < queue.Count - 1 => currentIndex + 1,
                    _ => -1
                };
                if (currentIndex < 0)
                {
                    completionReason = MusicPlaybackCompletionReason.NaturalCompletion;
                    break;
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            lock (_syncRoot)
            {
                if (_stopRequested)
                {
                    completionReason = MusicPlaybackCompletionReason.ExplicitStop;
                }
            }
            // TaskRunner 负责记录任务取消
        }
        finally
        {
            _transport?.ReleaseAll();
            MusicPlaybackEndedEventArgs ended;
            lock (_syncRoot)
            {
                ended = new MusicPlaybackEndedEventArgs(
                    completionReason,
                    _queueIndex,
                    GetCurrentPositionLocked());
                _controlCancellationTokenSource?.Cancel();
                _controlCancellationTokenSource?.Dispose();
                _controlCancellationTokenSource = null;
                _state = MusicPlaybackState.Stopped;
                _anchorPosition = TimeSpan.Zero;
                _anchorTimestamp = 0;
                _trackName = string.Empty;
                _queueIndex = -1;
                _timeline = PerformanceTimeline.Empty;
                _stopRequested = false;
                _skipDirection = 0;
                _restartFromAnchorPosition = false;
                _snapshot = CreateSnapshotLocked();
            }

            PlaybackEnded?.Invoke(this, ended);
            PublishSnapshot();
        }
    }

    public void Pause()
    {
        lock (_syncRoot)
        {
            if (_state != MusicPlaybackState.Playing)
            {
                return;
            }

            _anchorPosition = GetCurrentPositionLocked();
            _anchorTimestamp = 0;
            _state = MusicPlaybackState.Paused;
            _needsHeldKeyRebuild = true;
            _resumeSource = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            SignalControlLocked();
            _snapshot = CreateSnapshotLocked();
        }

        _transport?.ReleaseAll();
        PublishSnapshot();
    }

    public void Resume()
    {
        lock (_syncRoot)
        {
            if (_state != MusicPlaybackState.Paused)
            {
                return;
            }

            _state = MusicPlaybackState.Playing;
            _anchorTimestamp = 0;
            _restartFromAnchorPosition = true;
            _resumeSource.TrySetResult();
            SignalControlLocked();
            _snapshot = CreateSnapshotLocked();
        }

        PublishSnapshot();
    }

    public void Stop()
    {
        lock (_syncRoot)
        {
            if (_state == MusicPlaybackState.Stopped)
            {
                return;
            }

            _stopRequested = true;
            _resumeSource.TrySetResult();
            SignalControlLocked();
        }

        _transport?.ReleaseAll();
    }

    public void Next()
    {
        Skip(1);
    }

    public void Previous()
    {
        Skip(-1);
    }

    public void Seek(TimeSpan position)
    {
        lock (_syncRoot)
        {
            if (_state == MusicPlaybackState.Stopped)
            {
                return;
            }

            _anchorPosition = Clamp(position, TimeSpan.Zero, _timeline.Duration);
            _anchorTimestamp = 0;
            _restartFromAnchorPosition = _state == MusicPlaybackState.Playing;
            _needsHeldKeyRebuild = true;
            SignalControlLocked();
            _snapshot = CreateSnapshotLocked();
        }

        _transport?.ReleaseAll();
        PublishSnapshot();
    }

    public void SetSpeed(double speed)
    {
        lock (_syncRoot)
        {
            speed = Math.Clamp(speed, 0.5, 2.0);
            if (Math.Abs(_speed - speed) < 0.001)
            {
                return;
            }

            _anchorPosition = GetCurrentPositionLocked();
            _speed = speed;
            _anchorTimestamp = 0;
            _restartFromAnchorPosition = _state == MusicPlaybackState.Playing;
            SignalControlLocked();
            _snapshot = CreateSnapshotLocked();
        }

        PublishSnapshot();
    }

    public void SetPlaybackMode(MusicPlaybackMode mode)
    {
        lock (_syncRoot)
        {
            _playbackMode = mode;
        }
    }

    private async Task<TrackResult> PlayTimelineAsync(CancellationToken cancellationToken)
    {
        while (true)
        {
            Task? resumeTask = null;
            CancellationToken controlToken;
            TimeSpan position;
            bool rebuildHeldKeys;

            lock (_syncRoot)
            {
                if (_stopRequested)
                {
                    return TrackResult.Stop;
                }

                if (_skipDirection != 0)
                {
                    var result = _skipDirection > 0 ? TrackResult.Next : TrackResult.Previous;
                    _skipDirection = 0;
                    return result;
                }

                if (_state == MusicPlaybackState.Paused)
                {
                    resumeTask = _resumeSource.Task;
                    controlToken = CancellationToken.None;
                    position = _anchorPosition;
                    rebuildHeldKeys = false;
                }
                else
                {
                    _controlCancellationTokenSource?.Dispose();
                    _controlCancellationTokenSource = new CancellationTokenSource();
                    controlToken = _controlCancellationTokenSource.Token;
                    if (_restartFromAnchorPosition)
                    {
                        position = _anchorPosition;
                        _anchorTimestamp = Stopwatch.GetTimestamp();
                        _restartFromAnchorPosition = false;
                    }
                    else
                    {
                        position = GetCurrentPositionLocked();
                    }
                    rebuildHeldKeys = _needsHeldKeyRebuild;
                    _needsHeldKeyRebuild = false;
                }
            }

            if (resumeTask != null)
            {
                await resumeTask.WaitAsync(cancellationToken);
                continue;
            }

            if (rebuildHeldKeys)
            {
                try
                {
                    RebuildHeldKeys(position);
                }
                catch (MusicInputUnavailableException)
                {
                    using var rebuildCancellation =
                        CancellationTokenSource.CreateLinkedTokenSource(
                            controlToken, cancellationToken);
                    await FreezeUntilInputAvailableAsync(
                        rebuildCancellation.Token,
                        forceFreeze: true,
                        freezeAtOrBefore: position);
                    continue;
                }
            }

            var startIndex = FindFirstEventAtOrAfter(position);
            try
            {
                for (var eventIndex = startIndex; eventIndex < _timeline.Events.Count;)
                {
                    var item = _timeline.Events[eventIndex];
                    await WaitUntilAsync(item.Time, controlToken, cancellationToken);
                    var batchStartIndex = eventIndex;
                    do
                    {
                        eventIndex++;
                    } while (eventIndex < _timeline.Events.Count &&
                             _timeline.Events[eventIndex].Time == item.Time);
                    var batchCount = eventIndex - batchStartIndex;

                    try
                    {
                        var dispatchStarted = Stopwatch.GetTimestamp();
                        _transport?.DispatchBatch(
                            _timeline.Events,
                            batchStartIndex,
                            batchCount);
                        var dispatchElapsed = Stopwatch.GetElapsedTime(dispatchStarted);
                        if (dispatchElapsed >= TimeSpan.FromMilliseconds(10))
                        {
                            _logger.LogDebug(
                                "自动演奏同刻事件派发耗时 {ElapsedMilliseconds:F1} ms，事件数 {EventCount}",
                                dispatchElapsed.TotalMilliseconds,
                                batchCount);
                        }
                    }
                    catch (MusicInputUnavailableException)
                    {
                        using var inputCancellation =
                            CancellationTokenSource.CreateLinkedTokenSource(
                                controlToken, cancellationToken);
                    await FreezeUntilInputAvailableAsync(
                        inputCancellation.Token,
                        forceFreeze: true,
                        freezeAtOrBefore: item.Time);
                        throw new OperationCanceledException(controlToken);
                    }
                }

                await WaitUntilAsync(_timeline.Duration, controlToken, cancellationToken);
                lock (_syncRoot)
                {
                    _anchorPosition = _timeline.Duration;
                    _anchorTimestamp = 0;
                    _snapshot = CreateSnapshotLocked();
                }

                PublishSnapshot();
                return TrackResult.Finished;
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                // 暂停、跳转、调速或切歌会中断当前等待，并从新锚点继续。
            }
        }
    }

    private async Task WaitUntilAsync(
        TimeSpan targetPosition,
        CancellationToken controlToken,
        CancellationToken cancellationToken)
    {
        using var linkedCancellationTokenSource =
            CancellationTokenSource.CreateLinkedTokenSource(controlToken, cancellationToken);
        while (true)
        {
            if (await FreezeUntilInputAvailableAsync(
                    linkedCancellationTokenSource.Token,
                    freezeAtOrBefore: targetPosition))
            {
                throw new OperationCanceledException(controlToken);
            }

            double speed;
            TimeSpan currentPosition;
            lock (_syncRoot)
            {
                currentPosition = GetCurrentPositionLocked();
                speed = _speed;
                _snapshot = CreateSnapshotLocked();
            }

            PublishSnapshot();
            var remaining = targetPosition - currentPosition;
            if (remaining <= TimeSpan.Zero)
            {
                return;
            }

            var realDelay = TimeSpan.FromTicks((long)(remaining.Ticks / speed));
            var delay = realDelay > TimeSpan.FromMilliseconds(100)
                ? TimeSpan.FromMilliseconds(100)
                : realDelay;
            await Task.Delay(delay, linkedCancellationTokenSource.Token);
        }
    }

    private async Task<bool> FreezeUntilInputAvailableAsync(
        CancellationToken cancellationToken,
        bool forceFreeze = false,
        TimeSpan? freezeAtOrBefore = null)
    {
        TimeSpan freezePosition;
        lock (_syncRoot)
        {
            freezePosition = GetCurrentPositionLocked();
            if (freezeAtOrBefore is { } pendingPosition &&
                pendingPosition < freezePosition)
            {
                freezePosition = pendingPosition;
            }
        }

        if (!forceFreeze && _playbackGate.IsAvailable(cancellationToken))
        {
            return false;
        }

        cancellationToken.ThrowIfCancellationRequested();
        lock (_syncRoot)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (_state != MusicPlaybackState.Playing)
            {
                return false;
            }

            _anchorPosition = freezePosition;
            _anchorTimestamp = 0;
            _needsHeldKeyRebuild = true;
            _restartFromAnchorPosition = true;
            _snapshot = CreateSnapshotLocked();
        }

        _transport?.ReleaseAll();
        PublishSnapshot();
        await _playbackGate.WaitUntilAvailableAsync(cancellationToken);

        lock (_syncRoot)
        {
            if (_state == MusicPlaybackState.Playing)
            {
                _anchorTimestamp = 0;
                _snapshot = CreateSnapshotLocked();
            }
        }

        PublishSnapshot();
        return true;
    }

    private void PrepareTrack(
        PerformanceTimeline timeline,
        string trackName,
        int queueIndex,
        TimeSpan startPosition)
    {
        lock (_syncRoot)
        {
            _timeline = timeline;
            _trackName = trackName;
            _queueIndex = queueIndex;
            _anchorPosition = Clamp(startPosition, TimeSpan.Zero, timeline.Duration);
            _anchorTimestamp = 0;
            _state = MusicPlaybackState.Playing;
            _skipDirection = 0;
            _needsHeldKeyRebuild = _anchorPosition > TimeSpan.Zero;
            _restartFromAnchorPosition = true;
            _resumeSource = CreateCompletedSource();
            _snapshot = CreateSnapshotLocked();
        }

        _logger.LogInformation("正在播放：{TrackName}", trackName);
        PublishSnapshot();
    }

    private void Skip(int direction)
    {
        lock (_syncRoot)
        {
            if (_state == MusicPlaybackState.Stopped)
            {
                return;
            }

            _skipDirection = direction;
            _state = MusicPlaybackState.Playing;
            _resumeSource.TrySetResult();
            SignalControlLocked();
        }

        _transport?.ReleaseAll();
    }

    private void RebuildHeldKeys(TimeSpan position)
    {
        _transport?.ReleaseAll();
        var states = new Dictionary<char, bool>();
        foreach (var item in _timeline.Events)
        {
            if (item.Time >= position)
            {
                break;
            }

            states[item.Key] = item.Type == PerformanceEventType.KeyDown;
        }

        foreach (var key in states.Where(x => x.Value).Select(x => x.Key))
        {
            _transport?.KeyDown(key);
        }
    }

    private int FindFirstEventAtOrAfter(TimeSpan position)
    {
        var low = 0;
        var high = _timeline.Events.Count;
        while (low < high)
        {
            var middle = low + (high - low) / 2;
            if (_timeline.Events[middle].Time < position)
            {
                low = middle + 1;
            }
            else
            {
                high = middle;
            }
        }

        return low;
    }

    private TimeSpan GetCurrentPositionLocked()
    {
        if (_state != MusicPlaybackState.Playing || _anchorTimestamp == 0)
        {
            return Clamp(_anchorPosition, TimeSpan.Zero, _timeline.Duration);
        }

        var elapsedSeconds = (Stopwatch.GetTimestamp() - _anchorTimestamp) / (double)Stopwatch.Frequency;
        var position = _anchorPosition + TimeSpan.FromSeconds(elapsedSeconds * _speed);
        return Clamp(position, TimeSpan.Zero, _timeline.Duration);
    }

    private PlaybackSnapshot CreateSnapshotLocked()
    {
        return new PlaybackSnapshot
        {
            State = _state,
            Position = GetCurrentPositionLocked(),
            Duration = _timeline.Duration,
            Speed = _speed,
            TrackName = _trackName,
            QueueIndex = _queueIndex
        };
    }

    private void SignalControlLocked()
    {
        try
        {
            _controlCancellationTokenSource?.Cancel();
        }
        catch (ObjectDisposedException)
        {
            // 调度循环已经替换了控制令牌
        }
    }

    private void PublishSnapshot()
    {
        PlaybackSnapshot snapshot;
        lock (_syncRoot)
        {
            snapshot = _snapshot = CreateSnapshotLocked();
        }

        SnapshotChanged?.Invoke(this, snapshot);
    }

    private static int GetRandomIndex(int count, int currentIndex)
    {
        var next = Random.Shared.Next(count - 1);
        return next >= currentIndex ? next + 1 : next;
    }

    private static TimeSpan Clamp(TimeSpan value, TimeSpan min, TimeSpan max)
    {
        if (value < min)
        {
            return min;
        }

        return value > max ? max : value;
    }

    private static TaskCompletionSource CreateCompletedSource()
    {
        var source = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        source.TrySetResult();
        return source;
    }

    private enum TrackResult
    {
        Finished,
        Next,
        Previous,
        Stop
    }

    private sealed class AlwaysAvailableMusicPlaybackGate : IMusicPlaybackGate
    {
        public static readonly AlwaysAvailableMusicPlaybackGate Instance = new();

        public bool IsAvailable(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return true;
        }

        public Task WaitUntilAvailableAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.CompletedTask;
        }
    }
}
