using Microsoft.Extensions.Logging;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.AutoFight;

public sealed record OneKeyFightSettings(
    bool Enabled,
    string HotkeyMode,
    int Priority);

public interface IOneKeyFightRuntimePlatform
{
    OneKeyFightSettings Settings { get; }
    ILogger Logger { get; }
    string EnsureAvatarMacroPath();
}

public static class OneKeyFightRuntimePlatform
{
    private static IOneKeyFightRuntimePlatform? _current;

    public static IOneKeyFightRuntimePlatform Current =>
        Volatile.Read(ref _current)
        ?? throw new InvalidOperationException(
            "One-key fight runtime platform has not been composed.");

    public static void Configure(IOneKeyFightRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
        {
            throw new InvalidOperationException(
                "One-key fight runtime platform has already been configured.");
        }
    }
}
