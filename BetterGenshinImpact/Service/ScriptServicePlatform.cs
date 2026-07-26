using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.GameTask.FarmingPlan;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.Service;

/// <summary>
/// Platform/composition operations used by the shared ScriptService scheduler.
/// Ordering, skip, retry, RunNum, cancellation and exception decisions remain
/// in ScriptService; implementations may only perform the requested side effect.
/// </summary>
public interface IScriptServicePlatform
{
    ILogger Logger { get; }
    string AutoPathingRoot { get; }
    string MapMatchingMethod { get; }
    IReadOnlyList<ScriptGroup> ScriptGroups { get; }
    bool FarmingPlanEnabled { get; }
    bool PropagateProjectExceptions => false;
    bool IsDailyFarmingLimitReached(FarmingSession farmingSession, out string message);
    void ClearTriggers();
    SchedulerRestartPolicy RestartPolicy { get; }
    void SetCurrentScriptProject(ScriptGroupProject project);
    Task StartGameTask(bool waitForMainUi);
    Task HandleBlessingOfTheWelkinMoon(CancellationToken cancellationToken);
    void NotifyGroupStart(string groupName);
    void NotifyGroupEndSuccess(string groupName);
    void NotifyGroupEndError(string message);
    void CloseGame();
    void RestartApplication(string taskProgressName);
}

public readonly record struct SchedulerRestartPolicy(
    bool Enabled,
    int FailureCount,
    bool RestartGameTogether,
    bool LinkedStartEnabled,
    bool AutoEnterGameEnabled);

public static class ScriptServicePlatform
{
    private static IScriptServicePlatform? _current;

    public static IScriptServicePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("ScriptService platform has not been composed.");

    public static void Configure(IScriptServicePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("ScriptService platform has already been configured.");
    }
}
