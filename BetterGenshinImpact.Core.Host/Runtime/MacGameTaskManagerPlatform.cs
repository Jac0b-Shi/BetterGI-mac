using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.Platform.Abstractions;
using Newtonsoft.Json.Linq;
using System.Diagnostics;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.QuickTeleport;
using BetterGenshinImpact.GameTask.AutoEat;
using BetterGenshinImpact.GameTask.GameLoading;
using BetterGenshinImpact.GameTask.MapMask;
using BetterGenshinImpact.GameTask.SkillCd;
using BetterGenshinImpact.Core.Script.Dependence.Model.TimerConfig;
using Microsoft.Extensions.Logging;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>macOS construction boundary for the shared GameTaskManager.</summary>
public sealed class MacGameTaskManagerPlatform(
    RuntimeLayout layout,
    PlatformCallbackChannel callbacks, string sessionToken, CancellationToken cancellationToken,
    ILoggerFactory loggerFactory)
    : IGameTaskManagerPlatform
{
    private readonly AutoSkipConfig _autoSkipConfig = LoadAutoSkipConfig(layout);

    public void UpdateAutoSkipConfig(AutoSkipConfig source)
    {
        _autoSkipConfig.QuicklySkipConversationsEnabled = source.QuicklySkipConversationsEnabled;
        _autoSkipConfig.AfterChooseOptionSleepDelay = source.AfterChooseOptionSleepDelay;
        _autoSkipConfig.AutoWaitDialogueOptionVoiceEnabled = source.AutoWaitDialogueOptionVoiceEnabled;
        _autoSkipConfig.DialogueOptionVoiceMaxWaitSeconds = source.DialogueOptionVoiceMaxWaitSeconds;
        _autoSkipConfig.BeforeClickConfirmDelay = source.BeforeClickConfirmDelay;
        _autoSkipConfig.AutoGetDailyRewardsEnabled = source.AutoGetDailyRewardsEnabled;
        _autoSkipConfig.AutoReExploreEnabled = source.AutoReExploreEnabled;
        _autoSkipConfig.ClickChatOption = source.ClickChatOption;
        _autoSkipConfig.CustomPriorityOptionsEnabled = source.CustomPriorityOptionsEnabled;
        _autoSkipConfig.CustomPriorityOptions = source.CustomPriorityOptions;
        _autoSkipConfig.AutoHangoutEventEnabled = source.AutoHangoutEventEnabled;
        _autoSkipConfig.AutoHangoutEndChoose = source.AutoHangoutEndChoose;
        _autoSkipConfig.AutoHangoutChooseOptionSleepDelay = source.AutoHangoutChooseOptionSleepDelay;
        _autoSkipConfig.AutoHangoutPressSkipEnabled = source.AutoHangoutPressSkipEnabled;
        _autoSkipConfig.SubmitGoodsEnabled = source.SubmitGoodsEnabled;
        _autoSkipConfig.ClosePopupPagedEnabled = source.ClosePopupPagedEnabled;
    }

    public ISystemInfo SystemInfo => CreateSystemInfo(Metrics());

    internal static ISystemInfo CreateSystemInfo(JObject metrics) => new CallbackSystemInfo(metrics);

    public IReadOnlyList<KeyValuePair<string, ITaskTrigger>> CreateInitialTriggers(
        IInputBackend inputBackend, ISystemInfo systemInfo, IAutoPickRuntimeState runtimeState,
        IAutoPickConfigProvider autoPickConfigProvider,
        IPaddleAutoPickTextRecognizer paddleRecognizer, IYapAutoPickTextRecognizer yapRecognizer)
    {
        return
        [
            new("GameLoading", new GameLoadingTrigger()),
            new("AutoPick", new AutoPickTrigger(null, runtimeState, autoPickConfigProvider,
                inputBackend, systemInfo, loggerFactory.CreateLogger<AutoPickTrigger>(),
                paddleRecognizer, yapRecognizer)),
            new("QuickTeleport", new QuickTeleportTrigger()),
            new("AutoSkip", new AutoSkipTrigger(_autoSkipConfig)),
            new("AutoFish", new AutoFishingTrigger()),
            new("AutoEat", new AutoEatTrigger()),
            new("MapMask", new MapMaskTrigger()),
            new("SkillCd", new SkillCdTrigger()),
        ];
    }

    public KeyValuePair<string, ITaskTrigger>? CreateTrigger(
        string name, object? externalConfig, IAutoPickRuntimeState runtimeState,
        IInputBackend inputBackend, ISystemInfo systemInfo, IAutoPickConfigProvider autoPickConfigProvider,
        IPaddleAutoPickTextRecognizer paddleRecognizer, IYapAutoPickTextRecognizer yapRecognizer) =>
        name switch
        {
            "AutoPick" => new KeyValuePair<string, ITaskTrigger>(
                name,
                new AutoPickTrigger(
                    externalConfig as AutoPickExternalConfig,
                    runtimeState,
                    autoPickConfigProvider,
                    inputBackend,
                    systemInfo,
                    loggerFactory.CreateLogger<AutoPickTrigger>(),
                    paddleRecognizer,
                    yapRecognizer)),
            "AutoSkip" => new KeyValuePair<string, ITaskTrigger>(
                name,
                externalConfig is AutoSkipConfig config
                    ? new AutoSkipTrigger(config)
                    : new AutoSkipTrigger(_autoSkipConfig)),
            "AutoFish" => new KeyValuePair<string, ITaskTrigger>(name, new AutoFishingTrigger()),
            "QuickTeleport" => new KeyValuePair<string, ITaskTrigger>(name, new QuickTeleportTrigger()),
            "AutoEat" => new KeyValuePair<string, ITaskTrigger>(name, new AutoEatTrigger()),
            "GameLoading" => new KeyValuePair<string, ITaskTrigger>(name, new GameLoadingTrigger()),
            "MapMask" => new KeyValuePair<string, ITaskTrigger>(name, new MapMaskTrigger()),
            "SkillCd" => new KeyValuePair<string, ITaskTrigger>(name, new SkillCdTrigger()),
            _ => throw Unavailable($"trigger '{name}'")
        };

    public void ReloadAssets()
    {
        RecognitionAssets.ClearAll();
    }
    public void ClearOverlay() => BetterGenshinImpact.Core.Recognition.OverlayDrawPlatform.Current.ClearAll();

    private static AutoSkipConfig LoadAutoSkipConfig(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return new AutoSkipConfig();
        var root = JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
        return root["autoSkipConfig"]?.Deserialize<AutoSkipConfig>(ConfigJson.Options)
            ?? new AutoSkipConfig();
    }

    private JObject Metrics() => callbacks.InvokeAsync(
            "window.metrics", null, sessionToken, cancellationToken).GetAwaiter().GetResult() as JObject
        ?? throw new InvalidDataException("window.metrics did not return an object.");
    private static CapabilityUnavailableException Unavailable(string capability) =>
        new($"GameTaskManager {capability} is not composed on macOS yet.");

    private sealed class CallbackSystemInfo : ISystemInfo
    {
        public CallbackSystemInfo(JObject metrics)
        {
            var width = Required(metrics, "captureWidth");
            var height = Required(metrics, "captureHeight");
            var displayWidth = Required(metrics, "workingAreaWidth");
            var displayHeight = Required(metrics, "workingAreaHeight");
            var x = Required(metrics, "captureX");
            var y = Required(metrics, "captureY");
            DisplaySize = new(displayWidth, displayHeight);
            GameScreenSize = new(0, 0, width, height);
            CaptureAreaRect = new(x, y, width, height);
            var scale = Math.Min(1d, width / 1920d);
            AssetScale = scale;
            ZoomOutMax1080PRatio = scale;
            ScaleTo1080PRatio = width / 1920d;
            ScaleMax1080PCaptureRect = new(0, 0, Math.Min(width, 1920), Math.Min(height, 1080));
            GameProcessId = Required(metrics, "processId");
            DesktopRectArea = new DesktopRegion(displayWidth, displayHeight);
        }
        public System.Drawing.Size DisplaySize { get; }
        public BgiRect GameScreenSize { get; }
        public double AssetScale { get; }
        public double ZoomOutMax1080PRatio { get; }
        public double ScaleTo1080PRatio { get; }
        public BgiRect CaptureAreaRect { get; set; }
        public BgiRect ScaleMax1080PCaptureRect { get; set; }
        public Process? GameProcess => null;
        public string GameProcessName => "GenshinImpact";
        public int GameProcessId { get; }
        public DesktopRegion DesktopRectArea { get; }
        private static int Required(JObject metrics, string name) => metrics.Value<int?>(name)
            ?? throw new InvalidDataException($"window.metrics did not return {name}.");
    }
}
