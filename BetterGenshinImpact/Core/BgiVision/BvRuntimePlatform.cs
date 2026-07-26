using System;
using System.Threading;
using BetterGenshinImpact.GameTask.Model;

namespace BetterGenshinImpact.Core.BgiVision;

public interface IBvRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
}

public static class BvRuntimePlatform
{
    private static IBvRuntimePlatform? _current;

    public static IBvRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("Bv runtime platform has not been composed.");

    public static void Configure(IBvRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("Bv runtime platform has already been configured.");
    }
}
