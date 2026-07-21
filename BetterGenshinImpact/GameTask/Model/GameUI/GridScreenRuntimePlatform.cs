using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.Model.GameUI;

public interface IGridScreenRuntimePlatform
{
    double AssetScale { get; }
    int CaptureAreaX { get; }
    int CaptureAreaY { get; }
}

public static class GridScreenRuntimePlatform
{
    private static IGridScreenRuntimePlatform? _current;

    public static IGridScreenRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("GridScreen runtime platform has not been composed.");

    public static void Configure(IGridScreenRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("GridScreen runtime platform has already been configured.");
    }
}
