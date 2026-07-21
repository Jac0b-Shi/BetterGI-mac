using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.Core.Script.Project;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.GameTask.Model.Area;
using Newtonsoft.Json.Linq;
using Microsoft.ClearScript;
using Microsoft.ClearScript.V8;
using Microsoft.ClearScript.JavaScript;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using System.Text.RegularExpressions;

var root = args.Length == 1
    ? Path.GetFullPath(args[0])
    : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "betterGI-mac");
var layout = new RuntimeLayout(root);
var groupPath = Path.Combine(layout.ScriptGroupPath, "狗粮+锄地.json");
if (!File.Exists(groupPath))
    throw new FileNotFoundException("Required real ScriptGroup is missing.", groupPath);

Global.StartUpPath = root;
var document = new ScriptGroupCatalog(layout).Get("狗粮+锄地");
var group = ScriptGroup.FromJson(document.Document.ToString());
if (group.Projects.Count == 0)
    throw new InvalidDataException("狗粮+锄地 contains no projects.");

var projectCatalog = new ScriptProjectCatalog(layout);
var javascriptProjects = group.Projects.Where(project => project.Type == "Javascript").ToArray();
if (javascriptProjects.Length == 0)
    throw new InvalidDataException("狗粮+锄地 contains no JavaScript projects.");

foreach (var groupProject in javascriptProjects)
{
    if (groupProject.JsScriptSettingsObject is null)
        throw new InvalidDataException($"{groupProject.FolderName} has no jsScriptSettingsObject.");
    var catalogProject = projectCatalog.Get(groupProject.FolderName);
    var scriptProject = new ScriptProject(groupProject.FolderName);
    if (!string.Equals(scriptProject.Manifest.Name, groupProject.Name, StringComparison.Ordinal))
        throw new InvalidDataException(
            $"Manifest name mismatch for {groupProject.FolderName}: {scriptProject.Manifest.Name} != {groupProject.Name}");
    var loader = new PackageDocumentLoader(scriptProject.ProjectPath);
    VerifyJavaScriptGraph(scriptProject, loader);
    Console.WriteLine(
        $"PASS {groupProject.FolderName}: graph=compiled, main={scriptProject.Manifest.Main}, settings={((JArray)catalogProject.Settings).Count}, " +
        $"saved_files={scriptProject.Manifest.SavedFiles?.Length ?? 0}, libraries={scriptProject.Manifest.Library?.Length ?? 0}");
}

var recordingRuntime = new RecordingGlobalMethodRuntime();
GlobalMethod.Configure(recordingRuntime);
ScriptHostServices.Configure(new VerificationScriptHostServices());
ScriptProjectHost.Configure(new MacScriptProjectHostInitializer());
VerifyProductionHostSurface(javascriptProjects);

var executableProject = javascriptProjects.SingleOrDefault(project =>
    project.FolderName == "ExitGameMultipleMode")
    ?? throw new InvalidDataException("狗粮+锄地 must reference ExitGameMultipleMode for execution verification.");
await new ScriptProject(executableProject.FolderName).ExecuteAsync(executableProject.JsScriptSettingsObject);
var expectedInput = new[] { "down:MENU", "down:F4", "up:MENU", "up:F4" };
if (!recordingRuntime.Input.SequenceEqual(expectedInput, StringComparer.Ordinal))
    throw new InvalidDataException(
        $"Real User script input order mismatch: {string.Join(",", recordingRuntime.Input)}");
Console.WriteLine(
    "PASS ExitGameMultipleMode: actual User project executed through shared ScriptProject/ClearScript host; " +
    "input=down:MENU,down:F4,up:MENU,up:F4");

Console.WriteLine($"Real User verification passed: group={group.Name}, projects={group.Projects.Count}, javascript={javascriptProjects.Length}.");

static void VerifyProductionHostSurface(IEnumerable<ScriptGroupProject> projects)
{
    string[] hostObjectNames =
    [
        "genshin", "dispatcher", "pathingScript", "keyMouseScript", "file", "log",
        "notification", "http", "strategyFile", "host"
    ];
    var hostPattern = new Regex(
        $@"\b(?<host>{string.Join("|", hostObjectNames.Select(Regex.Escape))})\s*\.\s*(?<member>[A-Za-z_$][A-Za-z0-9_$]*)",
        RegexOptions.CultureInvariant);
    var timerPattern = new Regex(
        "\\bnew\\s+RealtimeTimer\\s*\\(\\s*['\"](?<name>[^'\"]+)['\"]",
        RegexOptions.CultureInvariant);
    var memberReferences = new HashSet<(string Host, string Member)>();
    var timerNames = new HashSet<string>(StringComparer.Ordinal);

    foreach (var project in projects)
    {
        var projectPath = new ScriptProject(project.FolderName).ProjectPath;
        foreach (var sourcePath in Directory.EnumerateFiles(projectPath, "*.js", SearchOption.AllDirectories))
        {
            var source = File.ReadAllText(sourcePath);
            foreach (Match match in hostPattern.Matches(source))
                memberReferences.Add((match.Groups["host"].Value, match.Groups["member"].Value));
            foreach (Match match in timerPattern.Matches(source))
                timerNames.Add(match.Groups["name"].Value);
        }
    }

    var firstProject = projects.First();
    var firstProjectPath = new ScriptProject(firstProject.FolderName).ProjectPath;
    using var engine = new V8ScriptEngine(
        V8ScriptEngineFlags.UseCaseInsensitiveMemberBinding |
        V8ScriptEngineFlags.EnableTaskPromiseConversion);
    new MacScriptProjectHostInitializer().Initialize(
        engine, firstProjectPath, [".", "./packages"], firstProject.JsScriptSettingsObject);

    var hostTypes = new Dictionary<string, Type>(StringComparer.Ordinal)
    {
        ["genshin"] = typeof(Genshin),
        ["dispatcher"] = typeof(Dispatcher),
        ["pathingScript"] = typeof(AutoPathingScript),
        ["keyMouseScript"] = typeof(KeyMouseScript),
        ["file"] = typeof(LimitedFile),
        ["log"] = typeof(Log),
        ["notification"] = typeof(Notification),
        ["http"] = typeof(Http),
        ["strategyFile"] = typeof(StrategyFile),
        ["host"] = typeof(CustomHostFunctions)
    };
    var missingRoots = hostObjectNames
        .Where(name => !Convert.ToBoolean(engine.Evaluate(
            $"typeof globalThis['{name}'] !== 'undefined'")))
        .ToArray();
    if (missingRoots.Length > 0)
        throw new InvalidDataException(
            "Production script host is missing roots: " + string.Join(", ", missingRoots));

    var missingMembers = memberReferences
        .Where(reference => !hostTypes[reference.Host].GetMembers(
                System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance)
            .Any(member => string.Equals(
                member.Name, reference.Member, StringComparison.OrdinalIgnoreCase)))
        .Select(reference => $"{reference.Host}.{reference.Member}")
        .OrderBy(name => name, StringComparer.Ordinal)
        .ToArray();
    if (missingMembers.Length > 0)
        throw new InvalidDataException(
            "Real User projects reference missing production host members: " + string.Join(", ", missingMembers));

    string[] requiredGlobals =
    [
        "sleep", "getVersion", "keyDown", "keyUp", "keyPress", "setGameMetrics", "getGameMetrics",
        "moveMouseBy", "moveMouseTo", "click", "leftButtonClick", "leftButtonDown", "leftButtonUp",
        "rightButtonClick", "rightButtonDown", "rightButtonUp", "middleButtonClick", "middleButtonDown",
        "middleButtonUp", "verticalScroll", "captureGameRegion", "getAvatars", "inputText",
        "RealtimeTimer", "RecognitionObject", "BvPage", "BvLocator", "BvImage"
    ];
    var missingGlobals = requiredGlobals
        .Where(name => !Convert.ToBoolean(engine.Evaluate(
            $"typeof globalThis['{name}'] !== 'undefined'")))
        .ToArray();
    if (missingGlobals.Length > 0)
        throw new InvalidDataException(
            "Production script host is missing canonical globals: " + string.Join(", ", missingGlobals));

    var unsupportedTimers = timerNames
        .Where(name => name is not ("AutoPick" or "AutoSkip"))
        .OrderBy(name => name, StringComparer.Ordinal)
        .ToArray();
    if (unsupportedTimers.Length > 0)
        throw new InvalidDataException(
            "Real User projects request uncomposed realtime triggers: " + string.Join(", ", unsupportedTimers));
    if (!timerNames.SetEquals(["AutoPick", "AutoSkip"]))
        throw new InvalidDataException(
            "Real User realtime trigger surface changed: " + string.Join(", ", timerNames.Order()));

    Console.WriteLine(
        $"PASS production host surface: members={memberReferences.Count}, globals={requiredGlobals.Length}, " +
        $"realtimeTriggers={string.Join(",", timerNames.Order())}");
}

static void VerifyJavaScriptGraph(ScriptProject project, PackageDocumentLoader loader)
{
    var mainPath = Path.Combine(project.ProjectPath, project.Manifest.Main);
    var code = File.ReadAllText(mainPath);
    using var engine = new V8ScriptEngine(V8ScriptEngineFlags.EnableTaskPromiseConversion);
    engine.DocumentSettings.Loader = loader;
    engine.DocumentSettings.SearchPath = string.Join(';', project.ProjectPath, Path.Combine(project.ProjectPath, "packages"));
    var isModule = (project.Manifest.Library?.Length ?? 0) != 0
        || code.Contains("import ", StringComparison.Ordinal)
        || code.Contains("export ", StringComparison.Ordinal);
    if (!isModule)
    {
        using var compiled = engine.Compile(new DocumentInfo(new Uri(mainPath)), code);
        return;
    }

    try
    {
        var rewritten = loader.RewriteScriptCode(code, mainPath);
        engine.Evaluate(new DocumentInfo(new Uri(mainPath)) { Category = ModuleCategory.Standard }, rewritten);
    }
    catch (FileNotFoundException)
    {
        throw;
    }
    catch (ScriptEngineException exception) when (
        exception.ErrorDetails.Contains("ReferenceError", StringComparison.Ordinal))
    {
        // Static module linking has completed; execution stopped only because production host objects
        // are intentionally absent from this dependency-graph verifier.
    }
}

sealed class RecordingGlobalMethodRuntime : IGlobalMethodRuntime
{
    public List<string> Input { get; } = [];
    public CancellationToken CancellationToken => CancellationToken.None;
    public double DpiScale => 1;
    public void KeyDown(string key) => Input.Add($"down:{key}");
    public void KeyUp(string key) => Input.Add($"up:{key}");
    public void KeyPress(string key) => Input.Add($"press:{key}");
    public void MoveMouseBy(int x, int y) => Unexpected(nameof(MoveMouseBy));
    public void MoveMouseToGameCoordinate(int x, int y, int gameWidth, int gameHeight) =>
        Unexpected(nameof(MoveMouseToGameCoordinate));
    public void LeftButtonClick() => Unexpected(nameof(LeftButtonClick));
    public void LeftButtonDown() => Unexpected(nameof(LeftButtonDown));
    public void LeftButtonUp() => Unexpected(nameof(LeftButtonUp));
    public void RightButtonClick() => Unexpected(nameof(RightButtonClick));
    public void RightButtonDown() => Unexpected(nameof(RightButtonDown));
    public void RightButtonUp() => Unexpected(nameof(RightButtonUp));
    public void MiddleButtonClick() => Unexpected(nameof(MiddleButtonClick));
    public void MiddleButtonDown() => Unexpected(nameof(MiddleButtonDown));
    public void MiddleButtonUp() => Unexpected(nameof(MiddleButtonUp));
    public void VerticalScroll(int scrollAmountInClicks) => Unexpected(nameof(VerticalScroll));
    public ImageRegion CaptureGameRegion() => throw UnexpectedException(nameof(CaptureGameRegion));
    public string[] GetAvatars() => throw UnexpectedException(nameof(GetAvatars));
    public void InputText(string text) => Unexpected(nameof(InputText));
    private static void Unexpected(string member) => throw UnexpectedException(member);
    private static InvalidOperationException UnexpectedException(string member) =>
        new($"Real User execution invoked unexpected platform member {member}.");
}

sealed class VerificationScriptHostServices : IScriptHostServices
{
    public ILogger CreateLogger(string categoryName) => NullLogger.Instance;
    public ScriptGroupProject? CurrentProject => null;
    public TimeSpan ServerTimeZoneOffset => TimeSpan.FromHours(8);
    public bool JsNotificationEnabled => false;
    public void EmitNotification(ScriptNotificationKind kind, string message) =>
        throw new InvalidOperationException("Real User execution unexpectedly emitted a notification.");
}
