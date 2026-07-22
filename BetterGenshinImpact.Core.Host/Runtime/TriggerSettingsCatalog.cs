using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.AutoEat;
using BetterGenshinImpact.GameTask.MapMask;
using BetterGenshinImpact.GameTask.QuickTeleport;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class TriggerSettingsCatalog(RuntimeLayout layout)
{
    private readonly object _lock = new();
    private Action<AutoEatConfig>? _autoEatUpdated;
    private Action<QuickTeleportConfig>? _quickTeleportUpdated;
    private Action<MapMaskConfig>? _mapMaskUpdated;

    public void AttachAutoEatUpdated(Action<AutoEatConfig> callback) =>
        _autoEatUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public void AttachQuickTeleportUpdated(Action<QuickTeleportConfig> callback) =>
        _quickTeleportUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public void AttachMapMaskUpdated(Action<MapMaskConfig> callback) =>
        _mapMaskUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public bool IsAvailable(string name) => name is "AutoFish" or "AutoEat" or "QuickTeleport" or "MapMask";

    public object Get(string name)
    {
        lock (_lock)
        {
            var root = LoadRoot();
            return name switch
            {
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
        "AutoEat" => SaveAutoEat(settings),
        "QuickTeleport" => SaveQuickTeleport(settings),
        "MapMask" => SaveMapMask(settings),
        _ => throw Unavailable(name),
    };

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

    private static object Describe(AutoEatConfig config) => new
    {
        checkInterval = config.CheckInterval,
        eatInterval = config.EatInterval,
    };

    private static object Describe(QuickTeleportConfig config) => new
    {
        teleportListClickDelay = config.TeleportListClickDelay,
        waitTeleportPanelDelay = config.WaitTeleportPanelDelay,
        hotkeyTpEnabled = config.HotkeyTpEnabled,
    };

    private static object Describe(MapMaskConfig config) => new
    {
        miniMapMaskEnabled = config.MiniMapMaskEnabled,
    };

    private static int RequiredNonNegative(JObject settings, string name)
    {
        var value = settings.Value<int?>(name) ?? throw new ArgumentException($"{name} is required.");
        return value >= 0 ? value : throw new ArgumentOutOfRangeException(name);
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
