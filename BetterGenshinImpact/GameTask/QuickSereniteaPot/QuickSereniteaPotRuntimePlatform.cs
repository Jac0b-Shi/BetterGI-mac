using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask.Model.Area;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.QuickSereniteaPot;

public interface IQuickSereniteaPotRuntimePlatform
{
    bool IsInitialized { get; }
    bool IsGameProcessActive { get; }
    void NotifyNotStarted();
    ImageRegion Capture(bool forceNew, CancellationToken cancellationToken);
    void SimulateAction(GIActions action, CancellationToken cancellationToken);
    void ClickGame1080P(
        double x,
        double y,
        CancellationToken cancellationToken);
    void Wait(int milliseconds, CancellationToken cancellationToken);
    void ClearOverlay();
    void LogInformation(string message);
    void LogWarning(Exception exception);
}

public static class QuickSereniteaPotRuntimePlatform
{
    private static IQuickSereniteaPotRuntimePlatform? _current;

    public static IQuickSereniteaPotRuntimePlatform Current =>
        Volatile.Read(ref _current)
        ?? throw new InvalidOperationException(
            "Quick-Serenitea-Pot runtime platform has not been composed.");

    public static void Configure(IQuickSereniteaPotRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
        {
            throw new InvalidOperationException(
                "Quick-Serenitea-Pot runtime platform has already been configured.");
        }
    }
}
