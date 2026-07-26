using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.Macro;

public interface IQuickEnhanceArtifactRuntimePlatform
{
    bool IsInitialized { get; }
    int EnhanceWaitDelay { get; }
    void NotifyNotStarted();
    void ClickGame1080P(double x, double y, CancellationToken cancellationToken);
    void MoveGame1080P(double x, double y, CancellationToken cancellationToken);
    void Wait(int milliseconds, CancellationToken cancellationToken);
}

public static class QuickEnhanceArtifactRuntimePlatform
{
    private static IQuickEnhanceArtifactRuntimePlatform? _current;

    public static IQuickEnhanceArtifactRuntimePlatform Current =>
        Volatile.Read(ref _current)
        ?? throw new InvalidOperationException(
            "Quick-enhance runtime platform has not been composed.");

    public static void Configure(
        IQuickEnhanceArtifactRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
        {
            throw new InvalidOperationException(
                "Quick-enhance runtime platform has already been configured.");
        }
    }
}
