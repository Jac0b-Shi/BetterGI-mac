using BetterGenshinImpact.Core.Host.Protocol;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.Core.Script.Project;
using BetterGenshinImpact.Model;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System.Text;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class ScriptGroupCatalog(RuntimeLayout layout)
{
    private readonly object _writeLock = new();

    public IReadOnlyList<ScriptGroupSummary> List()
    {
        layout.EnsureCreated();
        return Directory.EnumerateFiles(layout.ScriptGroupPath, "*.json", SearchOption.TopDirectoryOnly)
            .OrderBy(Path.GetFileName, StringComparer.Ordinal)
            .Select(ReadSummary)
            .ToArray();
    }

    public ScriptGroupDocument Get(string name)
    {
        var path = Resolve(name);
        if (!File.Exists(path))
            throw new FileNotFoundException($"Script group does not exist: {name}", path);
        return Read(path);
    }

    public ScriptGroupDocument Save(string name, JObject document)
    {
        ArgumentNullException.ThrowIfNull(document);
        var group = ScriptGroup.FromJson(document.ToString(Formatting.None));
        if (!string.Equals(group.Name, name, StringComparison.Ordinal))
            throw new InvalidDataException($"Script group document name '{group.Name}' does not match target name '{name}'.");
        lock (_writeLock)
            return SaveGroup(name, group);
    }

    public ScriptGroupSummary SetProjectEnabled(string name, int projectIndex, bool enabled)
    {
        lock (_writeLock)
        {
            var path = Resolve(name);
            if (!File.Exists(path))
                throw new FileNotFoundException($"Script group does not exist: {name}", path);
            var group = ScriptGroup.FromJson(File.ReadAllText(path, Encoding.UTF8));
            var matches = group.Projects.Where(project => project.Index == projectIndex).ToArray();
            if (matches.Length != 1)
                throw new InvalidDataException(
                    $"Script group '{name}' must contain exactly one project with index {projectIndex}.");
            matches[0].Status = enabled ? "Enabled" : "Disabled";
            SaveGroup(name, group);
            return ReadSummary(path);
        }
    }

    public ScriptGroupProjectCommonSettings GetProjectCommonSettings(string name, int projectIndex)
    {
        var project = ReadProject(name, projectIndex);
        var urls = Array.Empty<string>();
        if (project.Type == "Javascript")
        {
            project.BuildScriptProjectRelation();
            urls = project.Project?.Manifest.HttpAllowedUrls ?? [];
        }
        return new ScriptGroupProjectCommonSettings(
            project.Index, project.Status, project.Type == "Javascript",
            project.AllowJsNotification, project.Type == "Javascript" && project.AllowJsHTTP, urls);
    }

    public ScriptGroupSummary SaveProjectCommonSettings(
        string name, int projectIndex, string status, bool? allowJsNotification, bool allowJsHttp)
    {
        if (status is not ("Enabled" or "Disabled"))
            throw new ArgumentException("Project status must be Enabled or Disabled.", nameof(status));
        lock (_writeLock)
        {
            var (path, group, project) = ReadProjectForWrite(name, projectIndex);
            project.Status = status;
            if (project.Type == "Javascript")
            {
                project.AllowJsNotification = allowJsNotification;
                project.AllowJsHTTPHash = allowJsHttp ? project.GetHttpAllowedUrlsHash() : null;
            }
            SaveGroup(name, group);
            return ReadSummary(path);
        }
    }

    public ScriptGroupProjectCustomSettings GetProjectCustomSettings(string name, int projectIndex)
    {
        var project = ReadProject(name, projectIndex);
        var scriptProject = RequireJavascriptProject(project);
        var schema = scriptProject.Manifest.LoadSettingItems(scriptProject.ProjectPath);
        var values = JObject.FromObject(project.JsScriptSettingsObject ?? new System.Dynamic.ExpandoObject());
        ApplyDefaults(schema, values);
        var schemaDocument = new JArray(schema.Select(item => new JObject
        {
            ["name"] = item.Name,
            ["type"] = item.Type,
            ["label"] = item.Label,
            ["options"] = item.Options == null ? null : JArray.FromObject(item.Options),
            ["cascadeOptions"] = item.CascadeOptions == null ? null : JObject.FromObject(item.CascadeOptions),
            ["default"] = item.Default == null ? null : SettingDefaultToken(item)
        }));
        return new ScriptGroupProjectCustomSettings(project.Index, schemaDocument, values);
    }

    public ScriptGroupSummary SaveProjectCustomSettings(string name, int projectIndex, JObject values)
    {
        ArgumentNullException.ThrowIfNull(values);
        lock (_writeLock)
        {
            var (path, group, project) = ReadProjectForWrite(name, projectIndex);
            var scriptProject = RequireJavascriptProject(project);
            var schema = scriptProject.Manifest.LoadSettingItems(scriptProject.ProjectPath);
            var merged = JObject.FromObject(project.JsScriptSettingsObject ?? new System.Dynamic.ExpandoObject());
            ApplyDefaults(schema, merged);
            foreach (var item in schema.Where(item => item.Type != "separator" && !string.IsNullOrWhiteSpace(item.Name)))
            {
                if (!values.TryGetValue(item.Name, out var value)) continue;
                merged[item.Name] = ValidateSettingValue(item, value);
            }
            project.JsScriptSettingsObject = merged.ToObject<System.Dynamic.ExpandoObject>();
            SaveGroup(name, group);
            return ReadSummary(path);
        }
    }

    public IReadOnlyList<ScriptGroupAddCandidate> ListAddCandidates(string type)
    {
        layout.EnsureCreated();
        return type switch
        {
            "Javascript" => Directory.EnumerateDirectories(Path.Combine(layout.UserPath, "JsScript"))
                .Select(path => new ScriptProject(Path.GetFileName(path)))
                .OrderBy(project => project.Manifest.Name, StringComparer.OrdinalIgnoreCase)
                .Select(project => new ScriptGroupAddCandidate(project.FolderName, project.Manifest.Name, project.FolderName, type))
                .ToArray(),
            "Pathing" => EnumerateFiles(Path.Combine(layout.UserPath, "AutoPathing"), "*.json", type),
            "KeyMouse" => EnumerateFiles(Path.Combine(layout.UserPath, "KeyMouseScript"), "*", type),
            "Shell" => [],
            _ => throw new ArgumentException($"Unsupported project type: {type}", nameof(type))
        };
    }

    public ScriptGroupSummary AddProjects(string name, string type, JArray candidateIds, string? shellCommand)
    {
        lock (_writeLock)
        {
            var path = Resolve(name);
            var group = ReadGroup(path);
            if (type == "Shell")
            {
                if (string.IsNullOrWhiteSpace(shellCommand))
                    throw new ArgumentException("Shell command cannot be empty.", nameof(shellCommand));
                group.AddProject(ScriptGroupProject.BuildShellProject(shellCommand));
            }
            else
            {
                var candidates = ListAddCandidates(type).ToDictionary(item => item.Id, StringComparer.Ordinal);
                foreach (var id in candidateIds.Values<string>().OfType<string>().Distinct(StringComparer.Ordinal))
                {
                    if (!candidates.TryGetValue(id, out var candidate))
                        throw new InvalidDataException($"Unknown {type} candidate: {id}");
                    group.AddProject(type switch
                    {
                        "Javascript" => new ScriptGroupProject(new ScriptProject(candidate.FolderName)),
                        "Pathing" => ScriptGroupProject.BuildPathingProject(candidate.Name, candidate.FolderName),
                        "KeyMouse" => ScriptGroupProject.BuildKeyMouseProject(candidate.Name),
                        _ => throw new ArgumentException($"Unsupported project type: {type}", nameof(type))
                    });
                }
            }
            Reindex(group);
            SaveGroup(name, group);
            return ReadSummary(path);
        }
    }

    public ScriptGroupSummary RemoveProject(string name, int projectIndex, bool sameFolder)
    {
        lock (_writeLock)
        {
            var path = Resolve(name);
            var group = ReadGroup(path);
            var project = RequireProject(group, name, projectIndex);
            if (sameFolder)
            {
                var matches = group.Projects.Where(item => item.FolderName == project.FolderName).ToArray();
                foreach (var match in matches) group.Projects.Remove(match);
            }
            else group.Projects.Remove(project);
            Reindex(group);
            SaveGroup(name, group);
            return ReadSummary(path);
        }
    }

    public ScriptGroupSummary Clear(string name) => MutateProjects(name, group => group.Projects.Clear());

    public ScriptGroupSummary Reverse(string name) => MutateProjects(name, group =>
    {
        var reversed = group.Projects.Reverse().ToArray();
        group.Projects.Clear();
        foreach (var project in reversed) group.AddProject(project);
    });

    public ScriptGroupSummary UpdatePathingFolders(string name) => MutateProjects(name, group =>
    {
        var result = new List<ScriptGroupProject>();
        var visited = new HashSet<string>(StringComparer.Ordinal);
        foreach (var project in group.Projects)
        {
            if (project.Type != "Pathing") { result.Add(project); continue; }
            if (!visited.Add(project.FolderName)) continue;
            var directory = ResolveUnder(Path.Combine(layout.UserPath, "AutoPathing"), project.FolderName);
            if (!Directory.Exists(directory)) continue;
            var existing = group.Projects.Where(item => item.Type == "Pathing" && item.FolderName == project.FolderName)
                .ToDictionary(item => item.Name, StringComparer.Ordinal);
            foreach (var file in Directory.EnumerateFiles(directory, "*.json", SearchOption.TopDirectoryOnly).OrderBy(Path.GetFileName))
                result.Add(existing.GetValueOrDefault(Path.GetFileName(file)) ??
                    ScriptGroupProject.BuildPathingProject(Path.GetFileName(file), project.FolderName));
        }
        group.Projects.Clear();
        foreach (var project in result) group.AddProject(project);
    });

    public ScriptGroupSummary SetNextProject(string name, int projectIndex)
    {
        var project = ReadProject(name, projectIndex);
        layout.EnsureCreated();
        WriteAtomic(layout.SchedulerStatePath, JObject.FromObject(new
        {
            groupName = name, index = project.Index, folderName = project.FolderName, projectName = project.Name
        }).ToString(Formatting.Indented) + Environment.NewLine);
        return ReadSummary(Resolve(name));
    }

    public object GetProjectLocation(string name, int projectIndex)
    {
        var project = ReadProject(name, projectIndex);
        var path = project.Type switch
        {
            "Javascript" => ResolveUnder(Path.Combine(layout.UserPath, "JsScript"), project.FolderName),
            "Pathing" => ResolveUnder(Path.Combine(layout.UserPath, "AutoPathing"), project.FolderName),
            "KeyMouse" => Path.Combine(layout.UserPath, "KeyMouseScript"),
            _ => throw new InvalidOperationException($"Project type {project.Type} has no directory.")
        };
        if (!Directory.Exists(path)) throw new DirectoryNotFoundException(path);
        return new { path };
    }

    public JObject GetGroupConfig(string name)
    {
        var group = ReadGroup(Resolve(name));
        return JObject.Parse(System.Text.Json.JsonSerializer.Serialize(group.Config, ConfigJson.Options));
    }

    public ScriptGroupSummary SaveGroupConfig(string name, JObject config)
    {
        ArgumentNullException.ThrowIfNull(config);
        lock (_writeLock)
        {
            var path = Resolve(name);
            var group = ReadGroup(path);
            var current = JObject.Parse(System.Text.Json.JsonSerializer.Serialize(group.Config, ConfigJson.Options));
            current.Merge(config, new JsonMergeSettings { MergeArrayHandling = MergeArrayHandling.Replace });
            group.Config = current.ToObject<ScriptGroupConfig>() ?? throw new InvalidDataException("Invalid group config.");
            SaveGroup(name, group);
            return ReadSummary(path);
        }
    }

    private ScriptGroupDocument SaveGroup(string name, ScriptGroup group)
    {
        layout.EnsureCreated();
        var path = Resolve(name);
        var tempPath = path + ".tmp-" + Guid.NewGuid().ToString("N");
        var json = Normalize(group);
        File.WriteAllText(tempPath, json, new UTF8Encoding(false));
        File.Move(tempPath, path, true);
        return Read(path);
    }

    private ScriptGroupDocument Read(string path)
    {
        var text = File.ReadAllText(path, Encoding.UTF8);
        var group = ScriptGroup.FromJson(text);
        var document = JObject.Parse(group.ToJson());
        var name = group.Name;
        if (string.IsNullOrWhiteSpace(name))
            name = Path.GetFileNameWithoutExtension(path);
        return new ScriptGroupDocument(name, Path.GetRelativePath(layout.RootPath, path), document);
    }

    private ScriptGroupSummary ReadSummary(string path)
    {
        var group = ScriptGroup.FromJson(File.ReadAllText(path, Encoding.UTF8));
        var name = string.IsNullOrWhiteSpace(group.Name) ? Path.GetFileNameWithoutExtension(path) : group.Name;
        return new ScriptGroupSummary(
            name,
            Path.GetRelativePath(layout.RootPath, path),
            group.Index,
            group.Projects.Select(project => new ScriptGroupProjectSummary(
                project.Index,
                project.Name,
                project.Type,
                project.Status,
                project.Schedule,
                project.RunNum,
                project.FolderName,
                HasCustomSettings(project),
                IsNextProject(name, project))).ToArray());
    }

    private ScriptGroupSummary MutateProjects(string name, Action<ScriptGroup> mutation)
    {
        lock (_writeLock)
        {
            var path = Resolve(name);
            var group = ReadGroup(path);
            mutation(group);
            Reindex(group);
            SaveGroup(name, group);
            return ReadSummary(path);
        }
    }

    private ScriptGroupProject ReadProject(string name, int projectIndex) =>
        RequireProject(ReadGroup(Resolve(name)), name, projectIndex);

    private (string Path, ScriptGroup Group, ScriptGroupProject Project) ReadProjectForWrite(string name, int projectIndex)
    {
        var path = Resolve(name);
        var group = ReadGroup(path);
        return (path, group, RequireProject(group, name, projectIndex));
    }

    private static ScriptGroupProject RequireProject(ScriptGroup group, string name, int projectIndex)
    {
        var matches = group.Projects.Where(project => project.Index == projectIndex).ToArray();
        return matches.Length == 1 ? matches[0] : throw new InvalidDataException(
            $"Script group '{name}' must contain exactly one project with index {projectIndex}.");
    }

    private ScriptGroup ReadGroup(string path)
    {
        if (!File.Exists(path)) throw new FileNotFoundException("Script group does not exist.", path);
        return ScriptGroup.FromJson(File.ReadAllText(path, Encoding.UTF8));
    }

    private static ScriptProject RequireJavascriptProject(ScriptGroupProject project)
    {
        if (project.Type != "Javascript") throw new InvalidOperationException("Only JavaScript projects have custom settings.");
        project.BuildScriptProjectRelation();
        return project.Project ?? throw new InvalidDataException("JavaScript project could not be loaded.");
    }

    private static bool HasCustomSettings(ScriptGroupProject project)
    {
        if (project.Type != "Javascript") return false;
        try
        {
            var scriptProject = RequireJavascriptProject(project);
            return scriptProject.Manifest.LoadSettingItems(scriptProject.ProjectPath).Count > 0;
        }
        catch { return false; }
    }

    private bool IsNextProject(string groupName, ScriptGroupProject project)
    {
        if (!File.Exists(layout.SchedulerStatePath)) return false;
        try
        {
            var state = JObject.Parse(File.ReadAllText(layout.SchedulerStatePath));
            return state.Value<string>("groupName") == groupName && state.Value<int?>("index") == project.Index &&
                   state.Value<string>("folderName") == project.FolderName && state.Value<string>("projectName") == project.Name;
        }
        catch { return false; }
    }

    private static void ApplyDefaults(IEnumerable<SettingItem> schema, JObject values)
    {
        foreach (var item in schema.Where(item => item.Type != "separator" && !string.IsNullOrWhiteSpace(item.Name)))
            if (values[item.Name] == null && item.Default != null) values[item.Name] = SettingDefaultToken(item);
    }

    private static JToken SettingDefaultToken(SettingItem item) => item.Type switch
    {
        "input-text" or "select" or "cascade-select" => new JValue(DefaultText(item.Default!)),
        "checkbox" => new JValue(bool.TryParse(DefaultText(item.Default!), out var value) && value),
        "multi-checkbox" => DefaultToken(item.Default!),
        _ => DefaultToken(item.Default!)
    };

    private static string DefaultText(object value) => value is System.Text.Json.JsonElement element
        ? element.ValueKind == System.Text.Json.JsonValueKind.String ? element.GetString() ?? string.Empty : element.ToString()
        : value.ToString() ?? string.Empty;

    private static JToken DefaultToken(object value) => value is System.Text.Json.JsonElement element
        ? JToken.Parse(element.GetRawText())
        : JToken.FromObject(value);

    private static JToken ValidateSettingValue(SettingItem item, JToken value) => item.Type switch
    {
        "input-text" when value.Type == JTokenType.String => value.DeepClone(),
        "checkbox" when value.Type == JTokenType.Boolean => value.DeepClone(),
        "select" when value.Type == JTokenType.String && item.Options?.Contains(value.Value<string>()!) == true => value.DeepClone(),
        "cascade-select" when value.Type == JTokenType.String && item.CascadeOptions?.Values
            .Any(options => options.Contains(value.Value<string>()!)) == true => value.DeepClone(),
        "multi-checkbox" when value is JArray array && item.Options != null &&
            array.Values<string>().All(value => value != null && item.Options.Contains(value)) => array.DeepClone(),
        _ => throw new InvalidDataException($"Invalid value for setting '{item.Name}' ({item.Type}).")
    };

    private IReadOnlyList<ScriptGroupAddCandidate> EnumerateFiles(string root, string pattern, string type)
    {
        if (!Directory.Exists(root)) return [];
        return Directory.EnumerateFiles(root, pattern, SearchOption.AllDirectories)
            .OrderBy(path => Path.GetRelativePath(root, path), StringComparer.OrdinalIgnoreCase)
            .Select(path =>
            {
                var relative = Path.GetRelativePath(root, path);
                var folder = Path.GetDirectoryName(relative) ?? string.Empty;
                return new ScriptGroupAddCandidate(relative, Path.GetFileName(path), folder, type);
            }).ToArray();
    }

    private static void Reindex(ScriptGroup group)
    {
        var index = 1;
        foreach (var project in group.Projects) project.Index = index++;
    }

    private static string ResolveUnder(string root, string relative)
    {
        var fullRoot = Path.GetFullPath(root) + Path.DirectorySeparatorChar;
        var full = Path.GetFullPath(Path.Combine(root, relative));
        if (!full.StartsWith(fullRoot, StringComparison.Ordinal) && full != fullRoot.TrimEnd(Path.DirectorySeparatorChar))
            throw new InvalidDataException("Resolved path escapes its runtime root.");
        return full;
    }

    private static void WriteAtomic(string path, string text)
    {
        var temp = path + ".tmp-" + Guid.NewGuid().ToString("N");
        File.WriteAllText(temp, text, new UTF8Encoding(false));
        File.Move(temp, path, true);
    }

    private static string Normalize(ScriptGroup group) =>
        JObject.Parse(group.ToJson()).ToString(Formatting.Indented) + Environment.NewLine;

    private string Resolve(string name)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Script group name cannot be empty.", nameof(name));
        if (name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 || name is "." or ".." || name.Contains('/') || name.Contains('\\'))
            throw new ArgumentException("Script group name contains invalid path characters.", nameof(name));
        return Path.Combine(layout.ScriptGroupPath, name + ".json");
    }
}
