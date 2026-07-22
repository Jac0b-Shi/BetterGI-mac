using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.AutoEat;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.AutoSkip.Assets;
using BetterGenshinImpact.GameTask.MapMask;
using BetterGenshinImpact.GameTask.QuickTeleport;
using BetterGenshinImpact.GameTask.SkillCd;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class TriggerSettingsCatalog(RuntimeLayout layout)
{
    private readonly object _lock = new();
    private Action<AutoEatConfig>? _autoEatUpdated;
    private Action<AutoPickConfig>? _autoPickUpdated;
    private Action? _autoPickListsUpdated;
    private Action<AutoSkipConfig>? _autoSkipUpdated;
    private Action<QuickTeleportConfig>? _quickTeleportUpdated;
    private Action<MapMaskConfig>? _mapMaskUpdated;
    private Action<SkillCdConfig>? _skillCdUpdated;

    public void AttachAutoEatUpdated(Action<AutoEatConfig> callback) =>
        _autoEatUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public void AttachAutoPickUpdated(Action<AutoPickConfig> callback) =>
        _autoPickUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public void AttachAutoPickListsUpdated(Action callback) =>
        _autoPickListsUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public void AttachAutoSkipUpdated(Action<AutoSkipConfig> callback) =>
        _autoSkipUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public void AttachQuickTeleportUpdated(Action<QuickTeleportConfig> callback) =>
        _quickTeleportUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public void AttachMapMaskUpdated(Action<MapMaskConfig> callback) =>
        _mapMaskUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public void AttachSkillCdUpdated(Action<SkillCdConfig> callback) =>
        _skillCdUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public bool IsAvailable(string name) =>
        name is "AutoPick" or "AutoSkip" or "AutoFish" or "AutoEat" or "QuickTeleport" or "MapMask" or "SkillCd";

    public object Get(string name)
    {
        lock (_lock)
        {
            var root = LoadRoot();
            return name switch
            {
                "AutoPick" => Describe(LoadConfig<AutoPickConfig>(root, "autoPickConfig")),
                "AutoSkip" => Describe(LoadConfig<AutoSkipConfig>(root, "autoSkipConfig")),
                "AutoFish" => new { },
                "AutoEat" => Describe(LoadConfig<AutoEatConfig>(root, "autoEatConfig")),
                "QuickTeleport" => Describe(
                    LoadConfig<QuickTeleportConfig>(root, "quickTeleportConfig")),
                "MapMask" => Describe(LoadConfig<MapMaskConfig>(root, "mapMaskConfig")),
                "SkillCd" => Describe(LoadConfig<SkillCdConfig>(root, "skillCdConfig")),
                _ => throw Unavailable(name),
            };
        }
    }

    public object Save(string name, JObject settings) => name switch
    {
        "AutoPick" => SaveAutoPick(settings),
        "AutoSkip" => SaveAutoSkip(settings),
        "AutoEat" => SaveAutoEat(settings),
        "QuickTeleport" => SaveQuickTeleport(settings),
        "MapMask" => SaveMapMask(settings),
        "SkillCd" => SaveSkillCd(settings),
        _ => throw Unavailable(name),
    };

    private object SaveSkillCd(JObject settings)
    {
        var triggerOnSkillUse = RequiredBoolean(settings, "triggerOnSkillUse");
        var hideWhenZero = RequiredBoolean(settings, "hideWhenZero");
        var pX = RequiredDoubleRange(settings, "pX", 0, 1920);
        var pY = RequiredDoubleRange(settings, "pY", 0, 1080);
        var gap = RequiredDoubleRange(settings, "gap", 0, 200);
        var scale = RequiredDoubleRange(settings, "scale", 0, 10);
        var textNormalColor = RequiredHexColor(settings, "textNormalColor");
        var backgroundNormalColor = RequiredHexColor(settings, "backgroundNormalColor");
        var textReadyColor = RequiredHexColor(settings, "textReadyColor");
        var backgroundReadyColor = RequiredHexColor(settings, "backgroundReadyColor");
        var customCdList = settings["customCdList"] is JArray rules
            ? rules.OfType<JObject>()
                .Select(rule => new SkillCdRule
                {
                    RoleName = RequiredString(rule, "roleName").Trim(),
                    CdValueText = RequiredString(rule, "cdValueText").Trim(),
                })
                .Where(rule => !string.IsNullOrWhiteSpace(rule.RoleName))
                .ToList()
            : throw new ArgumentException("customCdList is required.");

        lock (_lock)
        {
            var root = LoadRoot();
            var config = LoadConfig<SkillCdConfig>(root, "skillCdConfig");
            config.CustomCdList = customCdList;
            config.TriggerOnSkillUse = triggerOnSkillUse;
            config.HideWhenZero = hideWhenZero;
            config.PX = pX;
            config.PY = pY;
            config.Gap = gap;
            config.Scale = scale;
            config.TextNormalColor = textNormalColor;
            config.BackgroundNormalColor = backgroundNormalColor;
            config.TextReadyColor = textReadyColor;
            config.BackgroundReadyColor = backgroundReadyColor;
            SaveConfig(root, "skillCdConfig", config);
            _skillCdUpdated?.Invoke(config);
            return Describe(config);
        }
    }

    private object SaveAutoSkip(JObject settings)
    {
        var quicklySkipConversationsEnabled = RequiredBoolean(settings, "quicklySkipConversationsEnabled");
        var afterChooseOptionSleepDelay = RequiredNonNegative(settings, "afterChooseOptionSleepDelay");
        var autoWaitDialogueOptionVoiceEnabled = RequiredBoolean(settings, "autoWaitDialogueOptionVoiceEnabled");
        var dialogueOptionVoiceMaxWaitSeconds = RequiredRange(
            settings, "dialogueOptionVoiceMaxWaitSeconds", 0, 600);
        var beforeClickConfirmDelay = RequiredNonNegative(settings, "beforeClickConfirmDelay");
        var autoGetDailyRewardsEnabled = RequiredBoolean(settings, "autoGetDailyRewardsEnabled");
        var autoReExploreEnabled = RequiredBoolean(settings, "autoReExploreEnabled");
        var clickChatOption = RequiredOption(settings, "clickChatOption", ClickChatOptions);
        var customPriorityOptionsEnabled = RequiredBoolean(settings, "customPriorityOptionsEnabled");
        var customPriorityOptions = RequiredString(settings, "customPriorityOptions");
        var autoHangoutEventEnabled = RequiredBoolean(settings, "autoHangoutEventEnabled");
        var autoHangoutEndChoose = RequiredString(settings, "autoHangoutEndChoose");
        var hangoutOptions = HangoutConfig.Instance.HangoutOptionsTitleList;
        if (autoHangoutEndChoose.Length > 0 && !hangoutOptions.Contains(autoHangoutEndChoose))
            throw new ArgumentException("autoHangoutEndChoose has an unsupported value.");
        var autoHangoutChooseOptionSleepDelay = RequiredNonNegative(
            settings, "autoHangoutChooseOptionSleepDelay");
        var autoHangoutPressSkipEnabled = RequiredBoolean(settings, "autoHangoutPressSkipEnabled");
        var submitGoodsEnabled = RequiredBoolean(settings, "submitGoodsEnabled");
        var closePopupPagedEnabled = RequiredBoolean(settings, "closePopupPagedEnabled");

        lock (_lock)
        {
            var root = LoadRoot();
            var config = LoadConfig<AutoSkipConfig>(root, "autoSkipConfig");
            config.QuicklySkipConversationsEnabled = quicklySkipConversationsEnabled;
            config.AfterChooseOptionSleepDelay = afterChooseOptionSleepDelay;
            config.AutoWaitDialogueOptionVoiceEnabled = autoWaitDialogueOptionVoiceEnabled;
            config.DialogueOptionVoiceMaxWaitSeconds = dialogueOptionVoiceMaxWaitSeconds;
            config.BeforeClickConfirmDelay = beforeClickConfirmDelay;
            config.AutoGetDailyRewardsEnabled = autoGetDailyRewardsEnabled;
            config.AutoReExploreEnabled = autoReExploreEnabled;
            config.ClickChatOption = clickChatOption;
            config.CustomPriorityOptionsEnabled = customPriorityOptionsEnabled;
            config.CustomPriorityOptions = customPriorityOptions;
            config.AutoHangoutEventEnabled = autoHangoutEventEnabled;
            config.AutoHangoutEndChoose = autoHangoutEndChoose;
            config.AutoHangoutChooseOptionSleepDelay = autoHangoutChooseOptionSleepDelay;
            config.AutoHangoutPressSkipEnabled = autoHangoutPressSkipEnabled;
            config.SubmitGoodsEnabled = submitGoodsEnabled;
            config.ClosePopupPagedEnabled = closePopupPagedEnabled;
            SaveConfig(root, "autoSkipConfig", config);
            _autoSkipUpdated?.Invoke(config);
            return Describe(config);
        }
    }

    private object SaveAutoPick(JObject settings)
    {
        var ocrEngine = RequiredOption(settings, "ocrEngine",
            nameof(PickOcrEngineEnum.Paddle), nameof(PickOcrEngineEnum.Yap));
        var pickKey = settings.Value<string>("pickKey")?.Trim().ToUpperInvariant()
            ?? throw new ArgumentException("pickKey is required.");
        if (pickKey.Length != 1 || pickKey[0] is < 'A' or > 'Z')
            throw new ArgumentException("pickKey must be one uppercase Latin letter.");
        var blackListEnabled = RequiredBoolean(settings, "blackListEnabled");
        var whiteListEnabled = RequiredBoolean(settings, "whiteListEnabled");
        var fastModeEnabled = RequiredBoolean(settings, "fastModeEnabled");
        var exactBlackList = RequiredString(settings, "exactBlackList");
        var fuzzyBlackList = RequiredString(settings, "fuzzyBlackList");
        var whiteList = RequiredString(settings, "whiteList");

        lock (_lock)
        {
            var root = LoadRoot();
            var config = LoadConfig<AutoPickConfig>(root, "autoPickConfig");
            config.OcrEngine = ocrEngine;
            config.PickKey = pickKey;
            config.BlackListEnabled = blackListEnabled;
            config.WhiteListEnabled = whiteListEnabled;
            config.FastModeEnabled = fastModeEnabled;
            SaveConfig(root, "autoPickConfig", config);
            WriteUserText("pick_black_lists.txt", exactBlackList);
            WriteUserText("pick_fuzzy_black_lists.txt", fuzzyBlackList);
            WriteUserText("pick_white_lists.txt", whiteList);
            _autoPickUpdated?.Invoke(config);
            _autoPickListsUpdated?.Invoke();
            return Describe(config);
        }
    }

    public void SaveEnabled(string name, bool enabled)
    {
        var propertyName = name switch
        {
            "AutoPick" => "autoPickConfig",
            "AutoSkip" => "autoSkipConfig",
            "AutoFish" => "autoFishingConfig",
            "AutoEat" => "autoEatConfig",
            "QuickTeleport" => "quickTeleportConfig",
            "MapMask" => "mapMaskConfig",
            "SkillCd" => "skillCdConfig",
            _ => null,
        };
        if (propertyName is null) return;

        lock (_lock)
        {
            var root = LoadRoot();
            var config = root[propertyName] as JsonObject ?? [];
            config["enabled"] = enabled;
            root[propertyName] = config;
            SaveRoot(root);
        }
    }

    public bool GetAutoHangoutEventEnabled()
    {
        lock (_lock)
        {
            return LoadConfig<AutoSkipConfig>(LoadRoot(), "autoSkipConfig")
                .AutoHangoutEventEnabled;
        }
    }

    private object SaveAutoEat(JObject settings)
    {
        var checkInterval = RequiredNonNegative(settings, "checkInterval");
        var eatInterval = RequiredNonNegative(settings, "eatInterval");
        lock (_lock)
        {
            var root = LoadRoot();
            var config = LoadConfig<AutoEatConfig>(root, "autoEatConfig");
            config.CheckInterval = checkInterval;
            config.EatInterval = eatInterval;
            SaveConfig(root, "autoEatConfig", config);
            _autoEatUpdated?.Invoke(config);
            return Describe(config);
        }
    }

    private object SaveQuickTeleport(JObject settings)
    {
        var listDelay = RequiredNonNegative(settings, "teleportListClickDelay");
        var panelDelay = RequiredNonNegative(settings, "waitTeleportPanelDelay");
        var hotkeyEnabled = settings.Value<bool?>("hotkeyTpEnabled")
            ?? throw new ArgumentException("hotkeyTpEnabled is required.");
        lock (_lock)
        {
            var root = LoadRoot();
            var config = LoadConfig<QuickTeleportConfig>(root, "quickTeleportConfig");
            config.TeleportListClickDelay = listDelay;
            config.WaitTeleportPanelDelay = panelDelay;
            config.HotkeyTpEnabled = hotkeyEnabled;
            SaveConfig(root, "quickTeleportConfig", config);
            _quickTeleportUpdated?.Invoke(config);
            return Describe(config);
        }
    }

    private object SaveMapMask(JObject settings)
    {
        var miniMapMaskEnabled = settings.Value<bool?>("miniMapMaskEnabled")
            ?? throw new ArgumentException("miniMapMaskEnabled is required.");
        lock (_lock)
        {
            var root = LoadRoot();
            var config = LoadConfig<MapMaskConfig>(root, "mapMaskConfig");
            config.MiniMapMaskEnabled = miniMapMaskEnabled;
            SaveConfig(root, "mapMaskConfig", config);
            _mapMaskUpdated?.Invoke(config);
            return Describe(config);
        }
    }

    public object GetMapMaskPickerSettings()
    {
        lock (_lock)
        {
            return DescribeMapMaskPicker(LoadConfig<MapMaskConfig>(LoadRoot(), "mapMaskConfig"));
        }
    }

    public object SaveMapMaskPickerSettings(JObject settings)
    {
        var providerText = RequiredOption(settings, "mapPointApiProvider",
            nameof(MapPointApiProvider.MihoyoMap),
            nameof(MapPointApiProvider.KongyingTavern),
            nameof(MapPointApiProvider.HoYoLab));
        var language = settings.Value<string>("hoYoLabLanguage")?.Trim().ToLowerInvariant()
            ?? throw new ArgumentException("hoYoLabLanguage is required.");
        if (language is not (MapMaskConfig.HoYoLabLanguageEnUs or
            MapMaskConfig.HoYoLabLanguagePtPt or MapMaskConfig.HoYoLabLanguageEsEs))
        {
            throw new ArgumentException("Unsupported HoYoLab language.");
        }

        lock (_lock)
        {
            var root = LoadRoot();
            var config = LoadConfig<MapMaskConfig>(root, "mapMaskConfig");
            config.MapPointApiProvider = Enum.Parse<MapPointApiProvider>(providerText);
            config.HoYoLabLanguage = language;
            SaveConfig(root, "mapMaskConfig", config);
            _mapMaskUpdated?.Invoke(config);
            return DescribeMapMaskPicker(config);
        }
    }

    private static object Describe(AutoEatConfig config) => new
    {
        checkInterval = config.CheckInterval,
        eatInterval = config.EatInterval,
    };

    private object Describe(AutoPickConfig config)
    {
        var pickKeyOptions = new List<string> { "F", "E", "G" };
        if (config.PickKey.Length == 1 && char.IsUpper(config.PickKey[0])
            && !pickKeyOptions.Contains(config.PickKey))
            pickKeyOptions.Add(config.PickKey);
        return new
        {
            ocrEngine = config.OcrEngine,
            ocrEngineOptions = new[] { nameof(PickOcrEngineEnum.Paddle), nameof(PickOcrEngineEnum.Yap) },
            blackListEnabled = config.BlackListEnabled,
            fastModeEnabled = config.FastModeEnabled,
            exactBlackList = ReadUserText("pick_black_lists.txt"),
            fuzzyBlackList = ReadUserText("pick_fuzzy_black_lists.txt"),
            whiteListEnabled = config.WhiteListEnabled,
            whiteList = ReadUserText("pick_white_lists.txt"),
            pickKey = config.PickKey,
            pickKeyOptions,
        };
    }

    private static readonly string[] ClickChatOptions =
    [
        "优先选择第一个选项",
        "随机选择选项",
        "优先选择最后一个选项",
        "不选择选项",
    ];

    private static object Describe(AutoSkipConfig config) => new
    {
        quicklySkipConversationsEnabled = config.QuicklySkipConversationsEnabled,
        afterChooseOptionSleepDelay = config.AfterChooseOptionSleepDelay,
        autoWaitDialogueOptionVoiceEnabled = config.AutoWaitDialogueOptionVoiceEnabled,
        dialogueOptionVoiceMaxWaitSeconds = config.DialogueOptionVoiceMaxWaitSeconds,
        beforeClickConfirmDelay = config.BeforeClickConfirmDelay,
        autoGetDailyRewardsEnabled = config.AutoGetDailyRewardsEnabled,
        autoReExploreEnabled = config.AutoReExploreEnabled,
        clickChatOption = config.ClickChatOption,
        clickChatOptionOptions = ClickChatOptions,
        customPriorityOptionsEnabled = config.CustomPriorityOptionsEnabled,
        customPriorityOptions = config.CustomPriorityOptions,
        autoHangoutEventEnabled = config.AutoHangoutEventEnabled,
        autoHangoutEndChoose = config.AutoHangoutEndChoose,
        autoHangoutEndChooseOptions = HangoutConfig.Instance.HangoutOptionsTitleList,
        autoHangoutChooseOptionSleepDelay = config.AutoHangoutChooseOptionSleepDelay,
        autoHangoutPressSkipEnabled = config.AutoHangoutPressSkipEnabled,
        submitGoodsEnabled = config.SubmitGoodsEnabled,
        closePopupPagedEnabled = config.ClosePopupPagedEnabled,
    };

    private static object Describe(QuickTeleportConfig config) => new
    {
        teleportListClickDelay = config.TeleportListClickDelay,
        waitTeleportPanelDelay = config.WaitTeleportPanelDelay,
        hotkeyTpEnabled = config.HotkeyTpEnabled,
    };

    private static object Describe(MapMaskConfig config) => new
    {
        miniMapMaskEnabled = config.MiniMapMaskEnabled
    };

    private static object Describe(SkillCdConfig config) => new
    {
        customCdList = (config.CustomCdList ?? []).Select(rule => new
        {
            roleName = rule.RoleName ?? string.Empty,
            cdValueText = rule.CdValueText ?? string.Empty,
        }),
        triggerOnSkillUse = config.TriggerOnSkillUse,
        hideWhenZero = config.HideWhenZero,
        pX = config.PX,
        pY = config.PY,
        gap = config.Gap,
        scale = config.Scale,
        textNormalColor = config.TextNormalColor,
        backgroundNormalColor = config.BackgroundNormalColor,
        textReadyColor = config.TextReadyColor,
        backgroundReadyColor = config.BackgroundReadyColor,
    };

    private static object DescribeMapMaskPicker(MapMaskConfig config) => new
    {
        mapPointApiProvider = config.MapPointApiProvider.ToString(),
        mapPointApiProviderOptions = Enum.GetNames<MapPointApiProvider>(),
        hoYoLabLanguage = config.HoYoLabLanguage,
        hoYoLabLanguageOptions = new[]
        {
            MapMaskConfig.HoYoLabLanguageEnUs,
            MapMaskConfig.HoYoLabLanguagePtPt,
            MapMaskConfig.HoYoLabLanguageEsEs
        }
    };

    private static int RequiredNonNegative(JObject settings, string name)
    {
        var value = settings.Value<int?>(name) ?? throw new ArgumentException($"{name} is required.");
        return value >= 0 ? value : throw new ArgumentOutOfRangeException(name);
    }

    private static int RequiredRange(JObject settings, string name, int minimum, int maximum)
    {
        var value = settings.Value<int?>(name) ?? throw new ArgumentException($"{name} is required.");
        return value >= minimum && value <= maximum
            ? value
            : throw new ArgumentOutOfRangeException(name);
    }

    private static double RequiredDoubleRange(JObject settings, string name, double minimum, double maximum)
    {
        var value = settings.Value<double?>(name) ?? throw new ArgumentException($"{name} is required.");
        return double.IsFinite(value) && value >= minimum && value <= maximum
            ? value
            : throw new ArgumentOutOfRangeException(name);
    }

    private static string RequiredHexColor(JObject settings, string name)
    {
        var value = RequiredString(settings, name).Trim().ToUpperInvariant();
        var digits = value.StartsWith('#') ? value[1..] : value;
        if (digits.Length is not (6 or 8) || !digits.All(Uri.IsHexDigit))
            throw new ArgumentException($"{name} must use #RRGGBB or #RRGGBBAA format.");
        return $"#{digits}";
    }

    private static bool RequiredBoolean(JObject settings, string name) =>
        settings.Value<bool?>(name) ?? throw new ArgumentException($"{name} is required.");

    private static string RequiredString(JObject settings, string name) =>
        settings.Value<string>(name) ?? throw new ArgumentException($"{name} is required.");

    private static string RequiredOption(JObject settings, string name, params string[] options)
    {
        var value = RequiredString(settings, name);
        return options.Contains(value, StringComparer.Ordinal)
            ? value
            : throw new ArgumentException($"{name} has an unsupported value '{value}'.");
    }

    private string ReadUserText(string fileName)
    {
        var path = Path.Combine(layout.UserPath, fileName);
        return File.Exists(path) ? File.ReadAllText(path) : string.Empty;
    }

    private void WriteUserText(string fileName, string content)
    {
        Directory.CreateDirectory(layout.UserPath);
        var path = Path.Combine(layout.UserPath, fileName);
        var temporaryPath = path + ".tmp";
        File.WriteAllText(temporaryPath, content);
        File.Move(temporaryPath, path, true);
    }

    private static T LoadConfig<T>(JsonObject root, string propertyName) where T : class, new() =>
        root[propertyName]?.Deserialize<T>(ConfigJson.Options) ?? new T();

    private void SaveConfig<T>(JsonObject root, string propertyName, T config)
    {
        var serialized = JsonSerializer.SerializeToNode(config, ConfigJson.Options) as JsonObject
            ?? throw new InvalidDataException($"{propertyName} did not serialize to an object.");
        var destination = root[propertyName] as JsonObject ?? [];
        foreach (var property in serialized)
            destination[property.Key] = property.Value?.DeepClone();
        root[propertyName] = destination;
        SaveRoot(root);
    }

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

    private static CapabilityUnavailableException Unavailable(string name) => new(
        $"trigger settings '{name}' are not composed in the macOS Core yet.");
}
