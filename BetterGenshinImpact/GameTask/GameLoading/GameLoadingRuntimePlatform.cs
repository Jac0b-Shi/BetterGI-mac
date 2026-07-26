using System;
using System.Threading;
using BetterGenshinImpact.Core.Config;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.GameTask.GameLoading;

public enum BiliLoginWindowType
{
    None,
    Agreement,
    Login
}

public interface IGameLoadingRuntimePlatform
{
    GenshinStartConfig Config { get; }
    ILogger<GameLoadingTrigger> Logger { get; }
    double DpiScale { get; }
    bool IsPlaytimeTrackingAvailable();
    bool TryStartPlaytimeTracking(string gameServer);
    string GetInstalledGameServer();
    BiliLoginWindowType GetBiliLoginWindowType();
    void BackgroundClick();
    void MoveToGame1080P(double x, double y);
    void ClickGame1080P(double x, double y);
}

public static class GameLoadingRuntimePlatform
{
    private static IGameLoadingRuntimePlatform? _current;
    public static IGameLoadingRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("GameLoading runtime platform has not been composed.");

    public static void Configure(IGameLoadingRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("GameLoading runtime platform has already been configured.");
    }
}
