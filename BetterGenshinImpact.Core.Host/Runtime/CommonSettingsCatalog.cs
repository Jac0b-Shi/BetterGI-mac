using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class CommonSettingsCatalog(RuntimeLayout layout)
{
    private static readonly string[] AdventurersGuildCountries =
        ["无", "枫丹", "稻妻", "璃月", "蒙德"];
    private static readonly int[] ServerTimeZoneOffsets = [8, 1, -5];
    private readonly object _lock = new();
    private Action<OtherConfig>? _otherConfigUpdated;

    public void AttachOtherConfigUpdated(Action<OtherConfig> callback) =>
        _otherConfigUpdated += callback ?? throw new ArgumentNullException(nameof(callback));

    public OtherConfig GetOtherConfig()
    {
        lock (_lock)
            return LoadOtherConfig(LoadRoot());
    }

    public object Get()
    {
        lock (_lock)
        {
            return Describe(LoadRoot());
        }
    }

    public object Save(JObject settings)
    {
        lock (_lock)
        {
            var root = LoadRoot();
            var common = root["commonConfig"] as JsonObject ?? [];
            common["screenshotEnabled"] = RequiredBool(settings, "screenshotEnabled");
            common["screenshotUidCoverEnabled"] =
                RequiredBool(settings, "screenshotUidCoverEnabled");
            root["commonConfig"] = common;
            var other = root["otherConfig"] as JsonObject ?? [];
            other["autoFetchDispatchAdventurersGuildCountry"] =
                RequiredOption(settings, "autoFetchDispatchCountry", AdventurersGuildCountries);
            var serverTimeZoneOffsetHours = RequiredInt(settings, "serverTimeZoneOffsetHours");
            if (!ServerTimeZoneOffsets.Contains(serverTimeZoneOffsetHours))
                throw new ArgumentException(
                    $"Unsupported server time zone offset: {serverTimeZoneOffsetHours}.");
            other["serverTimeZoneOffset"] = JsonSerializer.SerializeToNode(
                TimeSpan.FromHours(serverTimeZoneOffsetHours), ConfigJson.Options);

            var autoRestart = other["autoRestartConfig"] as JsonObject ?? [];
            autoRestart["enabled"] = RequiredBool(settings, "autoRestartEnabled");
            autoRestart["failureCount"] = RequiredInt(settings, "autoRestartFailureCount");
            autoRestart["restartGameTogether"] =
                RequiredBool(settings, "autoRestartGameTogether");
            autoRestart["isFightFailureExceptional"] =
                RequiredBool(settings, "fightFailureExceptional");
            autoRestart["isPathingFailureExceptional"] =
                RequiredBool(settings, "pathingFailureExceptional");
            other["autoRestartConfig"] = autoRestart;

            var farmingPlan = other["farmingPlanConfig"] as JsonObject ?? [];
            farmingPlan["enabled"] = RequiredBool(settings, "farmingPlanEnabled");
            farmingPlan["dailyEliteCap"] = RequiredInt(settings, "farmingDailyEliteCap");
            farmingPlan["dailyMobCap"] = RequiredInt(settings, "farmingDailyMobCap");
            var miyousheData = farmingPlan["miyousheDataConfig"] as JsonObject ?? [];
            miyousheData["enabled"] = RequiredBool(settings, "miyousheDataEnabled");
            miyousheData["dailyEliteCap"] =
                RequiredInt(settings, "miyousheDailyEliteCap");
            miyousheData["dailyMobCap"] =
                RequiredInt(settings, "miyousheDailyMobCap");
            farmingPlan["miyousheDataConfig"] = miyousheData;
            other["farmingPlanConfig"] = farmingPlan;

            var miyoushe = other["miyousheConfig"] as JsonObject ?? [];
            miyoushe["cookie"] = RequiredString(settings, "miyousheCookie");
            miyoushe["logSyncCookie"] = RequiredBool(settings, "miyousheLogSyncCookie");
            other["miyousheConfig"] = miyoushe;
            root["otherConfig"] = other;
            SaveRoot(root);
            var savedOtherConfig = LoadOtherConfig(root);
            _otherConfigUpdated?.Invoke(savedOtherConfig);
            return Describe(root);
        }
    }

    internal static bool ScreenshotEnabled(JsonObject root) =>
        root["commonConfig"]?["screenshotEnabled"]?.GetValue<bool>() ?? false;

    private static object Describe(JsonObject root)
    {
        var other = LoadOtherConfig(root);
        return new
        {
            screenshotEnabled = ScreenshotEnabled(root),
            screenshotUidCoverEnabled =
                root["commonConfig"]?["screenshotUidCoverEnabled"]?.GetValue<bool>() ?? true,
            autoFetchDispatchCountry = other.AutoFetchDispatchAdventurersGuildCountry,
            autoFetchDispatchCountryOptions = AdventurersGuildCountries,
            serverTimeZoneOffsetHours = (int)other.ServerTimeZoneOffset.TotalHours,
            serverTimeZoneOffsetOptions = ServerTimeZoneOffsets,
            autoRestartEnabled = other.AutoRestartConfig.Enabled,
            autoRestartFailureCount = other.AutoRestartConfig.FailureCount,
            autoRestartGameTogether = other.AutoRestartConfig.RestartGameTogether,
            fightFailureExceptional = other.AutoRestartConfig.IsFightFailureExceptional,
            pathingFailureExceptional = other.AutoRestartConfig.IsPathingFailureExceptional,
            farmingPlanEnabled = other.FarmingPlanConfig.Enabled,
            farmingDailyEliteCap = other.FarmingPlanConfig.DailyEliteCap,
            farmingDailyMobCap = other.FarmingPlanConfig.DailyMobCap,
            miyousheDataEnabled = other.FarmingPlanConfig.MiyousheDataConfig.Enabled,
            miyousheDailyEliteCap =
                other.FarmingPlanConfig.MiyousheDataConfig.DailyEliteCap,
            miyousheDailyMobCap =
                other.FarmingPlanConfig.MiyousheDataConfig.DailyMobCap,
            miyousheCookie = other.MiyousheConfig.Cookie,
            miyousheLogSyncCookie = other.MiyousheConfig.LogSyncCookie,
        };
    }

    private static bool RequiredBool(JObject settings, string name) =>
        settings.Value<bool?>(name) ?? throw new ArgumentException($"{name} is required.");

    private static int RequiredInt(JObject settings, string name) =>
        settings.Value<int?>(name) ?? throw new ArgumentException($"{name} is required.");

    private static string RequiredString(JObject settings, string name) =>
        settings.Value<string>(name) ?? throw new ArgumentException($"{name} is required.");

    private static string RequiredOption(
        JObject settings,
        string name,
        IReadOnlyCollection<string> options)
    {
        var value = RequiredString(settings, name);
        if (!options.Contains(value))
            throw new ArgumentException($"Unsupported {name}: {value}.");
        return value;
    }

    private static OtherConfig LoadOtherConfig(JsonObject root) =>
        root["otherConfig"]?.Deserialize<OtherConfig>(ConfigJson.Options)
        ?? new OtherConfig();

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
