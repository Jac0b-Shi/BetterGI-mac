using BetterGenshinImpact.Core.Host.Protocol;
using BetterGenshinImpact.Core.Script.Project;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class ScriptRepositoryCatalog(RuntimeLayout layout)
{
    private const string RepositoryFolderName = "bettergi-scripts-list";
    private const string ReleaseBranchName = "release";
    private static readonly HashSet<string> AllowedTextExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".txt", ".md", ".json", ".js", ".ts", ".vue", ".css", ".html",
        ".csv", ".xml", ".yaml", ".yml", ".ini", ".config"
    };
    private static readonly HashSet<string> AllowedImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".ico"
    };
    private static readonly IReadOnlyDictionary<string, string> UserDirectoryByRoot =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["pathing"] = "AutoPathing",
            ["js"] = "JsScript",
            ["combat"] = "AutoFight",
            ["tcg"] = "AutoGeniusInvokation"
        };
    public static readonly IReadOnlyDictionary<string, string> RepositoryChannels =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["CNB"] = "https://cnb.cool/bettergi/bettergi-scripts-list",
            ["GitCode"] = "https://gitcode.com/huiyadanli/bettergi-scripts-list",
            ["GitHub"] = "https://github.com/babalae/bettergi-scripts-list",
        };

    private static readonly Regex PackageReferenceRegex = new(
        """(?:import\s+(?:[\w\s{},*]*?from\s+)?|export\s+(?:[\w\s{},*]*?from\s+)?|require\s*\(\s*)['"]([^'"\n]+)['"]""",
        RegexOptions.Compiled);

    private readonly SemaphoreSlim _writeLock = new(1, 1);

    private string RepositoryRoot => Path.Combine(layout.RootPath, "Repos", RepositoryFolderName);
    private string RepositoryContentRoot => Path.Combine(RepositoryRoot, "repo");
    private string SubscriptionPath => Path.Combine(layout.UserPath, "Subscriptions", $"{RepositoryFolderName}.json");
    private string GuideStatusPath => Path.Combine(layout.UserPath, "Subscriptions", "script-repository-guide.json");
    private string WebIndexPath => Path.Combine(layout.RootPath, "Assets", "Web", "ScriptRepo", "index.html");

    public ScriptRepositoryState GetState()
    {
        layout.EnsureCreated();
        var indexPath = ResolveIndexPath(required: false);
        return new ScriptRepositoryState(
            indexPath is not null,
            RepositoryRoot,
            indexPath,
            File.Exists(WebIndexPath) ? WebIndexPath : null,
            indexPath is null ? null : File.GetLastWriteTime(indexPath),
            ReadSubscriptions());
    }

    public async Task<ScriptRepositoryUpdateResult> UpdateAsync(
        string channel,
        string repositoryUrl,
        CancellationToken cancellationToken)
    {
        if (!Uri.TryCreate(repositoryUrl, UriKind.Absolute, out var uri) ||
            uri.Scheme is not ("https" or "http"))
            throw new ArgumentException("Repository URL must be an HTTP(S) URL.", nameof(repositoryUrl));

        await _writeLock.WaitAsync(cancellationToken);
        try
        {
            layout.EnsureCreated();
            var previousHead = await TryReadHeadAsync(RepositoryRoot, cancellationToken);
            string status;
            if (Directory.Exists(Path.Combine(RepositoryRoot, ".git")))
            {
                await RunGitAsync(["-C", RepositoryRoot, "remote", "set-url", "origin", uri.AbsoluteUri], cancellationToken);
                await RunGitAsync(["-C", RepositoryRoot, "fetch", "--depth", "1", "origin", ReleaseBranchName], cancellationToken);
                await RunGitAsync(["-C", RepositoryRoot, "checkout", "-B", ReleaseBranchName, "FETCH_HEAD"], cancellationToken);
                await RunGitAsync(["-C", RepositoryRoot, "reset", "--hard", "FETCH_HEAD"], cancellationToken);
                await RunGitAsync(["-C", RepositoryRoot, "clean", "-fd"], cancellationToken);
                var currentHead = await TryReadHeadAsync(RepositoryRoot, cancellationToken);
                status = previousHead == currentHead ? "alreadyUpToDate" : "updated";
            }
            else
            {
                var staging = Path.Combine(layout.RootPath, "Repos", $".{RepositoryFolderName}-{Guid.NewGuid():N}");
                try
                {
                    await RunGitAsync(
                        ["clone", "--depth", "1", "--branch", ReleaseBranchName, "--single-branch",
                            uri.AbsoluteUri, staging],
                        cancellationToken);
                    ValidateRepository(staging);
                    ReplaceRepository(staging);
                }
                finally
                {
                    if (Directory.Exists(staging))
                        Directory.Delete(staging, true);
                }
                status = "cloned";
            }

            ValidateRepository(RepositoryRoot);
            RefreshUpdateIndex();
            return new ScriptRepositoryUpdateResult(
                status,
                channel,
                RepositoryRoot,
                ResolveIndexPath(required: true)!);
        }
        finally
        {
            _writeLock.Release();
        }
    }

    public async Task ResetAsync(CancellationToken cancellationToken)
    {
        await _writeLock.WaitAsync(cancellationToken);
        try
        {
            if (Directory.Exists(RepositoryRoot))
                Directory.Delete(RepositoryRoot, true);
        }
        finally
        {
            _writeLock.Release();
        }
    }

    public string GetRepoJson() => File.ReadAllText(ResolveIndexPath(required: true)!, Encoding.UTF8);

    public string GetSubscribedPathsJson() =>
        JsonConvert.SerializeObject(ReadSubscriptions());

    public string GetFile(string path)
    {
        try
        {
            var normalized = NormalizeWebPath(Uri.UnescapeDataString(path));
            var filePath = ResolveUnder(RepositoryContentRoot, normalized);
            RejectSymbolicLink(filePath);
            if (!File.Exists(filePath))
                return "404";
            var extension = Path.GetExtension(filePath);
            if (AllowedTextExtensions.Contains(extension))
                return File.ReadAllText(filePath, Encoding.UTF8);
            if (AllowedImageExtensions.Contains(extension))
                return Convert.ToBase64String(File.ReadAllBytes(filePath));
            return "404";
        }
        catch
        {
            return "404";
        }
    }

    public async Task<ScriptRepositoryImportResult> ImportUriAsync(
        string uri,
        CancellationToken cancellationToken)
    {
        var paths = DecodeImportUri(uri);
        foreach (var path in paths)
            await InstallAsync(path, cancellationToken);
        return new ScriptRepositoryImportResult(paths.Count, ReadSubscriptions());
    }

    public async Task<ScriptRepositoryBatchUpdateResult> UpdateSubscribedAsync(
        CancellationToken cancellationToken)
    {
        await _writeLock.WaitAsync(cancellationToken);
        try
        {
            layout.EnsureCreated();
            ValidateRepository(RepositoryRoot);

            var subscriptions = ReadSubscriptions();
            var validSubscriptions = subscriptions
                .Where(RepositoryItemExists)
                .ToArray();
            if (validSubscriptions.Length != subscriptions.Count)
                WriteSubscriptions(validSubscriptions);

            var paths = ExpandTopLevelSubscriptions(validSubscriptions)
                .Where(RepositoryItemExists)
                .Distinct(StringComparer.Ordinal)
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
            var failedPaths = new List<string>();
            var successCount = 0;
            foreach (var path in paths)
            {
                cancellationToken.ThrowIfCancellationRequested();
                try
                {
                    _ = InstallCore(path, persistSubscription: false);
                    successCount++;
                }
                catch
                {
                    failedPaths.Add(path);
                }
            }

            return new ScriptRepositoryBatchUpdateResult(
                paths.Length,
                successCount,
                failedPaths.Count,
                failedPaths,
                validSubscriptions);
        }
        finally
        {
            _writeLock.Release();
        }
    }

    public async Task<ScriptRepositoryBatchUpdateResult> UpdateRepositoryAndSubscribedAsync(
        string channel,
        string repositoryUrl,
        CancellationToken cancellationToken)
    {
        _ = await UpdateAsync(channel, repositoryUrl, cancellationToken);
        return await UpdateSubscribedAsync(cancellationToken);
    }

    public async Task<ScriptRepositoryBatchUpdateResult> AutoUpdateSubscribedAsync(
        bool commandLineRun,
        CancellationToken cancellationToken)
    {
        var preferences = ReadAutoUpdatePreferences();
        if (!preferences.AutoUpdateSubscribedScripts ||
            commandLineRun && !preferences.AutoUpdateBeforeCommandLineRun)
            return EmptyBatchResult();

        var subscriptions = ReadSubscriptions();
        if (subscriptions.Count == 0)
            return EmptyBatchResult();

        var repositoryUrl = ResolveRepositoryUrl(preferences);
        if (repositoryUrl is null)
            return EmptyBatchResult();

        return await UpdateRepositoryAndSubscribedAsync(
            preferences.Channel, repositoryUrl, cancellationToken);
    }

    public bool ResetUpdateFlag(string path)
    {
        var normalizedPath = NormalizePath(path);
        var indexPath = ResolveIndexPath(required: true)!;
        var root = JObject.Parse(File.ReadAllText(indexPath, Encoding.UTF8));
        var nodes = (JArray?)root["indexes"] ?? throw new InvalidDataException("Repository index has no indexes array.");
        var node = (JObject)FindNode(nodes, normalizedPath);
        ResetUpdateFlag(node);
        WriteAtomic(indexPath, root.ToString(Formatting.Indented) + Environment.NewLine);
        return true;
    }

    public bool ClearUpdateFlags()
    {
        var originalPath = Path.Combine(RepositoryRoot, "repo.json");
        if (!File.Exists(originalPath))
            throw new FileNotFoundException("Repository index does not exist.", originalPath);
        File.Copy(originalPath, Path.Combine(RepositoryRoot, "repo_updated.json"), true);
        return true;
    }

    public bool GetGuideStatus()
    {
        if (!File.Exists(GuideStatusPath))
            return false;
        return JObject.Parse(File.ReadAllText(GuideStatusPath, Encoding.UTF8)).Value<bool?>("completed") ?? false;
    }

    public bool SetGuideStatus(bool status)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(GuideStatusPath)!);
        WriteAtomic(
            GuideStatusPath,
            new JObject { ["completed"] = status }.ToString(Formatting.Indented) + Environment.NewLine);
        return true;
    }

    public async Task<ScriptRepositoryInstallResult> InstallAsync(string path, CancellationToken cancellationToken)
    {
        var normalizedPath = NormalizePath(path);
        await _writeLock.WaitAsync(cancellationToken);
        try
        {
            return InstallCore(normalizedPath, persistSubscription: true);
        }
        finally
        {
            _writeLock.Release();
        }
    }

    private ScriptRepositoryInstallResult InstallCore(
        string normalizedPath,
        bool persistSubscription)
    {
        layout.EnsureCreated();
        _ = FindNode((JArray?)ReadIndex()["indexes"] ?? [], normalizedPath);
        var source = ResolveUnder(RepositoryContentRoot, normalizedPath);
        if (!File.Exists(source) && !Directory.Exists(source))
            throw new FileNotFoundException("Repository item does not exist.", source);

        var destination = DestinationPath(normalizedPath);
        var stagingRoot = Path.Combine(
            layout.UserPath, "Temp", "repository-install", Guid.NewGuid().ToString("N"));
        var staged = Path.Combine(stagingRoot, "payload");
        Directory.CreateDirectory(stagingRoot);
        try
        {
            CopyItem(source, staged);
            if (normalizedPath.StartsWith("js/", StringComparison.OrdinalIgnoreCase) &&
                Directory.Exists(staged))
            {
                PreserveSavedFiles(source, destination, staged);
                ResolvePackageDependencies(staged);
            }
            ReplaceItem(staged, destination, stagingRoot);
        }
        finally
        {
            if (Directory.Exists(stagingRoot))
                Directory.Delete(stagingRoot, true);
        }

        var subscriptions = persistSubscription
            ? AddSubscription(normalizedPath)
            : ReadSubscriptions();
        return new ScriptRepositoryInstallResult(normalizedPath, destination, subscriptions);
    }

    private AutoUpdatePreferences ReadAutoUpdatePreferences()
    {
        var configPath = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(configPath))
            return new(false, false, "CNB", "");

        var root = JObject.Parse(File.ReadAllText(configPath, Encoding.UTF8));
        var script = root["scriptConfig"] as JObject;
        var channel = script?.Value<string>("selectedChannelName");
        if (string.IsNullOrWhiteSpace(channel) ||
            channel != "自定义" && !RepositoryChannels.ContainsKey(channel))
            channel = "CNB";
        return new AutoUpdatePreferences(
            script?.Value<bool?>("autoUpdateSubscribedScripts") ?? false,
            script?.Value<bool?>("autoUpdateBeforeCommandLineRun") ?? false,
            channel,
            script?.Value<string>("customRepoUrl") ?? "");
    }

    private static string? ResolveRepositoryUrl(AutoUpdatePreferences preferences)
    {
        if (preferences.Channel == "自定义")
        {
            var value = preferences.CustomUrl.Trim();
            if (value.Length == 0 ||
                value == "https://example.com/custom-repo" ||
                !Uri.TryCreate(value, UriKind.Absolute, out var customUri) ||
                customUri.Scheme is not ("https" or "http"))
                return null;
            return customUri.AbsoluteUri;
        }

        return RepositoryChannels.TryGetValue(preferences.Channel, out var url)
            ? url
            : RepositoryChannels["CNB"];
    }

    private ScriptRepositoryBatchUpdateResult EmptyBatchResult() =>
        new(0, 0, 0, [], ReadSubscriptions());

    private sealed record AutoUpdatePreferences(
        bool AutoUpdateSubscribedScripts,
        bool AutoUpdateBeforeCommandLineRun,
        string Channel,
        string CustomUrl);

    private JObject ReadIndex()
    {
        var path = ResolveIndexPath(required: true)!;
        return JObject.Parse(File.ReadAllText(path, Encoding.UTF8));
    }

    private static IReadOnlyList<string> DecodeImportUri(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
            !string.Equals(uri.Scheme, "bettergi", StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(uri.Host, "script", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Invalid BetterGI script import URI.", nameof(value));
        var query = uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => part.Split('=', 2))
            .FirstOrDefault(part => part.Length == 2 &&
                string.Equals(Uri.UnescapeDataString(part[0]), "import", StringComparison.OrdinalIgnoreCase));
        if (query is null)
            throw new ArgumentException("Script import URI has no import payload.", nameof(value));
        var base64 = Uri.UnescapeDataString(query[1]).Replace(' ', '+');
        var decoded = Encoding.UTF8.GetString(Convert.FromBase64String(base64));
        var paths = JsonConvert.DeserializeObject<List<string>>(Uri.UnescapeDataString(decoded)) ?? [];
        return paths.Select(NormalizePath).Distinct(StringComparer.Ordinal).ToArray();
    }

    private static string NormalizeWebPath(string path)
    {
        var trimmed = path.Trim().Replace('\\', '/');
        var parts = trimmed.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0 || trimmed.StartsWith('/') || parts.Any(part => part is "." or ".."))
            throw new ArgumentException($"Unsafe repository path: {path}", nameof(path));
        return string.Join('/', parts);
    }

    private static void ResetUpdateFlag(JObject node)
    {
        if (node["hasUpdate"]?.Type == JTokenType.Boolean)
            node["hasUpdate"] = false;
        if (node["children"] is not JArray children)
            return;
        foreach (var child in children.OfType<JObject>())
            ResetUpdateFlag(child);
    }

    private void RefreshUpdateIndex()
    {
        var original = Path.Combine(RepositoryRoot, "repo.json");
        File.Copy(original, Path.Combine(RepositoryRoot, "repo_updated.json"), true);
    }

    private static void ValidateRepository(string root)
    {
        var indexPath = Path.Combine(root, "repo.json");
        var contentPath = Path.Combine(root, "repo");
        if (!File.Exists(indexPath))
            throw new InvalidDataException("Script repository has no repo.json.");
        if (!Directory.Exists(contentPath))
            throw new InvalidDataException("Script repository has no repo directory.");
        var rootObject = JObject.Parse(File.ReadAllText(indexPath, Encoding.UTF8));
        if (rootObject["indexes"] is not JArray)
            throw new InvalidDataException("Script repository index has no indexes array.");
    }

    private void ReplaceRepository(string staging)
    {
        var backup = Path.Combine(layout.RootPath, "Repos", $".{RepositoryFolderName}-previous-{Guid.NewGuid():N}");
        if (Directory.Exists(RepositoryRoot))
            Directory.Move(RepositoryRoot, backup);
        try
        {
            Directory.Move(staging, RepositoryRoot);
        }
        catch
        {
            if (Directory.Exists(backup))
                Directory.Move(backup, RepositoryRoot);
            throw;
        }
        if (Directory.Exists(backup))
            Directory.Delete(backup, true);
    }

    private static async Task<string?> TryReadHeadAsync(string repositoryRoot, CancellationToken cancellationToken)
    {
        if (!Directory.Exists(Path.Combine(repositoryRoot, ".git")))
            return null;
        try
        {
            return (await RunGitAsync(["-C", repositoryRoot, "rev-parse", "HEAD"], cancellationToken)).Trim();
        }
        catch
        {
            return null;
        }
    }

    private static async Task<string> RunGitAsync(
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo("/usr/bin/git")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        foreach (var argument in arguments)
            startInfo.ArgumentList.Add(argument);
        using var process = Process.Start(startInfo) ??
            throw new InvalidOperationException("Unable to start /usr/bin/git.");
        var standardOutput = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var standardError = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        var output = await standardOutput;
        var error = await standardError;
        if (process.ExitCode != 0)
            throw new InvalidOperationException(
                $"git {string.Join(' ', arguments)} failed ({process.ExitCode}): {error.Trim()}");
        return output;
    }

    private string? ResolveIndexPath(bool required)
    {
        var updated = Path.Combine(RepositoryRoot, "repo_updated.json");
        if (File.Exists(updated))
            return updated;
        var original = Path.Combine(RepositoryRoot, "repo.json");
        if (File.Exists(original))
            return original;
        if (!required)
            return null;
        throw new FileNotFoundException(
            "BetterGI script repository is unavailable. Update the local repository first.",
            original);
    }

    private static JToken FindNode(JArray roots, string normalizedPath)
    {
        JArray current = roots;
        JToken? found = null;
        foreach (var part in normalizedPath.Split('/'))
        {
            found = current.OfType<JObject>().SingleOrDefault(
                node => string.Equals(node.Value<string>("name"), part, StringComparison.Ordinal));
            if (found is null)
                throw new DirectoryNotFoundException($"Repository path does not exist: {normalizedPath}");
            current = (JArray?)found["children"] ?? [];
        }
        return found!;
    }

    private IReadOnlyList<string> ReadSubscriptions()
    {
        if (!File.Exists(SubscriptionPath))
            return [];
        try
        {
            return JsonConvert.DeserializeObject<List<string>>(File.ReadAllText(SubscriptionPath, Encoding.UTF8))?
                .Select(NormalizePath)
                .Distinct(StringComparer.Ordinal)
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray() ?? [];
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private IReadOnlyList<string> AddSubscription(string normalizedPath)
    {
        var paths = ReadSubscriptions()
            .Append(normalizedPath)
            .Distinct(StringComparer.Ordinal)
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToArray();
        WriteSubscriptions(paths);
        return paths;
    }

    private void WriteSubscriptions(IEnumerable<string> paths)
    {
        var normalized = paths
            .Select(NormalizePath)
            .Distinct(StringComparer.Ordinal)
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToArray();
        Directory.CreateDirectory(Path.GetDirectoryName(SubscriptionPath)!);
        WriteAtomic(
            SubscriptionPath,
            JsonConvert.SerializeObject(normalized, Formatting.Indented) + Environment.NewLine);
    }

    private bool RepositoryItemExists(string normalizedPath)
    {
        var source = ResolveUnder(RepositoryContentRoot, normalizedPath);
        return File.Exists(source) || Directory.Exists(source);
    }

    private IEnumerable<string> ExpandTopLevelSubscriptions(
        IEnumerable<string> subscriptions)
    {
        foreach (var path in subscriptions)
        {
            var parts = path.Split('/');
            if (parts.Length != 1)
            {
                yield return path;
                continue;
            }

            var source = ResolveUnder(RepositoryContentRoot, path);
            if (!Directory.Exists(source))
                continue;
            foreach (var child in Directory.EnumerateFileSystemEntries(source)
                         .OrderBy(Path.GetFileName, StringComparer.Ordinal))
            {
                RejectSymbolicLink(child);
                yield return NormalizePath($"{path}/{Path.GetFileName(child)}");
            }
        }
    }

    private string DestinationPath(string normalizedPath)
    {
        var parts = normalizedPath.Split('/');
        if (!UserDirectoryByRoot.TryGetValue(parts[0], out var userDirectory))
            throw new InvalidOperationException($"Unsupported repository root: {parts[0]}");
        var root = Path.Combine(layout.UserPath, userDirectory);
        return parts.Length == 1 ? root : ResolveUnder(root, string.Join(Path.DirectorySeparatorChar, parts.Skip(1)));
    }

    private static string NormalizePath(string path)
    {
        var trimmed = path.Trim().Replace('\\', '/');
        var parts = trimmed.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0 || trimmed.StartsWith('/') || parts.Any(part => part is "." or ".."))
            throw new ArgumentException($"Unsafe repository path: {path}", nameof(path));
        var root = parts[0].ToLowerInvariant();
        if (!UserDirectoryByRoot.ContainsKey(root))
            throw new ArgumentException($"Unsupported repository root: {parts[0]}", nameof(path));
        return string.Join('/', new[] { root }.Concat(parts.Skip(1)));
    }

    private static string ResolveUnder(string root, string relativePath)
    {
        var rootPath = Path.GetFullPath(root);
        var path = Path.GetFullPath(Path.Combine(rootPath, relativePath));
        if (path != rootPath && !path.StartsWith(rootPath + Path.DirectorySeparatorChar, StringComparison.Ordinal))
            throw new InvalidOperationException($"Path escapes repository boundary: {relativePath}");
        return path;
    }

    private static void CopyItem(string source, string destination)
    {
        if (File.Exists(source))
        {
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(source, destination, true);
            return;
        }
        CopyDirectory(source, destination);
    }

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (var file in Directory.EnumerateFiles(source))
        {
            RejectSymbolicLink(file);
            File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), true);
        }
        foreach (var directory in Directory.EnumerateDirectories(source))
        {
            RejectSymbolicLink(directory);
            CopyDirectory(directory, Path.Combine(destination, Path.GetFileName(directory)));
        }
    }

    private static void ReplaceItem(string staged, string destination, string stagingRoot)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        var previous = Path.Combine(stagingRoot, "previous");
        if (Directory.Exists(destination))
            Directory.Move(destination, previous);
        else if (File.Exists(destination))
            File.Move(destination, previous);
        try
        {
            if (Directory.Exists(staged))
                Directory.Move(staged, destination);
            else
                File.Move(staged, destination);
        }
        catch
        {
            if (Directory.Exists(previous))
                Directory.Move(previous, destination);
            else if (File.Exists(previous))
                File.Move(previous, destination);
            throw;
        }
        if (Directory.Exists(previous))
            Directory.Delete(previous, true);
        else if (File.Exists(previous))
            File.Delete(previous);
    }

    private static void PreserveSavedFiles(string source, string currentDestination, string stagedDestination)
    {
        if (!Directory.Exists(currentDestination))
            return;
        var manifestPath = Path.Combine(source, "manifest.json");
        if (!File.Exists(manifestPath))
            return;
        var manifest = Manifest.FromJson(File.ReadAllText(manifestPath, Encoding.UTF8));
        foreach (var pattern in manifest.SavedFiles)
        {
            var regex = GlobRegex(pattern);
            foreach (var file in EnumerateFilesWithoutLinks(currentDestination))
            {
                var relative = Path.GetRelativePath(currentDestination, file).Replace('\\', '/');
                if (!regex.IsMatch(relative))
                    continue;
                var destination = ResolveUnder(stagedDestination, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                File.Copy(file, destination, true);
            }
        }
    }

    private static Regex GlobRegex(string pattern)
    {
        var normalized = pattern.Trim().Replace('\\', '/').TrimStart('/');
        if (normalized.EndsWith('/'))
            normalized += "**";
        var builder = new StringBuilder("^");
        for (var index = 0; index < normalized.Length; index++)
        {
            var character = normalized[index];
            if (character == '*' && index + 1 < normalized.Length && normalized[index + 1] == '*')
            {
                builder.Append(".*");
                index++;
            }
            else if (character == '*')
                builder.Append("[^/]*");
            else if (character == '?')
                builder.Append("[^/]");
            else
                builder.Append(Regex.Escape(character.ToString()));
        }
        builder.Append('$');
        return new Regex(builder.ToString(), RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    }

    private void ResolvePackageDependencies(string stagedScript)
    {
        var queue = new Queue<string>(Directory.EnumerateFiles(stagedScript, "*.js", SearchOption.AllDirectories));
        var processed = new HashSet<string>(StringComparer.Ordinal);
        while (queue.TryDequeue(out var file))
        {
            if (!processed.Add(file))
                continue;
            var content = File.ReadAllText(file, Encoding.UTF8);
            foreach (Match match in PackageReferenceRegex.Matches(content))
            {
                var reference = match.Groups[1].Value.Replace('\\', '/');
                var packageIndex = reference.IndexOf("packages/", StringComparison.OrdinalIgnoreCase);
                string? packagePath = packageIndex >= 0 ? reference[packageIndex..] : null;
                if (packagePath is null && reference.StartsWith(".", StringComparison.Ordinal))
                {
                    var relativeCurrentFile = Path.GetRelativePath(stagedScript, file).Replace('\\', '/');
                    if (relativeCurrentFile.StartsWith("packages/", StringComparison.OrdinalIgnoreCase))
                    {
                        var relativeDirectory = Path.GetDirectoryName(relativeCurrentFile) ?? string.Empty;
                        var candidate = Path.GetFullPath(Path.Combine(stagedScript, relativeDirectory, reference));
                        var candidateRelative = Path.GetRelativePath(stagedScript, candidate).Replace('\\', '/');
                        if (candidateRelative.StartsWith("packages/", StringComparison.OrdinalIgnoreCase))
                            packagePath = candidateRelative;
                    }
                }
                if (packagePath is null)
                    continue;
                var source = ResolveUnder(RepositoryContentRoot, packagePath);
                if (!File.Exists(source) && File.Exists(source + ".js"))
                    source += ".js";
                if (!File.Exists(source))
                    continue;
                RejectSymbolicLink(source);
                var relative = Path.GetRelativePath(RepositoryContentRoot, source);
                var destination = ResolveUnder(stagedScript, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                File.Copy(source, destination, true);
                if (destination.EndsWith(".js", StringComparison.OrdinalIgnoreCase))
                    queue.Enqueue(destination);
            }
        }
    }

    private static IEnumerable<string> EnumerateFilesWithoutLinks(string root)
    {
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.TryPop(out var directory))
        {
            foreach (var file in Directory.EnumerateFiles(directory))
            {
                if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) == 0)
                    yield return file;
            }
            foreach (var child in Directory.EnumerateDirectories(directory))
            {
                if ((File.GetAttributes(child) & FileAttributes.ReparsePoint) == 0)
                    pending.Push(child);
            }
        }
    }

    private static void RejectSymbolicLink(string path)
    {
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            throw new InvalidDataException($"Repository item cannot be a symbolic link: {path}");
    }

    private static void WriteAtomic(string path, string content)
    {
        var temporary = path + $".{Guid.NewGuid():N}.tmp";
        File.WriteAllText(temporary, content, new UTF8Encoding(false));
        File.Move(temporary, path, true);
    }
}
