using BetterGenshinImpact.GameTask.Model.Area;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.QuickBuy;

public interface IQuickBuyRuntimePlatform
{
    bool IsInitialized { get; }
    bool IsGameProcessActive { get; }
    void NotifyNotStarted();
    ImageRegion Capture();
    void MoveGame1080P(double x, double y, CancellationToken cancellationToken);
    void ClickGame1080P(double x, double y, CancellationToken cancellationToken);
    void ClickFromBottomRight1080P(
        double x,
        double y,
        CancellationToken cancellationToken);
    void MoveMouseBy(int x, int y, CancellationToken cancellationToken);
    void LeftButtonDown(CancellationToken cancellationToken);
    void LeftButtonUp(CancellationToken cancellationToken);
    void Wait(int milliseconds, CancellationToken cancellationToken);
    void ClearOverlay();
    void LogWarning(Exception exception);
}

public static class QuickBuyRuntimePlatform
{
    private static IQuickBuyRuntimePlatform? _current;

    public static IQuickBuyRuntimePlatform Current =>
        Volatile.Read(ref _current)
        ?? throw new InvalidOperationException(
            "Quick-buy runtime platform has not been composed.");

    public static void Configure(IQuickBuyRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
        {
            throw new InvalidOperationException(
                "Quick-buy runtime platform has already been configured.");
        }
    }
}
