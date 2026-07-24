using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Script.OneDragon;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed record OneDragonConfigSummary(
    string Name,
    int TaskCount,
    int EnabledTaskCount);

public sealed record OneDragonConfigDocument(
    string Name,
    JObject Config,
    IReadOnlyList<OneDragonPlanStep> Tasks);

public sealed class OneDragonCatalog(RuntimeLayout layout)
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
        return Directory
            .EnumerateFiles(layout.OneDragonPath, "*.json", SearchOption.TopDirectoryOnly)
            .OrderBy(Path.GetFileName, StringComparer.Ordinal)
            .Select(ReadSummary)
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
        var config = JsonConvert.DeserializeObject<OneDragonFlowConfig>(
                document.ToString(Formatting.None))
            ?? throw new InvalidDataException("OneDragon config document is invalid.");
        if (!string.Equals(config.Name, name, StringComparison.Ordinal))
            throw new InvalidDataException(
                $"OneDragon config name '{config.Name}' does not match target '{name}'.");
        ValidatePlan(config);
        lock (_writeLock)
        {
            Write(Resolve(name), config);
            SaveSelectedName(name);
            return ToDocument(config);
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
            var config = ReadConfig(source);
            config.Name = newName;
            Write(destination, config);
            File.Delete(source);
            SaveSelectedName(newName);
            return ToDocument(config);
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

    private OneDragonConfigSummary ReadSummary(string path)
    {
        var config = ReadConfig(path);
        var plan = OneDragonPlan.FromConfig(config);
        return new OneDragonConfigSummary(
            config.Name,
            plan.OrderedSteps.Count,
            plan.OrderedSteps.Count(step => step.IsEnabled));
    }

    private OneDragonConfigDocument ReadDocument(string path) =>
        ToDocument(ReadConfig(path));

    private static OneDragonConfigDocument ToDocument(OneDragonFlowConfig config)
    {
        var plan = OneDragonPlan.FromConfig(config);
        return new OneDragonConfigDocument(
            config.Name,
            JObject.FromObject(config),
            plan.OrderedSteps);
    }

    private static OneDragonFlowConfig ReadConfig(string path)
    {
        var config = JsonConvert.DeserializeObject<OneDragonFlowConfig>(
                File.ReadAllText(path, Encoding.UTF8))
            ?? throw new InvalidDataException($"OneDragon config is invalid: {path}");
        ValidateName(config.Name);
        ValidatePlan(config);
        return config;
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
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(
                temporary,
                JsonConvert.SerializeObject(config, Formatting.Indented),
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
}
