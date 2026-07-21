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
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Config;
using Microsoft.Extensions.Logging;
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
    IOcrService ocrService,
    RuntimeLayout layout,
    ILoggerFactory loggerFactory) : IDispatcherRuntimePlatform
{
    public CancellationToken GlobalCancellationToken { get; } = globalCancellationToken;
    public int AutoWoodRoundNum => 0;
    public int AutoWoodDailyMaxCount => 2000;
    public string AutoBossStrategyName => throw Unavailable("AutoBoss");
    public DispatcherAutoEatSettings AutoEatSettings => throw Unavailable("AutoEat");

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

    public bool GetFightStrategy(string? strategyName, out string path) =>
        throw Unavailable(string.IsNullOrEmpty(strategyName) ? "AutoDomain" : "AutoBoss");

    public async Task<object?> ExecuteSoloTask(DispatcherSoloTaskRequest request,
        CancellationToken cancellationToken)
    {
        if (request is DispatcherFishingTaskRequest fishing)
        {
            await new AutoFishingTask(AutoFishingTaskParam.BuildFromSoloTaskConfig(fishing.Config))
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
        throw Unavailable(name);
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
