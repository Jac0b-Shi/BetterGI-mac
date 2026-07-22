using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.AutoBoss;
using BetterGenshinImpact.GameTask.AutoCook;
using BetterGenshinImpact.GameTask.AutoDomain;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.AutoArtifactSalvage;
using BetterGenshinImpact.GameTask.AutoMusicGame;
using BetterGenshinImpact.GameTask.AutoWood;
using BetterGenshinImpact.GameTask.AutoLeyLineOutcrop;
using BetterGenshinImpact.GameTask.Common.Element.Assets;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class SoloTaskSettingsCatalog(RuntimeLayout layout)
{
    private readonly object _lock = new();
    private Action<AutoFightConfig>? _autoFightConfigUpdated;
    private Action<AutoFishingConfig>? _autoFishingConfigUpdated;
    public bool AutoFishingSaveScreenshotOnKeyTick { get; private set; }
    public int AutoWoodRoundNum { get; private set; }
    public int AutoWoodDailyMaxCount { get; private set; } = 2000;

    public void AttachAutoFightConfigUpdated(Action<AutoFightConfig> callback) =>
        _autoFightConfigUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public void AttachAutoFishingConfigUpdated(Action<AutoFishingConfig> callback) =>
        _autoFishingConfigUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public AutoFishingTaskParam BuildAutoFishingTaskParam()
    {
        lock (_lock)
        {
            var config = LoadConfig<AutoFishingConfig>(LoadRoot(), "autoFishingConfig");
            return AutoFishingTaskParam.BuildFromConfig(
                config, AutoFishingSaveScreenshotOnKeyTick);
        }
    }

    public AutoLeyLineOutcropConfig BuildAutoLeyLineOutcropConfig()
    {
        lock (_lock)
        {
            return LoadConfig<AutoLeyLineOutcropConfig>(
                LoadRoot(), "autoLeyLineOutcropConfig");
        }
    }

    public object Get(string name)
    {
        lock (_lock)
        {
            var root = LoadRoot();
            return name switch
            {
                "AutoCook" => Describe(LoadConfig<AutoCookConfig>(root, "autoCookConfig")),
                "AutoFishing" => Describe(
                    LoadConfig<AutoFishingConfig>(root, "autoFishingConfig")),
                "AutoWood" => Describe(LoadConfig<AutoWoodConfig>(root, "autoWoodConfig")),
                "AutoMusicGame" => Describe(
                    LoadConfig<AutoMusicGameConfig>(root, "autoMusicGameConfig")),
                "AutoBoss" => Describe(LoadConfig<AutoBossConfig>(root, "autoBossConfig")),
                "AutoFight" => Describe(LoadConfig<AutoFightConfig>(root, "autoFightConfig")),
                "AutoDomain" => Describe(
                    LoadConfig<AutoDomainConfig>(root, "autoDomainConfig"),
                    LoadConfig<AutoFightConfig>(root, "autoFightConfig"),
                    LoadConfig<AutoArtifactSalvageConfig>(root, "autoArtifactSalvageConfig")),
                "AutoArtifactSalvage" => Describe(
                    LoadConfig<AutoArtifactSalvageConfig>(root, "autoArtifactSalvageConfig")),
                "AutoLeyLineOutcrop" => Describe(
                    LoadConfig<AutoLeyLineOutcropConfig>(root, "autoLeyLineOutcropConfig")),
                _ => throw Unavailable(name),
            };
        }
    }

    public object Save(string name, JObject settings)
    {
        return name switch
        {
            "AutoCook" => SaveAutoCook(settings),
            "AutoFishing" => SaveAutoFishing(settings),
            "AutoWood" => SaveAutoWood(settings),
            "AutoMusicGame" => SaveAutoMusicGame(settings),
            "AutoBoss" => SaveAutoBoss(settings),
            "AutoFight" => SaveAutoFight(settings),
            "AutoDomain" => SaveAutoDomain(settings),
            "AutoArtifactSalvage" => SaveAutoArtifactSalvage(settings),
            "AutoLeyLineOutcrop" => SaveAutoLeyLineOutcrop(settings),
            _ => throw Unavailable(name),
        };
    }

    private object SaveAutoCook(JObject settings)
    {
        var interval = settings.Value<int?>("checkIntervalMs")
                       ?? throw new ArgumentException("checkIntervalMs is required.");
        if (interval is < 1 or > 1000)
            throw new ArgumentOutOfRangeException(
                "checkIntervalMs", interval, "checkIntervalMs must be between 1 and 1000.");
        var stopWhenDetected = settings.Value<bool?>("stopTaskWhenRecoverButtonDetected")
                               ?? throw new ArgumentException(
                                   "stopTaskWhenRecoverButtonDetected is required.");

        lock (_lock)
        {
            var root = LoadRoot();
            var config = new AutoCookConfig
            {
                CheckIntervalMs = interval,
                StopTaskWhenRecoverButtonDetected = stopWhenDetected,
            };
            root["autoCookConfig"] = JsonSerializer.SerializeToNode(config, ConfigJson.Options);
            SaveRoot(root);
            return Describe(config);
        }
    }

    private object SaveAutoFishing(JObject settings)
    {
        var autoThrowRodTimeOut = RequiredInt(settings, "autoThrowRodTimeOut");
        if (autoThrowRodTimeOut is < 5 or > 60)
            throw new ArgumentOutOfRangeException(nameof(autoThrowRodTimeOut),
                autoThrowRodTimeOut, "autoThrowRodTimeOut must be between 5 and 60.");
        var wholeProcessTimeoutSeconds = RequiredInt(settings, "wholeProcessTimeoutSeconds");
        if (wholeProcessTimeoutSeconds is < 0 or > 1800)
            throw new ArgumentOutOfRangeException(nameof(wholeProcessTimeoutSeconds),
                wholeProcessTimeoutSeconds,
                "wholeProcessTimeoutSeconds must be between 0 and 1800.");
        var policyName = RequiredString(settings, "fishingTimePolicy");
        if (!Enum.TryParse<FishingTimePolicy>(policyName, out var fishingTimePolicy) ||
            !Enum.IsDefined(fishingTimePolicy))
            throw new ArgumentException($"Unsupported fishingTimePolicy: {policyName}");
        var saveScreenshotOnKeyTick = RequiredBool(settings, "saveScreenshotOnKeyTick");

        lock (_lock)
        {
            var root = LoadRoot();
            var config = LoadConfig<AutoFishingConfig>(root, "autoFishingConfig");
            config.AutoThrowRodTimeOut = autoThrowRodTimeOut;
            config.WholeProcessTimeoutSeconds = wholeProcessTimeoutSeconds;
            config.FishingTimePolicy = fishingTimePolicy;
            AutoFishingSaveScreenshotOnKeyTick = saveScreenshotOnKeyTick;
            root["autoFishingConfig"] = JsonSerializer.SerializeToNode(config, ConfigJson.Options);
            SaveRoot(root);
            _autoFishingConfigUpdated?.Invoke(config);
            return Describe(config);
        }
    }

    private object SaveAutoWood(JObject settings)
    {
        var roundNum = RequiredInt(settings, "roundNum");
        var dailyMaxCount = RequiredInt(settings, "dailyMaxCount");
        var config = new AutoWoodConfig
        {
            UseWonderlandRefresh = RequiredBool(settings, "useWonderlandRefresh"),
            WoodCountOcrEnabled = RequiredBool(settings, "woodCountOcrEnabled"),
            AfterZSleepDelay = RequiredInt(settings, "afterZSleepDelay"),
        };
        lock (_lock)
        {
            AutoWoodRoundNum = roundNum;
            AutoWoodDailyMaxCount = dailyMaxCount;
            SaveConfig("autoWoodConfig", config);
            return Describe(config);
        }
    }

    private object SaveAutoMusicGame(JObject settings)
    {
        var musicLevel = RequiredString(settings, "musicLevel");
        if (!MusicLevels.Contains(musicLevel, StringComparer.Ordinal))
            throw new ArgumentException($"Unsupported musicLevel: {musicLevel}");
        var config = new AutoMusicGameConfig
        {
            MustCanorusLevel = RequiredBool(settings, "mustCanorusLevel"),
            MusicLevel = musicLevel,
        };
        lock (_lock)
        {
            SaveConfig("autoMusicGameConfig", config);
            return Describe(config);
        }
    }

    private object SaveAutoBoss(JObject settings)
    {
        var bossName = RequiredString(settings, "bossName");
        if (!string.IsNullOrEmpty(bossName) && !AutoBossData.IsSupportedBoss(bossName))
            throw new ArgumentException($"Unsupported bossName: {bossName}");
        var strategyName = RequiredString(settings, "strategyName");
        if (!StrategyOptions().Contains(strategyName, StringComparer.Ordinal))
            throw new ArgumentException($"Unknown AutoFight strategy: {strategyName}");
        var config = new AutoBossConfig
        {
            BossName = bossName,
            StrategyName = strategyName,
            TeamName = RequiredString(settings, "teamName"),
            SpecifyRunCount = RequiredBool(settings, "specifyRunCount"),
            RunCount = Math.Max(1, RequiredInt(settings, "runCount")),
            UseTransientResin = RequiredBool(settings, "useTransientResin"),
            UseFragileResin = RequiredBool(settings, "useFragileResin"),
            ReturnToStatueAfterEachRound = RequiredBool(
                settings, "returnToStatueAfterEachRound"),
            RewardRecognitionEnabled = RequiredBool(settings, "rewardRecognitionEnabled"),
            ReviveRetryCount = Math.Max(0, RequiredInt(settings, "reviveRetryCount")),
        };
        if (!config.SpecifyRunCount)
        {
            config.UseTransientResin = false;
            config.UseFragileResin = false;
        }
        lock (_lock)
        {
            SaveConfig("autoBossConfig", config);
            return Describe(config);
        }
    }

    private object SaveAutoFight(JObject settings)
    {
        var strategyName = RequiredString(settings, "strategyName");
        if (!StrategyOptions().Contains(strategyName, StringComparer.Ordinal))
            throw new ArgumentException($"Unknown AutoFight strategy: {strategyName}");
        var guardianAvatar = RequiredString(settings, "guardianAvatar");
        if (guardianAvatar is not ("" or "1" or "2" or "3" or "4"))
            throw new ArgumentException($"Unsupported guardianAvatar: {guardianAvatar}");
        var rotaryFactor = RequiredInt(settings, "rotaryFactor");
        if (rotaryFactor is < 1 or > 13)
            throw new ArgumentOutOfRangeException("rotaryFactor", rotaryFactor,
                "rotaryFactor must be between 1 and 13.");
        var pickDropsSeconds = NonNegative(settings, "pickDropsAfterFightSeconds");
        var timeout = RequiredInt(settings, "timeout");
        if (timeout < 1)
            throw new ArgumentOutOfRangeException("timeout", timeout, "timeout must be positive.");

        lock (_lock)
        {
            var root = LoadRoot();
            var config = LoadConfig<AutoFightConfig>(root, "autoFightConfig");
            config.StrategyName = strategyName;
            config.ActionSchedulerByCd = RequiredString(settings, "actionSchedulerByCd");
            config.FightFinishDetectEnabled = RequiredBool(settings, "fightFinishDetectEnabled");
            config.FinishDetectConfig.FastCheckEnabled = RequiredBool(settings, "fastCheckEnabled");
            config.FinishDetectConfig.FastCheckParams = RequiredString(settings, "fastCheckParams");
            config.FinishDetectConfig.RotateFindEnemyEnabled =
                RequiredBool(settings, "rotateFindEnemyEnabled");
            config.FinishDetectConfig.RotaryFactor = rotaryFactor;
            config.FinishDetectConfig.CheckBeforeBurst = RequiredBool(settings, "checkBeforeBurst");
            config.FinishDetectConfig.IsFirstCheck = RequiredBool(settings, "isFirstCheck");
            config.FinishDetectConfig.CheckEndDelay = RequiredString(settings, "checkEndDelay");
            config.FinishDetectConfig.BeforeDetectDelay = RequiredString(settings, "beforeDetectDelay");
            config.GuardianAvatar = guardianAvatar;
            config.GuardianCombatSkip = RequiredBool(settings, "guardianCombatSkip");
            config.BurstEnabled = RequiredBool(settings, "burstEnabled");
            config.GuardianAvatarHold = RequiredBool(settings, "guardianAvatarHold");
            config.PickDropsAfterFightEnabled = RequiredBool(settings, "pickDropsAfterFightEnabled");
            config.PickDropsAfterFightSeconds = pickDropsSeconds;
            config.KazuhaPickupEnabled = RequiredBool(settings, "kazuhaPickupEnabled");
            config.QinDoublePickUp = RequiredBool(settings, "qinDoublePickUp");
            config.ExpBasedPickupEnabled = RequiredBool(settings, "expBasedPickupEnabled");
            config.Timeout = timeout;
            config.SwimmingEnabled = RequiredBool(settings, "swimmingEnabled");
            root["autoFightConfig"] = JsonSerializer.SerializeToNode(config, ConfigJson.Options);
            SaveRoot(root);
            _autoFightConfigUpdated?.Invoke(config);
            return Describe(config);
        }
    }

    private object SaveAutoDomain(JObject settings)
    {
        var strategyName = RequiredString(settings, "strategyName");
        if (!StrategyOptions().Contains(strategyName, StringComparer.Ordinal))
            throw new ArgumentException($"Unknown AutoFight strategy: {strategyName}");
        var domainName = RequiredString(settings, "domainName");
        if (!string.IsNullOrEmpty(domainName) &&
            !MapLazyAssets.Get().DomainNameList.Contains(domainName, StringComparer.Ordinal))
            throw new ArgumentException($"Unknown domainName: {domainName}");
        var artifactStar = RequiredString(settings, "maxArtifactStar");
        if (artifactStar is not ("1" or "2" or "3" or "4"))
            throw new ArgumentException($"Unsupported maxArtifactStar: {artifactStar}");

        lock (_lock)
        {
            var root = LoadRoot();
            var config = LoadConfig<AutoDomainConfig>(root, "autoDomainConfig");
            config.PartyName = RequiredString(settings, "partyName");
            config.DomainName = domainName;
            config.SpecifyResinUse = RequiredBool(settings, "specifyResinUse");
            config.OriginalResinUseCount = NonNegative(settings, "originalResinUseCount");
            config.CondensedResinUseCount = NonNegative(settings, "condensedResinUseCount");
            config.TransientResinUseCount = NonNegative(settings, "transientResinUseCount");
            config.FragileResinUseCount = NonNegative(settings, "fragileResinUseCount");
            config.AutoArtifactSalvage = RequiredBool(settings, "autoArtifactSalvage");
            config.FightEndDelay = RequiredDouble(settings, "fightEndDelay");
            config.ShortMovement = RequiredBool(settings, "shortMovement");
            config.WalkToF = RequiredBool(settings, "walkToF");
            config.LeftRightMoveTimes = RequiredInt(settings, "leftRightMoveTimes");
            config.AutoEat = RequiredBool(settings, "autoEat");
            config.RewardRecognitionEnabled = RequiredBool(settings, "rewardRecognitionEnabled");
            config.ReviveRetryCount = RequiredInt(settings, "reviveRetryCount");

            var fightConfig = LoadConfig<AutoFightConfig>(root, "autoFightConfig");
            fightConfig.StrategyName = strategyName;
            var artifactConfig = LoadConfig<AutoArtifactSalvageConfig>(
                root, "autoArtifactSalvageConfig");
            artifactConfig.MaxArtifactStar = artifactStar;
            root["autoDomainConfig"] = JsonSerializer.SerializeToNode(config, ConfigJson.Options);
            root["autoFightConfig"] = JsonSerializer.SerializeToNode(fightConfig, ConfigJson.Options);
            root["autoArtifactSalvageConfig"] = JsonSerializer.SerializeToNode(
                artifactConfig, ConfigJson.Options);
            SaveRoot(root);
            _autoFightConfigUpdated?.Invoke(fightConfig);
            return Describe(config, fightConfig, artifactConfig);
        }
    }

    private object SaveAutoArtifactSalvage(JObject settings)
    {
        var maxArtifactStar = RequiredString(settings, "maxArtifactStar");
        if (maxArtifactStar is not ("1" or "2" or "3" or "4"))
            throw new ArgumentException($"Unsupported maxArtifactStar: {maxArtifactStar}");
        var maxNumToCheck = RequiredInt(settings, "maxNumToCheck");
        if (maxNumToCheck < 1)
            throw new ArgumentOutOfRangeException(
                "maxNumToCheck", maxNumToCheck, "maxNumToCheck must be positive.");
        var policyName = RequiredString(settings, "recognitionFailurePolicy");
        if (!Enum.TryParse<RecognitionFailurePolicy>(policyName, out var policy) ||
            !Enum.IsDefined(policy))
            throw new ArgumentException($"Unsupported recognitionFailurePolicy: {policyName}");

        lock (_lock)
        {
            var root = LoadRoot();
            var config = LoadConfig<AutoArtifactSalvageConfig>(
                root, "autoArtifactSalvageConfig");
            config.JavaScript = RequiredString(settings, "javaScript");
            config.ArtifactSetFilter = RequiredString(settings, "artifactSetFilter");
            config.MaxArtifactStar = maxArtifactStar;
            config.MaxNumToCheck = maxNumToCheck;
            config.RecognitionFailurePolicy = policy;
            root["autoArtifactSalvageConfig"] = JsonSerializer.SerializeToNode(
                config, ConfigJson.Options);
            SaveRoot(root);
            return Describe(config);
        }
    }

    private object SaveAutoLeyLineOutcrop(JObject settings)
    {
        var leyLineOutcropType = RequiredString(settings, "leyLineOutcropType");
        if (!LeyLineOutcropTypes.Contains(leyLineOutcropType, StringComparer.Ordinal))
            throw new ArgumentException($"Unsupported leyLineOutcropType: {leyLineOutcropType}");
        var country = RequiredString(settings, "country");
        if (!LeyLineOutcropCountries.Contains(country, StringComparer.Ordinal))
            throw new ArgumentException($"Unsupported country: {country}");
        var strategyName = RequiredString(settings, "strategyName");
        if (!string.IsNullOrEmpty(strategyName) &&
            !StrategyOptions().Contains(strategyName, StringComparer.Ordinal))
            throw new ArgumentException($"Unknown AutoFight strategy: {strategyName}");
        var seekEnemyRotaryFactor = RequiredInt(settings, "seekEnemyRotaryFactor");
        if (seekEnemyRotaryFactor is < 1 or > 13)
            throw new ArgumentOutOfRangeException(nameof(seekEnemyRotaryFactor));
        var seekEnemyIntervalSeconds = RequiredInt(settings, "seekEnemyIntervalSeconds");
        if (seekEnemyIntervalSeconds is < 1 or > 60)
            throw new ArgumentOutOfRangeException(nameof(seekEnemyIntervalSeconds));
        var scanDropsAfterRewardSeconds = RequiredInt(settings, "scanDropsAfterRewardSeconds");
        if (scanDropsAfterRewardSeconds is < 0 or > 60)
            throw new ArgumentOutOfRangeException(nameof(scanDropsAfterRewardSeconds));
        var count = RequiredInt(settings, "count");
        if (count is < 1 or > 999)
            throw new ArgumentOutOfRangeException(nameof(count));
        var timeout = RequiredInt(settings, "timeout");
        if (timeout is < 1 or > 9999)
            throw new ArgumentOutOfRangeException(nameof(timeout));

        lock (_lock)
        {
            var root = LoadRoot();
            var config = LoadConfig<AutoLeyLineOutcropConfig>(
                root, "autoLeyLineOutcropConfig");
            config.LeyLineOutcropType = leyLineOutcropType;
            config.Country = country;
            config.FightConfig ??= new AutoLeyLineOutcropFightConfig();
            config.FightConfig.StrategyName = strategyName;
            config.FightConfig.ActionSchedulerByCd =
                RequiredString(settings, "actionSchedulerByCd");
            config.FightConfig.SeekEnemyEnabled = RequiredBool(settings, "seekEnemyEnabled");
            config.FightConfig.SeekEnemyRotaryFactor = seekEnemyRotaryFactor;
            config.FightConfig.SeekEnemyIntervalSeconds = seekEnemyIntervalSeconds;
            config.FightConfig.KazuhaPickupEnabled =
                RequiredBool(settings, "kazuhaPickupEnabled");
            config.FightConfig.QinDoublePickUp = RequiredBool(settings, "qinDoublePickUp");
            config.ScanDropsAfterRewardEnabled =
                RequiredBool(settings, "scanDropsAfterRewardEnabled");
            config.ScanDropsAfterRewardSeconds = scanDropsAfterRewardSeconds;
            config.IsResinExhaustionMode = RequiredBool(settings, "isResinExhaustionMode");
            config.OpenModeCountMin = RequiredBool(settings, "openModeCountMin");
            config.Count = count;
            config.UseTransientResin = RequiredBool(settings, "useTransientResin");
            config.UseFragileResin = RequiredBool(settings, "useFragileResin");
            config.Team = RequiredString(settings, "team");
            config.FriendshipTeam = RequiredString(settings, "friendshipTeam");
            config.Timeout = timeout;
            config.FightConfig.Timeout = timeout;
            config.UseAdventurerHandbook = RequiredBool(settings, "useAdventurerHandbook");
            config.IsNotification = RequiredBool(settings, "isNotification");
            root["autoLeyLineOutcropConfig"] =
                JsonSerializer.SerializeToNode(config, ConfigJson.Options);
            SaveRoot(root);
            return Describe(config);
        }
    }

    private static object Describe(AutoCookConfig config) => new
    {
        name = "AutoCook",
        checkIntervalMs = config.CheckIntervalMs,
        stopTaskWhenRecoverButtonDetected = config.StopTaskWhenRecoverButtonDetected,
    };

    private object Describe(AutoFishingConfig config) => new
    {
        name = "AutoFishing",
        autoThrowRodTimeOut = config.AutoThrowRodTimeOut,
        wholeProcessTimeoutSeconds = config.WholeProcessTimeoutSeconds,
        fishingTimePolicy = config.FishingTimePolicy.ToString(),
        fishingTimePolicyOptions = new[]
        {
            new { value = FishingTimePolicy.All.ToString(), displayName = "全天" },
            new { value = FishingTimePolicy.Daytime.ToString(), displayName = "白天" },
            new { value = FishingTimePolicy.Nighttime.ToString(), displayName = "夜晚" },
            new { value = FishingTimePolicy.DontChange.ToString(), displayName = "不调" },
        },
        saveScreenshotOnKeyTick = AutoFishingSaveScreenshotOnKeyTick,
        torchDllFullPath = config.TorchDllFullPath,
        torchDllSupported = false,
    };

    private object Describe(AutoWoodConfig config) => new
    {
        name = "AutoWood",
        roundNum = AutoWoodRoundNum,
        dailyMaxCount = AutoWoodDailyMaxCount,
        useWonderlandRefresh = config.UseWonderlandRefresh,
        woodCountOcrEnabled = config.WoodCountOcrEnabled,
        afterZSleepDelay = config.AfterZSleepDelay,
    };

    private static readonly string[] MusicLevels = ["传说", "大师", "困难", "普通", "所有"];

    private static object Describe(AutoMusicGameConfig config) => new
    {
        name = "AutoMusicGame",
        mustCanorusLevel = config.MustCanorusLevel,
        musicLevel = string.IsNullOrEmpty(config.MusicLevel) ? MusicLevels[0] : config.MusicLevel,
        musicLevelOptions = MusicLevels,
    };

    private object Describe(AutoBossConfig config) => new
    {
        name = "AutoBoss",
        bossName = config.BossName,
        bossOptions = AutoBossData.SupportedBossNames,
        strategyName = config.StrategyName,
        strategyOptions = StrategyOptions(),
        teamName = config.TeamName,
        specifyRunCount = config.SpecifyRunCount,
        runCount = config.RunCount,
        useTransientResin = config.UseTransientResin,
        useFragileResin = config.UseFragileResin,
        returnToStatueAfterEachRound = config.ReturnToStatueAfterEachRound,
        rewardRecognitionEnabled = config.RewardRecognitionEnabled,
        reviveRetryCount = config.ReviveRetryCount,
    };

    private object Describe(AutoFightConfig config) => new
    {
        name = "AutoFight",
        strategyName = config.StrategyName,
        strategyOptions = StrategyOptions(),
        actionSchedulerByCd = config.ActionSchedulerByCd,
        fightFinishDetectEnabled = config.FightFinishDetectEnabled,
        fastCheckEnabled = config.FinishDetectConfig.FastCheckEnabled,
        fastCheckParams = config.FinishDetectConfig.FastCheckParams,
        rotateFindEnemyEnabled = config.FinishDetectConfig.RotateFindEnemyEnabled,
        rotaryFactor = config.FinishDetectConfig.RotaryFactor,
        checkBeforeBurst = config.FinishDetectConfig.CheckBeforeBurst,
        isFirstCheck = config.FinishDetectConfig.IsFirstCheck,
        checkEndDelay = config.FinishDetectConfig.CheckEndDelay,
        beforeDetectDelay = config.FinishDetectConfig.BeforeDetectDelay,
        guardianAvatar = config.GuardianAvatar,
        guardianAvatarOptions = new[] { "", "1", "2", "3", "4" },
        guardianCombatSkip = config.GuardianCombatSkip,
        burstEnabled = config.BurstEnabled,
        guardianAvatarHold = config.GuardianAvatarHold,
        pickDropsAfterFightEnabled = config.PickDropsAfterFightEnabled,
        pickDropsAfterFightSeconds = config.PickDropsAfterFightSeconds,
        kazuhaPickupEnabled = config.KazuhaPickupEnabled,
        qinDoublePickUp = config.QinDoublePickUp,
        expBasedPickupEnabled = config.ExpBasedPickupEnabled,
        timeout = config.Timeout,
        swimmingEnabled = config.SwimmingEnabled,
    };

    private object Describe(
        AutoDomainConfig config, AutoFightConfig fightConfig,
        AutoArtifactSalvageConfig artifactConfig) => new
    {
        name = "AutoDomain",
        strategyName = fightConfig.StrategyName,
        strategyOptions = StrategyOptions(),
        partyName = config.PartyName,
        domainName = config.DomainName,
        domainOptions = MapLazyAssets.Get().DomainNameList,
        specifyResinUse = config.SpecifyResinUse,
        originalResinUseCount = config.OriginalResinUseCount,
        condensedResinUseCount = config.CondensedResinUseCount,
        transientResinUseCount = config.TransientResinUseCount,
        fragileResinUseCount = config.FragileResinUseCount,
        autoArtifactSalvage = config.AutoArtifactSalvage,
        maxArtifactStar = artifactConfig.MaxArtifactStar,
        maxArtifactStarOptions = new[] { "4", "3", "2", "1" },
        fightEndDelay = config.FightEndDelay,
        shortMovement = config.ShortMovement,
        walkToF = config.WalkToF,
        leftRightMoveTimes = config.LeftRightMoveTimes,
        autoEat = config.AutoEat,
        rewardRecognitionEnabled = config.RewardRecognitionEnabled,
        reviveRetryCount = config.ReviveRetryCount,
    };

    private static object Describe(AutoArtifactSalvageConfig config) => new
    {
        name = "AutoArtifactSalvage",
        javaScript = config.JavaScript,
        artifactSetFilter = config.ArtifactSetFilter,
        maxArtifactStar = config.MaxArtifactStar,
        maxArtifactStarOptions = new[] { "4", "3", "2", "1" },
        maxNumToCheck = config.MaxNumToCheck,
        recognitionFailurePolicy = config.RecognitionFailurePolicy.ToString(),
        recognitionFailurePolicyOptions = new[]
        {
            new { value = RecognitionFailurePolicy.Skip.ToString(), displayName = "跳过" },
            new { value = RecognitionFailurePolicy.Abort.ToString(), displayName = "终止" },
        },
    };

    private static readonly string[] LeyLineOutcropTypes = ["启示之花", "藏金之花"];
    private static readonly string[] LeyLineOutcropCountries =
        ["蒙德", "璃月", "稻妻", "须弥", "枫丹", "纳塔", "挪德卡莱"];

    private object Describe(AutoLeyLineOutcropConfig config)
    {
        var fightConfig = config.FightConfig ?? new AutoLeyLineOutcropFightConfig();
        return new
        {
            name = "AutoLeyLineOutcrop",
            leyLineOutcropType = config.LeyLineOutcropType,
            leyLineOutcropTypeOptions = LeyLineOutcropTypes,
            country = config.Country,
            countryOptions = LeyLineOutcropCountries,
            strategyName = fightConfig.StrategyName,
            strategyOptions = StrategyOptions(),
            actionSchedulerByCd = fightConfig.ActionSchedulerByCd,
            seekEnemyEnabled = fightConfig.SeekEnemyEnabled,
            seekEnemyRotaryFactor = fightConfig.SeekEnemyRotaryFactor,
            seekEnemyIntervalSeconds = fightConfig.SeekEnemyIntervalSeconds,
            kazuhaPickupEnabled = fightConfig.KazuhaPickupEnabled,
            qinDoublePickUp = fightConfig.QinDoublePickUp,
            scanDropsAfterRewardEnabled = config.ScanDropsAfterRewardEnabled,
            scanDropsAfterRewardSeconds = config.ScanDropsAfterRewardSeconds,
            isResinExhaustionMode = config.IsResinExhaustionMode,
            openModeCountMin = config.OpenModeCountMin,
            count = config.Count,
            useTransientResin = config.UseTransientResin,
            useFragileResin = config.UseFragileResin,
            team = config.Team,
            friendshipTeam = config.FriendshipTeam,
            timeout = fightConfig.Timeout > 0 ? fightConfig.Timeout : config.Timeout,
            useAdventurerHandbook = config.UseAdventurerHandbook,
            isNotification = config.IsNotification,
        };
    }

    private string[] StrategyOptions()
    {
        var folder = Path.Combine(layout.UserPath, "AutoFight");
        Directory.CreateDirectory(folder);
        return
        [
            "根据队伍自动选择",
            .. Directory.EnumerateFiles(folder, "*.*", SearchOption.AllDirectories)
                .Where(path => path.EndsWith(".txt", StringComparison.OrdinalIgnoreCase) ||
                               path.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
                .Select(path => Path.ChangeExtension(Path.GetRelativePath(folder, path), null))
                .Order(StringComparer.Ordinal),
        ];
    }

    private static T LoadConfig<T>(JsonObject root, string propertyName) where T : class, new() =>
        root[propertyName]?.Deserialize<T>(ConfigJson.Options) ?? new T();

    private void SaveConfig<T>(string propertyName, T config)
    {
        var root = LoadRoot();
        root[propertyName] = JsonSerializer.SerializeToNode(config, ConfigJson.Options);
        SaveRoot(root);
    }

    private static int RequiredInt(JObject settings, string name) =>
        settings.Value<int?>(name) ?? throw new ArgumentException($"{name} is required.");

    private static bool RequiredBool(JObject settings, string name) =>
        settings.Value<bool?>(name) ?? throw new ArgumentException($"{name} is required.");

    private static string RequiredString(JObject settings, string name) =>
        settings.Value<string>(name) ?? throw new ArgumentException($"{name} is required.");

    private static double RequiredDouble(JObject settings, string name) =>
        settings.Value<double?>(name) ?? throw new ArgumentException($"{name} is required.");

    private static int NonNegative(JObject settings, string name)
    {
        var value = RequiredInt(settings, name);
        return value >= 0 ? value : throw new ArgumentOutOfRangeException(name);
    }

    private static CapabilityUnavailableException Unavailable(string name) => new(
        $"solo task settings '{name}' are not composed in the macOS Core yet.");

    private JsonObject LoadRoot()
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return [];
        return JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip,
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
    }

    private void SaveRoot(JsonObject root)
    {
        Directory.CreateDirectory(layout.UserPath);
        var path = Path.Combine(layout.UserPath, "config.json");
        var temporaryPath = path + ".tmp";
        File.WriteAllText(temporaryPath, root.ToJsonString(ConfigJson.Options));
        File.Move(temporaryPath, path, true);
    }
}
