using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.FarmingPlan;
using System.Threading;

namespace BetterGenshinImpact.GameTask;

public sealed class WindowsScriptGroupExecutionServices : IScriptGroupExecutionServices
{
    public IPathExecutor CreatePathExecutor(CancellationToken cancellationToken) => new PathExecutor(
        cancellationToken, PathExecutorPlatform.Current, PathExecutorAutoSkipPlatform.Current, this);
    public PathingPartyConfig DefaultPartyConfig => PathingPartyConfig.BuildDefault();
    public void AddAutoPickTrigger() => TaskTriggerDispatcher.Instance().AddTrigger("AutoPick", null);

    public PathingFailurePolicy PathingFailurePolicy
    {
        get
        {
            OtherConfig.AutoRestart config = TaskContext.Instance().Config.OtherConfig.AutoRestartConfig;
            return new PathingFailurePolicy(
                config.Enabled,
                config.IsPathingFailureExceptional,
                config.IsFightFailureExceptional);
        }
    }

    public void RecordFarmingSession(FarmingSession session, FarmingRouteInfo route) =>
        FarmingStatsRecorder.RecordFarmingSession(session, route);
}
