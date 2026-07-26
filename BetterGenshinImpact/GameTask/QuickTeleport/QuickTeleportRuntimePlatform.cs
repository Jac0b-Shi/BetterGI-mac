using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.QuickTeleport;

public interface IQuickTeleportRuntimePlatform
{
    QuickTeleportConfig Config { get; }
    string TickHotkey { get; }
    bool IsTickHotkeyPressed();
    bool IsHdrCapture { get; }
}

public static class QuickTeleportRuntimePlatform
{
    private static IQuickTeleportRuntimePlatform? _current;
    public static IQuickTeleportRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("QuickTeleport runtime platform has not been composed.");

    public static void Configure(IQuickTeleportRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("QuickTeleport runtime platform has already been configured.");
    }
}
