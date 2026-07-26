using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.GameTask.FarmingPlan;
using BetterGenshinImpact.Service;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

var runtimeRoot = ParseRuntimeRoot(args);
var pathingRoot = Path.Combine(runtimeRoot, "User", "AutoPathing");
if (!Directory.Exists(pathingRoot))
    throw new DirectoryNotFoundException($"AutoPathing runtime library is missing: {pathingRoot}");
ScriptServicePlatform.Configure(new VerificationScriptServicePlatform(pathingRoot));

string[] factoryOnlyLegacyActions = ["normal_attack", "elemental_skill"];
if (factoryOnlyLegacyActions.Any(PathExecutor.SupportsAction))
    throw new InvalidDataException(
        "PathExecutor began executing factory-only legacy actions that upstream currently ignores.");

var actionCounts = new Dictionary<string, int>(StringComparer.Ordinal);
var unsupported = new Dictionary<string, List<string>>(StringComparer.Ordinal);
var documentCount = 0;
var waypointCount = 0;

foreach (var path in Directory.EnumerateFiles(pathingRoot, "*.json", SearchOption.AllDirectories))
{
    PathingTask task;
    try
    {
        task = PathingTask.BuildFromJson(File.ReadAllText(path));
    }
    catch (Exception exception)
    {
        throw new InvalidDataException(
            $"Pathing document cannot be read by the production serializer: {path}", exception);
    }

    documentCount++;
    waypointCount += task.Positions.Count;
    foreach (var waypoint in task.Positions)
    {
        if (string.IsNullOrEmpty(waypoint.Action))
            continue;

        actionCounts[waypoint.Action] = actionCounts.GetValueOrDefault(waypoint.Action) + 1;
        if (PathExecutor.SupportsAction(waypoint.Action))
            continue;

        if (!unsupported.TryGetValue(waypoint.Action, out var paths))
        {
            paths = [];
            unsupported.Add(waypoint.Action, paths);
        }
        if (paths.Count < 5)
            paths.Add(Path.GetRelativePath(pathingRoot, path));
    }
}

if (documentCount == 0)
    throw new InvalidDataException($"AutoPathing runtime library contains no JSON documents: {pathingRoot}");
if (unsupported.Count > 0)
{
    var details = unsupported
        .OrderBy(pair => pair.Key, StringComparer.Ordinal)
        .Select(pair => $"{pair.Key}: {string.Join(", ", pair.Value)}");
    throw new InvalidDataException(
        "Runtime pathing library references actions that PathExecutor cannot execute:\n" +
        string.Join("\n", details));
}

Console.WriteLine(
    $"Pathing library verification passed: documents={documentCount}, waypoints={waypointCount}, " +
    $"actions={actionCounts.Count}");
foreach (var pair in actionCounts.OrderBy(pair => pair.Key, StringComparer.Ordinal))
    Console.WriteLine($"  {pair.Key}: {pair.Value}");

static string ParseRuntimeRoot(string[] arguments)
{
    if (arguments.Length == 0)
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "betterGI-mac");
    }
    if (arguments.Length == 2 && arguments[0] == "--runtime-root")
        return Path.GetFullPath(arguments[1]);

    throw new ArgumentException("Usage: BetterGenshinImpact.Pathing.Verification [--runtime-root <path>]");
}

sealed class VerificationScriptServicePlatform(string autoPathingRoot) : IScriptServicePlatform
{
    public ILogger Logger => NullLogger.Instance;
    public string AutoPathingRoot { get; } = autoPathingRoot;
    public string MapMatchingMethod => "TemplateMatch";
    public IReadOnlyList<ScriptGroup> ScriptGroups => [];
    public bool FarmingPlanEnabled => false;
    public SchedulerRestartPolicy RestartPolicy => default;

    public bool IsDailyFarmingLimitReached(FarmingSession farmingSession, out string message)
    {
        message = string.Empty;
        return false;
    }

    public void ClearTriggers() { }
    public void SetCurrentScriptProject(ScriptGroupProject project) { }
    public Task StartGameTask(bool waitForMainUi) => Task.CompletedTask;
    public Task HandleBlessingOfTheWelkinMoon(CancellationToken cancellationToken) => Task.CompletedTask;
    public void NotifyGroupStart(string groupName) { }
    public void NotifyGroupEndSuccess(string groupName) { }
    public void NotifyGroupEndError(string message) { }
    public void CloseGame() { }
    public void RestartApplication(string taskProgressName) { }
}
