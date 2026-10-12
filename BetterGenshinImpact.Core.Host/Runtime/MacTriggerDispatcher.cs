using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.MapMask;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>
/// macOS capture loop for the shared BetterGI trigger registry. Capture and input remain Swift-owned;
/// trigger selection, UI classification and execution remain the upstream C# business objects.
/// </summary>
public sealed class MacTriggerDispatcher(
    ILogger<MacTriggerDispatcher> logger,
    CancellationToken shutdown,
    Func<CancellationToken, Task>? runLoop = null,
    Func<CancellationToken, Task>? stopCleanup = null,
    Func<CancellationToken, bool>? isGameActive = null,
    Func<bool>? isTaskRunning = null)
{
    private const int IntervalMilliseconds = 50;
    private const int CaptureFailureBackoffMilliseconds = 500;
    private const int CaptureFailureLogInterval = 20;
    private readonly object _startLock = new();
    private Task? _loop;
    private CancellationTokenSource? _runCancellation;
    private int _frameIndex;
    private GameUiCategory _previousCategory = GameUiCategory.Unknown;
    private DateTime _categoryChangedAt = DateTime.MinValue;
    private MapMaskTrigger? _mapMaskCompanion;
    private sealed class Slot(ITaskTrigger trigger)
    {
        public ITaskTrigger Trigger { get; } = trigger;
        public bool Active;
        public (long Refresh, long Request, bool InTask) Version;
    }
    private readonly Dictionary<ITaskTrigger, Slot> _slots = new(ReferenceEqualityComparer.Instance);
    private readonly object _lifecycleLock = new();


    internal bool IsRunning
    {
        get
        {
            lock (_startLock)
                return _loop is { IsCompleted: false };
        }
    }

    internal object? MapMaskRuntimeStatus =>
        Volatile.Read(ref _mapMaskCompanion)?.GetRuntimeStatus();

    internal void SetMapMaskCompanion(MapMaskTrigger trigger)
    {
        ArgumentNullException.ThrowIfNull(trigger);
        var previous = Interlocked.Exchange(ref _mapMaskCompanion, trigger);
        if (previous is not null && !ReferenceEquals(previous, trigger))
            previous.Invalidate();
    }

    public void Start()
    {
        lock (_startLock)
        {
            if (_loop is { IsCompleted: false })
                throw new InvalidOperationException("macOS trigger dispatcher has already been started.");
            _runCancellation?.Dispose();
            var runCancellation = CancellationTokenSource.CreateLinkedTokenSource(shutdown);
            _runCancellation = runCancellation;
            _loop = Task.Run(
                () => RunConfiguredLoopAsync(runCancellation),
                CancellationToken.None);
        }
    }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        Task? loop;
        lock (_startLock)
        {
            loop = _loop;
            if (loop is { IsCompleted: false })
                _runCancellation?.Cancel();
        }

        InvalidateMapMask();
        if (loop is not null)
            await loop.WaitAsync(cancellationToken);
        if (stopCleanup is not null)
            await stopCleanup(cancellationToken);
    }

    private async Task RunConfiguredLoopAsync(CancellationTokenSource runCancellation)
    {
        var cancellationToken = runCancellation.Token;
        try
        {
            if (runLoop is null)
                await RunAsync(cancellationToken);
            else
                await runLoop(cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "macOS trigger dispatcher stopped unexpectedly");
        }
        finally
        {
            DisableAllTriggers();
            lock (_startLock)
            {
                if (ReferenceEquals(_runCancellation, runCancellation))
                    _runCancellation = null;
            }
            runCancellation.Dispose();
        }
    }

    private async Task RunAsync(CancellationToken cancellationToken)
    {
        var consecutiveCaptureFailures = 0;
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(IntervalMilliseconds));
        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            try
            {
                var gameActive = isGameActive is null || isGameActive(cancellationToken);
                var registeredTriggers = UpdateLifecycle(gameActive);
                var triggers = SelectTriggersForFrame(
                    registeredTriggers, registeredTriggers.OfType<MapMaskTrigger>().FirstOrDefault());
                if (triggers.Length == 0) continue;

                if (RunnerContext.Instance.AutoPickTriggerStopCount > 0 || RunnerContext.Instance.IsSuspend)
                    continue;

                using var content = new CaptureContent(
                    TaskControl.CaptureToRectArea(), _frameIndex++, IntervalMilliseconds);
                content.CurrentGameUiCategory = Bv.WhichGameUiForTriggers(content.CaptureRectArea);
                if (content.CurrentGameUiCategory != _previousCategory)
                    _categoryChangedAt = DateTime.Now;

                DispatchTriggers(triggers, content);
                _previousCategory = content.CurrentGameUiCategory;
                if (consecutiveCaptureFailures > 0)
                {
                    logger.LogInformation(
                        "macOS trigger capture recovered after {FailureCount} consecutive failure(s)",
                        consecutiveCaptureFailures);
                    consecutiveCaptureFailures = 0;
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception)
            {
                consecutiveCaptureFailures++;
                if (consecutiveCaptureFailures == 1 ||
                    consecutiveCaptureFailures % CaptureFailureLogInterval == 0)
                {
                    logger.LogError(
                        exception,
                        "macOS trigger capture failed {FailureCount} consecutive time(s); retrying",
                        consecutiveCaptureFailures);
                }
                await Task.Delay(CaptureFailureBackoffMilliseconds, cancellationToken);
            }
        }
    }

    internal ITaskTrigger[] UpdateLifecycle(bool gameActive)
    {
        lock (_lifecycleLock)
        {
            var registered = GameTaskManager.TriggerDictionary?.ToArray() ?? [];
            var companion = Volatile.Read(ref _mapMaskCompanion);
            var retained = registered.Select(pair => pair.Value).ToHashSet(ReferenceEqualityComparer.Instance);
            if (companion is not null) retained.Add(companion);
            var retired = _slots.Keys.Where(trigger => !retained.Contains(trigger)).ToHashSet(ReferenceEqualityComparer.Instance);
            while (GameTaskManager.RetiredTriggers.TryDequeue(out var trigger)) retired.Add(trigger);
            foreach (var removed in retired.OfType<ITaskTrigger>().Where(trigger => !retained.Contains(trigger)))
            {
                if (_slots.Remove(removed, out var slot)) Disable(slot);
                (removed as IDisposable)?.Dispose();
            }
            bool inTask = isTaskRunning?.Invoke() ?? TaskRunnerPlatform.Current.TaskSemaphore.CurrentCount == 0;
            var selected = new List<ITaskTrigger>();
            foreach (var pair in registered)
            {
                if (pair.Value is MapMaskTrigger) continue;
                GameTaskManager.RequestedTriggers.TryGetValue(pair.Key, out var request);
                bool wanted = (inTask ? request is not null : pair.Value.IsEnabledByConfig)
                    && (gameActive || pair.Value.IsBackgroundRunning);
                var version = (GameTaskManager.RefreshVersion(pair.Key), inTask ? request?.Version ?? 0 : 0, inTask);
                Apply(pair.Value, wanted, inTask ? request?.Options : null, version);
                if (_slots[pair.Value].Active) selected.Add(pair.Value);
            }
            if (companion is not null)
            {
                Apply(companion, companion.IsEnabledByConfig && (gameActive || ((ITaskTrigger)companion).IsBackgroundRunning), null,
                    (GameTaskManager.RefreshVersion("MapMask"), 0, false));
                if (_slots[companion].Active) selected.Add(companion);
            }
            return selected.OrderByDescending(trigger => trigger.Priority).ToArray();
        }
    }

    private void Apply(ITaskTrigger trigger, bool wanted, object? options, (long Refresh, long Request, bool InTask) version)
    {
        if (!_slots.TryGetValue(trigger, out var slot)) _slots.Add(trigger, slot = new Slot(trigger));
        if (slot.Active && (!wanted || slot.Version != version)) Disable(slot);
        if (wanted && !slot.Active)
        {
            try { trigger.OnEnabled(options); slot.Active = true; slot.Version = version; }
            catch (Exception e)
            {
                logger.LogError(e, "macOS trigger {TriggerName} enable failed", trigger.Name);
                try { trigger.OnDisabled(); } catch (Exception cleanup) { logger.LogError(cleanup, "Trigger enable cleanup failed"); }
            }
        }
    }
    private void Disable(Slot slot)
    {
        if (!slot.Active) return;
        slot.Active = false;
        try { slot.Trigger.OnDisabled(); }
        catch (Exception e) { logger.LogError(e, "macOS trigger {TriggerName} disable failed", slot.Trigger.Name); }
    }
    private void DisableAllTriggers()
    {
        lock (_lifecycleLock) foreach (var slot in _slots.Values) Disable(slot);
    }

    internal void DispatchTriggers(IEnumerable<ITaskTrigger> triggers, CaptureContent content)
    {
        foreach (var trigger in triggers)
        {
            if (!ShouldRunTrigger(
                    trigger, content.CurrentGameUiCategory, _previousCategory,
                    _categoryChangedAt, DateTime.Now))
                continue;

            try
            {
                trigger.OnCapture(content);
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "macOS trigger {TriggerName} failed for one capture frame", trigger.Name);
            }
        }
    }

    internal static bool ShouldRunTrigger(
        ITaskTrigger trigger,
        GameUiCategory currentCategory,
        GameUiCategory previousCategory,
        DateTime categoryChangedAt,
        DateTime now) =>
        previousCategory != currentCategory ||
        (now - categoryChangedAt).TotalSeconds <= 30 ||
        trigger.SupportsGameUiCategory(currentCategory);

    internal static ITaskTrigger[] SelectTriggersForFrame(
        ITaskTrigger[] triggers, MapMaskTrigger? mapMaskCompanion)
    {
        var businessTriggers = triggers
            .Where(trigger => trigger is not MapMaskTrigger)
            .ToArray();
        var exclusive = businessTriggers.FirstOrDefault(trigger => trigger.IsExclusive);
        var mapMask = mapMaskCompanion is { IsEnabledByConfig: true } ? mapMaskCompanion : null;
        if (exclusive is null)
        {
            return mapMask is null
                ? businessTriggers
                : businessTriggers
                    .Append(mapMask)
                    .OrderByDescending(trigger => trigger.Priority)
                    .ToArray();
        }

        return mapMask is null ? [exclusive] : [mapMask, exclusive];
    }

    private void InvalidateMapMask()
    {
        Volatile.Read(ref _mapMaskCompanion)?.Invalidate();
    }

}
