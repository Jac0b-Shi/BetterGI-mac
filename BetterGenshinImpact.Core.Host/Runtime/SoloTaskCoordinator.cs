using BetterGenshinImpact.Core.Script.Dependence;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class SoloTaskCoordinator(
    IDispatcherRuntimePlatform platform,
    CancellationToken shutdownToken)
{
    private readonly object _lock = new();
    private CancellationTokenSource? _activeCancellation;
    private Task? _activeTask;
    private string? _activeTaskId;
    private string? _activeName;
    private string _state = "idle";
    private string? _error;

    public object List() => new[]
    {
        Descriptor("AutoGeniusInvokation", "自动七圣召唤", false),
        Descriptor("AutoWood", "自动伐木", true),
        Descriptor("AutoFight", "自动战斗", true),
        Descriptor("AutoDomain", "自动秘境", false),
        Descriptor("AutoBoss", "自动首领讨伐", false),
        Descriptor("AutoStygianOnslaught", "自动幽境危战", false),
        Descriptor("AutoFishing", "全自动钓鱼（单个鱼塘）", true),
        Descriptor("AutoLeyLineOutcrop", "自动地脉花", false),
        Descriptor("AutoMusicGame", "自动千音雅集", true),
        Descriptor("AutoCook", "自动烹饪", true),
        Descriptor("AutoArtifactSalvage", "自动分解圣遗物", false),
    };

    public object Start(string name)
    {
        if (name is not ("AutoWood" or "AutoFishing" or "AutoFight" or "AutoCook" or "AutoMusicGame"))
            throw new CapabilityUnavailableException(
                $"solo task '{name}' is not composed in the macOS Core yet; no task was executed.");

        lock (_lock)
        {
            if (_activeTask is { IsCompleted: false })
                throw new InvalidOperationException($"Solo task '{_activeName}' is already running.");

            _activeCancellation?.Dispose();
            _activeCancellation = CancellationTokenSource.CreateLinkedTokenSource(shutdownToken);
            _activeTaskId = Guid.NewGuid().ToString("N");
            _activeName = name;
            _state = "running";
            _error = null;
            var taskId = _activeTaskId;
            _activeTask = RunAsync(taskId, name, _activeCancellation.Token);
            return new { taskId, name, state = _state };
        }
    }

    public object Stop(string taskId)
    {
        lock (_lock)
        {
            if (_activeTaskId != taskId)
                throw new KeyNotFoundException($"Unknown solo task id: {taskId}");
            if (_activeTask is null || _activeTask.IsCompleted)
                return new { taskId, name = _activeName, state = _state };
            _state = "stopping";
            _activeCancellation?.Cancel();
            return new { taskId, name = _activeName, state = _state };
        }
    }

    public object Status()
    {
        lock (_lock)
        {
            return new { taskId = _activeTaskId, name = _activeName, state = _state, error = _error };
        }
    }

    private async Task RunAsync(string taskId, string name, CancellationToken cancellationToken)
    {
        try
        {
            var request = name switch
            {
                "AutoFishing" => (DispatcherSoloTaskRequest)new DispatcherFishingTaskRequest(null),
                "AutoWood" => new DispatcherWoodTaskRequest(
                    platform.AutoWoodRoundNum, platform.AutoWoodDailyMaxCount),
                "AutoFight" => new DispatcherFightTaskRequest(null),
                "AutoCook" => new DispatcherCookTaskRequest(),
                "AutoMusicGame" => new DispatcherMusicGameTaskRequest(),
                _ => throw new CapabilityUnavailableException($"Unknown composed solo task '{name}'.")
            };
            await platform.ExecuteSoloTask(request, cancellationToken);
            Complete(taskId, "completed", null);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            Complete(taskId, "cancelled", null);
        }
        catch (Exception exception)
        {
            Complete(taskId, "failed", exception.Message);
        }
    }

    private void Complete(string taskId, string state, string? error)
    {
        lock (_lock)
        {
            if (_activeTaskId != taskId) return;
            _state = state;
            _error = error;
        }
    }

    private static object Descriptor(string name, string displayName, bool available) => new
    {
        name,
        displayName,
        available,
        unavailableReason = available ? null : "尚未完成共享 C# 任务的平台组合"
    };
}
