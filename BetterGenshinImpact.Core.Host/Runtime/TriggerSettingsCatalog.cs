using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.AutoEat;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.MapMask;
using BetterGenshinImpact.GameTask.QuickTeleport;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class TriggerSettingsCatalog(RuntimeLayout layout)
{
    private readonly object _lock = new();
    private Action<AutoEatConfig>? _autoEatUpdated;
    private Action<AutoPickConfig>? _autoPickUpdated;
    private Action? _autoPickListsUpdated;
    private Action<QuickTeleportConfig>? _quickTeleportUpdated;
    private Action<MapMaskConfig>? _mapMaskUpdated;

    public void AttachAutoEatUpdated(Action<AutoEatConfig> callback) =>
        _autoEatUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public void AttachAutoPickUpdated(Action<AutoPickConfig> callback) =>
        _autoPickUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public void AttachAutoPickListsUpdated(Action callback) =>
        _autoPickListsUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public void AttachQuickTeleportUpdated(Action<QuickTeleportConfig> callback) =>
        _quickTeleportUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public void AttachMapMaskUpdated(Action<MapMaskConfig> callback) =>
        _mapMaskUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public bool IsAvailable(string name) =>
        name is "AutoPick" or "AutoFish" or "AutoEat" or "QuickTeleport" or "MapMask";

    public object Get(string name)
    {
        lock (_lock)
        {
            var root = LoadRoot();
            return name switch
            {
                "AutoPick" => Describe(LoadConfig<AutoPickConfig>(root, "autoPickConfig")),
                "AutoFish" => new { },
                "AutoEat" => Describe(LoadConfig<AutoEatConfig>(root, "autoEatConfig")),
                "QuickTeleport" => Describe(
                    LoadConfig<QuickTeleportConfig>(root, "quickTeleportConfig")),
                "MapMask" => Describe(LoadConfig<MapMaskConfig>(root, "mapMaskConfig")),
                _ => throw Unavailable(name),
            };
        }
    }

    public object Save(string name, JObject settings) => name switch
    {
        "AutoPick" => SaveAutoPick(settings),
        "AutoEat" => SaveAutoEat(settings),
        "QuickTeleport" => SaveQuickTeleport(settings),
        "MapMask" => SaveMapMask(settings),
        _ => throw Unavailable(name),
    };

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
            exactBlackList = ReadUserText("pick_black_lists.txt"),
            fuzzyBlackList = ReadUserText("pick_fuzzy_black_lists.txt"),
            whiteListEnabled = config.WhiteListEnabled,
            whiteList = ReadUserText("pick_white_lists.txt"),
            pickKey = config.PickKey,
            pickKeyOptions,
        };
    }

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
        root[propertyName] = JsonSerializer.SerializeToNode(config, ConfigJson.Options);
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
