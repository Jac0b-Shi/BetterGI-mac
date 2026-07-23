using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Verification.Framework;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class SoloTaskSettingsSuite : IVerificationSuite
{
    public string Name => "solo-settings";

    public async Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        var root = Path.Combine(Path.GetTempPath(), $"bettergi-solo-fast-{Guid.NewGuid():N}");
        try
        {
            var layout = new RuntimeLayout(root);
            layout.EnsureCreated();
            await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "config.json"), """
                {
                  "autoGeniusInvokationConfig": {
                    "strategyName": "1.测试策略",
                    "sleepDelay": 25,
                    "activeCharacterCardSpace": 55
                  },
                  "autoMusicGameConfig": {
                    "mustCanorusLevel": false,
                    "musicLevel": "大师"
                  },
                  "autoLeyLineOutcropConfig": {
                    "leyLineOutcropType": "启示之花",
                    "country": "蒙德",
                    "isGoToSynthesizer": true,
                    "fightConfig": {
                      "strategyName": "",
                      "fightFinishDetectEnabled": false,
                      "finishDetectConfig": { "fastCheckEnabled": true },
                      "timeout": 120
                    }
                  },
                  "autoStygianOnslaughtConfig": {
                    "strategyName": "",
                    "bossNum": 1,
                    "resinPriorityList": ["脆弱树脂", "原粹树脂"]
                  },
                  "autoArtifactSalvageConfig": {
                    "maxArtifactStar": "4",
                    "javaScript": "Output = true;"
                  }
                }
                """, cancellationToken);

            var catalog = new SoloTaskSettingsCatalog(layout);
            var tcgFolder = Path.Combine(layout.UserPath, "AutoGeniusInvokation");
            Directory.CreateDirectory(tcgFolder);
            const string tcgStrategy = "角色定义:\n角色1=莫娜\n角色2=砂糖\n角色3=琴\n";
            await File.WriteAllTextAsync(
                Path.Combine(tcgFolder, "1.测试策略.txt"), tcgStrategy, cancellationToken);
            _ = catalog.Save("AutoGeniusInvokation", JObject.FromObject(new
            {
                strategyName = "1.测试策略",
                sleepDelay = 350,
            }));
            var platform = new RecordingDispatcherPlatform();
            var coordinator = new SoloTaskCoordinator(platform, catalog, CancellationToken.None);
            var descriptors = JArray.FromObject(coordinator.List());
            foreach (var item in descriptors.OfType<JObject>())
            {
                var name = item.Value<string>("name")
                    ?? throw new InvalidDataException("Solo task descriptor has no name.");
                context.Require(
                    item.Value<bool>("settingsAvailable") == catalog.IsAvailable(name),
                    $"Solo task '{name}' settings availability drifted from the Core catalog.");
                context.Require(
                    !string.IsNullOrWhiteSpace(item.Value<string>("description")),
                    $"Solo task '{name}' did not expose its upstream description.");
            }
            var upstreamDescriptions = new Dictionary<string, string>
            {
                ["AutoGeniusInvokation"] = "全自动打牌",
                ["AutoWood"] = "装备「王树瑞佑」，通过循环重启游戏刷新并收集木材",
                ["AutoFight"] = "自动执行选择的战斗策略",
                ["AutoDomain"] = "基于钟离的自动循环刷本",
                ["AutoBoss"] = "自动传送、战斗并领取奖励",
                ["AutoStygianOnslaught"] = "自动传送并进入幽境危战",
                ["AutoFishing"] = "不要携带跟宠！在出现钓鱼F按钮的位置启动本任务",
                ["AutoLeyLineOutcrop"] = "自动定位并刷取地脉花",
                ["AutoMusicGame"] = "可以自动演奏单个，也可以全自动完成整个专辑",
                ["AutoAlbum"] = "可以自动演奏单个，也可以全自动完成整个专辑",
                ["AutoCook"] = "在手动烹饪界面运行，自动识别并点击结束烹饪",
                ["AutoArtifactSalvage"] = "指定匹配表达式逐一筛选分解，支持5星圣遗物",
                ["AutoRedeemCode"] = "自动使用输入的兑换码",
            };
            foreach (var (name, description) in upstreamDescriptions)
            {
                context.Require(
                    descriptors.Single(item => item.Value<string>("name") == name)
                        .Value<string>("description") == description,
                    $"Solo task '{name}' description drifted from the upstream task settings page.");
            }
            context.Require(
                descriptors.Single(item => item.Value<string>("name") == "AutoRedeemCode")
                    .Value<bool>("settingsAvailable") == false,
                "AutoRedeemCode exposed a fake expandable settings surface.");
            var descriptor = descriptors.Single(item =>
                item.Value<string>("name") == "AutoGeniusInvokation");
            context.Require(descriptor.Value<bool>("available") &&
                            descriptor.Value<bool>("settingsAvailable"),
                "AutoGeniusInvokation was not exposed as a composed configurable solo task.");
            _ = coordinator.Start("AutoGeniusInvokation");
            for (var retry = 0; retry < 20 && platform.Request is null; retry++)
                await Task.Delay(10, cancellationToken);
            var genius = platform.Request as DispatcherGeniusTaskRequest;
            var geniusConfig = catalog.BuildAutoGeniusInvokationConfig();
            var geniusPersisted = JObject.Parse(await File.ReadAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"), cancellationToken));
            context.Require(genius?.Strategy == tcgStrategy && geniusConfig.SleepDelay == 350 &&
                            geniusPersisted["autoGeniusInvokationConfig"]?
                                .Value<int>("activeCharacterCardSpace") == 55,
                "AutoGeniusInvokation did not preserve hidden config or dispatch the selected strategy.");

            _ = catalog.Save("AutoAlbum", JObject.FromObject(new
            {
                mustCanorusLevel = true,
                musicLevel = "所有",
            }));
            var albumSettings = JObject.FromObject(catalog.Get("AutoAlbum"));
            var musicSettings = JObject.FromObject(catalog.Get("AutoMusicGame"));
            context.Require(albumSettings.Value<string>("name") == "AutoAlbum" &&
                            albumSettings.Value<bool>("mustCanorusLevel") &&
                            albumSettings.Value<string>("musicLevel") == "所有" &&
                            musicSettings.Value<bool>("mustCanorusLevel") &&
                            musicSettings.Value<string>("musicLevel") == "所有",
                "AutoAlbum did not share the Core-owned AutoMusicGame settings.");
            platform.Reset();
            descriptors = JArray.FromObject(coordinator.List());
            descriptor = descriptors.Single(item =>
                item.Value<string>("name") == "AutoAlbum");
            context.Require(descriptor.Value<bool>("available") &&
                            descriptor.Value<bool>("settingsAvailable"),
                "AutoAlbum was not exposed as a composed configurable solo task.");
            _ = coordinator.Start("AutoAlbum");
            for (var retry = 0; retry < 20 && platform.Request is null; retry++)
                await Task.Delay(10, cancellationToken);
            context.Require(platform.Request is DispatcherAlbumTaskRequest,
                "SoloTaskCoordinator did not dispatch the upstream AutoAlbum task.");

            platform.Reset();
            descriptors = JArray.FromObject(coordinator.List());
            descriptor = descriptors.Single(item =>
                item.Value<string>("name") == "AutoRedeemCode");
            context.Require(descriptor.Value<bool>("available") &&
                            !descriptor.Value<bool>("settingsAvailable") &&
                            descriptor.Value<string>("inputKind") == "multilineText",
                "AutoRedeemCode did not expose its Core-owned multiline input contract.");
            _ = coordinator.Start("AutoRedeemCode", " CODE-A \n\nCODE-B\r\n");
            for (var retry = 0; retry < 20 && platform.Request is null; retry++)
                await Task.Delay(10, cancellationToken);
            context.Require(platform.Request is DispatcherRedeemCodeTaskRequest redeem &&
                            redeem.Codes.SequenceEqual(["CODE-A", "CODE-B"]),
                "AutoRedeemCode input was not normalized into the typed dispatcher request.");

            var initial = JObject.FromObject(catalog.Get("AutoLeyLineOutcrop"));
            context.Require(initial.Value<string>("leyLineOutcropType") == "启示之花" &&
                            initial["countryOptions"]?.Values<string>().Contains("挪德卡莱") == true,
                "AutoLeyLineOutcrop settings did not expose the upstream options.");

            _ = catalog.Save("AutoLeyLineOutcrop", JObject.FromObject(new
            {
                leyLineOutcropType = "藏金之花",
                country = "枫丹",
                strategyName = "",
                actionSchedulerByCd = "钟离,12",
                seekEnemyEnabled = true,
                seekEnemyRotaryFactor = 8,
                seekEnemyIntervalSeconds = 4,
                kazuhaPickupEnabled = true,
                qinDoublePickUp = true,
                scanDropsAfterRewardEnabled = true,
                scanDropsAfterRewardSeconds = 15,
                isResinExhaustionMode = true,
                openModeCountMin = true,
                count = 9,
                useTransientResin = true,
                useFragileResin = false,
                team = "战斗队",
                friendshipTeam = "好感队",
                timeout = 180,
                useAdventurerHandbook = true,
                isNotification = true,
            }));

            var persisted = JObject.Parse(await File.ReadAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"), cancellationToken));
            var node = persisted["autoLeyLineOutcropConfig"]!;
            var config = catalog.BuildAutoLeyLineOutcropConfig();
            context.Require(node.Value<bool>("isGoToSynthesizer") &&
                            node["fightConfig"]?.Value<bool>("fightFinishDetectEnabled") == false &&
                            node["fightConfig"]?["finishDetectConfig"]?
                                .Value<bool>("fastCheckEnabled") == true,
                "AutoLeyLineOutcrop save did not preserve hidden upstream settings.");
            context.Require(config.LeyLineOutcropType == "藏金之花" &&
                            config.Country == "枫丹" && config.Count == 9 &&
                            config.FightConfig.ActionSchedulerByCd == "钟离,12" &&
                            config.FightConfig.Timeout == 180 && config.Timeout == 180 &&
                            config.UseAdventurerHandbook && config.IsNotification,
                "AutoLeyLineOutcrop task config did not reflect the saved Core-owned settings.");

            platform.Reset();
            descriptors = JArray.FromObject(coordinator.List());
            descriptor = descriptors.Single(item =>
                item.Value<string>("name") == "AutoLeyLineOutcrop");
            context.Require(descriptor.Value<bool>("available") &&
                            descriptor.Value<bool>("settingsAvailable"),
                "AutoLeyLineOutcrop was not exposed as a composed configurable solo task.");
            _ = coordinator.Start("AutoLeyLineOutcrop");
            for (var retry = 0; retry < 20 && platform.Request is null; retry++)
                await Task.Delay(10, cancellationToken);
            context.Require(platform.Request is DispatcherLeyLineTaskRequest request &&
                            request.Config.Country == "枫丹" && request.Config.Count == 9,
                "SoloTaskCoordinator did not dispatch the Core-owned AutoLeyLineOutcrop config.");

            _ = catalog.Save("AutoStygianOnslaught", JObject.FromObject(new
            {
                strategyName = "",
                bossNum = 3,
                fightTeamName = "幽境队",
                specifyResinUse = true,
                originalResinUseCount = 2,
                condensedResinUseCount = 1,
                transientResinUseCount = 0,
                fragileResinUseCount = 1,
                autoArtifactSalvage = true,
                maxArtifactStar = "3",
            }));
            persisted = JObject.Parse(await File.ReadAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"), cancellationToken));
            context.Require(
                persisted["autoStygianOnslaughtConfig"]?["resinPriorityList"]?
                    .Values<string>().SequenceEqual(["脆弱树脂", "原粹树脂"]) == true &&
                persisted["autoArtifactSalvageConfig"]?.Value<string>("javaScript") ==
                    "Output = true;" &&
                persisted["autoArtifactSalvageConfig"]?.Value<string>("maxArtifactStar") == "3",
                "AutoStygianOnslaught save did not preserve hidden upstream settings.");

            descriptors = JArray.FromObject(coordinator.List());
            descriptor = descriptors.Single(item =>
                item.Value<string>("name") == "AutoStygianOnslaught");
            context.Require(descriptor.Value<bool>("available") &&
                            descriptor.Value<bool>("settingsAvailable"),
                "AutoStygianOnslaught was not exposed as a composed configurable solo task.");
            platform.Reset();
            _ = coordinator.Start("AutoStygianOnslaught");
            for (var retry = 0; retry < 20 && platform.Request is null; retry++)
                await Task.Delay(10, cancellationToken);
            var stygian = platform.Request as DispatcherStygianTaskRequest;
            context.Require(stygian is not null &&
                            stygian.Config.BossNum == 3 &&
                            stygian.Config.FightTeamName == "幽境队" &&
                            stygian.ArtifactSalvageStar == 3 &&
                            stygian.Config.ResinPriorityList.SequenceEqual(
                                ["脆弱树脂", "原粹树脂"]),
                $"SoloTaskCoordinator did not dispatch the Core-owned AutoStygianOnslaught config: " +
                $"type={platform.Request?.GetType().Name ?? "null"}, " +
                $"boss={stygian?.Config.BossNum}, team={stygian?.Config.FightTeamName}, " +
                $"star={stygian?.ArtifactSalvageStar}, " +
                $"priority={string.Join(',', stygian?.Config.ResinPriorityList ?? [])}, " +
                $"status={JObject.FromObject(coordinator.Status()).ToString(Newtonsoft.Json.Formatting.None)}.");

            platform.Reset();
            platform.BlockUntilCancelled = true;
            _ = coordinator.Start("AutoCook");
            await platform.Started.Task.WaitAsync(cancellationToken);
            context.Require(await coordinator.StopActiveAsync(cancellationToken),
                "Runtime stop did not cancel the active solo task.");
            var stoppedStatus = JObject.FromObject(coordinator.Status());
            context.Require(stoppedStatus.Value<string>("state") == "cancelled",
                "Active solo task did not reach cancelled after runtime stop.");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    private sealed class RecordingDispatcherPlatform : IDispatcherRuntimePlatform
    {
        public DispatcherSoloTaskRequest? Request { get; private set; }
        public bool BlockUntilCancelled { get; set; }
        public TaskCompletionSource Started { get; private set; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);
        public void Reset()
        {
            Request = null;
            BlockUntilCancelled = false;
            Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        }
        public CancellationToken GlobalCancellationToken => CancellationToken.None;
        public int AutoWoodRoundNum => 0;
        public int AutoWoodDailyMaxCount => 0;
        public string AutoBossStrategyName => string.Empty;
        public DispatcherAutoEatSettings AutoEatSettings => new(0, 0, false);
        public void ClearTriggers() { }
        public bool AddTrigger(string name, object? config) => true;
        public bool GetTcgStrategy(out string content) { content = string.Empty; return false; }
        public bool GetFightStrategy(string? strategyName, out string path)
        {
            path = string.Empty;
            return false;
        }
        public Task<object?> ExecuteSoloTask(
            DispatcherSoloTaskRequest request, CancellationToken cancellationToken)
        {
            Request = request;
            Started.TrySetResult();
            if (BlockUntilCancelled)
                return WaitForCancellation(cancellationToken);
            return Task.FromResult<object?>(null);
        }
        public Task<object?> RunParameterizedTask(
            string name, object parameter, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        private static async Task<object?> WaitForCancellation(CancellationToken cancellationToken)
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return null;
        }
    }
}
