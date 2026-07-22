using System;
using System.Collections.Generic;
using System.Dynamic;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.GameTask.AutoBoss;
using BetterGenshinImpact.GameTask.AutoCook;
using BetterGenshinImpact.GameTask.AutoDomain;
using BetterGenshinImpact.GameTask.AutoEat;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.AutoGeniusInvokation;
using BetterGenshinImpact.GameTask.AutoLeyLineOutcrop;
using BetterGenshinImpact.GameTask.AutoPathing.Handler;
using BetterGenshinImpact.GameTask.AutoStygianOnslaught;
using BetterGenshinImpact.GameTask.AutoWood;
using BetterGenshinImpact.GameTask.AutoMusicGame;
using BetterGenshinImpact.GameTask.AutoArtifactSalvage;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.ViewModel.Pages;
using BetterGenshinImpact.GameTask;

namespace BetterGenshinImpact.Core.Script.Dependence;

public sealed class WindowsDispatcherRuntimePlatform(
    IAutoWoodRuntimePlatform autoWoodRuntimePlatform,
    IAutoMusicGameRuntimePlatform autoMusicGameRuntimePlatform)
    : IDispatcherRuntimePlatform
{
    public CancellationToken GlobalCancellationToken => CancellationContext.Instance.Cts.Token;
    private static TaskSettingsPageViewModel Settings => App.GetService<TaskSettingsPageViewModel>()
        ?? throw new InvalidOperationException("TaskSettingsPageViewModel is unavailable.");
    public int AutoWoodRoundNum => Settings.AutoWoodRoundNum;
    public int AutoWoodDailyMaxCount => Settings.AutoWoodDailyMaxCount;
    public string AutoBossStrategyName => TaskContext.Instance().Config.AutoBossConfig.StrategyName;
    public DispatcherAutoEatSettings AutoEatSettings
    {
        get
        {
            var config = TaskContext.Instance().Config.AutoEatConfig;
            return new DispatcherAutoEatSettings(
                config.CheckInterval, config.EatInterval, config.ShowNotification);
        }
    }

    public void ClearTriggers() => TaskTriggerDispatcher.Instance().ClearTriggers();

    public bool AddTrigger(string name, object? config) =>
        TaskTriggerDispatcher.Instance().AddTrigger(name, config);

    public bool GetTcgStrategy(out string content) => Settings.GetTcgStrategy(out content);

    public bool GetFightStrategy(string? strategyName, out string path) =>
        string.IsNullOrEmpty(strategyName)
            ? Settings.GetFightStrategy(out path)
            : Settings.GetFightStrategy(strategyName, out path);

    public async Task<object?> ExecuteSoloTask(DispatcherSoloTaskRequest request,
        CancellationToken cancellationToken)
    {
        switch (request)
        {
            case DispatcherGeniusTaskRequest genius:
                await new AutoGeniusInvokationTask(new GeniusInvokationTaskParam(genius.Strategy))
                    .Start(cancellationToken);
                return null;
            case DispatcherWoodTaskRequest wood:
                await new AutoWoodTask(
                        new WoodTaskParam(wood.RoundNum, wood.DailyMaxCount),
                        TaskContext.Instance().Config.AutoWoodConfig,
                        autoWoodRuntimePlatform)
                    .Start(cancellationToken);
                return null;
            case DispatcherFightTaskRequest fight:
                await new AutoFightHandler().RunAsyncByScript(cancellationToken, null, fight.Config);
                return null;
            case DispatcherMusicGameTaskRequest:
                await new AutoMusicGameTask(new AutoMusicGameParam(), autoMusicGameRuntimePlatform)
                    .Start(cancellationToken);
                return null;
            case DispatcherDomainTaskRequest domain:
                return await new AutoDomainTask(new AutoDomainParam(0, domain.StrategyPath))
                    .Start(cancellationToken);
            case DispatcherBossTaskRequest boss:
                return await new AutoBossTask(new AutoBossParam(boss.StrategyPath)).Start(cancellationToken);
            case DispatcherFishingTaskRequest fishing:
                await new AutoFishingTask(
                        fishing.Param ?? AutoFishingTaskParam.BuildFromSoloTaskConfig(fishing.Config))
                    .Start(cancellationToken);
                return null;
            case DispatcherCookTaskRequest:
                await new AutoCookTask().Start(cancellationToken);
                return null;
            case DispatcherArtifactSalvageTaskRequest:
            {
                var config = TaskContext.Instance().Config.AutoArtifactSalvageConfig;
                await new AutoArtifactSalvageTask(new AutoArtifactSalvageTaskParam(
                        int.Parse(config.MaxArtifactStar), config.JavaScript,
                        config.ArtifactSetFilter, config.MaxNumToCheck,
                        config.RecognitionFailurePolicy))
                    .Start(cancellationToken);
                return null;
            }
            case DispatcherLeyLineTaskRequest leyLine:
                await new AutoLeyLineOutcropTask(
                        new AutoLeyLineOutcropParam(leyLine.Config))
                    .Start(cancellationToken);
                return null;
            case DispatcherEatTaskRequest eat:
                return await new AutoEatTask(new AutoEatParam
                {
                    CheckInterval = eat.Settings.CheckInterval,
                    EatInterval = eat.Settings.EatInterval,
                    ShowNotification = eat.Settings.ShowNotification,
                    FoodName = eat.FoodName
                }).Start(cancellationToken);
            case DispatcherCountInventoryTaskRequest count:
                var countParam = new CountInventoryItemParam
                {
                    GridScreenName = (GameTask.Model.GameUI.GridScreenName)count.GridScreenName,
                    ItemName = count.ItemName,
                    ItemNames = [.. count.ItemNames]
                };
                return await RunCountInventory(countParam, cancellationToken);
            default:
                throw new ArgumentException($"未知的任务请求: {request.Name}", nameof(request));
        }
    }

    public async Task<object?> RunParameterizedTask(string name, object parameter,
        CancellationToken cancellationToken) => name switch
    {
        "AutoDomain" when parameter is AutoDomainParam value =>
            await new AutoDomainTask(value).Start(cancellationToken),
        "AutoBoss" when parameter is AutoBossParam value =>
            await new AutoBossTask(value).Start(cancellationToken),
        "AutoFight" when parameter is AutoFightParam value =>
            await RunAutoFight(value, cancellationToken),
        "AutoLeyLineOutcrop" when parameter is AutoLeyLineOutcropParam value =>
            await RunAutoLeyLine(value, cancellationToken),
        "AutoStygianOnslaught" when parameter is AutoStygianOnslaughtParam value =>
            await RunAutoStygian(value, cancellationToken),
        "CountInventoryItem" when parameter is CountInventoryItemParam value =>
            await RunCountInventory(value, cancellationToken),
        _ => throw new ArgumentException($"{name} 参数类型错误: {parameter.GetType().FullName}", nameof(parameter))
    };

    private static async Task<object?> RunAutoFight(AutoFightParam parameter, CancellationToken cancellationToken)
    {
        var factory = BetterGenshinImpact.GameTask.AutoFight.Factory.CombatTaskFactoryProvider
            .GetFactory(parameter.CombatStrategyPath);
        await factory.CreateTask(parameter).Start(cancellationToken);
        return null;
    }

    private static async Task<object?> RunAutoLeyLine(
        AutoLeyLineOutcropParam parameter, CancellationToken cancellationToken)
    {
        await new AutoLeyLineOutcropTask(parameter).Start(cancellationToken);
        return null;
    }

    private static async Task<object?> RunAutoStygian(
        AutoStygianOnslaughtParam parameter, CancellationToken cancellationToken)
    {
        await new AutoStygianOnslaughtTask(parameter).Start(cancellationToken);
        return null;
    }

    private static async Task<object?> RunCountInventory(
        CountInventoryItemParam parameter, CancellationToken cancellationToken)
    {
        var result = await new CountInventoryItem(parameter).Start(cancellationToken);
        if (parameter.ItemName is not null) return result;
        dynamic expando = new ExpandoObject();
        var dictionary = (IDictionary<string, object>)expando;
        foreach (var pair in (Dictionary<string, int>)result) dictionary[pair.Key] = pair.Value;
        return expando;
    }
}
