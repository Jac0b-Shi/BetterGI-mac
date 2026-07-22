using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.GameTask;
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
    private string? _taskId;
    private Task? _execution;

    public object Run(string groupName)
    {
        ScriptGroup group;
        var path = ResolveGroup(groupName);
        group = ScriptGroup.FromJson(File.ReadAllText(path));
        ApplyNextProject(group);
        if (group.Projects.Count == 0)
            throw new InvalidDataException($"Script group '{groupName}' contains no projects.");

        lock (_sync)
        {
            if (_execution is { IsCompleted: false })
                throw new InvalidOperationException($"Scheduler task '{_taskId}' is already running.");
            RunnerContext.Instance.IsSuspend = false;
            var taskId = Guid.NewGuid().ToString("N");
            _taskId = taskId;
            _execution = ExecuteAsync(taskId, group);
            return new { taskId, state = "running", groupName = group.Name };
        }
    }

    public object Pause(string taskId)
    {
        RequireActive(taskId);
        RunnerContext.Instance.IsSuspend = true;
        EmitAsync(taskId, "paused", null).GetAwaiter().GetResult();
        return new { taskId, state = "paused" };
    }

    public object Resume(string taskId)
    {
        RequireActive(taskId);
        RunnerContext.Instance.IsSuspend = false;
        EmitAsync(taskId, "running", null).GetAwaiter().GetResult();
        return new { taskId, state = "running" };
    }

    public object Stop(string taskId)
    {
        RequireActive(taskId);
        CancellationContext.Instance.ManualCancel();
        return new { taskId, state = "stopping" };
    }

    private async Task ExecuteAsync(string taskId, ScriptGroup group)
    {
        try
        {
            await EmitAsync(taskId, "running", null);
            await new ScriptService().RunMulti(group.Projects, group.Name);
            var state = CancellationContext.Instance.IsManualStop ? "cancelled" : "completed";
            await EmitAsync(taskId, state, null);
        }
        catch (Exception ex)
        {
            await EmitAsync(taskId, "failed", new { code = ex.GetType().Name, message = ex.Message });
        }
        finally
        {
            RunnerContext.Instance.IsSuspend = false;
        }
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
        lock (_sync)
        {
            if (_execution is not { IsCompleted: false } || !string.Equals(taskId, _taskId, StringComparison.Ordinal))
                throw new InvalidOperationException($"Scheduler task '{taskId}' is not active.");
        }
    }

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

    private void ApplyNextProject(ScriptGroup group)
    {
        if (!File.Exists(layout.SchedulerStatePath)) return;
        try
        {
            var state = JObject.Parse(File.ReadAllText(layout.SchedulerStatePath));
            if (state.Value<string>("groupName") != group.Name) return;
            var startIndex = group.Projects.ToList().FindIndex(project =>
                project.Index == state.Value<int?>("index") &&
                project.FolderName == state.Value<string>("folderName") &&
                project.Name == state.Value<string>("projectName"));
            if (startIndex < 0) return;
            for (var index = 0; index < startIndex; index++) group.Projects[index].SkipFlag = true;
            File.Delete(layout.SchedulerStatePath);
        }
        catch (Exception exception) when (exception is IOException or Newtonsoft.Json.JsonException)
        {
            throw new InvalidDataException("The saved scheduler start position is invalid.", exception);
        }
    }
}
