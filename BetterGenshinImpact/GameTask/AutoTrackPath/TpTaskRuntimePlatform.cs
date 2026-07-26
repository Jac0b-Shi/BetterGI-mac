using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.QuickTeleport;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.AutoTrackPath;

public interface ITpTaskRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
    TpConfig TpConfig { get; }
    QuickTeleportConfig QuickTeleportConfig { get; }
    string MapMatchingMethod { get; }
    double DpiScale { get; }
}

public static class TpTaskRuntimePlatform
{
    private static ITpTaskRuntimePlatform? _current;
    public static ITpTaskRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("TpTask runtime platform has not been composed.");

    public static void Configure(ITpTaskRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("TpTask runtime platform has already been configured.");
    }
}
