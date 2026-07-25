using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.GameTask.TaskProgress;
using BetterGenshinImpact.Verification.Framework;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class SchedulerStatusSuite : IVerificationSuite
{
    public string Name => "scheduler-status";

    public Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var tracker = new SchedulerStatusTracker();
        context.Require(
            tracker.Snapshot() == new SchedulerStatusSnapshot(null, "idle", null, null),
            "Scheduler status did not start idle.");

        const string taskId = "task-a";
        context.Require(
            tracker.Start(taskId, "Group A") ==
            new SchedulerStatusSnapshot(taskId, "running", "Group A", null),
            "Scheduler status did not expose the running task.");
        context.Require(
            tracker.Transition(taskId, "paused").State == "paused" &&
            tracker.Transition(taskId, "running").State == "running" &&
            tracker.Transition(taskId, "stopping").State == "stopping" &&
            tracker.Transition(taskId, "cancelled").State == "cancelled",
            "Scheduler status did not preserve its lifecycle transitions.");

        tracker.Start("task-b", "Group B");
        var failed = tracker.Transition("task-b", "failed", "failure");
        context.Require(
            failed.State == "failed" && failed.Error == "failure",
            "Scheduler status did not preserve terminal error details.");

        var staleTransitionRejected = false;
        try
        {
            tracker.Transition(taskId, "completed");
        }
        catch (InvalidOperationException)
        {
            staleTransitionRejected = true;
        }
        context.Require(
            staleTransitionRejected,
            "Scheduler status accepted a stale task transition.");

        var invalidStateRejected = false;
        try
        {
            tracker.Transition("task-b", "unknown");
        }
        catch (ArgumentException)
        {
            invalidStateRejected = true;
        }
        context.Require(
            invalidStateRejected,
            "Scheduler status accepted an unsupported lifecycle state.");

        var progress = new TaskProgress
        {
            Name = "20260725123456",
            ScriptGroupNames = ["每日", "狗粮"],
            CurrentScriptGroupName = "狗粮",
            CurrentScriptGroupProjectInfo = new TaskProgress.ScriptGroupProjectInfo
            {
                Index = 3,
                Name = "锄地一条龙"
            },
            Loop = true,
            LoopCount = 2
        };
        var summary = SchedulerCoordinator.CreateProgressSummary(progress);
        context.Require(
            summary.Name == progress.Name &&
            summary.DisplayName == "20260725123456_狗粮_循环(2)_3_锄地一条龙" &&
            summary.ScriptGroupNames.SequenceEqual(progress.ScriptGroupNames) &&
            summary.CurrentProjectName == "锄地一条龙",
            "Scheduler progress summary diverged from the upstream continue-task display semantics.");

        var firstGroup = new ScriptGroup { Name = "每日" };
        firstGroup.AddProject(new ScriptGroupProject
        {
            Name = "委托",
            FolderName = "AutoEntrust"
        });
        firstGroup.AddProject(new ScriptGroupProject
        {
            Name = "派遣",
            FolderName = "AutoExpedition"
        });
        var secondGroup = new ScriptGroup { Name = "锄地" };
        secondGroup.AddProject(new ScriptGroupProject
        {
            Name = "路线",
            FolderName = "AutoHoeing"
        });
        progress.LastScriptGroupName = firstGroup.Name;
        progress.LastSuccessScriptGroupProjectInfo =
            new TaskProgress.ScriptGroupProjectInfo
            {
                Name = "委托",
                FolderName = "AutoEntrust"
            };
        TaskProgressManager.GenerNextProjectInfo(progress, [firstGroup, secondGroup]);
        context.Require(
            progress.Next is
                {
                    GroupName: "每日",
                    Index: 1,
                    ProjectName: "派遣"
                },
            "Upstream task progress did not resume at the next project in the current group.");
        progress.LastSuccessScriptGroupProjectInfo =
            new TaskProgress.ScriptGroupProjectInfo
            {
                Name = "派遣",
                FolderName = "AutoExpedition"
            };
        TaskProgressManager.GenerNextProjectInfo(progress, [firstGroup, secondGroup]);
        context.Require(
            progress.Next is
                {
                    GroupName: "锄地",
                    Index: 0,
                    ProjectName: "路线"
                },
            "Upstream task progress did not continue into the next script group.");
        return Task.CompletedTask;
    }
}
