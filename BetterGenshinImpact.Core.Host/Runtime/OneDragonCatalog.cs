using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Script.OneDragon;
using BetterGenshinImpact.GameTask.AutoBoss;
using BetterGenshinImpact.GameTask.Common.Element.Assets;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed record OneDragonConfigSummary(
    [property: JsonProperty("name")] string Name,
    [property: JsonProperty("taskCount")] int TaskCount,
    [property: JsonProperty("enabledTaskCount")] int EnabledTaskCount,
    [property: JsonProperty("selected")] bool Selected);

public sealed record OneDragonTaskSummary(
    [property: JsonProperty("id")] string Id,
    [property: JsonProperty("name")] string Name,
    [property: JsonProperty("isEnabled")] bool IsEnabled,
    [property: JsonProperty("isResumeStep")] bool IsResumeStep);

public sealed record OneDragonConfigDocument(
    [property: JsonProperty("name")] string Name,
    [property: JsonProperty("config")] JObject Config,
    [property: JsonProperty("tasks")] IReadOnlyList<OneDragonTaskSummary> Tasks,
    [property: JsonProperty("builtInTaskNames")] IReadOnlyList<string> BuiltInTaskNames,
    [property: JsonProperty("options")] OneDragonConfigOptions Options);

public sealed record OneDragonConfigOptions(
    [property: JsonProperty("craftingBenchCountries")]
    IReadOnlyList<string> CraftingBenchCountries,
    [property: JsonProperty("adventurersGuildCountries")]
    IReadOnlyList<string> AdventurersGuildCountries,
    [property: JsonProperty("domainNames")] IReadOnlyList<string> DomainNames,
    [property: JsonProperty("sundayRewardOptions")]
    IReadOnlyList<string> SundayRewardOptions,
    [property: JsonProperty("bossNames")] IReadOnlyList<string> BossNames,
    [property: JsonProperty("fightStrategies")] IReadOnlyList<string> FightStrategies,
    [property: JsonProperty("leyLineTypes")] IReadOnlyList<string> LeyLineTypes,
    [property: JsonProperty("leyLineCountries")] IReadOnlyList<string> LeyLineCountries,
    [property: JsonProperty("secretTreasureObjects")]
    IReadOnlyList<string> SecretTreasureObjects,
    [property: JsonProperty("sereniteaPotTpTypes")]
    IReadOnlyList<string> SereniteaPotTpTypes,
    [property: JsonProperty("completionActions")]
    IReadOnlyList<string> CompletionActions);

public sealed class OneDragonCatalog(
    RuntimeLayout layout,
    Func<IReadOnlyList<string>>? domainNameProvider = null)
{
    private static readonly string[] DefaultTaskNames =
    [
        "领取邮件",
        "合成树脂",
        "自动秘境",
        "自动首领讨伐",
        "自动幽境危战",
        "自动地脉花",
        "领取每日奖励",
        "领取尘歌壶奖励",
    ];

    private readonly object _writeLock = new();

    public IReadOnlyList<OneDragonConfigSummary> List()
    {
        layout.EnsureCreated();
        EnsureDefaultConfig();
        var selectedName = ReadSelectedName();
        return Directory
            .EnumerateFiles(layout.OneDragonPath, "*.json", SearchOption.TopDirectoryOnly)
            .OrderBy(Path.GetFileName, StringComparer.Ordinal)
            .Select(path => ReadSummary(path, selectedName))
            .ToArray();
    }

    public OneDragonConfigDocument Get(string name)
    {
        var path = Resolve(name);
        if (!File.Exists(path))
            throw new FileNotFoundException($"OneDragon config does not exist: {name}", path);
        return ReadDocument(path);
    }

    public OneDragonConfigDocument Create(string name)
    {
        ValidateName(name);
        lock (_writeLock)
        {
            var path = Resolve(name);
            if (File.Exists(path))
                throw new IOException($"OneDragon config already exists: {name}");
            var config = CreateDefault(name);
            Write(path, config);
            SaveSelectedName(name);
            return ToDocument(config);
        }
    }

    public OneDragonConfigDocument Save(string name, JObject document)
    {
        ArgumentNullException.ThrowIfNull(document);
        ValidateName(name);
        var preservedDocument = (JObject)document.DeepClone();
        var config = DeserializeConfig(
            preservedDocument,
            "OneDragon config document is invalid.");
        if (!string.Equals(config.Name, name, StringComparison.Ordinal))
            throw new InvalidDataException(
                $"OneDragon config name '{config.Name}' does not match target '{name}'.");
        ValidatePlan(config);
        lock (_writeLock)
        {
            Write(Resolve(name), preservedDocument);
            SaveSelectedName(name);
            return ToDocument(preservedDocument);
        }
    }

    public OneDragonConfigDocument Rename(string name, string newName)
    {
        ValidateName(name);
        ValidateName(newName);
        lock (_writeLock)
        {
            var source = Resolve(name);
            var destination = Resolve(newName);
            if (!File.Exists(source))
                throw new FileNotFoundException($"OneDragon config does not exist: {name}", source);
            if (File.Exists(destination))
                throw new IOException($"OneDragon config already exists: {newName}");
            var document = ReadRawDocument(source);
            SetConfigName(document, newName);
            var config = DeserializeConfig(
                document,
                $"OneDragon config is invalid: {source}");
            ValidatePlan(config);
            Write(destination, document);
            File.Delete(source);
            SaveSelectedName(newName);
            return ToDocument(document);
        }
    }

    public object Delete(string name)
    {
        ValidateName(name);
        lock (_writeLock)
        {
            var path = Resolve(name);
            if (!File.Exists(path))
                throw new FileNotFoundException($"OneDragon config does not exist: {name}", path);
            File.Delete(path);
            var remaining = Directory
                .EnumerateFiles(layout.OneDragonPath, "*.json", SearchOption.TopDirectoryOnly)
                .OrderBy(Path.GetFileName, StringComparer.Ordinal)
                .FirstOrDefault();
            if (remaining is null)
            {
                var fallback = CreateDefault("默认配置");
                Write(Resolve(fallback.Name), fallback);
                SaveSelectedName(fallback.Name);
                return new { deleted = name, selectedName = fallback.Name };
            }
            var selected = ReadConfig(remaining).Name;
            SaveSelectedName(selected);
            return new { deleted = name, selectedName = selected };
        }
    }

    public OneDragonFlowConfig Load(string name) => ReadConfig(ResolveExisting(name));

    public void Select(string name)
    {
        ResolveExisting(name);
        lock (_writeLock)
            SaveSelectedName(name);
    }

    public void Save(OneDragonFlowConfig config)
    {
        ArgumentNullException.ThrowIfNull(config);
        ValidateName(config.Name);
        ValidatePlan(config);
        lock (_writeLock)
            Write(Resolve(config.Name), config);
    }

    private void EnsureDefaultConfig()
    {
        lock (_writeLock)
        {
            if (Directory.EnumerateFiles(
                    layout.OneDragonPath,
                    "*.json",
                    SearchOption.TopDirectoryOnly).Any())
                return;
            var config = CreateDefault("默认配置");
            Write(Resolve(config.Name), config);
            SaveSelectedName(config.Name);
        }
    }

    private static OneDragonFlowConfig CreateDefault(string name)
    {
        var config = new OneDragonFlowConfig { Name = name };
        foreach (var taskName in DefaultTaskNames)
        {
            var id = Guid.NewGuid().ToString();
            config.TaskDefinitions[id] = taskName;
            config.TaskEnabledList[id] = false;
            config.TaskOrder.Add(id);
        }
        return config;
    }

    private static void ValidatePlan(OneDragonFlowConfig config)
    {
        var plan = OneDragonPlan.FromConfig(config);
        if (plan.OrderedSteps.Select(step => step.Id).Distinct(StringComparer.Ordinal).Count()
            != plan.OrderedSteps.Count)
        {
            throw new InvalidDataException("OneDragon task identifiers must be unique.");
        }
    }

    private OneDragonConfigSummary ReadSummary(string path, string? selectedName)
    {
        var config = ReadConfig(path);
        var plan = OneDragonPlan.FromConfig(config);
        return new OneDragonConfigSummary(
            config.Name,
            plan.OrderedSteps.Count,
            plan.OrderedSteps.Count(step => step.IsEnabled),
            string.Equals(config.Name, selectedName, StringComparison.Ordinal));
    }

    private OneDragonConfigDocument ReadDocument(string path) =>
        ToDocument(ReadRawDocument(path));

    private OneDragonConfigDocument ToDocument(OneDragonFlowConfig config)
    {
        var plan = OneDragonPlan.FromConfig(config);
        return new OneDragonConfigDocument(
            config.Name,
            JObject.FromObject(config),
            ToTaskSummaries(plan.OrderedSteps),
            DefaultTaskNames,
            BuildOptions());
    }

    private OneDragonConfigDocument ToDocument(JObject document)
    {
        var config = DeserializeConfig(
            document,
            "OneDragon config document is invalid.");
        ValidatePlan(config);
        var plan = OneDragonPlan.FromConfig(config);
        return new OneDragonConfigDocument(
            config.Name,
            (JObject)document.DeepClone(),
            ToTaskSummaries(plan.OrderedSteps),
            DefaultTaskNames,
            BuildOptions());
    }

    private OneDragonConfigOptions BuildOptions()
    {
        var autoFightFolder = Path.Combine(layout.UserPath, "AutoFight");
        Directory.CreateDirectory(autoFightFolder);
        string[] fightStrategies =
        [
            "根据队伍自动选择",
            .. Directory.EnumerateFiles(
                    autoFightFolder,
                    "*.*",
                    SearchOption.AllDirectories)
                .Where(path =>
                    path.EndsWith(".txt", StringComparison.OrdinalIgnoreCase) ||
                    path.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
                .Select(path => Path.ChangeExtension(
                    Path.GetRelativePath(autoFightFolder, path),
                    null))
                .Order(StringComparer.Ordinal),
        ];
        return new OneDragonConfigOptions(
            ["枫丹", "稻妻", "璃月", "蒙德"],
            ["挪德卡莱", "枫丹", "稻妻", "璃月", "蒙德"],
            ["", .. (domainNameProvider?.Invoke() ?? MapLazyAssets.Get().DomainNameList)],
            ["", "1", "2", "3"],
            ["", .. AutoBossData.SupportedBossNames],
            fightStrategies,
            ["", "启示之花", "藏金之花"],
            ["", "蒙德", "璃月", "稻妻", "须弥", "枫丹", "纳塔", "挪德卡莱"],
            ["布匹", "须臾树脂", "大英雄的经验", "流浪者的经验",
                "精锻用魔矿", "摩拉", "祝圣精华", "祝圣油膏"],
            ["地图传送", "尘歌壶道具"],
            ["无", "关闭游戏", "关闭软件", "关闭游戏和软件", "关机"]);
    }

    private static IReadOnlyList<OneDragonTaskSummary> ToTaskSummaries(
        IReadOnlyList<OneDragonPlanStep> steps)
    {
        return steps.Select(step => new OneDragonTaskSummary(
            step.Id,
            step.Name,
            step.IsEnabled,
            step.IsResumeStep)).ToArray();
    }

    private static OneDragonFlowConfig ReadConfig(string path)
    {
        var config = DeserializeConfig(
            ReadRawDocument(path),
            $"OneDragon config is invalid: {path}");
        ValidateName(config.Name);
        ValidatePlan(config);
        return config;
    }

    private static JObject ReadRawDocument(string path)
    {
        try
        {
            return JObject.Parse(File.ReadAllText(path, Encoding.UTF8));
        }
        catch (Newtonsoft.Json.JsonException exception)
        {
            throw new InvalidDataException(
                $"OneDragon config is invalid: {path}",
                exception);
        }
    }

    private static OneDragonFlowConfig DeserializeConfig(
        JObject document,
        string errorMessage)
    {
        return JsonConvert.DeserializeObject<OneDragonFlowConfig>(
                document.ToString(Formatting.None))
            ?? throw new InvalidDataException(errorMessage);
    }

    private static void SetConfigName(JObject document, string name)
    {
        var property = document.Properties().FirstOrDefault(
            item => string.Equals(
                item.Name,
                nameof(OneDragonFlowConfig.Name),
                StringComparison.OrdinalIgnoreCase));
        if (property is null)
            document[nameof(OneDragonFlowConfig.Name)] = name;
        else
            property.Value = name;
    }

    private string ResolveExisting(string name)
    {
        var path = Resolve(name);
        return File.Exists(path)
            ? path
            : throw new FileNotFoundException($"OneDragon config does not exist: {name}", path);
    }

    private string Resolve(string name)
    {
        ValidateName(name);
        layout.EnsureCreated();
        return Path.Combine(layout.OneDragonPath, name + ".json");
    }

    private static void ValidateName(string name)
    {
        if (string.IsNullOrWhiteSpace(name) ||
            name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 ||
            name.Contains('/') ||
            name.Contains('\\') ||
            name is "." or "..")
        {
            throw new ArgumentException("Invalid OneDragon config name.", nameof(name));
        }
    }

    private static void Write(string path, OneDragonFlowConfig config)
    {
        Write(path, JObject.FromObject(config));
    }

    private static void Write(string path, JObject document)
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(
                temporary,
                document.ToString(Formatting.Indented),
                new UTF8Encoding(false));
            File.Move(temporary, path, true);
        }
        finally
        {
            if (File.Exists(temporary))
                File.Delete(temporary);
        }
    }

    private void SaveSelectedName(string name)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        JsonObject root;
        if (File.Exists(path))
        {
            root = JsonNode.Parse(
                    File.ReadAllText(path),
                    documentOptions: new JsonDocumentOptions
                    {
                        AllowTrailingCommas = true,
                        CommentHandling = JsonCommentHandling.Skip,
                    }) as JsonObject
                ?? throw new InvalidDataException("User/config.json root must be an object.");
        }
        else
        {
            root = [];
        }
        root["selectedOneDragonFlowConfigName"] = name;
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(
                temporary,
                root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }),
                new UTF8Encoding(false));
            File.Move(temporary, path, true);
        }
        finally
        {
            if (File.Exists(temporary))
                File.Delete(temporary);
        }
    }

    private string? ReadSelectedName()
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path))
            return null;
        var root = JsonNode.Parse(
                File.ReadAllText(path),
                documentOptions: new JsonDocumentOptions
                {
                    AllowTrailingCommas = true,
                    CommentHandling = JsonCommentHandling.Skip,
                }) as JsonObject
            ?? throw new InvalidDataException("User/config.json root must be an object.");
        return root["selectedOneDragonFlowConfigName"]?.GetValue<string>();
    }
}
