using BetterGenshinImpact.GameTask.LogParse;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System.Globalization;
using System.Text;
using LogParser = BetterGenshinImpact.GameTask.LogParse.LogParse;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed record LogParseOption(
    [property: JsonProperty("value")] string Value,
    [property: JsonProperty("label")] string Label);

public sealed record LogParseSettingsDocument(
    [property: JsonProperty("groupName")] string GroupName,
    [property: JsonProperty("rangeValue")] string RangeValue,
    [property: JsonProperty("dayRangeValue")] string DayRangeValue,
    [property: JsonProperty("mergerStatsSwitch")] bool MergerStatsSwitch,
    [property: JsonProperty("faultStatsSwitch")] bool FaultStatsSwitch,
    [property: JsonProperty("hoeingStatsSwitch")] bool HoeingStatsSwitch,
    [property: JsonProperty("generateFarmingPlanData")] bool GenerateFarmingPlanData,
    [property: JsonProperty("hoeingDelay")] string HoeingDelay,
    [property: JsonProperty("cookie")] string Cookie,
    [property: JsonProperty("rangeOptions")] IReadOnlyList<LogParseOption> RangeOptions,
    [property: JsonProperty("dayRangeOptions")] IReadOnlyList<LogParseOption> DayRangeOptions);

public sealed record LogParseGenerationResult(
    [property: JsonProperty("filePath")] string FilePath,
    [property: JsonProperty("logFileCount")] int LogFileCount,
    [property: JsonProperty("configGroupCount")] int ConfigGroupCount,
    [property: JsonProperty("hoeingStatsEnabled")] bool HoeingStatsEnabled,
    [property: JsonProperty("statusMessages")] IReadOnlyList<string> StatusMessages);

public sealed class LogParseCoordinator(RuntimeLayout layout)
{
    private static readonly LogParseOption[] RangeOptions =
    [
        new("CurrentConfig", "当前配置组"),
        new("All", "所有"),
    ];

    private static readonly LogParseOption[] DayRangeOptions =
    [
        new("1", "1天"),
        new("3", "3天"),
        new("7", "7天"),
        new("15", "15天"),
        new("31", "31天"),
        new("61", "61天"),
        new("92", "92天"),
        new("All", "所有"),
    ];

    private readonly SemaphoreSlim _generationLock = new(1, 1);

    public LogParseSettingsDocument GetSettings(string groupName)
    {
        ValidateGroupName(groupName);
        var config = LogParser.LoadConfig();
        if (!config.ScriptGroupLogDictionary.TryGetValue(groupName, out var settings))
            settings = new LogParseConfig.ScriptGroupLogParseConfig();
        return Describe(groupName, config.Cookie, settings);
    }

    public async Task<LogParseGenerationResult> GenerateAsync(
        string groupName,
        JObject values,
        CancellationToken cancellationToken)
    {
        ValidateGroupName(groupName);
        ArgumentNullException.ThrowIfNull(values);
        var settings = ParseSettings(values);
        await _generationLock.WaitAsync(cancellationToken);
        try
        {
            var statusMessages = new List<string>();
            void OnStatusChanged(string message)
            {
                lock (statusMessages)
                    statusMessages.Add(message);
            }

            LogParser.HtmlGenerationStatusChanged += OnStatusChanged;
            try
            {
                var config = LogParser.LoadConfig();
                config.Cookie = settings.Cookie;
                config.ScriptGroupLogDictionary[groupName] = settings.Config;
                LogParser.WriteConfigFile(config);

                var logFiles = LogParser.GetLogFiles(layout.LogPath);
                if (settings.Config.DayRangeValue != "All")
                {
                    var dayCount = int.Parse(
                        settings.Config.DayRangeValue,
                        CultureInfo.InvariantCulture);
                    if (dayCount < logFiles.Count)
                        logFiles = logFiles.GetRange(logFiles.Count - dayCount, dayCount);
                }

                GameInfo? cachedGameInfo = null;
                if (!string.IsNullOrEmpty(settings.Cookie))
                    config.CookieDictionary.TryGetValue(settings.Cookie, out cachedGameInfo);

                var gameInfo = cachedGameInfo;
                if (settings.Config.HoeingStatsSwitch &&
                    string.IsNullOrWhiteSpace(settings.Cookie))
                {
                    OnStatusChanged("未填写cookie，此次将不启用锄地统计！");
                }
                else if (settings.Config.HoeingStatsSwitch)
                {
                    try
                    {
                        OnStatusChanged("正在从米游社获取旅行札记数据，请耐心等待！");
                        gameInfo = await TravelsDiaryDetailManager
                            .UpdateTravelsDiaryDetailManager(settings.Cookie);
                        OnStatusChanged("米游社数据获取成功，开始进行解析，请耐心等待！");
                    }
                    catch (Exception exception)
                    {
                        OnStatusChanged(cachedGameInfo is null
                            ? $"访问米游社接口异常，此次将不启用锄地统计：{exception.Message}"
                            : $"访问米游社接口异常，此次将使用本地缓存：{exception.Message}");
                        gameInfo = cachedGameInfo;
                    }
                }

                if (gameInfo is not null && !string.IsNullOrEmpty(settings.Cookie))
                {
                    config.CookieDictionary[settings.Cookie] = gameInfo;
                    LogParser.WriteConfigFile(config);
                }

                var configGroups = LogParser.ParseFile(logFiles);
                if (settings.Config.RangeValue == "CurrentConfig")
                {
                    configGroups = configGroups
                        .Where(group => string.Equals(
                            group.Name, groupName, StringComparison.Ordinal))
                        .ToList();
                }
                if (configGroups.Count == 0)
                    throw new InvalidOperationException("未解析出日志记录！");

                configGroups.Reverse();
                var hoeingStatsEnabled =
                    settings.Config.HoeingStatsSwitch && gameInfo is not null;
                var generated = LogParser.GenerHtmlByConfigGroupEntity(
                    configGroups,
                    hoeingStatsEnabled ? gameInfo : null,
                    settings.Config);
                var filePath = PersistGeneratedHtml(generated);
                return new LogParseGenerationResult(
                    filePath,
                    logFiles.Count,
                    configGroups.Count,
                    hoeingStatsEnabled,
                    statusMessages.ToArray());
            }
            finally
            {
                LogParser.HtmlGenerationStatusChanged -= OnStatusChanged;
            }
        }
        finally
        {
            _generationLock.Release();
        }
    }

    public string WriteCookieHelp()
    {
        var directory = Path.Combine(layout.LogPath, "logparse");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "hoeing-statistics-help.html");
        File.WriteAllText(
            path,
            TravelsDiaryDetailManager.generHtmlMessage(),
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        return path;
    }

    private string PersistGeneratedHtml(string generated)
    {
        if (Uri.TryCreate(generated, UriKind.Absolute, out var uri) && uri.IsFile)
            return uri.LocalPath;

        var directory = Path.Combine(layout.LogPath, "logparse");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(
            directory,
            $"LogAnalysis_{DateTime.Now:yyyyMMdd_HHmmss_fff}.html");
        File.WriteAllText(
            path,
            generated,
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        return path;
    }

    private static (
        LogParseConfig.ScriptGroupLogParseConfig Config,
        string Cookie) ParseSettings(JObject values)
    {
        var rangeValue = RequiredOption(values, "rangeValue", RangeOptions);
        var dayRangeValue = RequiredOption(values, "dayRangeValue", DayRangeOptions);
        var delay = values.Value<string>("hoeingDelay")?.Trim()
            ?? throw new ArgumentException("hoeingDelay is required.");
        if (!int.TryParse(delay, NumberStyles.Integer, CultureInfo.InvariantCulture, out var seconds) ||
            seconds < 0)
        {
            throw new ArgumentException("hoeingDelay must be a non-negative integer.");
        }

        return (
            new LogParseConfig.ScriptGroupLogParseConfig
            {
                RangeValue = rangeValue,
                DayRangeValue = dayRangeValue,
                MergerStatsSwitch = RequiredBoolean(values, "mergerStatsSwitch"),
                FaultStatsSwitch = RequiredBoolean(values, "faultStatsSwitch"),
                HoeingStatsSwitch = RequiredBoolean(values, "hoeingStatsSwitch"),
                GenerateFarmingPlanData = RequiredBoolean(
                    values, "generateFarmingPlanData"),
                HoeingDelay = seconds.ToString(CultureInfo.InvariantCulture),
            },
            values.Value<string>("cookie")?.Trim() ?? string.Empty);
    }

    private static LogParseSettingsDocument Describe(
        string groupName,
        string cookie,
        LogParseConfig.ScriptGroupLogParseConfig settings) =>
        new(
            groupName,
            settings.RangeValue,
            settings.DayRangeValue,
            settings.MergerStatsSwitch,
            settings.FaultStatsSwitch,
            settings.HoeingStatsSwitch,
            settings.GenerateFarmingPlanData,
            settings.HoeingDelay,
            cookie,
            RangeOptions,
            DayRangeOptions);

    private static string RequiredOption(
        JObject values,
        string name,
        IReadOnlyList<LogParseOption> options)
    {
        var value = values.Value<string>(name)
            ?? throw new ArgumentException($"{name} is required.");
        if (!options.Any(option => option.Value == value))
            throw new ArgumentException($"{name} is unsupported: {value}");
        return value;
    }

    private static bool RequiredBoolean(JObject values, string name) =>
        values.Value<bool?>(name)
        ?? throw new ArgumentException($"{name} is required.");

    private static void ValidateGroupName(string groupName)
    {
        if (string.IsNullOrWhiteSpace(groupName))
            throw new ArgumentException("groupName is required.");
    }
}
