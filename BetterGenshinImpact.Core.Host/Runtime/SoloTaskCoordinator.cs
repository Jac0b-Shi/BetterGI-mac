using BetterGenshinImpact.Core.Script.Dependence;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class SoloTaskCoordinator(
    IDispatcherRuntimePlatform platform,
    SoloTaskSettingsCatalog settings,
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
        Descriptor("AutoGeniusInvokation", "自动七圣召唤", "全自动打牌", true),
        Descriptor(
            "AutoWood", "自动伐木",
            "装备「王树瑞佑」，通过循环重启游戏刷新并收集木材", true),
        Descriptor("AutoFight", "自动战斗", "自动执行选择的战斗策略", true),
        Descriptor("AutoDomain", "自动秘境", "基于钟离的自动循环刷本", true),
        Descriptor("AutoBoss", "自动首领讨伐", "自动传送、战斗并领取奖励", true),
        Descriptor(
            "AutoStygianOnslaught", "自动幽境危战",
            "自动传送并进入幽境危战", true),
        Descriptor(
            "AutoFishing", "全自动钓鱼（单个鱼塘）",
            "不要携带跟宠！在出现钓鱼F按钮的位置启动本任务", true),
        Descriptor("AutoLeyLineOutcrop", "自动地脉花", "自动定位并刷取地脉花", true),
        Descriptor(
            "AutoMusicGame", "自动千音雅集",
            "可以自动演奏单个，也可以全自动完成整个专辑", true),
        Descriptor(
            "AutoAlbum", "自动千音雅集（整个专辑）",
            "可以自动演奏单个，也可以全自动完成整个专辑", true),
        Descriptor(
            "AutoCook", "自动烹饪",
            "在手动烹饪界面运行，自动识别并点击结束烹饪", true),
        Descriptor(
            "AutoArtifactSalvage", "自动分解圣遗物",
            "指定匹配表达式逐一筛选分解，支持5星圣遗物", true),
        Descriptor(
            "AutoRedeemCode", "自动使用兑换码", "自动使用输入的兑换码", true,
            inputKind: "multilineText", inputTitle: "输入兑换码",
            inputPlaceholder: "每行一条兑换码"),
    };

    public object Start(string name, string? inputText = null)
    {
        if (name is not ("AutoGeniusInvokation" or "AutoWood" or "AutoFishing" or "AutoFight" or "AutoCook" or "AutoMusicGame" or "AutoAlbum" or "AutoArtifactSalvage" or "AutoDomain" or "AutoBoss" or "AutoLeyLineOutcrop" or "AutoStygianOnslaught" or "AutoRedeemCode"))
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
            _activeTask = RunAsync(taskId, name, inputText, _activeCancellation.Token);
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

    public object Toggle(string name)
    {
        lock (_lock)
        {
            if (_activeTask is { IsCompleted: false })
            {
                if (!string.Equals(_activeName, name, StringComparison.Ordinal))
                    throw new InvalidOperationException(
                        $"Solo task '{_activeName}' is already running.");
                _state = "stopping";
                _activeCancellation?.Cancel();
                return new
                {
                    taskId = _activeTaskId,
                    name = _activeName,
                    state = _state,
                };
            }
        }
        return Start(name);
    }

    public async Task<bool> StopActiveAsync(CancellationToken cancellationToken)
    {
        Task? activeTask;
        lock (_lock)
        {
            if (_activeTask is not { IsCompleted: false })
                return false;
            _state = "stopping";
            _activeCancellation?.Cancel();
            activeTask = _activeTask;
        }

        await activeTask.WaitAsync(cancellationToken);
        return true;
    }

    public object Status()
    {
        lock (_lock)
        {
            return new { taskId = _activeTaskId, name = _activeName, state = _state, error = _error };
        }
    }

    private async Task RunAsync(
        string taskId, string name, string? inputText,
        CancellationToken cancellationToken)
    {
        try
        {
            var request = name switch
            {
                "AutoGeniusInvokation" => new DispatcherGeniusTaskRequest(
                    settings.GetTcgStrategy()),
                "AutoFishing" => (DispatcherSoloTaskRequest)new DispatcherFishingTaskRequest(
                    null, settings.BuildAutoFishingTaskParam()),
                "AutoWood" => new DispatcherWoodTaskRequest(
                    settings.AutoWoodRoundNum, settings.AutoWoodDailyMaxCount),
                "AutoFight" => new DispatcherFightTaskRequest(null),
                "AutoCook" => new DispatcherCookTaskRequest(),
                "AutoMusicGame" => new DispatcherMusicGameTaskRequest(),
                "AutoAlbum" => new DispatcherAlbumTaskRequest(),
                "AutoArtifactSalvage" => new DispatcherArtifactSalvageTaskRequest(),
                "AutoRedeemCode" => new DispatcherRedeemCodeTaskRequest(
                    ParseRedeemCodes(inputText)),
                "AutoLeyLineOutcrop" => new DispatcherLeyLineTaskRequest(
                    settings.BuildAutoLeyLineOutcropConfig()),
                "AutoStygianOnslaught" => BuildStygianRequest(),
                "AutoDomain" => new DispatcherDomainTaskRequest(
                    !platform.GetFightStrategy(null, out var path)
                        ? path
                        : throw new CapabilityUnavailableException(
                            "AutoDomain combat strategy is unavailable.")),
                "AutoBoss" => new DispatcherBossTaskRequest(
                    !platform.GetFightStrategy(platform.AutoBossStrategyName, out var bossPath)
                        ? bossPath
                        : throw new CapabilityUnavailableException(
                            "AutoBoss combat strategy is unavailable.")),
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

    private static string[] ParseRedeemCodes(string? inputText)
    {
        var codes = (inputText ?? string.Empty)
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Select(code => code.Trim())
            .Where(code => code.Length > 0)
            .ToArray();
        if (codes.Length == 0)
            throw new ArgumentException("AutoRedeemCode requires at least one redeem code.");
        return codes;
    }

    private DispatcherStygianTaskRequest BuildStygianRequest()
    {
        var config = settings.BuildAutoStygianOnslaughtConfig();
        var strategyName = string.IsNullOrWhiteSpace(config.StrategyName)
            ? null
            : config.StrategyName;
        if (platform.GetFightStrategy(strategyName, out var path))
            throw new CapabilityUnavailableException(
                "AutoStygianOnslaught combat strategy is unavailable.");
        var defaults = settings.BuildAutoStygianOnslaughtDefaults();
        return new DispatcherStygianTaskRequest(
            config, defaults.DefaultStrategyName, defaults.ArtifactSalvageStar, path);
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

    private object Descriptor(
        string name, string displayName, string description, bool available,
        string? inputKind = null, string? inputTitle = null,
        string? inputPlaceholder = null) => new
    {
        name,
        displayName,
        description,
        available,
        settingsAvailable = settings.IsAvailable(name),
        inputKind,
        inputTitle,
        inputPlaceholder,
        unavailableReason = available ? null : "尚未完成共享 C# 任务的平台组合"
    };
}
