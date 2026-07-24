using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.Core.Script.OneDragon;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class OneDragonCoordinator(
    OneDragonCatalog catalog,
    IOneDragonExecutionPlatform platform,
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken hostCancellationToken)
{
    private readonly object _sync = new();
    private readonly SchedulerStatusTracker _status = new();
    private CancellationTokenSource? _operationCancellation;
    private Task? _execution;

    public object Start(string configName)
    {
        lock (_sync)
        {
            var current = _status.Snapshot();
            if (_execution is { IsCompleted: false } &&
                !SchedulerStatusTracker.IsTerminal(current.State))
            {
                throw new InvalidOperationException(
                    $"OneDragon config '{current.GroupName}' is already running.");
            }

            var config = catalog.Load(configName);
            catalog.Select(config.Name);
            var plan = OneDragonPlan.FromConfig(config);
            _operationCancellation?.Dispose();
            _operationCancellation =
                CancellationTokenSource.CreateLinkedTokenSource(hostCancellationToken);
            var taskId = Guid.NewGuid().ToString("N");
            var status = _status.Start(taskId, config.Name);
            _execution = ExecuteAsync(
                taskId,
                config,
                plan,
                _operationCancellation.Token);
            return ToRpcStatus(status);
        }
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

    public object Status() => ToRpcStatus(_status.Snapshot());

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
                ?? throw new InvalidOperationException(
                    "Active OneDragon task omitted its id."),
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
        BetterGenshinImpact.Core.Config.OneDragonFlowConfig config,
        OneDragonPlan plan,
        CancellationToken cancellationToken)
    {
        using var cancellationRegistration = cancellationToken.Register(
            CancellationContext.Instance.Cancel);
        try
        {
            await EmitAsync(taskId, "running", null);
            var result = await new OneDragonRunner(platform).RunAsync(
                config,
                plan,
                cancellationToken);
            var state = result.State is
                OneDragonRunState.Cancelled or
                OneDragonRunState.CancelledDuringStartup
                ? "cancelled"
                : "completed";
            SetStatus(taskId, state);
            await TryEmitTerminalAsync(taskId, state, null);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            SetStatus(taskId, "cancelled");
            await TryEmitTerminalAsync(taskId, "cancelled", null);
        }
        catch (Exception exception)
        {
            SetStatus(taskId, "failed", exception.Message);
            await TryEmitTerminalAsync(taskId, "failed", new
            {
                code = exception.GetType().Name,
                message = exception.Message,
            });
        }
    }

    private async Task EmitAsync(string taskId, string state, object? error)
    {
        var response = await callbacks.InvokeAsync(
            "oneDragon.event",
            JObject.FromObject(new { taskId, state, error }),
            sessionToken,
            hostCancellationToken);
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException(
                "oneDragon.event did not return acknowledged=true.");
    }

    private async Task TryEmitTerminalAsync(
        string taskId,
        string state,
        object? error)
    {
        try
        {
            await EmitAsync(taskId, state, error);
        }
        catch (Exception exception)
        {
            platform.Logger.LogError(
                exception,
                "OneDragon terminal event callback failed: {TaskId} {State}",
                taskId,
                state);
        }
    }

    private void RequireActive(string taskId)
    {
        var status = _status.Snapshot();
        if (_execution is not { IsCompleted: false } ||
            SchedulerStatusTracker.IsTerminal(status.State) ||
            !string.Equals(taskId, status.TaskId, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"OneDragon task '{taskId}' is not active.");
        }
    }

    private void SetStatus(string taskId, string state, string? error = null)
    {
        lock (_sync)
            _status.Transition(taskId, state, error);
    }

    private static object ToRpcStatus(SchedulerStatusSnapshot status) => new
    {
        taskId = status.TaskId,
        state = status.State,
        configName = status.GroupName,
        error = status.Error,
    };
}
