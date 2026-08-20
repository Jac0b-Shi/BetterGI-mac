using System.Collections.Concurrent;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Adapters;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.MapMask;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.SkillCd;
using BetterGenshinImpact.Platform.Abstractions;
using BetterGenshinImpact.Verification.Framework;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class TriggerSettingsSuite : IVerificationSuite
{
    public string Name => "trigger-settings";

    public async Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        var previousStartupPath = Global.StartUpPath;
        Global.StartUpPath = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory, "../../../../../../BetterGenshinImpact"));
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

        var previousMapMaskPlatform = MapMaskRuntimePlatform.Current;
        var recordingMapMaskPlatform = new RecordingMapMaskPlatform();
        MapMaskRuntimePlatform.Configure(recordingMapMaskPlatform);
        try
        {
            var trigger = new MapMaskTrigger();
            trigger.IsEnabled = true;
            var exclusiveTrigger = new ExclusiveTrigger();
            var selected = MacTriggerDispatcher.SelectTriggersForFrame(
                [exclusiveTrigger, mapMaskCategoryTrigger], trigger);
            context.Require(
                selected.Length == 2 &&
                ReferenceEquals(selected[0], trigger) &&
                ReferenceEquals(selected[1], exclusiveTrigger),
                "The macOS dispatcher did not run the read-only MapMask companion before the exclusive trigger.");
            selected = MacTriggerDispatcher.SelectTriggersForFrame([], trigger);
            context.Require(
                selected.Length == 1 && ReferenceEquals(selected[0], trigger),
                "The macOS dispatcher dropped MapMask when a script cleared the shared trigger registry.");
            trigger.ObserveBigMapPresence(true);
            context.Require(
                trigger.IsInBigMapUi,
                "MapMask did not retain the observed big-map state.");
            trigger.ObserveBigMapPresence(false);
            var clearCommand = recordingMapMaskPlatform.LastCommand;
            context.Require(
                !trigger.IsInBigMapUi &&
                clearCommand?.IsInBigMapUi == false &&
                clearCommand?.BigMapViewport?.Width == 0 &&
                clearCommand?.MiniMapViewport?.Width == 0,
                "Leaving the big map did not clear stale map viewports.");
        }
        finally
        {
            MapMaskRuntimePlatform.Current = previousMapMaskPlatform;
        }

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
                    "mode": "Blacklist",
                    "blacklistModePickEnabled": true,
                    "whitelistModeDoNotPickEnabled": false
                  },
                  "autoSkipConfig": {
                    "enabled": true,
                    "quicklySkipConversationsEnabled": true,
                    "clickChatOption": "优先选择第一个选项",
                    "skipBuiltInClickOptions": true
                  },
                  "skillCdConfig": {
                    "enabled": false,
                    "pX": 1520.0,
                    "pY": 245.0,
                    "gap": 91.2,
                    "scale": 1.0,
                    "textNormalColor": "#DA4A23FF",
                    "backgroundNormalColor": "#FFFFFFFF",
                    "textReadyColor": "#5DCC17FF",
                    "backgroundReadyColor": "#FFFFFFFF",
                    "futureField": "preserved"
                  }
                }
                """, cancellationToken);
            await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "pick_black_lists.txt"),
                "精致的宝箱\n", cancellationToken);
            await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "pick_fuzzy_black_lists.txt"),
                "凯瑟琳\n", cancellationToken);
            await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "pick_white_lists.txt"),
                "调查\n", cancellationToken);
            await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "pick_whitelist_mode_pick_lists.txt"),
                "晶核\n", cancellationToken);
            await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "pick_whitelist_mode_do_not_pick_lists.txt"),
                "低品质圣遗物\n", cancellationToken);

            var trigger = new RecordingTrigger();
            var platform = new RecordingGameTaskManagerPlatform();
            GameTaskManagerPlatform.Configure(platform);
            GameTaskManager.TriggerDictionary = new ConcurrentDictionary<string, ITaskTrigger>(
                new[] { new KeyValuePair<string, ITaskTrigger>("AutoPick", trigger) });
            var liveConfig = new AutoPickConfig();
            var adapter = new MacCoreRuntimeAdapter(
                liveConfig, PaddleOcrModelConfig.V5Auto, "zh-Hans");
            var catalog = new TriggerSettingsCatalog(layout);
            AutoSkipConfig? updatedAutoSkip = null;
            SkillCdConfig? updatedSkillCd = null;
            catalog.AttachAutoPickUpdated(adapter.UpdateAutoPickConfig);
            catalog.AttachAutoPickListsUpdated(() => GameTaskManager.RefreshTriggerConfig("AutoPick"));
            catalog.AttachAutoSkipUpdated(config => updatedAutoSkip = config);
            catalog.AttachSkillCdUpdated(config => updatedSkillCd = config);

            var initial = JObject.FromObject(catalog.Get("AutoPick"));
            context.Require(initial.Value<string>("ocrEngine") == "Paddle" &&
                            initial.Value<bool>("fastModeEnabled") &&
                            initial.Value<string>("mode") == "Blacklist" &&
                            initial.Value<bool>("blacklistModePickEnabled") &&
                            !initial.Value<bool>("whitelistModeDoNotPickEnabled") &&
                            initial.Value<string>("exactBlackList") == "精致的宝箱\n" &&
                            initial.Value<string>("fuzzyBlackList") == "凯瑟琳\n" &&
                            initial.Value<string>("whiteList") == "调查\n" &&
                            initial.Value<string>("whitelistModePickList") == "晶核\n" &&
                            initial.Value<string>("whitelistModeDoNotPickList") == "低品质圣遗物\n",
                "AutoPick settings did not read the runtime User tree.");

            _ = catalog.Save("AutoPick", JObject.FromObject(new
            {
                ocrEngine = "Yap",
                fastModeEnabled = false,
                mode = "Whitelist",
                blacklistModePickEnabled = false,
                exactBlackList = "史莱姆凝液\n",
                fuzzyBlackList = "对话\n",
                whitelistModeDoNotPickEnabled = false,
                whiteList = "合成\n启动\n",
                whitelistModePickList = "晶核\n",
                whitelistModeDoNotPickList = "低品质圣遗物\n",
                pickKey = "G",
            }));

            var persisted = JObject.Parse(await File.ReadAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"), cancellationToken));
            context.Require(liveConfig.OcrEngine == "Yap" && liveConfig.PickKey == "G" &&
                            !liveConfig.FastModeEnabled &&
                            liveConfig.Mode == AutoPickMode.Whitelist &&
                            !liveConfig.BlacklistModePickEnabled &&
                            !liveConfig.WhitelistModeDoNotPickEnabled &&
                            persisted["autoPickConfig"]?["itemIconLeftOffset"]?.Value<int>() == 61 &&
                            persisted["autoPickConfig"]?["fastModeEnabled"]?.Value<bool>() == false,
                "AutoPick save did not persist fast mode or update the live adapter.");
            context.Require(trigger.InitCount == 1 && platform.ReloadAssetsCount == 1,
                "AutoPick save did not refresh the shared trigger and recognition assets exactly once.");
            context.Require(await File.ReadAllTextAsync(
                                Path.Combine(layout.UserPath, "pick_black_lists.txt"), cancellationToken) == "史莱姆凝液\n" &&
                            await File.ReadAllTextAsync(
                                Path.Combine(layout.UserPath, "pick_fuzzy_black_lists.txt"), cancellationToken) == "对话\n" &&
                            await File.ReadAllTextAsync(
                                Path.Combine(layout.UserPath, "pick_white_lists.txt"), cancellationToken) == "合成\n启动\n" &&
                            await File.ReadAllTextAsync(
                                Path.Combine(layout.UserPath, "pick_whitelist_mode_pick_lists.txt"), cancellationToken) == "晶核\n" &&
                            await File.ReadAllTextAsync(
                                Path.Combine(layout.UserPath, "pick_whitelist_mode_do_not_pick_lists.txt"), cancellationToken) == "低品质圣遗物\n",
                "AutoPick save did not persist the five upstream text lists.");

            var initialAutoSkip = JObject.FromObject(catalog.Get("AutoSkip"));
            var hangoutOptions = initialAutoSkip["autoHangoutEndChooseOptions"]?.Values<string>().ToArray();
            var hangoutOption = hangoutOptions?.FirstOrDefault()
                ?? throw new InvalidDataException("AutoSkip hangout option catalog is empty.");
            context.Require(catalog.IsAvailable("AutoSkip") &&
                            initialAutoSkip.Value<string>("clickChatOption") == "优先选择第一个选项" &&
                            initialAutoSkip["clickChatOptionOptions"]?.Values<string>().Count() == 4 &&
                            hangoutOptions is { Length: > 0 },
                "AutoSkip settings did not expose the upstream option catalogs.");

            _ = catalog.Save("AutoSkip", JObject.FromObject(new
            {
                quicklySkipConversationsEnabled = false,
                afterChooseOptionSleepDelay = 250,
                autoWaitDialogueOptionVoiceEnabled = true,
                dialogueOptionVoiceMaxWaitSeconds = 45,
                beforeClickConfirmDelay = 100,
                autoGetDailyRewardsEnabled = false,
                autoReExploreEnabled = false,
                clickChatOption = "优先选择最后一个选项",
                customPriorityOptionsEnabled = true,
                customPriorityOptions = "重要选项；确认",
                autoHangoutEventEnabled = true,
                autoHangoutEndChoose = hangoutOption,
                autoHangoutChooseOptionSleepDelay = 300,
                autoHangoutPressSkipEnabled = false,
                submitGoodsEnabled = false,
                closePopupPagedEnabled = false,
            }));

            persisted = JObject.Parse(await File.ReadAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"), cancellationToken));
            context.Require(updatedAutoSkip is not null &&
                            updatedAutoSkip.ClickChatOption == "优先选择最后一个选项" &&
                            updatedAutoSkip.DialogueOptionVoiceMaxWaitSeconds == 45 &&
                            persisted["autoSkipConfig"]?["skipBuiltInClickOptions"]?.Value<bool>() == true &&
                            persisted["autoSkipConfig"]?["customPriorityOptions"]?.Value<string>() == "重要选项；确认",
                "AutoSkip save did not preserve hidden fields, persist settings, and update the live config.");

            _ = catalog.Save("SkillCd", JObject.FromObject(new
            {
                customCdList = new[]
                {
                    new { roleName = " 玛薇卡 ", cdValueText = " 15.0 " },
                    new { roleName = " ", cdValueText = "9" },
                },
                triggerOnSkillUse = true,
                hideWhenZero = true,
                pX = 1500.5,
                pY = 240.5,
                gap = 90.5,
                scale = 1.25,
                textNormalColor = "#da4a23ff",
                backgroundNormalColor = "#ffffff",
                textReadyColor = "#5dcc17ff",
                backgroundReadyColor = "#ffffffff",
            }));

            persisted = JObject.Parse(await File.ReadAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"), cancellationToken));
            context.Require(catalog.IsAvailable("SkillCd") && updatedSkillCd is not null &&
                            updatedSkillCd.CustomCdList.Count == 1 &&
                            updatedSkillCd.CustomCdList[0].RoleName == "玛薇卡" &&
                            updatedSkillCd.Scale == 1.25 &&
                            updatedSkillCd.TextNormalColor == "#DA4A23FF" &&
                            persisted["skillCdConfig"]?["futureField"]?.Value<string>() == "preserved",
                "SkillCd save did not normalize rules, preserve unknown fields, or update the live config.");
        }
        finally
        {
            Global.StartUpPath = previousStartupPath;
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }

        await VerifyAutoPickLegacyMigrationAsync(context, cancellationToken);
    }

    /// <summary>
    /// 旧版 whiteListEnabled 配置必须在 Mac 读取链完成迁移，
    /// 保存后清理旧 key，重读不得复活旧语义。
    /// </summary>
    private static async Task VerifyAutoPickLegacyMigrationAsync(
        VerificationContext context, CancellationToken cancellationToken)
    {
        var root = Path.Combine(Path.GetTempPath(), $"bettergi-fast-{Guid.NewGuid():N}");
        try
        {
            var layout = new RuntimeLayout(root);
            layout.EnsureCreated();
            await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "config.json"), """
                {
                  "autoPickConfig": {
                    "enabled": true,
                    "whiteListEnabled": true
                  }
                }
                """, cancellationToken);

            var catalog = new TriggerSettingsCatalog(layout);
            var migrated = JObject.FromObject(catalog.Get("AutoPick"));
            context.Require(
                migrated.Value<string>("mode") == "Blacklist" &&
                migrated.Value<bool>("blacklistModePickEnabled"),
                "Legacy whiteListEnabled=true was not migrated to blacklistModePickEnabled on read.");

            var runtimeConfig = MacBvSimpleOperationPlatform.LoadAutoPickConfig(
                JsonNode.Parse(await File.ReadAllTextAsync(
                    Path.Combine(layout.UserPath, "config.json"), cancellationToken)) as JsonObject
                ?? throw new InvalidDataException("config.json root must be an object."));
            context.Require(
                runtimeConfig.Mode == AutoPickMode.Blacklist &&
                runtimeConfig.BlacklistModePickEnabled &&
                runtimeConfig.LegacyWhiteListEnabled is null,
                "The runtime AutoPick load path did not apply the legacy migration.");

            _ = catalog.Save("AutoPick", JObject.FromObject(new
            {
                ocrEngine = "Paddle",
                fastModeEnabled = false,
                mode = "Blacklist",
                blacklistModePickEnabled = false,
                whitelistModeDoNotPickEnabled = false,
                exactBlackList = "",
                fuzzyBlackList = "",
                whiteList = "",
                whitelistModePickList = "",
                whitelistModeDoNotPickList = "",
                pickKey = "F",
            }));

            var persisted = JObject.Parse(await File.ReadAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"), cancellationToken));
            context.Require(
                persisted["autoPickConfig"]?["whiteListEnabled"] is null &&
                persisted["autoPickConfig"]?["blacklistModePickEnabled"]?.Value<bool>() == false,
                "AutoPick save did not purge the legacy whiteListEnabled key.");

            var reloaded = JObject.FromObject(catalog.Get("AutoPick"));
            context.Require(
                reloaded.Value<bool>("blacklistModePickEnabled") == false,
                "The purged legacy key resurrected on reload and overrode the saved value.");
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

    private sealed class ExclusiveTrigger : ITaskTrigger
    {
        public string Name => "独占测试触发器";
        public bool IsEnabled { get; set; } = true;
        public int Priority => 100;
        public bool IsExclusive => true;
        public void Init() { }
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

    private sealed class RecordingMapMaskPlatform : IMapMaskRuntimePlatform
    {
        public MapMaskConfig Config { get; } = new() { Enabled = true };
        public string MapMatchingMethod => "FeatureMatcher";
        public Microsoft.Extensions.Logging.ILogger<MapMaskTrigger> Logger =>
            Microsoft.Extensions.Logging.Abstractions.NullLogger<MapMaskTrigger>.Instance;
        public MapMaskDrawCommand? LastCommand { get; private set; }
        public void Publish(MapMaskDrawCommand command) => LastCommand = command;
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
