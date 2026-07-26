using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.GameTask.Model.GameUI;
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
                  "autoRedeemCodeConfig": {
                    "clipboardListenerEnabled": true
                  },
                  "commonConfig": {
                    "screenshotEnabled": false,
                    "screenshotUidCoverEnabled": true,
                    "rewardRecognitionScreenshotEnabled": true
                  },
                  "pathingConditionConfig": {
                    "mapMatchingMethod": "TemplateMatch",
                    "preserved": { "value": 37 }
                  },
                  "scriptConfig": {
                    "preserved": { "value": 91 },
                    "autoUpdateSubscribedScripts": false,
                    "autoUpdateBeforeCommandLineRun": false,
                    "selectedChannelName": "CNB",
                    "customRepoUrl": ""
                  },
                  "otherConfig": {
                    "preserved": { "value": 73 },
                    "autoFetchDispatchAdventurersGuildCountry": "无",
                    "serverTimeZoneOffset": "08:00:00",
                    "autoRestartConfig": {
                      "enabled": false,
                      "failureCount": 5,
                      "restartGameTogether": false,
                      "isFightFailureExceptional": false,
                      "isPathingFailureExceptional": false
                    },
                    "farmingPlanConfig": {
                      "enabled": false,
                      "dailyEliteCap": 400,
                      "dailyMobCap": 2000,
                      "miyousheDataConfig": {
                        "enabled": false,
                        "dailyEliteCap": 400,
                        "dailyMobCap": 2000
                      }
                    },
                    "miyousheConfig": {
                      "cookie": "",
                      "logSyncCookie": true
                    }
                  },
                  "autoLeyLineOutcropConfig": {
                    "leyLineOutcropType": "蓝花（经验书）",
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
            var commonSettingsCatalog = new CommonSettingsCatalog(layout);
            _ = catalog.Save("AutoFishing", JObject.FromObject(new
            {
                autoThrowRodTimeOut = 15,
                wholeProcessTimeoutSeconds = 300,
                fishingTimePolicy = "All",
                saveScreenshotOnKeyTick = true,
            }));
            var fishingSettings = JObject.FromObject(catalog.Get("AutoFishing"));
            context.Require(
                fishingSettings.Value<bool>("screenshotEnabled") == false &&
                fishingSettings.Value<bool>("saveScreenshotOnKeyTick") == false,
                "AutoFishing exposed key-tick screenshots while the upstream global gate was off.");
            var hiddenGridIconsCoordinator = new SoloTaskCoordinator(
                new RecordingDispatcherPlatform(), catalog, layout, CancellationToken.None);
            context.Require(
                JArray.FromObject(hiddenGridIconsCoordinator.List()).All(item =>
                    item.Value<string>("name") != "GetGridIcons"),
                "GetGridIcons was listed while the upstream screenshot gate was off.");
            OtherConfig? updatedOtherConfig = null;
            commonSettingsCatalog.AttachOtherConfigUpdated(
                value => updatedOtherConfig = value);
            _ = commonSettingsCatalog.Save(JObject.FromObject(new
            {
                screenshotEnabled = true,
                screenshotUidCoverEnabled = false,
                mapMatchingMethod = "SIFT",
                autoFetchDispatchCountry = "璃月",
                serverTimeZoneOffsetHours = 1,
                autoRestartEnabled = true,
                autoRestartFailureCount = 7,
                autoRestartGameTogether = true,
                fightFailureExceptional = true,
                pathingFailureExceptional = true,
                farmingPlanEnabled = true,
                farmingDailyEliteCap = 410,
                farmingDailyMobCap = 2010,
                miyousheDataEnabled = true,
                miyousheDailyEliteCap = 420,
                miyousheDailyMobCap = 2020,
                miyousheCookie = "test-cookie",
                miyousheLogSyncCookie = false,
                autoUpdateSubscribedScripts = true,
                autoUpdateBeforeCommandLineRun = true,
                scriptRepositoryChannel = "GitHub",
                scriptRepositoryCustomUrl = "",
            }));
            fishingSettings = JObject.FromObject(catalog.Get("AutoFishing"));
            var commonSettings = JObject.FromObject(commonSettingsCatalog.Get());
            var commonPersisted = JObject.Parse(await File.ReadAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"), cancellationToken));
            context.Require(
                fishingSettings.Value<bool>("screenshotEnabled") &&
                fishingSettings.Value<bool>("saveScreenshotOnKeyTick") &&
                commonSettings.Value<bool>("screenshotEnabled") &&
                commonSettings.Value<bool>("screenshotUidCoverEnabled") == false &&
                commonSettings.Value<string>("mapMatchingMethod") == "SIFT" &&
                ((JArray)commonSettings["mapMatchingMethodOptions"]!)
                    .Values<string>().SequenceEqual(["SIFT", "TemplateMatch"]) &&
                commonSettings.Value<string>("autoFetchDispatchCountry") == "璃月" &&
                commonSettings.Value<int>("serverTimeZoneOffsetHours") == 1 &&
                commonSettings.Value<bool>("autoRestartEnabled") &&
                commonSettings.Value<int>("autoRestartFailureCount") == 7 &&
                commonSettings.Value<bool>("farmingPlanEnabled") &&
                commonSettings.Value<bool>("miyousheDataEnabled") &&
                commonSettings.Value<string>("miyousheCookie") == "test-cookie" &&
                commonSettings.Value<bool>("autoUpdateSubscribedScripts") &&
                commonSettings.Value<bool>("autoUpdateBeforeCommandLineRun") &&
                commonSettings.Value<string>("scriptRepositoryChannel") == "GitHub" &&
                ((JArray)commonSettings["scriptRepositoryChannelOptions"]!)
                    .Values<string>().SequenceEqual(["CNB", "GitCode", "GitHub", "自定义"]) &&
                commonSettings.SelectToken(
                    "scriptRepositoryChannelUrls.GitHub")?.Value<string>() ==
                    "https://github.com/babalae/bettergi-scripts-list" &&
                updatedOtherConfig?.AutoFetchDispatchAdventurersGuildCountry == "璃月" &&
                updatedOtherConfig?.ServerTimeZoneOffset == TimeSpan.FromHours(1) &&
                commonPersisted.SelectToken(
                    "commonConfig.rewardRecognitionScreenshotEnabled")?.Value<bool>() == true &&
                commonPersisted.SelectToken(
                    "pathingConditionConfig.mapMatchingMethod")?.Value<string>() == "SIFT" &&
                commonPersisted.SelectToken(
                    "pathingConditionConfig.preserved.value")?.Value<int>() == 37 &&
                commonPersisted.SelectToken(
                    "otherConfig.preserved.value")?.Value<int>() == 73 &&
                commonPersisted.SelectToken(
                    "scriptConfig.preserved.value")?.Value<int>() == 91 &&
                commonPersisted.SelectToken(
                    "scriptConfig.autoUpdateBeforeCommandLineRun")?.Value<bool>() == true,
                "Common settings did not preserve unknown values, persist unattended settings or publish the live update.");
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
            var coordinator = new SoloTaskCoordinator(
                platform, catalog, layout, CancellationToken.None);
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
                ["AutoCook"] = "在手动烹饪界面运行，自动识别并点击结束烹饪",
                ["AutoArtifactSalvage"] = "指定匹配表达式逐一筛选分解，支持5星圣遗物",
                ["AutoRedeemCode"] = "自动使用输入的兑换码",
                ["GetGridIcons"] = "需要启用保存截图，文件保存在 log/gridIcons",
            };
            foreach (var (name, description) in upstreamDescriptions)
            {
                context.Require(
                    descriptors.Single(item => item.Value<string>("name") == name)
                        .Value<string>("description") == description,
                    $"Solo task '{name}' description drifted from the upstream task settings page.");
            }
            var upstreamTutorialUrls = new Dictionary<string, string>
            {
                ["AutoGeniusInvokation"] = "https://www.bettergi.com/feats/task/tcg.html",
                ["AutoWood"] = "https://www.bettergi.com/feats/task/felling.html",
                ["AutoFight"] = "https://www.bettergi.com/feats/task/domain.html",
                ["AutoDomain"] = "https://www.bettergi.com/feats/task/domain.html",
                ["AutoStygianOnslaught"] = "https://www.bettergi.com/feats/task/stygian.html",
                ["AutoFishing"] = "https://www.bettergi.com/feats/task/fish.html",
                ["AutoLeyLineOutcrop"] = "https://www.bettergi.com/feats/task/leyline.html",
                ["AutoMusicGame"] = "https://www.bettergi.com/feats/task/music.html",
                ["AutoArtifactSalvage"] =
                    "https://www.bettergi.com/feats/task/artifactSalvage.html",
                ["GetGridIcons"] = "https://www.bettergi.com/dev/getGridIcons.html",
            };
            foreach (var (name, tutorialUrl) in upstreamTutorialUrls)
            {
                context.Require(
                    descriptors.Single(item => item.Value<string>("name") == name)
                        .Value<string>("tutorialUrl") == tutorialUrl,
                    $"Solo task '{name}' tutorial link drifted from the upstream task settings page.");
            }
            var repositoryTasks = new HashSet<string>
            {
                "AutoGeniusInvokation", "AutoFight", "AutoDomain",
                "AutoStygianOnslaught", "AutoLeyLineOutcrop",
            };
            var directoryTasks = new HashSet<string>
            {
                "AutoFight", "AutoDomain", "AutoStygianOnslaught",
                "AutoLeyLineOutcrop", "GetGridIcons",
            };
            foreach (var item in descriptors.OfType<JObject>())
            {
                var name = item.Value<string>("name")!;
                context.Require(
                    item.Value<bool>("showsScriptRepository") == repositoryTasks.Contains(name),
                    $"Solo task '{name}' script repository entry drifted from upstream.");
                context.Require(
                    (item.Value<string>("scriptDirectoryPath") is not null) ==
                    directoryTasks.Contains(name),
                    $"Solo task '{name}' script directory entry drifted from upstream.");
            }
            context.Require(
                directoryTasks.Where(name => name != "GetGridIcons").All(name =>
                    descriptors.Single(item => item.Value<string>("name") == name)
                        .Value<string>("scriptDirectoryPath") ==
                    Path.Combine(layout.UserPath, "AutoFight")),
                "Solo task combat script directory did not resolve to the canonical runtime path.");
            var gridDescriptor = descriptors.Single(item =>
                item.Value<string>("name") == "GetGridIcons");
            var gridActions = gridDescriptor["actions"]?.OfType<JObject>().ToArray();
            context.Require(
                gridDescriptor.Value<bool>("settingsAvailable") &&
                gridDescriptor.Value<bool>("headerAction") == false &&
                gridDescriptor.Value<string>("scriptDirectoryPath") ==
                    Path.Combine(layout.LogPath, "gridIcons") &&
                gridActions is { Length: 2 } &&
                gridActions[0].Value<string>("name") == "GetGridIcons" &&
                gridActions[1].Value<string>("name") == "GridIconsAccuracyTest",
                "GetGridIcons did not expose the upstream gated card and actions.");
            _ = catalog.Save("GetGridIcons", JObject.FromObject(new
            {
                gridName = "Food",
                starAsSuffix = true,
                lvAsSuffix = false,
                maxNumToGet = 12,
            }));
            var gridSettings = JObject.FromObject(catalog.Get("GetGridIcons"));
            context.Require(
                gridSettings.Value<string>("gridName") == "Food" &&
                gridSettings.Value<bool>("starAsSuffix") &&
                !gridSettings.Value<bool>("lvAsSuffix") &&
                gridSettings.Value<int>("maxNumToGet") == 12 &&
                gridSettings["gridNameOptions"]?.OfType<JObject>().Any(option =>
                    option.Value<string>("value") == "Food" &&
                    option.Value<string>("displayName") == "食物") == true,
                "GetGridIcons did not persist or describe its upstream settings.");
            platform.Reset();
            _ = coordinator.Start("GetGridIcons");
            for (var retry = 0; retry < 20 && platform.Request is null; retry++)
                await Task.Delay(10, cancellationToken);
            context.Require(
                platform.Request is DispatcherGetGridIconsTaskRequest
                {
                    GridName: GridScreenName.Food,
                    StarAsSuffix: true,
                    MaxNumToGet: 12,
                    AccuracyTest: false,
                },
                "GetGridIcons did not dispatch its typed Core-owned request.");
            context.Require(
                descriptors.Single(item => item.Value<string>("name") == "AutoRedeemCode")
                    .Value<bool>("settingsAvailable"),
                "AutoRedeemCode did not expose its upstream clipboard-listener setting.");
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
                item.Value<string>("name") == "AutoMusicGame");
            var musicActions = descriptor["actions"]?.OfType<JObject>().ToArray();
            context.Require(descriptor.Value<bool>("available") &&
                            descriptor.Value<bool>("settingsAvailable") &&
                            descriptor.Value<bool>("headerAction") == false &&
                            musicActions is { Length: 2 } &&
                            musicActions[0].Value<string>("name") == "AutoMusicGame" &&
                            musicActions[0].Value<string>("title") == "【乐曲】 演奏单个乐曲" &&
                            musicActions[0].Value<string>("description") ==
                                "进入演奏界面使用，下落模式必须选择垂落模式" &&
                            musicActions[1].Value<string>("name") == "AutoAlbum" &&
                            musicActions[1].Value<string>("title") == "【专辑】 全自动完成整个专辑" &&
                            musicActions[1].Value<string>("description") ==
                                "进入专辑界面使用，自动演奏未完成乐曲",
                "AutoMusicGame did not expose the two upstream in-card actions.");
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
                            descriptor.Value<bool>("settingsAvailable") &&
                            descriptor.Value<string>("inputKind") == "multilineText",
                "AutoRedeemCode did not expose its Core-owned input and settings contracts.");
            var redeemSettings = JObject.FromObject(catalog.Get("AutoRedeemCode"));
            _ = catalog.Save("AutoRedeemCode", JObject.FromObject(new
            {
                clipboardListenerEnabled = false,
            }));
            var redeemSaved = JObject.FromObject(catalog.Get("AutoRedeemCode"));
            context.Require(redeemSettings.Value<bool>("clipboardListenerEnabled") &&
                            !redeemSaved.Value<bool>("clipboardListenerEnabled"),
                "AutoRedeemCode did not persist its upstream clipboard-listener setting.");
            _ = coordinator.Start("AutoRedeemCode", " CODE-A \n\nCODE-B\r\n");
            for (var retry = 0; retry < 20 && platform.Request is null; retry++)
                await Task.Delay(10, cancellationToken);
            context.Require(platform.Request is DispatcherRedeemCodeTaskRequest redeem &&
                            redeem.Codes.SequenceEqual(["CODE-A", "CODE-B"]),
                "AutoRedeemCode input was not normalized into the typed dispatcher request.");

            var initial = JObject.FromObject(catalog.Get("AutoLeyLineOutcrop"));
            var normalizedLeyLineConfig = JObject.Parse(await File.ReadAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"), cancellationToken));
            context.Require(initial.Value<string>("leyLineOutcropType") == "启示之花" &&
                            initial["countryOptions"]?.Values<string>().Contains("挪德卡莱") == true &&
                            normalizedLeyLineConfig.SelectToken(
                                "autoLeyLineOutcropConfig.leyLineOutcropType")?.Value<string>()
                                == "启示之花",
                "AutoLeyLineOutcrop settings did not normalize legacy types or expose upstream options.");

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
