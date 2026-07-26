namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class RuntimeLayout
{
    private static readonly string[] UserDirectories =
    [
        "JsScript", "AutoPathing", "AutoFight", "AutoGeniusInvokation",
        "KeyMouseScript", "ScriptGroup", "OneDragon", "Subscriptions", "Temp",
        Path.Combine("Cache", "MemoryFileCache")
    ];

    public RuntimeLayout(string rootPath)
    {
        if (string.IsNullOrWhiteSpace(rootPath))
            throw new ArgumentException("Runtime root cannot be empty.", nameof(rootPath));
        RootPath = Path.GetFullPath(rootPath);
    }

    public string RootPath { get; }
    public string UserPath => Path.Combine(RootPath, "User");
    public string ScriptGroupPath => Path.Combine(UserPath, "ScriptGroup");
    public string OneDragonPath => Path.Combine(UserPath, "OneDragon");
    public string KeyMouseScriptPath => Path.Combine(UserPath, "KeyMouseScript");
    public string RunPath => Path.Combine(RootPath, "Run");
    public string LogPath => Path.Combine(RootPath, "log");
    public string DownloadCachePath => Path.Combine(RootPath, "Cache", "Downloads");
    public string SchedulerStatePath => Path.Combine(RunPath, "scheduler-state.json");

    public void EnsureCreated()
    {
        Directory.CreateDirectory(RootPath);
        Directory.CreateDirectory(Path.Combine(RootPath, "Repos"));
        Directory.CreateDirectory(Path.Combine(RootPath, "Assets"));
        Directory.CreateDirectory(DownloadCachePath);
        Directory.CreateDirectory(Path.Combine(RootPath, "Cache", "Model"));
        Directory.CreateDirectory(Path.Combine(RootPath, "log"));
        Directory.CreateDirectory(RunPath);
        foreach (var relativePath in UserDirectories)
            Directory.CreateDirectory(Path.Combine(UserPath, relativePath));
    }
}
