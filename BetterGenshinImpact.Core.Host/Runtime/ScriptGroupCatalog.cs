using BetterGenshinImpact.Core.Host.Protocol;
using BetterGenshinImpact.Core.Script.Group;
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
                project.RunNum)).ToArray());
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
