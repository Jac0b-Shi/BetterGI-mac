using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.TaskProgress;
using BetterGenshinImpact.Service;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>Owns one real upstream ScriptService.RunMulti execution at a time.</summary>
public sealed class SchedulerCoordinator(
    RuntimeLayout layout,
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken hostCancellationToken)
{
    private readonly object _sync = new();
    private readonly SchedulerStatusTracker _status = new();
    private Task? _execution;
    private CancellationTokenSource? _operationCancellation;

    public object Run(string groupName)
    {
        var path = ResolveGroup(groupName);
        var group = ScriptGroup.FromJson(File.ReadAllText(path));
        ScriptGroupResumeState.ApplyAndConsume(layout, group);
        if (group.Projects.Count == 0)
            throw new InvalidDataException($"Script group '{groupName}' contains no projects.");
        return Start(group.Name, _ => RunGroupAsync(group));
    }

    public object RunGroups(IReadOnlyList<string> groupNames)
    {
        ArgumentNullException.ThrowIfNull(groupNames);
        if (groupNames.Count == 0)
            throw new ArgumentException("At least one script group name is required.", nameof(groupNames));

        var groups = groupNames
            .Select(groupName =>
            {
                var path = ResolveGroup(groupName);
                var group = ScriptGroup.FromJson(File.ReadAllText(path));
                ScriptGroupResumeState.ApplyAndConsume(layout, group);
                if (group.Projects.Count == 0)
                    throw new InvalidDataException($"Script group '{groupName}' contains no projects.");
                return group;
            })
            .ToArray();
        var displayName = string.Join(",", groups.Select(group => group.Name));
        return Start(displayName, cancellationToken => RunGroupsAsync(groups, cancellationToken));
    }

    public object RunProject(ScriptGroupProject project, string displayName)
    {
        ArgumentNullException.ThrowIfNull(project);
        if (string.IsNullOrWhiteSpace(displayName))
            throw new ArgumentException("Task display name cannot be empty.", nameof(displayName));
        return Start(displayName, _ =>
            new ScriptService().RunMulti([project], displayName));
    }

    public object Status()
        => ToRpcStatus(_status.Snapshot());

    private object Start(string displayName, Func<CancellationToken, Task> operation)
    {
        lock (_sync)
        {
            if (_execution is { IsCompleted: false })
                throw new InvalidOperationException(
                    $"Scheduler task '{_status.Snapshot().TaskId}' is already running.");
            _operationCancellation?.Dispose();
            _operationCancellation = CancellationTokenSource.CreateLinkedTokenSource(hostCancellationToken);
            RunnerContext.Instance.IsSuspend = false;
            var taskId = Guid.NewGuid().ToString("N");
            var status = _status.Start(taskId, displayName);
            _execution = ExecuteAsync(
                taskId, displayName, operation, _operationCancellation.Token);
            return ToRpcStatus(status);
        }
    }

    public object Pause(string taskId)
    {
        lock (_sync)
        {
            RequireActive(taskId);
            RunnerContext.Instance.IsSuspend = true;
            _status.Transition(taskId, "paused");
        }
        EmitAsync(taskId, "paused", null).GetAwaiter().GetResult();
        return Status();
    }

    public object Resume(string taskId)
    {
        lock (_sync)
        {
            RequireActive(taskId);
            RunnerContext.Instance.IsSuspend = false;
            _status.Transition(taskId, "running");
        }
        EmitAsync(taskId, "running", null).GetAwaiter().GetResult();
        return Status();
    }

    public object Stop(string taskId)
    {
        lock (_sync)
        {
            RequireActive(taskId);
            var status = _status.Transition(taskId, "stopping");
            CancellationContext.Instance.ManualCancel();
            _operationCancellation?.Cancel();
            return ToRpcStatus(status);
        }
    }

    public async Task<bool> StopActiveAsync(CancellationToken cancellationToken)
    {
        Task? execution;
        lock (_sync)
        {
            var status = _status.Snapshot();
            if (_execution is not { IsCompleted: false } ||
                SchedulerStatusTracker.IsTerminal(status.State))
                return false;
            _status.Transition(
                status.TaskId
                ?? throw new InvalidOperationException("Active scheduler task omitted its id."),
                "stopping");
            CancellationContext.Instance.ManualCancel();
            _operationCancellation?.Cancel();
            execution = _execution;
        }

        await execution.WaitAsync(cancellationToken);
        return true;
    }

    private async Task ExecuteAsync(
        string taskId,
        string displayName,
        Func<CancellationToken, Task> operation,
        CancellationToken cancellationToken)
    {
        try
        {
            await EmitAsync(taskId, "running", null);
            await operation(cancellationToken);
            var state = CancellationContext.Instance.IsManualStop ? "cancelled" : "completed";
            SetExecutionStatus(taskId, state);
            await EmitAsync(taskId, state, null);
        }
        catch (OperationCanceledException) when (
            CancellationContext.Instance.IsManualStop || cancellationToken.IsCancellationRequested)
        {
            SetExecutionStatus(taskId, "cancelled");
            await EmitAsync(taskId, "cancelled", null);
        }
        catch (Exception ex)
        {
            SetExecutionStatus(taskId, "failed", ex.Message);
            await EmitAsync(taskId, "failed", new { code = ex.GetType().Name, message = ex.Message });
        }
        finally
        {
            RunnerContext.Instance.IsSuspend = false;
        }
    }

    private static async Task RunGroupsAsync(
        IReadOnlyList<ScriptGroup> groups,
        CancellationToken cancellationToken)
    {
        RunnerContext.Instance.Reset();
        RunnerContext.Instance.IsContinuousRunGroup = true;
        var taskProgress = new TaskProgress
        {
            ScriptGroupNames = groups.Select(group => group.Name).ToList(),
            Loop = false
        };
        RunnerContext.Instance.taskProgress = taskProgress;
        try
        {
            var service = new ScriptService();
            for (var index = 0; index < groups.Count; index++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var group = groups[index];
                taskProgress.CurrentScriptGroupName = group.Name;
                TaskProgressManager.SaveTaskProgress(taskProgress);
                await service.RunMulti(group.Projects, group.Name, taskProgress);
                cancellationToken.ThrowIfCancellationRequested();
                await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken);
            }
            taskProgress.LoopCount++;
            if (taskProgress.ConsecutiveFailureCount == 0)
            {
                taskProgress.EndTime = DateTime.Now;
                TaskProgressManager.SaveTaskProgress(taskProgress);
            }
        }
        finally
        {
            RunnerContext.Instance.Reset();
        }
    }

    private static async Task RunGroupAsync(ScriptGroup group)
    {
        RunnerContext.Instance.Reset();
        var taskProgress = new TaskProgress
        {
            ScriptGroupNames = [group.Name],
            CurrentScriptGroupName = group.Name
        };
        RunnerContext.Instance.taskProgress = taskProgress;
        TaskProgressManager.SaveTaskProgress(taskProgress);
        await new ScriptService().RunMulti(group.Projects, group.Name, taskProgress);
    }

    private async Task EmitAsync(string taskId, string state, object? error)
    {
        var response = await callbacks.InvokeAsync("scheduler.event", JObject.FromObject(new
        {
            taskId,
            state,
            error
        }), sessionToken, hostCancellationToken);
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException("scheduler.event did not return acknowledged=true.");
    }

    private void RequireActive(string taskId)
    {
        var status = _status.Snapshot();
        if (_execution is not { IsCompleted: false } ||
            SchedulerStatusTracker.IsTerminal(status.State) ||
            !string.Equals(taskId, status.TaskId, StringComparison.Ordinal))
            throw new InvalidOperationException($"Scheduler task '{taskId}' is not active.");
    }

    private void SetExecutionStatus(string taskId, string state, string? error = null)
    {
        lock (_sync)
        {
            _status.Transition(taskId, state, error);
        }
    }

    private static object ToRpcStatus(SchedulerStatusSnapshot status) => new
    {
        taskId = status.TaskId,
        state = status.State,
        groupName = status.GroupName,
        error = status.Error
    };

    private string ResolveGroup(string groupName)
    {
        if (string.IsNullOrWhiteSpace(groupName) || groupName.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 ||
            groupName.Contains('/') || groupName.Contains('\\') || groupName is "." or "..")
            throw new ArgumentException("Invalid script group name.", nameof(groupName));
        var path = Path.Combine(layout.ScriptGroupPath, groupName + ".json");
        if (!File.Exists(path))
            throw new FileNotFoundException($"Script group does not exist: {groupName}", path);
        return path;
    }

}
