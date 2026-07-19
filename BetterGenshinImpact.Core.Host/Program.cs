using BetterGenshinImpact.Core.Host;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Core.Script.Project;
using BetterGenshinImpact.Core.Recorder;
using BetterGenshinImpact.GameTask.Shell;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.AutoPick.Assets;
using BetterGenshinImpact.GameTask.Common.Element.Assets;
using BetterGenshinImpact.Service;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;

if (!OperatingSystem.IsMacOS())
    throw new PlatformNotSupportedException("BetterGI Core Host currently supports macOS only.");

if (args is ["--dependency-smoke"])
{
    Console.WriteLine(JsonConvert.SerializeObject(NativeDependencySmoke.Run()));
    return;
}

static string RequiredArgument(string[] arguments, string name)
{
    var index = Array.IndexOf(arguments, name);
    if (index < 0 || index + 1 >= arguments.Length || string.IsNullOrWhiteSpace(arguments[index + 1]))
        throw new ArgumentException($"Missing required argument: {name}");
    return arguments[index + 1];
}

var runtimeRoot = RequiredArgument(args, "--runtime-root");
var socketPath = RequiredArgument(args, "--socket");
var sessionToken = RequiredArgument(args, "--session-token");
var layout = new RuntimeLayout(runtimeRoot);
Global.StartUpPath = layout.RootPath;
var socketDirectory = Path.GetDirectoryName(Path.GetFullPath(socketPath));
if (socketDirectory is null || Path.GetFullPath(socketDirectory) != layout.RunPath)
    throw new ArgumentException("Socket must be located in the runtime Run directory.");
if (System.Text.Encoding.UTF8.GetByteCount(socketPath) > 103)
    throw new ArgumentException("Socket path exceeds the macOS sockaddr_un limit (103 UTF-8 bytes).", nameof(socketPath));

using var shutdown = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) => { eventArgs.Cancel = true; shutdown.Cancel(); };
var server = new CoreRpcServer(socketPath, sessionToken, layout);
using var loggerFactory = LoggerFactory.Create(builder => builder.AddSimpleConsole(options =>
{
    options.SingleLine = true;
    options.TimestampFormat = "HH:mm:ss.fff ";
}));
var scriptHostServices = new MacScriptHostServices(
    loggerFactory, server.PlatformCallbacks, sessionToken, shutdown.Token);
ScriptHostServices.Configure(scriptHostServices);
server.AttachScriptHostServices(scriptHostServices);
var captureRing = new SharedCaptureRingReader(layout);
var globalMethodRuntime = new MacGlobalMethodRuntime(
    server.PlatformCallbacks, sessionToken, shutdown.Token, captureRing);
var gameTaskManagerPlatform = new MacGameTaskManagerPlatform(
    server.PlatformCallbacks, sessionToken, shutdown.Token);
var bvSimpleOperationPlatform = new MacBvSimpleOperationPlatform(
    layout, gameTaskManagerPlatform.SystemInfo);
server.AttachPlatformAssetInitializer(() =>
{
    MapAssets.Initialize(gameTaskManagerPlatform.SystemInfo);
    ElementAssets.Initialize(gameTaskManagerPlatform.SystemInfo);
    BetterGenshinImpact.GameTask.AutoFight.Assets.AutoFightAssets.Initialize(
        gameTaskManagerPlatform.SystemInfo);
    BetterGenshinImpact.GameTask.AutoFishing.Assets.AutoFishingAssets.Initialize(
        gameTaskManagerPlatform.SystemInfo);
    BetterGenshinImpact.GameTask.AutoSkip.Assets.AutoSkipAssets.Initialize(
        gameTaskManagerPlatform.SystemInfo);
    BetterGenshinImpact.GameTask.QuickTeleport.Assets.QuickTeleportAssets.Initialize(
        gameTaskManagerPlatform.SystemInfo);
    AutoPickAssets.Initialize(
        gameTaskManagerPlatform.SystemInfo,
        new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
            bvSimpleOperationPlatform.AutoPickConfig,
            PaddleOcrModelConfig.V5Auto,
            "zh-Hans"),
        loggerFactory.CreateLogger<AutoPickAssets>());
});
var imageRegionOcrService = new MacImageRegionOcrService(
    layout, loggerFactory.CreateLogger<BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory>());
BetterGenshinImpact.Core.Recognition.OCR.ImageRegionOcrPlatform.Configure(imageRegionOcrService);
TaskControlPlatform.Configure(new MacTaskControlPlatform(
    server.PlatformCallbacks, sessionToken, shutdown.Token, captureRing,
    loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.Common.TaskControl")));
AutoFightRuntimePlatform.Configure(new MacAutoFightRuntimePlatform(
    gameTaskManagerPlatform.SystemInfo, imageRegionOcrService));
var autoFishingRuntimePlatform = new MacAutoFishingRuntimePlatform(
    layout, gameTaskManagerPlatform.SystemInfo, imageRegionOcrService, loggerFactory);
AutoFishingRuntimePlatform.Configure(autoFishingRuntimePlatform);
TaskParameterPlatform.Configure(new MacTaskParameterPlatform(
    autoFishingRuntimePlatform.GameCultureInfoName));
BvSimpleOperationPlatform.Configure(bvSimpleOperationPlatform);
AutoSkipRuntimePlatform.Configure(new MacAutoSkipRuntimePlatform(
    server.PlatformCallbacks, sessionToken, shutdown.Token));
ExitAndReloginPlatform.Configure(new MacExitAndReloginPlatform());
var pathExecutorPlatform = new MacPathExecutorPlatform(
    server.PlatformCallbacks, sessionToken, shutdown.Token);
PathExecutorPlatform.Configure(pathExecutorPlatform);
server.AttachPathExecutorPlatform(pathExecutorPlatform);
NavigationPlatform.Configure(new MacNavigationPlatform(
    server.PlatformCallbacks, sessionToken, shutdown.Token));
BetterGenshinImpact.GameTask.AutoFight.Script.CombatCommandPlatform.Configure(
    new MacCombatCommandPlatform(globalMethodRuntime));
BetterGenshinImpact.GameTask.AutoFight.Script.CombatSceneProvider.Configure(
    new MacCombatSceneProvider());
var scriptServicePlatform = new MacScriptServicePlatform(
    layout, loggerFactory.CreateLogger("BetterGenshinImpact.Service.ScriptService"), scriptHostServices,
    server.PlatformCallbacks, sessionToken, shutdown.Token, captureRing, gameTaskManagerPlatform);
ScriptServicePlatform.Configure(scriptServicePlatform);
server.AttachScriptServicePlatform(scriptServicePlatform);
ShellTaskPlatform.Configure(new MacShellTaskPlatform(server.PlatformCallbacks, sessionToken, shutdown.Token));
KeyMouseMacroPlatform.Configure(new MacKeyMouseMacroPlatform(
    server.PlatformCallbacks, sessionToken, shutdown.Token,
    loggerFactory.CreateLogger("BetterGenshinImpact.Core.Recorder.KeyMouseMacroPlayer")));
ScriptGroupExecutionServices.Configure(new MacScriptGroupExecutionServices());
DesktopRegionInputPlatform.Configure(new MacSemanticInputBackend(
    server.PlatformCallbacks, sessionToken, shutdown.Token));
TaskRunnerPlatform.Configure(new MacTaskRunnerPlatform(
    server.PlatformCallbacks, sessionToken, shutdown.Token,
    loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.TaskRunner"),
    loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.RunnerContext")));
GameTaskManagerPlatform.Configure(gameTaskManagerPlatform);
OverlayDrawPlatform.Configure(new MacOverlayDrawPlatform(
    server.PlatformCallbacks, sessionToken, shutdown.Token));
GlobalMethod.Configure(globalMethodRuntime);
ScriptProjectHost.Configure(new MacScriptProjectHostInitializer());
await server.RunAsync(shutdown.Token);
imageRegionOcrService.Dispose();
Microsoft.ML.OnnxRuntime.OrtEnv.Instance().Dispose();
