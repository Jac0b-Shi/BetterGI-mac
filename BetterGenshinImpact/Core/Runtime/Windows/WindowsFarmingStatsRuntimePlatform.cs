using System;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.FarmingPlan;
using BetterGenshinImpact.Helpers;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsFarmingStatsRuntimePlatform : IFarmingStatsRuntimePlatform
{
    public string LogDirectory => Global.Absolute(@"log\FarmingPlan");
    public OtherConfig.FarmingPlan Config => TaskContext.Instance().Config.OtherConfig.FarmingPlanConfig;
    public ILogger Logger => App.GetLogger<WindowsFarmingStatsRuntimePlatform>();
    public DateTimeOffset ServerTimeNow => ServerTimeHelper.GetServerTimeNow();

    public Task UpdateMiyousheDataAsync(CancellationToken cancellationToken) =>
        FarmingStatsMiyousheUpdater.UpdateAsync(
            TaskContext.Instance().Config.OtherConfig,
            Logger,
            cancellationToken);
}
