using BetterGenshinImpact.GameTask.Model.Area;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.QuickClaimReward;

public sealed record OneKeyClaimRewardSettings(
    string HotkeyMode,
    bool ScrollDownEnabled,
    int ScrollDownAmount);

public interface IOneKeyClaimRewardRuntimePlatform
{
    bool IsInitialized { get; }
    bool IsGameProcessActive { get; }
    OneKeyClaimRewardSettings Settings { get; }
    ILogger Logger { get; }
    void NotifyNotStarted();
    ImageRegion Capture(CancellationToken cancellationToken);
    void Click(Region region, CancellationToken cancellationToken);
    void PressEscape(CancellationToken cancellationToken);
    void VerticalScroll(int clicks, CancellationToken cancellationToken);
}

public static class OneKeyClaimRewardRuntimePlatform
{
    private static IOneKeyClaimRewardRuntimePlatform? _current;

    public static IOneKeyClaimRewardRuntimePlatform Current =>
        Volatile.Read(ref _current)
        ?? throw new InvalidOperationException(
            "One-key claim-reward runtime platform has not been composed.");

    public static void Configure(IOneKeyClaimRewardRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
        {
            throw new InvalidOperationException(
                "One-key claim-reward runtime platform has already been configured.");
        }
    }
}
