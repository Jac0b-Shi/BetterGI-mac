using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using Newtonsoft.Json.Linq;
using SixLabors.ImageSharp;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class CommonSettingsCatalog(RuntimeLayout layout)
{
    private static readonly string[] AdventurersGuildCountries =
        ["无", "枫丹", "稻妻", "璃月", "蒙德"];
    private static readonly int[] ServerTimeZoneOffsets = [8, 1, -5];
    private static readonly string[] MapMatchingMethods =
        ["SIFT", "TemplateMatch"];
    private static readonly string[] MainBackgroundStretchOptions =
        ["UniformToFill", "Uniform", "Fill"];
    private static readonly string[] SupportedCultures =
        ["zh-Hans", "zh-Hant", "en", "fr", "it", "ru", "ja"];
    private static readonly string[] ScriptRepositoryChannels =
        [.. ScriptRepositoryCatalog.RepositoryChannels.Keys, "自定义"];
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
            common["mainBackgroundEnabled"] = settings.Value<bool?>("mainBackgroundEnabled")
                ?? common["mainBackgroundEnabled"]?.GetValue<bool>() ?? false;
            // The image is imported through ImportMainBackground. Do not trust a UI-provided
            // path here: macOS background assets must remain inside the Core runtime root.
            common["mainBackgroundImagePath"] = NormalizeBackgroundPath(
                common["mainBackgroundImagePath"]?.GetValue<string>() ?? "");
            var backgroundOpacity = settings.Value<double?>("mainBackgroundOpacity")
                ?? common["mainBackgroundOpacity"]?.GetValue<double>() ?? 0.35;
            if (backgroundOpacity is < 0 or > 1)
                throw new ArgumentOutOfRangeException(
                    "mainBackgroundOpacity", "Background opacity must be between 0 and 1.");
            common["mainBackgroundOpacity"] = backgroundOpacity;
            common["mainBackgroundStretch"] = StretchValue(
                settings.Value<string>("mainBackgroundStretch") is { } stretch
                ? ValidateOption(stretch, "mainBackgroundStretch", MainBackgroundStretchOptions)
                : ReadBackgroundStretch(root));
            root["commonConfig"] = common;
            var pathing = root["pathingConditionConfig"] as JsonObject ?? [];
            pathing["mapMatchingMethod"] = RequiredOption(
                settings, "mapMatchingMethod", MapMatchingMethods);
            root["pathingConditionConfig"] = pathing;
            var other = root["otherConfig"] as JsonObject ?? [];
            other["gameCultureInfoName"] = settings.Value<string>("gameCultureInfoName") is { } gameCulture
                ? ValidateOption(gameCulture, "gameCultureInfoName", SupportedCultures)
                : NormalizeCulture(other["gameCultureInfoName"]?.GetValue<string>());
            other["uiCultureInfoName"] = settings.Value<string>("uiCultureInfoName") is { } uiCulture
                ? ValidateOption(uiCulture, "uiCultureInfoName", SupportedCultures)
                : NormalizeCulture(other["uiCultureInfoName"]?.GetValue<string>());
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

            var script = root["scriptConfig"] as JsonObject ?? [];
            script["autoUpdateSubscribedScripts"] =
                RequiredBool(settings, "autoUpdateSubscribedScripts");
            script["autoUpdateBeforeCommandLineRun"] =
                RequiredBool(settings, "autoUpdateBeforeCommandLineRun");
            script["selectedChannelName"] = RequiredOption(
                settings, "scriptRepositoryChannel", ScriptRepositoryChannels);
            script["customRepoUrl"] =
                RequiredString(settings, "scriptRepositoryCustomUrl");
            root["scriptConfig"] = script;

            SaveRoot(root);
            var savedOtherConfig = LoadOtherConfig(root);
            _otherConfigUpdated?.Invoke(savedOtherConfig);
            return Describe(root);
        }
    }

    internal static bool ScreenshotEnabled(JsonObject root) =>
        root["commonConfig"]?["screenshotEnabled"]?.GetValue<bool>() ?? false;

    public string GetMapMatchingMethod()
    {
        lock (_lock)
            return ReadMapMatchingMethod(LoadRoot());
    }

    public object ImportMainBackground(string sourcePath)
    {
        if (string.IsNullOrWhiteSpace(sourcePath) || !File.Exists(sourcePath))
            throw new FileNotFoundException("Background image does not exist.", sourcePath);
        var destinationDirectory = Path.Combine(layout.UserPath, "Background");
        Directory.CreateDirectory(destinationDirectory);
        var destinationPath = Path.Combine(destinationDirectory, "main-background.png");
        var temporaryPath = $"{destinationPath}.{Guid.NewGuid():N}.tmp";
        try
        {
            using (var image = Image.Load(sourcePath))
                image.SaveAsPng(temporaryPath);
            File.Move(temporaryPath, destinationPath, true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
                File.Delete(temporaryPath);
        }

        lock (_lock)
        {
            var root = LoadRoot();
            var common = root["commonConfig"] as JsonObject ?? [];
            common["mainBackgroundImagePath"] = destinationPath;
            common["mainBackgroundEnabled"] = true;
            root["commonConfig"] = common;
            SaveRoot(root);
            return Describe(root);
        }
    }

    public object ClearMainBackground()
    {
        lock (_lock)
        {
            var root = LoadRoot();
            var common = root["commonConfig"] as JsonObject ?? [];
            var backgroundPath = NormalizeBackgroundPath(
                common["mainBackgroundImagePath"]?.GetValue<string>() ?? "");
            common["mainBackgroundEnabled"] = false;
            common["mainBackgroundImagePath"] = "";
            root["commonConfig"] = common;
            SaveRoot(root);
            if (!string.IsNullOrEmpty(backgroundPath) && File.Exists(backgroundPath))
                File.Delete(backgroundPath);
            return Describe(root);
        }
    }

    private object Describe(JsonObject root)
    {
        var other = LoadOtherConfig(root);
        var script = root["scriptConfig"];
        var scriptRepositoryChannel =
            script?["selectedChannelName"]?.GetValue<string>() ?? "CNB";
        if (!ScriptRepositoryChannels.Contains(scriptRepositoryChannel))
            scriptRepositoryChannel = "CNB";
        return new
        {
            screenshotEnabled = ScreenshotEnabled(root),
            screenshotUidCoverEnabled =
                root["commonConfig"]?["screenshotUidCoverEnabled"]?.GetValue<bool>() ?? true,
            mainBackgroundEnabled = ReadBackgroundEnabled(root),
            mainBackgroundImagePath = ReadBackgroundPath(root),
            mainBackgroundOpacity =
                root["commonConfig"]?["mainBackgroundOpacity"]?.GetValue<double>() ?? 0.35,
            mainBackgroundStretch = ReadBackgroundStretch(root),
            mainBackgroundStretchOptions = MainBackgroundStretchOptions,
            mapMatchingMethod = ReadMapMatchingMethod(root),
            mapMatchingMethodOptions = MapMatchingMethods,
            gameCultureInfoName = NormalizeCulture(other.GameCultureInfoName),
            uiCultureInfoName = NormalizeCulture(other.UiCultureInfoName),
            cultureOptions = SupportedCultures,
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
            autoUpdateSubscribedScripts =
                script?["autoUpdateSubscribedScripts"]?.GetValue<bool>() ?? false,
            autoUpdateBeforeCommandLineRun =
                script?["autoUpdateBeforeCommandLineRun"]?.GetValue<bool>() ?? false,
            scriptRepositoryChannel,
            scriptRepositoryChannelOptions = ScriptRepositoryChannels,
            scriptRepositoryChannelUrls =
                ScriptRepositoryCatalog.RepositoryChannels,
            scriptRepositoryCustomUrl =
                script?["customRepoUrl"]?.GetValue<string>() ?? "",
        };
    }

    private static string ReadMapMatchingMethod(JsonObject root)
    {
        var value = root["pathingConditionConfig"]?["mapMatchingMethod"]
            ?.GetValue<string>();
        return value is not null && MapMatchingMethods.Contains(value)
            ? value
            : "TemplateMatch";
    }

    private static string NormalizeCulture(string? value) =>
        value is not null && SupportedCultures.Contains(value) ? value : "zh-Hans";

    private static string ValidateOption(string value, string name, string[] options) =>
        options.Contains(value)
            ? value
            : throw new ArgumentException($"Unsupported {name}: {value}.");

    private bool ReadBackgroundEnabled(JsonObject root) =>
        root["commonConfig"]?["mainBackgroundEnabled"]?.GetValue<bool>() == true &&
        File.Exists(ReadBackgroundPath(root));

    private string ReadBackgroundPath(JsonObject root)
    {
        var value = root["commonConfig"]?["mainBackgroundImagePath"]?.GetValue<string>() ?? "";
        return NormalizeBackgroundPath(value);
    }

    private string NormalizeBackgroundPath(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return "";
        try
        {
            var fullPath = Path.GetFullPath(value);
            var backgroundRoot = Path.GetFullPath(Path.Combine(layout.UserPath, "Background"));
            return fullPath.StartsWith(backgroundRoot + Path.DirectorySeparatorChar,
                StringComparison.Ordinal) ? fullPath : "";
        }
        catch (Exception) when (value.Length > 0)
        {
            return "";
        }
    }

    private static string ReadBackgroundStretch(JsonObject root)
    {
        var node = root["commonConfig"]?["mainBackgroundStretch"];
        if (node is JsonValue value && value.TryGetValue<string>(out var text) &&
            MainBackgroundStretchOptions.Contains(text))
            return text;
        var numeric = node?.GetValue<int>() ?? 3;
        return numeric switch { 1 => "Fill", 2 => "Uniform", _ => "UniformToFill" };
    }

    private static int StretchValue(string value) =>
        value switch { "Fill" => 1, "Uniform" => 2, _ => 3 };

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
