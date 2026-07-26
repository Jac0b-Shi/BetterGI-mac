using System;
using System.Threading;
using Microsoft.Extensions.Logging;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Core.Simulator.Extensions;

namespace BetterGenshinImpact.GameTask.AutoEat;

public interface IAutoEatRuntimePlatform
{
    AutoEatConfig Config { get; }
    ILogger<T> GetLogger<T>();
    void SimulateAction(GIActions action);
}

public static class AutoEatRuntimePlatform
{
    private static IAutoEatRuntimePlatform? _current;
    public static IAutoEatRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("AutoEat runtime platform has not been composed.");
    public static void Configure(IAutoEatRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("AutoEat runtime platform has already been configured.");
    }
}
