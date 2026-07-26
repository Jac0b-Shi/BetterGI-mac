using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.Core.Script.OneDragon;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.Verification.Framework;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class OneDragonRunnerSuite : IVerificationSuite
{
    public string Name => "one-dragon-runner";

    public async Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        TaskRunnerPlatform.Configure(new RecordingTaskRunnerPlatform());

        var config = new OneDragonFlowConfig
        {
            NextTaskId = "mail",
            CompletionAction = "关闭游戏和软件",
        };
        var plan = OneDragonPlan.FromOrderedSteps(
        [
            new OneDragonPlanStep("mail", "领取邮件", true, true),
            new OneDragonPlanStep("disabled", "自动秘境", false, false),
            new OneDragonPlanStep("group", "地图追踪组", true, false),
            new OneDragonPlanStep("daily", "领取每日奖励", true, false),
        ], config.NextTaskId);
        var platform = new RecordingOneDragonPlatform();
        var result = await new OneDragonRunner(platform, OneDragonRunnerDelays.None)
            .RunAsync(config, plan);

        context.Require(
            result == new OneDragonRunResult(
                OneDragonRunState.Completed,
                EnabledTaskCount: 3,
                BuiltInTaskCount: 2,
                ScriptGroupCount: 1,
                ResumeMarkerFound: true),
            $"OneDragon runner returned unexpected result: {result}");
        context.Require(
            platform.Events.SequenceEqual(
            [
                "resume:",
                "start",
                "save",
                "notify-start:一条龙启动",
                "built-in:ClaimMail",
                "notify-start:配置组任务启动",
                "group:地图追踪组",
                "built-in:ClaimDailyRewards",
                "check-rewards",
                "notify-end:一条龙和配置组任务结束",
                "completion:CloseGameAndApplication",
            ]),
            "OneDragon runner lost upstream task, notification, or completion ordering: " +
            string.Join(" | ", platform.Events));
        context.Require(
            config.NextTaskId.Length == 0,
            "OneDragon runner did not consume the resume marker.");
        context.Require(
            !CancellationContext.Instance.IsCancellationRequested,
            "OneDragon runner leaked its cancellation context after completion.");

        var cancellationConfig = new OneDragonFlowConfig();
        var cancellationPlan = OneDragonPlan.FromOrderedSteps(
        [
            new OneDragonPlanStep("mail", "领取邮件", true, false),
            new OneDragonPlanStep("group", "不应执行", true, false),
        ], null);
        var cancellationPlatform = new RecordingOneDragonPlatform
        {
            CancelAfterBuiltIn = true,
        };
        var cancellationResult = await new OneDragonRunner(
                cancellationPlatform,
                OneDragonRunnerDelays.None)
            .RunAsync(cancellationConfig, cancellationPlan);

        context.Require(
            cancellationResult.State == OneDragonRunState.Cancelled &&
            cancellationPlatform.Events.SequenceEqual(
            [
                "start",
                "save",
                "notify-start:一条龙启动",
                "built-in:ClaimMail",
            ]),
            "OneDragon manual cancellation continued into later tasks or emitted a false completion: " +
            string.Join(" | ", cancellationPlatform.Events));
        context.Require(
            !CancellationContext.Instance.IsCancellationRequested,
            "OneDragon cancellation path leaked its cancellation context.");

        var externalCancellationConfig = new OneDragonFlowConfig();
        var externalCancellationPlan = OneDragonPlan.FromOrderedSteps(
        [
            new OneDragonPlanStep("mail", "领取邮件", true, false),
        ], null);
        using var externalCancellation = new CancellationTokenSource();
        var externalCancellationPlatform = new RecordingOneDragonPlatform
        {
            Started = () => externalCancellation.Cancel(),
        };
        var externalCancellationResult = await new OneDragonRunner(
                externalCancellationPlatform,
                OneDragonRunnerDelays.None)
            .RunAsync(
                externalCancellationConfig,
                externalCancellationPlan,
                externalCancellation.Token);

        context.Require(
            externalCancellationResult.State ==
                OneDragonRunState.CancelledDuringStartup &&
            externalCancellationPlatform.Events.SequenceEqual(["start"]),
            "OneDragon external cancellation did not stop the shared runner during startup.");
        context.Require(
            !CancellationContext.Instance.IsCancellationRequested,
            "OneDragon external cancellation leaked its cancellation context.");

        var disabledConfig = new OneDragonFlowConfig
        {
            NextTaskId = "disabled",
        };
        var disabledPlan = OneDragonPlan.FromOrderedSteps(
        [
            new OneDragonPlanStep("disabled", "自动秘境", false, true),
        ], disabledConfig.NextTaskId);
        var disabledPlatform = new RecordingOneDragonPlatform();
        var disabledResult = await new OneDragonRunner(
                disabledPlatform,
                OneDragonRunnerDelays.None)
            .RunAsync(disabledConfig, disabledPlan);

        context.Require(
            disabledResult.State == OneDragonRunState.NoEnabledTasks &&
            disabledConfig.NextTaskId.Length == 0 &&
            disabledPlatform.Events.SequenceEqual(["resume:"]),
            "OneDragon disabled plan did not consume its resume marker without starting tasks.");
    }

    private sealed class RecordingOneDragonPlatform : IOneDragonExecutionPlatform
    {
        public ILogger Logger => NullLogger.Instance;
        public List<string> Events { get; } = [];
        public bool CancelAfterBuiltIn { get; init; }
        public Action? Started { get; init; }

        public Task StartGameTask()
        {
            Events.Add("start");
            Started?.Invoke();
            return Task.CompletedTask;
        }

        public Task ExecuteBuiltInTask(
            OneDragonBuiltInTaskRequest request,
            CancellationToken cancellationToken)
        {
            Events.Add($"built-in:{request.Task}");
            if (CancelAfterBuiltIn)
            {
                CancellationContext.Instance.ManualCancel();
            }
            return Task.CompletedTask;
        }

        public Task ExecuteScriptGroup(
            OneDragonScriptGroupRequest request,
            CancellationToken cancellationToken)
        {
            Events.Add($"group:{request.Name}");
            return Task.CompletedTask;
        }

        public Task CheckRewards(CancellationToken cancellationToken)
        {
            Events.Add("check-rewards");
            return Task.CompletedTask;
        }

        public void SaveConfiguration(OneDragonFlowConfig config) => Events.Add("save");

        public void ResumeMarkerConsumed(OneDragonFlowConfig config) =>
            Events.Add($"resume:{config.NextTaskId}");

        public void NotifyDragonStart(string message) =>
            Events.Add($"notify-start:{message}");

        public void NotifyDragonEnd(string message) =>
            Events.Add($"notify-end:{message}");

        public void ReportScriptGroupFailure(
            OneDragonScriptGroupRequest request,
            Exception exception) =>
            Events.Add($"group-error:{request.Name}");

        public void ExecuteCompletionAction(OneDragonCompletionAction action) =>
            Events.Add($"completion:{action}");
    }

    private sealed class RecordingTaskRunnerPlatform : ITaskRunnerPlatform
    {
        public ILogger Logger => NullLogger.Instance;
        public ILogger RunnerLogger => NullLogger.Instance;
        public SemaphoreSlim TaskSemaphore { get; } = new(1, 1);
        public void InitializeTask() { }
        public void EndTask() { }
        public void NotifyCancellation(string message) { }
        public void NotifyError(string message, Exception exception) { }
    }
}
