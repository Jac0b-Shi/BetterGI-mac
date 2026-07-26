using System.Collections.ObjectModel;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Protocol;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.Model;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class PathingCatalog(RuntimeLayout layout)
{
    private const int MaximumReadmeBytes = 1024 * 1024;
    private readonly object _lock = new();
    private Action<PathingConditionConfig>? _settingsUpdated;
    private string RootPath => Path.Combine(layout.UserPath, "AutoPathing");
    private string ConfigPath => Path.Combine(layout.UserPath, "config.json");

    public void AttachSettingsUpdated(Action<PathingConditionConfig> callback) =>
        _settingsUpdated = callback ?? throw new ArgumentNullException(nameof(callback));

    public IReadOnlyList<PathingCatalogEntry> List()
    {
        lock (_lock)
        {
            Directory.CreateDirectory(RootPath);
            var entries = new List<PathingCatalogEntry>();
            AppendDirectory(entries, RootPath, null);
            return entries;
        }
    }

    public object GetRootLocation()
    {
        Directory.CreateDirectory(RootPath);
        return new { path = RootPath };
    }

    public PathingTaskDetail GetDetail(string id)
    {
        lock (_lock)
        {
            var path = ResolveEntry(id);
            if (Directory.Exists(path))
            {
                return new PathingTaskDetail(
                    NormalizeId(id), Path.GetFileName(path), null, null, null, null,
                    "Directory", string.Empty, 0, [], ReadReadme(path));
            }

            RequireJsonFile(path);
            var task = PathingTask.BuildFromFilePath(path)
                ?? throw new InvalidDataException(
                    $"Pathing task requires a newer BetterGI version: {NormalizeId(id)}");
            return new PathingTaskDetail(
                NormalizeId(id),
                string.IsNullOrWhiteSpace(task.Info.Name)
                    ? Path.GetFileNameWithoutExtension(path)
                    : task.Info.Name,
                task.Info.Description,
                task.Info.Author,
                task.Info.Version,
                task.Info.BgiVersion,
                task.Info.Type,
                task.Info.MapName,
                task.Positions.Count,
                task.Info.Tags,
                null);
        }
    }

    public ScriptGroupProject BuildProject(string id)
    {
        lock (_lock)
        {
            var path = ResolveEntry(id);
            RequireJsonFile(path);
            var relativeFolder = Path.GetRelativePath(RootPath, Path.GetDirectoryName(path)!);
            if (relativeFolder == ".") relativeFolder = string.Empty;
            return ScriptGroupProject.BuildPathingProject(Path.GetFileName(path), relativeFolder);
        }
    }

    public object Delete(string id)
    {
        lock (_lock)
        {
            var normalized = NormalizeId(id);
            var path = ResolveEntry(normalized);
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
                return new { id = normalized, deleted = true, type = "directory" };
            }

            RequireJsonFile(path);
            File.Delete(path);
            return new { id = normalized, deleted = true, type = "route" };
        }
    }

    public object GetSettings()
    {
        lock (_lock)
        {
            return DescribeSettings(LoadSettings());
        }
    }

    public object SaveSettings(JObject settings)
    {
        var partyConditions = ParseConditions(
            settings["partyConditions"] as JArray
            ?? throw new ArgumentException("partyConditions is required."),
            ConditionDefinitions.PartySubjects,
            allowFreeformResult: true);
        var avatarConditions = ParseConditions(
            settings["avatarConditions"] as JArray
            ?? throw new ArgumentException("avatarConditions is required."),
            ConditionDefinitions.AvatarSubjects,
            allowFreeformResult: false);
        var useGadgetIntervalMs = settings.Value<int?>("useGadgetIntervalMs")
            ?? throw new ArgumentException("useGadgetIntervalMs is required.");
        if (useGadgetIntervalMs is < 0 or > 3_600_000)
            throw new ArgumentOutOfRangeException(
                nameof(useGadgetIntervalMs), useGadgetIntervalMs,
                "useGadgetIntervalMs must be between 0 and 3600000.");
        var autoEatEnabled = settings.Value<bool?>("autoEatEnabled")
            ?? throw new ArgumentException("autoEatEnabled is required.");
        var recoverTimingText = settings.Value<string>("recoverTiming")
            ?? throw new ArgumentException("recoverTiming is required.");
        if (!Enum.TryParse<RecoverTiming>(recoverTimingText, out var recoverTiming) ||
            !Enum.IsDefined(recoverTiming))
        {
            throw new ArgumentException($"Unsupported recoverTiming: {recoverTimingText}");
        }

        lock (_lock)
        {
            var root = LoadRoot();
            var config = root["pathingConditionConfig"]?.Deserialize<PathingConditionConfig>(
                ConfigJson.Options) ?? new PathingConditionConfig();
            config.PartyConditions = new ObservableCollection<Condition>(partyConditions);
            config.AvatarConditions = new ObservableCollection<Condition>(avatarConditions);
            config.UseGadgetIntervalMs = useGadgetIntervalMs;
            config.AutoEatEnabled = autoEatEnabled;
            config.RecoverTiming = recoverTiming;
            root["pathingConditionConfig"] = JsonSerializer.SerializeToNode(
                config, ConfigJson.Options);
            SaveRoot(root);
            _settingsUpdated?.Invoke(config);
            return DescribeSettings(config);
        }
    }

    private void AppendDirectory(
        ICollection<PathingCatalogEntry> entries,
        string directory,
        string? parentId)
    {
        foreach (var child in new DirectoryInfo(directory).EnumerateDirectories()
                     .Where(item => !item.Attributes.HasFlag(FileAttributes.ReparsePoint))
                     .OrderBy(item => item.Name, StringComparer.OrdinalIgnoreCase))
        {
            var id = RelativeId(child.FullName);
            entries.Add(new PathingCatalogEntry(id, parentId, child.Name, true));
            AppendDirectory(entries, child.FullName, id);
        }

        foreach (var file in new DirectoryInfo(directory).EnumerateFiles("*.json")
                     .Where(item => !item.Attributes.HasFlag(FileAttributes.ReparsePoint))
                     .OrderBy(item => item.Name, StringComparer.OrdinalIgnoreCase))
        {
            entries.Add(new PathingCatalogEntry(
                RelativeId(file.FullName),
                parentId,
                Path.GetFileNameWithoutExtension(file.Name),
                false));
        }
    }

    private object DescribeSettings(PathingConditionConfig config) => new
    {
        partyConditions = config.PartyConditions.Select(DescribeCondition).ToArray(),
        avatarConditions = config.AvatarConditions.Select(DescribeCondition).ToArray(),
        config.UseGadgetIntervalMs,
        config.AutoEatEnabled,
        recoverTiming = config.RecoverTiming.ToString(),
        partySubjects = ConditionDefinitions.PartySubjects,
        avatarSubjects = ConditionDefinitions.AvatarSubjects,
        avatarResults = ConditionDefinitions.AvatarResultList,
        definitions = ConditionDefinitions.Definitions.ToDictionary(
            item => item.Key,
            item => new
            {
                predicates = item.Value.PredicateOptions,
                objects = item.Value.ObjectOptions?.ToArray() ?? [],
                results = item.Value.ResultOptions?.ToArray() ?? [],
                description = item.Value.Description,
            })
    };

    private static object DescribeCondition(Condition condition) => new
    {
        subject = condition.Subject ?? string.Empty,
        condition.Predicate,
        objects = condition.Object.ToArray(),
        result = condition.Result ?? string.Empty,
    };

    private static IReadOnlyList<Condition> ParseConditions(
        JArray items,
        IReadOnlyCollection<string> allowedSubjects,
        bool allowFreeformResult)
    {
        return items.OfType<JObject>().Select(item =>
        {
            var subject = item.Value<string>("subject")?.Trim()
                ?? throw new ArgumentException("Condition subject is required.");
            if (!allowedSubjects.Contains(subject))
                throw new ArgumentException($"Unsupported condition subject: {subject}");
            var definition = ConditionDefinitions.Definitions[subject];
            var predicate = item.Value<string>("predicate")?.Trim()
                ?? throw new ArgumentException("Condition predicate is required.");
            if (!definition.PredicateOptions.Contains(predicate))
                throw new ArgumentException($"Unsupported predicate for {subject}: {predicate}");
            var objects = item["objects"]?.Values<string>()
                .Where(value => !string.IsNullOrWhiteSpace(value))
                .Select(value => value!.Trim())
                .Distinct(StringComparer.Ordinal)
                .ToArray()
                ?? throw new ArgumentException("Condition objects are required.");
            var allowedObjects = definition.ObjectOptions?.ToHashSet(StringComparer.Ordinal) ?? [];
            var unknownObject = objects.FirstOrDefault(value => !allowedObjects.Contains(value));
            if (unknownObject is not null)
                throw new ArgumentException($"Unsupported object for {subject}: {unknownObject}");
            var result = item.Value<string>("result")?.Trim() ?? string.Empty;
            if (!allowFreeformResult &&
                !(definition.ResultOptions ?? []).Contains(result))
            {
                throw new ArgumentException($"Unsupported result for {subject}: {result}");
            }
            return new Condition
            {
                Subject = subject,
                Predicate = predicate,
                Object = new ObservableCollection<string>(objects),
                Result = result,
            };
        }).ToArray();
    }

    private PathingConditionConfig LoadSettings() =>
        LoadRoot()["pathingConditionConfig"]?.Deserialize<PathingConditionConfig>(
            ConfigJson.Options) ?? new PathingConditionConfig();

    private JsonObject LoadRoot()
    {
        if (!File.Exists(ConfigPath)) return [];
        return JsonNode.Parse(File.ReadAllText(ConfigPath), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip,
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
    }

    private void SaveRoot(JsonObject root)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(ConfigPath)!);
        var temporaryPath = ConfigPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        File.WriteAllText(
            temporaryPath,
            root.ToJsonString(ConfigJson.Options),
            new UTF8Encoding(false));
        File.Move(temporaryPath, ConfigPath, overwrite: true);
    }

    private string ResolveEntry(string id)
    {
        var normalized = NormalizeId(id);
        var path = Path.GetFullPath(Path.Combine(
            RootPath,
            normalized.Replace('/', Path.DirectorySeparatorChar)));
        var rootPrefix = Path.GetFullPath(RootPath)
            .TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!path.StartsWith(rootPrefix, StringComparison.Ordinal))
            throw new UnauthorizedAccessException("Pathing entry escapes User/AutoPathing.");
        EnsureNoSymlink(path);
        if (!File.Exists(path) && !Directory.Exists(path))
            throw new FileNotFoundException($"Pathing entry does not exist: {normalized}", path);
        return path;
    }

    private void EnsureNoSymlink(string path)
    {
        var current = Path.GetFullPath(RootPath);
        var relative = Path.GetRelativePath(current, path);
        foreach (var component in relative.Split(
                     Path.DirectorySeparatorChar,
                     StringSplitOptions.RemoveEmptyEntries))
        {
            current = Path.Combine(current, component);
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new UnauthorizedAccessException("Pathing entries cannot traverse symbolic links.");
        }
    }

    private static void RequireJsonFile(string path)
    {
        if (!File.Exists(path) ||
            !string.Equals(Path.GetExtension(path), ".json", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Pathing task must be an existing JSON file.");
        }
    }

    private string RelativeId(string path) =>
        Path.GetRelativePath(RootPath, path)
            .Replace(Path.DirectorySeparatorChar, '/');

    private static string NormalizeId(string id)
    {
        if (string.IsNullOrWhiteSpace(id))
            throw new ArgumentException("Pathing entry id cannot be empty.", nameof(id));
        var normalized = id.Replace('\\', '/').Trim('/');
        if (normalized.Length == 0 ||
            normalized.Split('/').Any(component => component is "." or ".." or ""))
        {
            throw new ArgumentException("Invalid pathing entry id.", nameof(id));
        }
        return normalized;
    }

    private static string? ReadReadme(string directory)
    {
        var path = new[] { "README.md", "readme.md" }
            .Select(name => Path.Combine(directory, name))
            .FirstOrDefault(File.Exists);
        if (path is null) return null;
        var info = new FileInfo(path);
        if (info.Length > MaximumReadmeBytes)
            throw new InvalidDataException("Pathing README exceeds the 1 MiB limit.");
        return File.ReadAllText(path);
    }
}
