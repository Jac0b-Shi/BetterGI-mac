using BetterGenshinImpact.Core.Mask;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Music.Service;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed partial class MusicCoordinator
{
    private readonly object _guidedGate = new();
    private readonly SemaphoreSlim _guidedEdit = new(1, 1);
    private readonly string? _guidedSettingsPath;
    private MusicGuidedKeyLayoutConfig _guidedLayout = new();
    private MusicGuidedSession? _guidedSession;
    private MacMusicGuidedInput? _guidedInput;
    private CancellationTokenSource? _guidedCancellation;
    private Task? _guidedTask;
    private string? _guidedID;
    private string? _guidedError;
    private bool IsGuidedActive => _guidedTask is { IsCompleted: false } || _guidedSession is not null;

    private object GuidedState()
    {
        lock (_guidedGate) return new {
            active = IsGuidedActive, session = _guidedID, error = _guidedError,
            segmentIndex = _guidedSession?.SegmentIndex ?? 0,
            segmentCount = _guidedSession?.SegmentCount ?? 0,
            progress = _guidedSession?.SegmentProgress ?? 0,
            errors = _guidedSession?.ErrorCount ?? 0,
            keyLayout = JObject.Parse(JsonSerializer.Serialize(_guidedLayout, ConfigJson.Options)),
        };
    }

    public async Task<object> StartGuidedAsync(int index, long windowID, int segmentSize, bool strictOrder,
        bool autoDetectKeys, bool overlayEnabled = true, MusicGuidedKeyLayoutConfig? layout = null)
    {
        ThrowIfDisposed();
        if (windowID <= 0 || windowID > uint.MaxValue) throw new ArgumentOutOfRangeException(nameof(windowID));
        if (segmentSize is < 1 or > 20) throw new ArgumentOutOfRangeException(nameof(segmentSize));
        await _mutationLock.WaitAsync(_hostCancellationToken);
        try
        {
            if (IsGuidedActive || _playbackTask is { IsCompleted: false })
                throw new InvalidOperationException("请先停止当前演奏会话。");
            if (index < 0 || index >= _queue.Count || !_queue[index].IsValid)
                throw new ArgumentOutOfRangeException(nameof(index));
            var score = _queue[index];
            var profile = _profileService.Find(score.OutputProfileName);
            var presses = MusicGuidedSegmentBuilder.Build(_timelineBuilder.Build(score, profile, score.Transpose));
            if (presses.Count == 0) throw new InvalidOperationException("曲谱没有可跟弹的按键。");
            _guidedCancellation?.Dispose();
            var cancellation = CancellationTokenSource.CreateLinkedTokenSource(_hostCancellationToken);
            _guidedCancellation = cancellation;
            _guidedID = Guid.NewGuid().ToString("N");
            _guidedError = null;
            var nextLayout = layout ?? ReadGuidedLayout();
            ValidateGuidedLayout(nextLayout);
            _guidedLayout = nextLayout;
            var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            _guidedTask = new TaskRunner().StartThread(async () => {
                using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellation.Token, CancellationContext.Instance.Cts.Token);
                var guideToken = linked.Token;
                using var inputScope = _input.UseCancellationToken(guideToken);
                try
                {
                    (double Width, double Height) size;
                    using (var first = TaskControlPlatform.Current.CaptureToRectArea(true, guideToken))
                    {
                        var captureBounds = first.ConvertPositionToGameCaptureRegion(0, 0, first.Width, first.Height);
                        size = (captureBounds.Width, captureBounds.Height);
                    }
                    var input = new MacMusicGuidedInput();
                    var overlay = new MacMusicGuidedOverlay(MaskWindowDrawingPlatform.Current, size, _guidedLayout);
                    var session = new MusicGuidedSession(presses, new MusicGuidedSessionOptions {
                        SegmentSize = segmentSize, StrictOrder = strictOrder, AutoDetectKeys = autoDetectKeys, OverlayEnabled = overlayEnabled,
                        KeyLayout = _guidedLayout, KeyProfile = profile, TrackName = score.DisplayTitle,
                        InputFactory = () => input, GameHandle = () => (nint)windowID,
                        CaptureSize = () => overlay.CanvasSize, HasModifiers = () => input.HasModifiers,
                        CaptureFrame = () => { using var frame = TaskControlPlatform.Current.CaptureToRectArea(true, guideToken); return frame.SrcMat.Clone(); },
                        IsGameActive = () => _input.IsGameFocused(linked.Token), Overlay = overlay,
                        Logger = text => _logger.LogInformation("{GuidedMusic}", text),
                    });
                    // Session disposal is serialized with RPC key delivery in the outer finally.
                    {
                        lock (_guidedGate)
                        {
                            linked.Token.ThrowIfCancellationRequested();
                            _guidedInput = input; _guidedSession = session;
                            if (!session.Start()) throw new InvalidOperationException("引导式跟弹启动失败。");
                            SaveGuidedLayout();
                            ready.TrySetResult();
                        }
                        while (!linked.IsCancellationRequested)
                        {
                            // Detection uses a normalised frame; the native HUD always consumes capture pixels.
                            var captureSize = _input.GetCapturePixelSize(guideToken);
                            lock (_guidedGate)
                            {
                                if (session.IsFinished) break;
                                if (!_input.IsGameFocused(linked.Token)) { input.Stop(); input.Start(); }
                                overlay.UpdateCanvasSize(captureSize);
                                session.Pump();
                            }
                            await Task.Delay(100, linked.Token);
                        }
                    }
                }
                catch (OperationCanceledException) when (linked.IsCancellationRequested) { ready.TrySetCanceled(linked.Token); }
                catch (Exception e) { ready.TrySetException(e); lock (_guidedGate) _guidedError = e.Message; _logger.LogError(e, "引导式跟弹失败"); }
                finally
                {
                    lock (_guidedGate)
                    {
                        _guidedSession?.Stop("已停止"); _guidedSession?.Dispose();
                        _guidedSession = null; _guidedInput?.Dispose(); _guidedInput = null;
                        MaskWindowDrawingPlatform.Current.Clear(new MaskWindowDrawingGroup("MusicGuided", MaskWindowDrawingKind.Feature));
                    }
                }
            }, cancellation.Token, waitForInputDuringInitialization: false);
            try
            {
                var first = await Task.WhenAny(ready.Task, _guidedTask).WaitAsync(TimeSpan.FromSeconds(15), cancellation.Token);
                if (first == ready.Task) await ready.Task;
                else { await _guidedTask; throw new InvalidOperationException("跟弹会话在准备完成前退出。"); }
            }
            catch { cancellation.Cancel(); throw; }
            return State();
        }
        finally { _mutationLock.Release(); }
    }

    public object GuidedKey(string session, int key, bool down, bool modifiers)
    {
        ThrowIfDisposed();
        lock (_guidedGate)
        {
            if (session != _guidedID || _guidedSession is null || _guidedSession.IsFinished)
                return new { acknowledged = false };
            if (key is < 65 or > 90) throw new ArgumentOutOfRangeException(nameof(key));
            if (!down || _input.IsGameFocused(_guidedCancellation?.Token ?? _hostCancellationToken)) _guidedInput?.Submit(key, down, modifiers);
            return new { acknowledged = true };
        }
    }

    public async Task<object> RedetectGuidedAsync(string id)
    {
        ThrowIfDisposed();
        await _guidedEdit.WaitAsync(_hostCancellationToken);
        try
        {
            MusicGuidedSession? session;
            lock (_guidedGate) session = id == _guidedID ? _guidedSession : null;
            if (session is null || session.IsFinished) throw new InvalidOperationException("跟弹会话已结束。");
            await session.RedetectKeysAsync();
            lock (_guidedGate) { if (id == _guidedID && ReferenceEquals(session, _guidedSession)) SaveGuidedLayout(); }
            return State();
        }
        finally { _guidedEdit.Release(); }
    }

    public async Task<object> UpdateGuidedLayoutAsync(string id, MusicGuidedKeyLayoutConfig layout)
    {
        ThrowIfDisposed();
        ValidateGuidedLayout(layout);
        await _guidedEdit.WaitAsync(_hostCancellationToken);
        try
        {
            lock (_guidedGate)
            {
                if (id != _guidedID || _guidedSession is null || _guidedSession.IsFinished) throw new InvalidOperationException("跟弹会话已结束。");
                _guidedLayout.BaseX = layout.BaseX; _guidedLayout.BaseY = layout.BaseY;
                _guidedLayout.ColumnSpacing = layout.ColumnSpacing; _guidedLayout.RowSpacing = layout.RowSpacing;
                _guidedLayout.RowIndent = layout.RowIndent; _guidedLayout.RingRadius = layout.RingRadius;
                _guidedLayout.RingThickness = layout.RingThickness; _guidedLayout.KeyOffsets = layout.KeyOffsets;
                _guidedLayout.ManualCalibrated = true;
                _guidedSession.RefreshLayout(); SaveGuidedLayout();
            }
            return State();
        }
        finally { _guidedEdit.Release(); }
    }

    private static void ValidateGuidedLayout(MusicGuidedKeyLayoutConfig layout)
    {
        var values = new[] { layout.BaseX, layout.BaseY, layout.ColumnSpacing, layout.RowSpacing, layout.RowIndent, layout.RingRadius, layout.RingThickness };
        if (values.Any(x => !double.IsFinite(x)) || layout.ColumnSpacing <= 0 || layout.RowSpacing <= 0 || layout.RingRadius <= 0 || layout.RingThickness <= 0)
            throw new ArgumentException("键位参数必须有限，间距与线宽必须大于零。");
        if (layout.KeyOffsets is null || layout.KeyOffsets.Any(x => x.Key.Length != 1 || !char.IsAsciiLetter(x.Key[0]) ||
            x.Value is null || !double.IsFinite(x.Value.X) || !double.IsFinite(x.Value.Y)))
            throw new ArgumentException("单键偏移必须使用字母键和有限坐标。");
    }

    private MusicGuidedKeyLayoutConfig ReadGuidedLayout()
    {
        if (_guidedSettingsPath is null || !File.Exists(_guidedSettingsPath)) return new();
        return JsonSerializer.Deserialize<MusicGuidedKeyLayoutConfig>(File.ReadAllText(_guidedSettingsPath), ConfigJson.Options) ?? new();
    }
    private void SaveGuidedLayout()
    {
        if (_guidedSettingsPath is null) return;
        Directory.CreateDirectory(Path.GetDirectoryName(_guidedSettingsPath)!);
        var temporary = _guidedSettingsPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temporary, JsonSerializer.Serialize(_guidedLayout, ConfigJson.Options)); File.Move(temporary, _guidedSettingsPath, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private void DisposeGuided()
    {
        var cancellation = Interlocked.Exchange(ref _guidedCancellation, null);
        cancellation?.Cancel();
        var task = _guidedTask;
        if (task is { IsCompleted: false })
            _ = task.ContinueWith(completed => { _ = completed.Exception; cancellation?.Dispose(); },
                CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
        else cancellation?.Dispose();
    }

    private async Task StopGuidedAsync()
    {
        _guidedCancellation?.Cancel();
        var task = _guidedTask;
        if (task is not null) try { await task; } catch (OperationCanceledException) { }
        await _guidedEdit.WaitAsync(_hostCancellationToken);
        _guidedEdit.Release();
    }
}
