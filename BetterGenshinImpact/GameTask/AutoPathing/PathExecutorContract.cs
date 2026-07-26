using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.GameTask.FarmingPlan;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.GameTask.AutoPathing;

public interface IPathExecutor
{
    PathingPartyConfig PartyConfig { get; set; }
    int SuccessFight { get; }
    bool SuccessEnd { get; }
    Task Pathing(PathingTask task);
}

public readonly record struct PathingFailurePolicy(
    bool RestartEnabled,
    bool PathingFailureExceptional,
    bool FightFailureExceptional);

public interface IScriptGroupExecutionServices
{
    IPathExecutor CreatePathExecutor(CancellationToken cancellationToken);
    PathingPartyConfig DefaultPartyConfig { get; }
    void AddAutoPickTrigger();
    PathingFailurePolicy PathingFailurePolicy { get; }
    void RecordFarmingSession(FarmingSession session, FarmingRouteInfo route);
}

public static class ScriptGroupExecutionServices
{
    private static IScriptGroupExecutionServices? _current;
    public static IScriptGroupExecutionServices Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("Script-group execution services have not been composed.");

    public static void Configure(IScriptGroupExecutionServices services)
    {
        ArgumentNullException.ThrowIfNull(services);
        if (Interlocked.CompareExchange(ref _current, services, null) is not null)
            throw new InvalidOperationException("Script-group execution services have already been configured.");
    }
}
