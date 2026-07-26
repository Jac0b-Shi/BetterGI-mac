using System;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.Core.Config;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.GameTask.FarmingPlan;

/// <summary>
/// Platform and composition dependencies for the shared upstream farming statistics logic.
/// Counting, caps, the 04:00 boundary and persistence format remain in <see cref="FarmingStatsRecorder"/>.
/// </summary>
public interface IFarmingStatsRuntimePlatform
{
    string LogDirectory { get; }
    OtherConfig.FarmingPlan Config { get; }
    ILogger Logger { get; }
    DateTimeOffset ServerTimeNow { get; }
    Task UpdateMiyousheDataAsync(CancellationToken cancellationToken);
}

public static class FarmingStatsRuntimePlatform
{
    private static IFarmingStatsRuntimePlatform? _current;

    public static IFarmingStatsRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("Farming statistics runtime platform has not been composed.");

    public static void Configure(IFarmingStatsRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("Farming statistics runtime platform has already been configured.");
    }
}
