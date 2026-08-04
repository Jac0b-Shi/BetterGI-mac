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
    Func<CancellationToken, bool>? isGameActive = null)
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
        trigger.Init();
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
            var registeredTriggers = GameTaskManager.TriggerDictionary?.Values
                .Where(trigger => trigger.IsEnabled)
                .OrderByDescending(trigger => trigger.Priority)
                .ToArray() ?? [];
            var triggers = SelectTriggersForFrame(
                registeredTriggers, Volatile.Read(ref _mapMaskCompanion));
            if (triggers.Length == 0)
                continue;

            try
            {
                if (isGameActive is not null && !isGameActive(cancellationToken))
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
        var mapMask = mapMaskCompanion is { IsEnabled: true } ? mapMaskCompanion : null;
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
