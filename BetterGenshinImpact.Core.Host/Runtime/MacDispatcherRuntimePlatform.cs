using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Platform.Abstractions;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.AutoCook;
using BetterGenshinImpact.GameTask.AutoPathing.Handler;
using BetterGenshinImpact.GameTask.AutoWood;
using BetterGenshinImpact.GameTask.AutoMusicGame;
using BetterGenshinImpact.GameTask.AutoArtifactSalvage;
using BetterGenshinImpact.GameTask.AutoDomain;
using BetterGenshinImpact.GameTask.AutoBoss;
using BetterGenshinImpact.GameTask.AutoEat;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.AutoLeyLineOutcrop;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Config;
using Microsoft.Extensions.Logging;
using System.Dynamic;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacDispatcherRuntimePlatform(
    CancellationToken globalCancellationToken,
    IAutoPickRuntimeState autoPickRuntimeState,
    IInputBackend inputBackend,
    Func<ISystemInfo> systemInfo,
    IAutoPickConfigProvider autoPickConfigProvider,
    IPaddleAutoPickTextRecognizer paddleRecognizer,
    IYapAutoPickTextRecognizer yapRecognizer,
    IAutoWoodRuntimePlatform autoWoodRuntimePlatform,
    IAutoMusicGameRuntimePlatform autoMusicGameRuntimePlatform,
    IAutoDomainRuntimePlatform autoDomainRuntimePlatform,
    IAutoBossRuntimePlatform autoBossRuntimePlatform,
    IAutoBossPathExecutorFactory autoBossPathExecutorFactory,
    IAutoEatRuntimePlatform autoEatRuntimePlatform,
    IAutoLeyLineOutcropRuntimePlatform autoLeyLineOutcropRuntimePlatform,
    IScriptGroupExecutionServices scriptGroupExecutionServices,
    IOcrService ocrService,
    RuntimeLayout layout,
    ILoggerFactory loggerFactory) : IDispatcherRuntimePlatform
{
    public CancellationToken GlobalCancellationToken { get; } = globalCancellationToken;
    public int AutoWoodRoundNum => 0;
    public int AutoWoodDailyMaxCount => 2000;
    public string AutoBossStrategyName =>
        LoadUserConfig<AutoBossConfig>(layout, "autoBossConfig").StrategyName;
    public DispatcherAutoEatSettings AutoEatSettings
    {
        get
        {
            var config = LoadUserConfig<AutoEatConfig>(layout, "autoEatConfig");
            return new DispatcherAutoEatSettings(
                config.CheckInterval, config.EatInterval, config.ShowNotification);
        }
    }

    public void ClearTriggers() => GameTaskManager.ClearTriggers();

    public bool AddTrigger(string name, object? config)
    {
        if (!GameTaskManager.AddTrigger(
                name, config, autoPickRuntimeState, inputBackend, systemInfo(),
                autoPickConfigProvider, paddleRecognizer, yapRecognizer))
            return false;

        var trigger = GameTaskManager.TriggerDictionary![name];
        trigger.Init();
        trigger.IsEnabled = true;
        return true;
    }

    public bool GetTcgStrategy(out string content) =>
        throw Unavailable("AutoGeniusInvokation");

    public bool GetFightStrategy(string? strategyName, out string path)
    {
        strategyName ??= LoadUserConfig<AutoFightConfig>(
            layout, "autoFightConfig").StrategyName;
        if (string.IsNullOrWhiteSpace(strategyName))
        {
            path = string.Empty;
            return true;
        }
        path = strategyName == "根据队伍自动选择"
            ? Global.Absolute("User/AutoFight/")
            : AutoFightParam.ResolveStrategyPath(strategyName).path;
        return !File.Exists(path) && !Directory.Exists(path);
    }

    public async Task<object?> ExecuteSoloTask(DispatcherSoloTaskRequest request,
        CancellationToken cancellationToken)
    {
        if (request is DispatcherFishingTaskRequest fishing)
        {
            await new AutoFishingTask(
                    fishing.Param ?? AutoFishingTaskParam.BuildFromSoloTaskConfig(fishing.Config))
                .Start(cancellationToken);
            return null;
        }
        if (request is DispatcherCookTaskRequest)
        {
            await new AutoCookTask(
                    LoadAutoCookConfig(layout),
                    systemInfo().AssetScale,
                    loggerFactory.CreateLogger<AutoCookTask>())
                .Start(cancellationToken);
            return null;
        }
        if (request is DispatcherFightTaskRequest fight)
        {
            await new AutoFightHandler().RunAsyncByScript(cancellationToken, null, fight.Config);
            return null;
        }
        if (request is DispatcherWoodTaskRequest wood)
        {
            await new AutoWoodTask(
                    new WoodTaskParam(wood.RoundNum, wood.DailyMaxCount),
                    LoadAutoWoodConfig(layout),
                    autoWoodRuntimePlatform)
                .Start(cancellationToken);
            return null;
        }
        if (request is DispatcherMusicGameTaskRequest)
        {
            await new AutoMusicGameTask(new AutoMusicGameParam(), autoMusicGameRuntimePlatform)
                .Start(cancellationToken);
            return null;
        }
        if (request is DispatcherArtifactSalvageTaskRequest)
        {
            var config = LoadAutoArtifactSalvageConfig(layout);
            await new AutoArtifactSalvageTask(
                    new AutoArtifactSalvageTaskParam(
                        int.Parse(config.MaxArtifactStar), config.JavaScript,
                        config.ArtifactSetFilter, config.MaxNumToCheck,
                        config.RecognitionFailurePolicy),
                    ocrService,
                    systemInfo().AssetScale,
                    loggerFactory.CreateLogger<AutoArtifactSalvageTask>())
                .Start(cancellationToken);
            return null;
        }
        if (request is DispatcherEatTaskRequest eat)
        {
            var config = LoadUserConfig<AutoEatConfig>(layout, "autoEatConfig");
            return await new AutoEatTask(
                    new AutoEatParam
                    {
                        CheckInterval = eat.Settings.CheckInterval,
                        EatInterval = eat.Settings.EatInterval,
                        ShowNotification = eat.Settings.ShowNotification,
                        FoodName = eat.FoodName
                    },
                    config,
                    systemInfo(),
                    ocrService,
                    autoEatRuntimePlatform,
                    loggerFactory.CreateLogger<AutoEatTask>())
                .Start(cancellationToken);
        }
        if (request is DispatcherCountInventoryTaskRequest count)
        {
            return await RunCountInventory(new CountInventoryItemParam
            {
                GridScreenName = (GameTask.Model.GameUI.GridScreenName)count.GridScreenName,
                ItemName = count.ItemName,
                ItemNames = [.. count.ItemNames]
            }, cancellationToken);
        }
        if (request is DispatcherDomainTaskRequest domain)
        {
            var config = LoadUserConfig<AutoDomainConfig>(layout, "autoDomainConfig");
            var artifactConfig = LoadUserConfig<AutoArtifactSalvageConfig>(
                layout, "autoArtifactSalvageConfig");
            var pickConfig = LoadUserConfig<AutoPickConfig>(layout, "autoPickConfig");
            var parameter = new AutoDomainParam(
                0, domain.StrategyPath, config, artifactConfig.MaxArtifactStar);
            return await new AutoDomainTask(
                    parameter, config, pickConfig.PickKey, autoDomainRuntimePlatform)
                .Start(cancellationToken);
        }
        if (request is DispatcherBossTaskRequest boss)
        {
            var config = LoadUserConfig<AutoBossConfig>(layout, "autoBossConfig");
            var parameter = new AutoBossParam(boss.StrategyPath, config);
            return await new AutoBossTask(
                    parameter, autoBossRuntimePlatform, autoBossPathExecutorFactory)
                .Start(cancellationToken);
        }
        if (request is DispatcherLeyLineTaskRequest leyLine)
        {
            await new AutoLeyLineOutcropTask(
                    new AutoLeyLineOutcropParam(leyLine.Config),
                    autoLeyLineOutcropRuntimePlatform,
                    scriptGroupExecutionServices)
                .Start(cancellationToken);
            return null;
        }
        throw Unavailable(request.Name);
    }

    public async Task<object?> RunParameterizedTask(string name, object parameter,
        CancellationToken cancellationToken)
    {
        if (name == "AutoFight" && parameter is AutoFightParam autoFightParam)
        {
            var factory = BetterGenshinImpact.GameTask.AutoFight.Factory.CombatTaskFactoryProvider
                .GetFactory(autoFightParam.CombatStrategyPath);
            await factory.CreateTask(autoFightParam).Start(cancellationToken);
            return null;
        }
        if (name == "AutoBoss" && parameter is AutoBossParam autoBossParam)
        {
            return await new AutoBossTask(
                    autoBossParam, autoBossRuntimePlatform, autoBossPathExecutorFactory)
                .Start(cancellationToken);
        }
        if (name == "CountInventoryItem" && parameter is CountInventoryItemParam countInventoryItemParam)
        {
            return await RunCountInventory(countInventoryItemParam, cancellationToken);
        }
        if (name == "AutoLeyLineOutcrop" && parameter is AutoLeyLineOutcropParam leyLineParam)
        {
            await new AutoLeyLineOutcropTask(
                    leyLineParam, autoLeyLineOutcropRuntimePlatform,
                    scriptGroupExecutionServices)
                .Start(cancellationToken);
            return null;
        }
        throw Unavailable(name);
    }

    private async Task<object?> RunCountInventory(
        CountInventoryItemParam parameter,
        CancellationToken cancellationToken)
    {
        var result = await new CountInventoryItem(
                parameter,
                ocrService,
                loggerFactory.CreateLogger<CountInventoryItem>())
            .Start(cancellationToken);
        if (parameter.ItemName is not null) return result;
        dynamic expando = new ExpandoObject();
        var dictionary = (IDictionary<string, object>)expando;
        foreach (var pair in (Dictionary<string, int>)result) dictionary[pair.Key] = pair.Value;
        return expando;
    }

    private static CapabilityUnavailableException Unavailable(string name) => new(
        $"dispatcher task '{name}' is not composed in the macOS Core yet; no task was executed.");

    private static AutoCookConfig LoadAutoCookConfig(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return new AutoCookConfig();
        var root = JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip,
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
        return root["autoCookConfig"]?.Deserialize<AutoCookConfig>(ConfigJson.Options)
               ?? new AutoCookConfig();
    }

    public static T LoadUserConfig<T>(RuntimeLayout layout, string propertyName) where T : class, new()
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return new T();
        var root = JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip,
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
        var node = root[propertyName];
        return node is null ? new T() : node.Deserialize<T>(ConfigJson.Options) ?? new T();
    }

    private static AutoWoodConfig LoadAutoWoodConfig(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return new AutoWoodConfig();
        var root = JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip,
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
        return root["autoWoodConfig"]?.Deserialize<AutoWoodConfig>(ConfigJson.Options)
               ?? new AutoWoodConfig();
    }

    private static AutoArtifactSalvageConfig LoadAutoArtifactSalvageConfig(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return new AutoArtifactSalvageConfig();
        var root = JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip,
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
        return root["autoArtifactSalvageConfig"]?.Deserialize<AutoArtifactSalvageConfig>(ConfigJson.Options)
               ?? new AutoArtifactSalvageConfig();
    }
}
