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
using BetterGenshinImpact.GameTask.AutoPick.Assets;
using BetterGenshinImpact.GameTask.AutoSkip.Assets;
using BetterGenshinImpact.GameTask.AutoFishing.Assets;
using BetterGenshinImpact.GameTask.QuickTeleport.Assets;
using BetterGenshinImpact.GameTask.AutoWood.Assets;
using BetterGenshinImpact.GameTask.AutoFight.Assets;
using BetterGenshinImpact.GameTask.Common.Element.Assets;
using BetterGenshinImpact.GameTask.GameLoading.Assets;
using BetterGenshinImpact.GameTask.QuickTeleport;
using BetterGenshinImpact.GameTask.AutoEat;
using BetterGenshinImpact.GameTask.AutoEat.Assets;
using BetterGenshinImpact.GameTask.GameLoading;
using BetterGenshinImpact.GameTask.Placeholder;
using BetterGenshinImpact.GameTask.MapMask;
using BetterGenshinImpact.GameTask.SkillCd;
using BetterGenshinImpact.Core.Script.Dependence.Model.TimerConfig;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>macOS construction boundary for the shared GameTaskManager.</summary>
public sealed class MacGameTaskManagerPlatform(
    PlatformCallbackChannel callbacks, string sessionToken, CancellationToken cancellationToken,
    ILoggerFactory loggerFactory)
    : IGameTaskManagerPlatform
{
    public ISystemInfo SystemInfo => new CallbackSystemInfo(Metrics());

    public IReadOnlyList<KeyValuePair<string, ITaskTrigger>> CreateInitialTriggers(
        IInputBackend inputBackend, ISystemInfo systemInfo, IAutoPickRuntimeState runtimeState,
        IAutoPickConfigProvider autoPickConfigProvider,
        IPaddleAutoPickTextRecognizer paddleRecognizer, IYapAutoPickTextRecognizer yapRecognizer) =>
        throw Unavailable("initial trigger set");

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
                    : new AutoSkipTrigger()),
            "AutoFish" => new KeyValuePair<string, ITaskTrigger>(name, new AutoFishingTrigger()),
            "QuickTeleport" => new KeyValuePair<string, ITaskTrigger>(name, new QuickTeleportTrigger()),
            "AutoEat" => new KeyValuePair<string, ITaskTrigger>(name, new AutoEatTrigger()),
            "GameLoading" => new KeyValuePair<string, ITaskTrigger>(name, new GameLoadingTrigger()),
            "RecognitionTest" => new KeyValuePair<string, ITaskTrigger>(name, new TestTrigger()),
            "MapMask" => new KeyValuePair<string, ITaskTrigger>(name, new MapMaskTrigger()),
            "SkillCd" => new KeyValuePair<string, ITaskTrigger>(name, new SkillCdTrigger()),
            _ => throw Unavailable($"trigger '{name}'")
        };

    public void ReloadAssets()
    {
        AutoPickAssets.DestroyInstance();
        AutoSkipAssets.DestroyInstance();
        AutoFishingAssets.DestroyInstance();
        QuickTeleportAssets.DestroyInstance();
        AutoWoodAssets.DestroyInstance();
        AutoFightAssets.DestroyInstance();
        ElementAssets.DestroyInstance();
        GameLoadingAssets.DestroyInstance();
        MapLazyAssets.DestroyInstance();
        AutoEatAssets.DestroyInstance();
    }
    public void ClearOverlay() => BetterGenshinImpact.Core.Recognition.OverlayDrawPlatform.Current.ClearAll();

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
            var scale = Math.Min(1d, 1920d / width);
            AssetScale = scale;
            ZoomOutMax1080PRatio = scale;
            ScaleTo1080PRatio = 1d / scale;
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
