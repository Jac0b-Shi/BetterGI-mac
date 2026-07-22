using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>
/// macOS capture loop for the shared BetterGI trigger registry. Capture and input remain Swift-owned;
/// trigger selection, UI classification and execution remain the upstream C# business objects.
/// </summary>
public sealed class MacTriggerDispatcher(
    ILogger<MacTriggerDispatcher> logger,
    CancellationToken shutdown,
    Func<CancellationToken, Task>? runLoop = null)
{
    private const int IntervalMilliseconds = 50;
    private readonly object _startLock = new();
    private Task? _loop;
    private CancellationTokenSource? _runCancellation;
    private int _frameIndex;
    private GameUiCategory _previousCategory = GameUiCategory.Unknown;
    private DateTime _categoryChangedAt = DateTime.MinValue;

    internal bool IsRunning
    {
        get
        {
            lock (_startLock)
                return _loop is { IsCompleted: false };
        }
    }

    public void Start()
    {
        lock (_startLock)
        {
            if (_loop is { IsCompleted: false })
                throw new InvalidOperationException("macOS trigger dispatcher has already been started.");
            _runCancellation?.Dispose();
            _runCancellation = CancellationTokenSource.CreateLinkedTokenSource(shutdown);
            var cancellationToken = _runCancellation.Token;
            _loop = Task.Run(() => RunConfiguredLoopAsync(cancellationToken), CancellationToken.None);
        }
    }

    public async Task StopAsync()
    {
        Task? loop;
        lock (_startLock)
        {
            loop = _loop;
            if (loop is null || loop.IsCompleted)
                return;
            _runCancellation?.Cancel();
        }

        await loop;
    }

    private async Task RunConfiguredLoopAsync(CancellationToken cancellationToken)
    {
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
    }

    private async Task RunAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(IntervalMilliseconds));
        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            var triggers = GameTaskManager.TriggerDictionary?.Values
                .Where(trigger => trigger.IsEnabled)
                .OrderByDescending(trigger => trigger.Priority)
                .ToArray() ?? [];
            if (triggers.Length == 0)
                continue;

            var exclusive = triggers.FirstOrDefault(trigger => trigger.IsExclusive);
            if (exclusive is not null)
                triggers = [exclusive];

            using var content = new CaptureContent(
                TaskControl.CaptureToRectArea(), _frameIndex++, IntervalMilliseconds);
            content.CurrentGameUiCategory = Bv.WhichGameUiForTriggers(content.CaptureRectArea);
            if (content.CurrentGameUiCategory != _previousCategory)
                _categoryChangedAt = DateTime.Now;

            DispatchTriggers(triggers, content);
            _previousCategory = content.CurrentGameUiCategory;
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
}
