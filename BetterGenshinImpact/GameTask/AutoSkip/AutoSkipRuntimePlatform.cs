using BetterGenshinImpact.Core.Simulator.Extensions;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.AutoSkip;

public interface IAutoSkipAudioWaiter
{
    bool IsWaiting { get; }
    void Cancel();
    void ReleaseDetector();
    bool Start(int maxWaitMilliseconds, int fallbackDelayMilliseconds, Microsoft.Extensions.Logging.ILogger logger);
    bool Update(Microsoft.Extensions.Logging.ILogger logger);
}

public interface IAutoSkipRuntimePlatform
{
    IAutoSkipAudioWaiter CreateAudioWaiter();
    void SimulateBackgroundAction(GIActions action);
    void PressBackgroundKey(int windowsVirtualKey);
    void BackgroundLeftButtonClick();
    void ReportError(string message);
}

public static class AutoSkipRuntimePlatform
{
    private static IAutoSkipRuntimePlatform? _current;

    public static IAutoSkipRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("AutoSkip runtime platform has not been composed.");

    public static void Configure(IAutoSkipRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("AutoSkip runtime platform has already been configured.");
    }
}
