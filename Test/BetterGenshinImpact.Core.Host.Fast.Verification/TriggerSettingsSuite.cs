using System.Collections.Concurrent;
using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Adapters;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Platform.Abstractions;
using BetterGenshinImpact.Verification.Framework;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class TriggerSettingsSuite : IVerificationSuite
{
    public string Name => "trigger-settings";

    public async Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        var mapMaskCategoryTrigger = new MapMaskCategoryTrigger();
        var now = DateTime.UtcNow;
        var stableCategorySince = now - TimeSpan.FromSeconds(31);
        context.Require(
            MacTriggerDispatcher.ShouldRunTrigger(
                mapMaskCategoryTrigger, GameUiCategory.BigMap, GameUiCategory.BigMap,
                stableCategorySince, now) &&
            MacTriggerDispatcher.ShouldRunTrigger(
                mapMaskCategoryTrigger, GameUiCategory.Unknown, GameUiCategory.Unknown,
                stableCategorySince, now) &&
            !MacTriggerDispatcher.ShouldRunTrigger(
                mapMaskCategoryTrigger, GameUiCategory.Talk, GameUiCategory.Talk,
                stableCategorySince, now),
            "MapMask did not preserve its upstream main-UI behavior while adding stable big-map updates.");

        var root = Path.Combine(Path.GetTempPath(), $"bettergi-fast-{Guid.NewGuid():N}");
        try
        {
            var layout = new RuntimeLayout(root);
            layout.EnsureCreated();
            await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "config.json"), """
                {
                  "autoPickConfig": {
                    "enabled": true,
                    "itemIconLeftOffset": 61,
                    "itemTextLeftOffset": 116,
                    "itemTextRightOffset": 401,
                    "ocrEngine": "Paddle",
                    "fastModeEnabled": true,
                    "pickKey": "F",
                    "blackListEnabled": true,
                    "whiteListEnabled": false
                  }
                }
                """, cancellationToken);
            await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "pick_black_lists.txt"),
                "精致的宝箱\n", cancellationToken);
            await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "pick_fuzzy_black_lists.txt"),
                "凯瑟琳\n", cancellationToken);
            await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "pick_white_lists.txt"),
                "调查\n", cancellationToken);

            var trigger = new RecordingTrigger();
            var platform = new RecordingGameTaskManagerPlatform();
            GameTaskManagerPlatform.Configure(platform);
            GameTaskManager.TriggerDictionary = new ConcurrentDictionary<string, ITaskTrigger>(
                new[] { new KeyValuePair<string, ITaskTrigger>("AutoPick", trigger) });
            var liveConfig = new AutoPickConfig();
            var adapter = new MacCoreRuntimeAdapter(
                liveConfig, PaddleOcrModelConfig.V5Auto, "zh-Hans");
            var catalog = new TriggerSettingsCatalog(layout);
            catalog.AttachAutoPickUpdated(adapter.UpdateAutoPickConfig);
            catalog.AttachAutoPickListsUpdated(() => GameTaskManager.RefreshTriggerConfig("AutoPick"));

            var initial = JObject.FromObject(catalog.Get("AutoPick"));
            context.Require(initial.Value<string>("ocrEngine") == "Paddle" &&
                            initial.Value<string>("exactBlackList") == "精致的宝箱\n" &&
                            initial.Value<string>("fuzzyBlackList") == "凯瑟琳\n" &&
                            initial.Value<string>("whiteList") == "调查\n",
                "AutoPick settings did not read the runtime User tree.");

            _ = catalog.Save("AutoPick", JObject.FromObject(new
            {
                ocrEngine = "Yap",
                blackListEnabled = false,
                exactBlackList = "史莱姆凝液\n",
                fuzzyBlackList = "对话\n",
                whiteListEnabled = true,
                whiteList = "合成\n启动\n",
                pickKey = "G",
            }));

            var persisted = JObject.Parse(await File.ReadAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"), cancellationToken));
            context.Require(liveConfig.OcrEngine == "Yap" && liveConfig.PickKey == "G" &&
                            persisted["autoPickConfig"]?["itemIconLeftOffset"]?.Value<int>() == 61 &&
                            persisted["autoPickConfig"]?["fastModeEnabled"]?.Value<bool>() == true,
                "AutoPick save did not preserve hidden config or update the live adapter.");
            context.Require(trigger.InitCount == 1 && platform.ReloadAssetsCount == 1,
                "AutoPick save did not refresh the shared trigger and recognition assets exactly once.");
            context.Require(await File.ReadAllTextAsync(
                                Path.Combine(layout.UserPath, "pick_black_lists.txt"), cancellationToken) == "史莱姆凝液\n" &&
                            await File.ReadAllTextAsync(
                                Path.Combine(layout.UserPath, "pick_fuzzy_black_lists.txt"), cancellationToken) == "对话\n" &&
                            await File.ReadAllTextAsync(
                                Path.Combine(layout.UserPath, "pick_white_lists.txt"), cancellationToken) == "合成\n启动\n",
                "AutoPick save did not persist the three upstream text lists.");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    private sealed class RecordingTrigger : ITaskTrigger
    {
        public string Name => "自动拾取";
        public bool IsEnabled { get; set; }
        public int Priority => 30;
        public bool IsExclusive => false;
        public int InitCount { get; private set; }
        public void Init() => InitCount++;
        public void OnCapture(CaptureContent content) { }
    }

    private sealed class MapMaskCategoryTrigger : ITaskTrigger
    {
        public string Name => "地图遮罩";
        public bool IsEnabled { get; set; }
        public int Priority => 1;
        public bool IsExclusive => false;
        public GameUiCategory SupportedGameUiCategory => GameUiCategory.Unknown;
        public bool SupportsGameUiCategory(GameUiCategory category) =>
            category is GameUiCategory.Unknown or GameUiCategory.BigMap;
        public void Init() { }
        public void OnCapture(CaptureContent content) { }
    }

    private sealed class RecordingGameTaskManagerPlatform : IGameTaskManagerPlatform
    {
        public ISystemInfo SystemInfo => throw new NotSupportedException();
        public int ReloadAssetsCount { get; private set; }
        public IReadOnlyList<KeyValuePair<string, ITaskTrigger>> CreateInitialTriggers(
            IInputBackend inputBackend, ISystemInfo systemInfo, IAutoPickRuntimeState runtimeState,
            IAutoPickConfigProvider autoPickConfigProvider,
            IPaddleAutoPickTextRecognizer paddleRecognizer, IYapAutoPickTextRecognizer yapRecognizer) =>
            throw new NotSupportedException();
        public KeyValuePair<string, ITaskTrigger>? CreateTrigger(
            string name, object? externalConfig, IAutoPickRuntimeState runtimeState,
            IInputBackend inputBackend, ISystemInfo systemInfo,
            IAutoPickConfigProvider autoPickConfigProvider,
            IPaddleAutoPickTextRecognizer paddleRecognizer, IYapAutoPickTextRecognizer yapRecognizer) =>
            throw new NotSupportedException();
        public void ReloadAssets() => ReloadAssetsCount++;
        public void ClearOverlay() => throw new NotSupportedException();
    }
}
