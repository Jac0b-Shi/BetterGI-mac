using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>
/// macOS capture loop for the shared BetterGI trigger registry. Capture and input remain Swift-owned;
/// trigger selection, UI classification and execution remain the upstream C# business objects.
/// </summary>
public sealed class MacTriggerDispatcher(ILogger<MacTriggerDispatcher> logger, CancellationToken shutdown)
{
    private const int IntervalMilliseconds = 50;
    private readonly object _startLock = new();
    private Task? _loop;
    private int _frameIndex;
    private GameUiCategory _previousCategory = GameUiCategory.Unknown;
    private DateTime _categoryChangedAt = DateTime.MinValue;

    public void Start()
    {
        lock (_startLock)
        {
            if (_loop is not null)
                throw new InvalidOperationException("macOS trigger dispatcher has already been started.");
            _loop = Task.Run(RunAsync, shutdown);
        }
    }

    private async Task RunAsync()
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(IntervalMilliseconds));
        try
        {
            while (await timer.WaitForNextTickAsync(shutdown))
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

                foreach (var trigger in triggers)
                {
                    if (_previousCategory != content.CurrentGameUiCategory ||
                        (DateTime.Now - _categoryChangedAt).TotalSeconds <= 30 ||
                        trigger.SupportedGameUiCategory == content.CurrentGameUiCategory)
                    {
                        trigger.OnCapture(content);
                    }
                }
                _previousCategory = content.CurrentGameUiCategory;
            }
        }
        catch (OperationCanceledException) when (shutdown.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "macOS trigger dispatcher stopped unexpectedly");
            throw;
        }
    }
}
