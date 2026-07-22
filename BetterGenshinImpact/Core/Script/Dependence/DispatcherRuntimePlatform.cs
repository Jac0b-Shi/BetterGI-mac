using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.GameTask.AutoFishing;

namespace BetterGenshinImpact.Core.Script.Dependence;

public interface IDispatcherRuntimePlatform
{
    CancellationToken GlobalCancellationToken { get; }
    int AutoWoodRoundNum { get; }
    int AutoWoodDailyMaxCount { get; }
    string AutoBossStrategyName { get; }
    DispatcherAutoEatSettings AutoEatSettings { get; }
    void ClearTriggers();
    bool AddTrigger(string name, object? config);
    bool GetTcgStrategy(out string content);
    bool GetFightStrategy(string? strategyName, out string path);
    Task<object?> ExecuteSoloTask(DispatcherSoloTaskRequest request,
        CancellationToken cancellationToken);
    Task<object?> RunParameterizedTask(string name, object parameter,
        CancellationToken cancellationToken);
}

public sealed record DispatcherAutoEatSettings(int CheckInterval, int EatInterval, bool ShowNotification);

public abstract record DispatcherSoloTaskRequest(string Name);
public sealed record DispatcherGeniusTaskRequest(string Strategy) : DispatcherSoloTaskRequest("AutoGeniusInvokation");
public sealed record DispatcherWoodTaskRequest(int RoundNum, int DailyMaxCount) : DispatcherSoloTaskRequest("AutoWood");
public sealed record DispatcherFightTaskRequest(object? Config) : DispatcherSoloTaskRequest("AutoFight");
public sealed record DispatcherDomainTaskRequest(string StrategyPath) : DispatcherSoloTaskRequest("AutoDomain");
public sealed record DispatcherBossTaskRequest(string StrategyPath) : DispatcherSoloTaskRequest("AutoBoss");
public sealed record DispatcherFishingTaskRequest(
    object? Config, AutoFishingTaskParam? Param = null) : DispatcherSoloTaskRequest("AutoFishing");
public sealed record DispatcherCookTaskRequest() : DispatcherSoloTaskRequest("AutoCook");
public sealed record DispatcherMusicGameTaskRequest() : DispatcherSoloTaskRequest("AutoMusicGame");
public sealed record DispatcherArtifactSalvageTaskRequest() : DispatcherSoloTaskRequest("AutoArtifactSalvage");
public sealed record DispatcherEatTaskRequest(string? FoodName, DispatcherAutoEatSettings Settings) : DispatcherSoloTaskRequest("AutoEat");
public sealed record DispatcherCountInventoryTaskRequest(
    int GridScreenName, string? ItemName, IReadOnlyList<string> ItemNames) : DispatcherSoloTaskRequest("CountInventoryItem");

public static class DispatcherRuntimePlatform
{
    public static IDispatcherRuntimePlatform Current { get; private set; } = null!;

    public static void Configure(IDispatcherRuntimePlatform platform) =>
        Current = platform ?? throw new ArgumentNullException(nameof(platform));
}
