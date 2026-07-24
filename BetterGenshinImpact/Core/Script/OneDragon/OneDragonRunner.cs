using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Script.OneDragon;

public enum OneDragonBuiltInTask
{
    ClaimMail,
    CraftCondensedResin,
    AutoDomain,
    AutoBoss,
    AutoStygianOnslaught,
    AutoLeyLineOutcrop,
    ClaimDailyRewards,
    ClaimSereniteaPotRewards,
}

public enum OneDragonCompletionAction
{
    None,
    CloseGame,
    CloseApplication,
    CloseGameAndApplication,
    Shutdown,
}

public sealed record OneDragonBuiltInTaskRequest(
    string Id,
    OneDragonBuiltInTask Task,
    OneDragonFlowConfig Config);

public sealed record OneDragonScriptGroupRequest(
    string Id,
    string Name);

public sealed record OneDragonRunnerDelays(
    TimeSpan BuiltInTaskInterval,
    TimeSpan BeforeScriptGroup,
    TimeSpan AfterScriptGroup,
    TimeSpan BeforeCompletion)
{
    public static OneDragonRunnerDelays Upstream { get; } = new(
        TimeSpan.FromSeconds(1),
        TimeSpan.FromMilliseconds(500),
        TimeSpan.FromSeconds(1),
        TimeSpan.FromMilliseconds(500));

    public static OneDragonRunnerDelays None { get; } = new(
        TimeSpan.Zero,
        TimeSpan.Zero,
        TimeSpan.Zero,
        TimeSpan.Zero);
}

public enum OneDragonRunState
{
    Completed,
    NoEnabledTasks,
    CancelledDuringStartup,
    Cancelled,
}

public sealed record OneDragonRunResult(
    OneDragonRunState State,
    int EnabledTaskCount,
    int BuiltInTaskCount,
    int ScriptGroupCount,
    bool ResumeMarkerFound);

public interface IOneDragonExecutionPlatform
{
    ILogger Logger { get; }
    Task StartGameTask();
    Task ExecuteBuiltInTask(
        OneDragonBuiltInTaskRequest request,
        CancellationToken cancellationToken);
    Task ExecuteScriptGroup(
        OneDragonScriptGroupRequest request,
        CancellationToken cancellationToken);
    Task CheckRewards(CancellationToken cancellationToken);
    void SaveConfiguration(OneDragonFlowConfig config);
    void ResumeMarkerConsumed(OneDragonFlowConfig config);
    void NotifyDragonStart(string message);
    void NotifyDragonEnd(string message);
    void ReportScriptGroupFailure(
        OneDragonScriptGroupRequest request,
        Exception exception);
    void ExecuteCompletionAction(OneDragonCompletionAction action);
}

public sealed class OneDragonRunner(
    IOneDragonExecutionPlatform platform,
    OneDragonRunnerDelays? delays = null)
{
    private static readonly IReadOnlyDictionary<string, OneDragonBuiltInTask> BuiltInTasks =
        new Dictionary<string, OneDragonBuiltInTask>(StringComparer.Ordinal)
        {
            ["领取邮件"] = OneDragonBuiltInTask.ClaimMail,
            ["合成树脂"] = OneDragonBuiltInTask.CraftCondensedResin,
            ["自动秘境"] = OneDragonBuiltInTask.AutoDomain,
            ["自动首领讨伐"] = OneDragonBuiltInTask.AutoBoss,
            ["自动幽境危战"] = OneDragonBuiltInTask.AutoStygianOnslaught,
            ["自动地脉花"] = OneDragonBuiltInTask.AutoLeyLineOutcrop,
            ["领取每日奖励"] = OneDragonBuiltInTask.ClaimDailyRewards,
            ["领取尘歌壶奖励"] = OneDragonBuiltInTask.ClaimSereniteaPotRewards,
        };

    private readonly OneDragonRunnerDelays _delays = delays ?? OneDragonRunnerDelays.Upstream;

    public async Task<OneDragonRunResult> RunAsync(
        OneDragonFlowConfig config,
        OneDragonPlan plan,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(config);
        ArgumentNullException.ThrowIfNull(plan);

        CancellationContext.Instance.Set();
        using var cancellationRegistration = cancellationToken.Register(
            CancellationContext.Instance.Cancel);
        try
        {
            var enabledSteps = plan.ExecutionSteps
                .Where(step => step.IsEnabled)
                .ToArray();
            var builtInCount = enabledSteps.Count(step => BuiltInTasks.ContainsKey(step.Name));
            var scriptGroupCount = enabledSteps.Length - builtInCount;
            platform.Logger.LogInformation("启用任务总数量: {Count}", enabledSteps.Length);

            if (!string.IsNullOrEmpty(config.NextTaskId))
            {
                if (plan.ResumeMarkerFound)
                {
                    platform.Logger.LogInformation(
                        "一条龙：任务将从 {Name} 开始执行",
                        plan.ExecutionSteps[0].Name);
                }
                else
                {
                    platform.Logger.LogWarning("一条龙：未找到标记的任务，将从头开始执行");
                }

                config.NextTaskId = string.Empty;
                platform.ResumeMarkerConsumed(config);
            }

            if (enabledSteps.Length == 0)
            {
                platform.Logger.LogInformation("没有配置,退出执行!");
                return Result(OneDragonRunState.NoEnabledTasks);
            }

            await platform.StartGameTask();
            if (CancellationContext.Instance.IsCancellationRequested)
            {
                platform.Logger.LogInformation("一条龙在启动阶段被取消");
                return Result(OneDragonRunState.CancelledDuringStartup);
            }

            platform.SaveConfiguration(config);
            platform.Logger.LogInformation("启用一条龙任务的数量: {Count}", enabledSteps.Length);
            platform.Logger.LogInformation("启用配置组任务的数量: {Count}", scriptGroupCount);
            platform.NotifyDragonStart("一条龙启动");

            var builtInIndex = 1;
            var scriptGroupIndex = 1;
            foreach (var step in enabledSteps)
            {
                if (BuiltInTasks.TryGetValue(step.Name, out var builtInTask))
                {
                    platform.Logger.LogInformation(
                        "一条龙任务执行: {Current}/{Total}",
                        builtInIndex++,
                        enabledSteps.Length);
                    await new TaskRunner().RunThreadAsync(async () =>
                    {
                        await platform.ExecuteBuiltInTask(
                            new OneDragonBuiltInTaskRequest(
                                step.Id,
                                builtInTask,
                                config),
                            CancellationContext.Instance.Cts.Token);
                        await Delay(_delays.BuiltInTaskInterval);
                    },
                    resetCancellationContext: false,
                    clearCancellationContextOnCompletion: false);
                }
                else
                {
                    var request = new OneDragonScriptGroupRequest(step.Id, step.Name);
                    try
                    {
                        platform.NotifyDragonStart("配置组任务启动");
                        platform.Logger.LogInformation(
                            "配置组任务执行: {Current}/{Total}",
                            scriptGroupIndex++,
                            scriptGroupCount);
                        await Delay(_delays.BeforeScriptGroup);
                        await platform.ExecuteScriptGroup(
                            request,
                            CancellationContext.Instance.Cts.Token);
                        await Delay(_delays.AfterScriptGroup);
                    }
                    catch (Exception exception)
                    {
                        platform.ReportScriptGroupFailure(request, exception);
                    }
                }

                if (!CancellationContext.Instance.Cts.IsCancellationRequested)
                {
                    continue;
                }

                platform.Logger.LogInformation("任务被取消，退出执行");
                if (!CancellationContext.Instance.IsManualStop)
                {
                    platform.NotifyDragonEnd("一条龙和配置组任务结束");
                }
                return Result(OneDragonRunState.Cancelled);
            }

            await new TaskRunner().RunThreadAsync(async () =>
            {
                await platform.CheckRewards(CancellationContext.Instance.Cts.Token);
                await Delay(_delays.BeforeCompletion);
                if (!CancellationContext.Instance.IsManualStop)
                {
                    platform.NotifyDragonEnd("一条龙和配置组任务结束");
                }
                platform.Logger.LogInformation("一条龙和配置组任务结束");
                platform.ExecuteCompletionAction(ParseCompletionAction(config.CompletionAction));
            },
            resetCancellationContext: false,
            clearCancellationContextOnCompletion: false);

            return Result(OneDragonRunState.Completed);

            OneDragonRunResult Result(OneDragonRunState state) => new(
                state,
                enabledSteps.Length,
                builtInCount,
                scriptGroupCount,
                plan.ResumeMarkerFound);
        }
        finally
        {
            CancellationContext.Instance.Clear();
        }
    }

    private static OneDragonCompletionAction ParseCompletionAction(string? action) =>
        action switch
        {
            "关闭游戏" => OneDragonCompletionAction.CloseGame,
            "关闭软件" => OneDragonCompletionAction.CloseApplication,
            "关闭游戏和软件" => OneDragonCompletionAction.CloseGameAndApplication,
            "关机" => OneDragonCompletionAction.Shutdown,
            _ => OneDragonCompletionAction.None,
        };

    private static Task Delay(TimeSpan delay) =>
        delay <= TimeSpan.Zero ? Task.CompletedTask : Task.Delay(delay);
}
