using OpenCvSharp;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.AutoPathing;

public interface INavigationPlatform
{
    void PublishCurrentPosition(Point2f position);
}

public static class NavigationPlatform
{
    private static INavigationPlatform? _current;

    public static INavigationPlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("Navigation platform has not been composed.");

    public static void Configure(INavigationPlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("Navigation platform has already been configured.");
    }
}
