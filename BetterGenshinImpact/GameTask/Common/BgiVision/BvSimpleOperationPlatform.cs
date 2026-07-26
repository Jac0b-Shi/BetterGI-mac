using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.Model;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.Common.BgiVision;

public interface IBvSimpleOperationPlatform
{
    ISystemInfo SystemInfo { get; }
    AutoPickConfig AutoPickConfig { get; }
    void PressPickKey();
}

public static class BvSimpleOperationPlatform
{
    private static IBvSimpleOperationPlatform? _current;
    public static IBvSimpleOperationPlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("Bv simple-operation platform has not been composed.");
    public static void Configure(IBvSimpleOperationPlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("Bv simple-operation platform has already been configured.");
    }
}
