using BetterGenshinImpact.Core.Host;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Core.Script.Project;
using BetterGenshinImpact.Core.Recorder;
using BetterGenshinImpact.GameTask.Shell;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.AutoTrackPath;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.AutoMusicGame;
using BetterGenshinImpact.GameTask.AutoWood;
using BetterGenshinImpact.GameTask.AutoBoss;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.AutoPick.Assets;
using BetterGenshinImpact.GameTask.FarmingPlan;
using BetterGenshinImpact.GameTask.QuickTeleport;
using BetterGenshinImpact.GameTask.AutoEat;
using BetterGenshinImpact.GameTask.GameLoading;
using BetterGenshinImpact.GameTask.MapMask;
using BetterGenshinImpact.GameTask.SkillCd;
using BetterGenshinImpact.GameTask.UseRedeemCode;
using BetterGenshinImpact.GameTask.Common.Element.Assets;
using BetterGenshinImpact.Service;
using BetterGenshinImpact.Helpers;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

if (!OperatingSystem.IsMacOS())
    throw new PlatformNotSupportedException("BetterGI Core Host currently supports macOS only.");

if (args is ["--dependency-smoke"])
{
    Console.WriteLine(JsonConvert.SerializeObject(NativeDependencySmoke.Run()));
    return;
}

if (args is ["--recognition-smoke", "--runtime-root", var recognitionRuntimeRoot])
{
    Global.StartUpPath = Path.GetFullPath(recognitionRuntimeRoot);
    Console.WriteLine(JsonConvert.SerializeObject(
        RecognitionResourceSmoke.Run(Global.StartUpPath)));
    return;
}

static string RequiredArgument(string[] arguments, string name)
{
    var index = Array.IndexOf(arguments, name);
    if (index < 0 || index + 1 >= arguments.Length || string.IsNullOrWhiteSpace(arguments[index + 1]))
        throw new ArgumentException($"Missing required argument: {name}");
    return arguments[index + 1];
}

static int? OptionalPositiveIntArgument(string[] arguments, string name)
{
    var index = Array.IndexOf(arguments, name);
    if (index < 0)
        return null;
    if (index + 1 >= arguments.Length || !int.TryParse(arguments[index + 1], out var value) || value <= 0)
        throw new ArgumentException($"Invalid positive integer argument: {name}");
    return value;
}

var runtimeRoot = RequiredArgument(args, "--runtime-root");
var socketPath = RequiredArgument(args, "--socket");
var sessionToken = RequiredArgument(args, "--session-token");
var parentProcessId = OptionalPositiveIntArgument(args, "--parent-pid");
var layout = new RuntimeLayout(runtimeRoot);
Global.StartUpPath = layout.RootPath;
var socketDirectory = Path.GetDirectoryName(Path.GetFullPath(socketPath));
if (socketDirectory is null || Path.GetFullPath(socketDirectory) != layout.RunPath)
    throw new ArgumentException("Socket must be located in the runtime Run directory.");
if (System.Text.Encoding.UTF8.GetByteCount(socketPath) > 103)
    throw new ArgumentException("Socket path exceeds the macOS sockaddr_un limit (103 UTF-8 bytes).", nameof(socketPath));

using var shutdown = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) => { eventArgs.Cancel = true; shutdown.Cancel(); };
var parentLifetimeTask = parentProcessId is { } processId
    ? new ParentProcessLifetime(processId).MonitorAsync(shutdown.Cancel, shutdown.Token)
    : null;
var nativeDependencies = NativeDependencySmoke.Run();
var server = new CoreRpcServer(socketPath, sessionToken, layout, nativeDependencies);
using var loggerFactory = LoggerFactory.Create(builder => builder.AddSimpleConsole(options =>
{
    options.SingleLine = true;
    options.TimestampFormat = "HH:mm:ss.fff ";
}));
var scriptHostServices = new MacScriptHostServices(loggerFactory);
var notificationSettings = new NotificationSettingsCatalog(
    layout, server.PlatformCallbacks, sessionToken, shutdown.Token);
notificationSettings.AttachScriptHostServices(scriptHostServices);
server.AttachNotificationSettings(notificationSettings);
ScriptHostServices.Configure(scriptHostServices);
ServerTimeHelper.Initialize(new ServerTimeProvider(TimeProvider.System, () => scriptHostServices.ServerTimeZoneOffset));
server.AttachScriptHostServices(scriptHostServices);
var runtimeArtifactProvisioner = new RuntimeArtifactProvisioner(
    layout, loggerFactory.CreateLogger<RuntimeArtifactProvisioner>());
server.AttachRuntimeArtifactInitializer(() =>
    runtimeArtifactProvisioner.EnsureInstalled(shutdown.Token));
var gameTaskManagerPlatform = new MacGameTaskManagerPlatform(
    layout, server.PlatformCallbacks, sessionToken, shutdown.Token, loggerFactory);
var captureRing = new SharedCaptureRingReader(
    layout, () => gameTaskManagerPlatform.SystemInfo.DesktopRectArea);
var foregroundInputCoordinator = new ForegroundInputCoordinator(
    server.PlatformCallbacks, sessionToken, shutdown.Token);
var globalMethodRuntime = new MacGlobalMethodRuntime(
    server.PlatformCallbacks, sessionToken, shutdown.Token, captureRing, foregroundInputCoordinator);
BetterGenshinImpact.Core.BgiVision.BvRuntimePlatform.Configure(
    new MacBvRuntimePlatform(() => gameTaskManagerPlatform.SystemInfo));
var bvSimpleOperationPlatform = new MacBvSimpleOperationPlatform(
    layout, () => gameTaskManagerPlatform.SystemInfo);
var imageRegionOcrService = new MacImageRegionOcrService(
    layout, loggerFactory.CreateLogger<BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory>());
var autoPickConfigProvider = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    bvSimpleOperationPlatform.AutoPickConfig, PaddleOcrModelConfig.V5Auto, "zh-Hans");
server.TriggerSettings.AttachAutoPickUpdated(autoPickConfigProvider.UpdateAutoPickConfig);
server.TriggerSettings.AttachAutoPickListsUpdated(() => GameTaskManager.RefreshTriggerConfig("AutoPick"));
server.TriggerSettings.AttachAutoSkipUpdated(gameTaskManagerPlatform.UpdateAutoSkipConfig);
var autoPickRuntimeState = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(
    () => RunnerContext.Instance.AutoPickTriggerStopCount);
var semanticInputBackend = new MacSemanticInputBackend(
    foregroundInputCoordinator, shutdown.Token);
var paddleAutoPickRecognizer = imageRegionOcrService.CreatePaddleAutoPickTextRecognizer();
var yapAutoPickRecognizer = imageRegionOcrService.CreateYapAutoPickTextRecognizer(layout);
var platformCallbacks = server.PlatformCallbacks;
var triggerDispatcher = new MacTriggerDispatcher(
    loggerFactory.CreateLogger<MacTriggerDispatcher>(),
    shutdown.Token,
    stopCleanup: async cancellationToken =>
    {
        var result = await platformCallbacks.InvokeAsync(
            "htmlMask.closeAll", null, sessionToken, cancellationToken);
        if (result is not JObject response ||
            response.Value<bool?>("acknowledged") != true)
        {
            throw new InvalidDataException(
                "macOS did not acknowledge HTML mask cleanup.");
        }
    });
server.AttachTriggerDispatcher(triggerDispatcher);
server.AttachPlatformAssetInitializer(() =>
{
    GameTaskManager.LoadInitialTriggers(
        semanticInputBackend, gameTaskManagerPlatform.SystemInfo, autoPickRuntimeState,
        autoPickConfigProvider, paddleAutoPickRecognizer, yapAutoPickRecognizer);
});
BetterGenshinImpact.Core.Recognition.OCR.ImageRegionOcrPlatform.Configure(imageRegionOcrService);
TaskControlPlatform.Configure(new MacTaskControlPlatform(
    server.PlatformCallbacks, sessionToken, shutdown.Token, captureRing,
    loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.Common.TaskControl"),
    foregroundInputCoordinator, new GameActionKeyResolver(layout)));
var autoFightRuntimePlatform = new MacAutoFightRuntimePlatform(
    layout, () => gameTaskManagerPlatform.SystemInfo, imageRegionOcrService, loggerFactory);
AutoFightRuntimePlatform.Configure(autoFightRuntimePlatform);
server.SoloTaskSettings.AttachAutoFightConfigUpdated(autoFightRuntimePlatform.UpdateConfig);
var autoWoodRuntimePlatform = new MacAutoWoodRuntimePlatform();
var autoMusicGameRuntimePlatform = new MacAutoMusicGameRuntimePlatform(
    () => gameTaskManagerPlatform.SystemInfo.AssetScale);
var autoAlbumRuntimePlatform = new MacAutoAlbumRuntimePlatform(
    () => gameTaskManagerPlatform.SystemInfo,
    loggerFactory.CreateLogger<AutoAlbumTask>());
var useRedemptionCodeRuntimePlatform = new MacUseRedemptionCodeRuntimePlatform(
    () => gameTaskManagerPlatform.SystemInfo,
    server.PlatformCallbacks, sessionToken, shutdown.Token,
    loggerFactory.CreateLogger<UseRedemptionCodeTask>());
var autoFishingRuntimePlatform = new MacAutoFishingRuntimePlatform(
    layout, () => gameTaskManagerPlatform.SystemInfo, imageRegionOcrService, loggerFactory);
AutoFishingRuntimePlatform.Configure(autoFishingRuntimePlatform);
server.SoloTaskSettings.AttachAutoFishingConfigUpdated(autoFishingRuntimePlatform.UpdateConfig);
var autoDomainRuntimePlatform = new MacAutoDomainRuntimePlatform(
    () => gameTaskManagerPlatform.SystemInfo, imageRegionOcrService, loggerFactory,
    server.PlatformCallbacks, sessionToken, shutdown.Token);
var autoSkipRuntimePlatform = new MacAutoSkipRuntimePlatform(
    () => gameTaskManagerPlatform.SystemInfo, loggerFactory, imageRegionOcrService,
    server.PlatformCallbacks, sessionToken, shutdown.Token, foregroundInputCoordinator,
    autoPickConfigProvider);
AutoSkipRuntimePlatform.Configure(autoSkipRuntimePlatform);
GenshinRuntimePlatform.Configure(new MacGenshinRuntimePlatform(
    () => gameTaskManagerPlatform.SystemInfo, autoFishingRuntimePlatform,
    imageRegionOcrService, loggerFactory, autoSkipRuntimePlatform, "TemplateMatch"));
TaskParameterPlatform.Configure(new MacTaskParameterPlatform(
    autoFishingRuntimePlatform.GameCultureInfoName));
GoToCraftingBenchRuntimePlatform.Configure(
    new MacGoToCraftingBenchRuntimePlatform(layout, imageRegionOcrService));
CraftMaterialRuntimePlatform.Configure(new MacCraftMaterialRuntimePlatform(
    loggerFactory.CreateLogger<CraftMaterialTask>()));
BetterGenshinImpact.GameTask.Model.GameUI.GridScreenRuntimePlatform.Configure(
    new MacGridScreenRuntimePlatform(() => gameTaskManagerPlatform.SystemInfo));
BetterGenshinImpact.GameTask.Common.Reward.RewardResultRuntimePlatform.Configure(
    new MacRewardResultRuntimePlatform(
        imageRegionOcrService,
        loggerFactory.CreateLogger<BetterGenshinImpact.GameTask.Common.Reward.RewardResultRecognizer>()));
BvSimpleOperationPlatform.Configure(bvSimpleOperationPlatform);
TpTaskRuntimePlatform.Configure(new MacTpTaskRuntimePlatform(
    layout, () => gameTaskManagerPlatform.SystemInfo));
var autoEatRuntimePlatform = new MacAutoEatRuntimePlatform(layout, loggerFactory);
AutoEatRuntimePlatform.Configure(autoEatRuntimePlatform);
server.TriggerSettings.AttachAutoEatUpdated(autoEatRuntimePlatform.UpdateConfig);
GameLoadingRuntimePlatform.Configure(new MacGameLoadingRuntimePlatform(
    layout, () => gameTaskManagerPlatform.SystemInfo, loggerFactory,
    server.PlatformCallbacks, sessionToken, shutdown.Token, foregroundInputCoordinator));
var mapMaskRuntimePlatform = new MacMapMaskRuntimePlatform(
    layout, loggerFactory, server.PlatformCallbacks, sessionToken, shutdown.Token);
MapMaskRuntimePlatform.Configure(mapMaskRuntimePlatform);
server.AttachMapMaskRuntimePlatform(mapMaskRuntimePlatform);
server.TriggerSettings.AttachMapMaskUpdated(mapMaskRuntimePlatform.UpdateConfig);
var skillCdRuntimePlatform = new MacSkillCdRuntimePlatform(
    layout, () => gameTaskManagerPlatform.SystemInfo, loggerFactory,
    server.PlatformCallbacks, sessionToken, shutdown.Token);
SkillCdRuntimePlatform.Configure(skillCdRuntimePlatform);
server.TriggerSettings.AttachSkillCdUpdated(skillCdRuntimePlatform.UpdateConfig);
ExitAndReloginPlatform.Configure(new MacExitAndReloginPlatform());
var pathExecutorPlatform = new MacPathExecutorPlatform(
    layout, imageRegionOcrService,
    server.PlatformCallbacks, sessionToken, shutdown.Token);
PathExecutorPlatform.Configure(pathExecutorPlatform);
PathExecutorAutoSkipPlatform.Configure(new PathExecutorAutoSkipSessionFactory());
server.AttachPathExecutorPlatform(pathExecutorPlatform);
NavigationPlatform.Configure(new MacNavigationPlatform(
    server.PlatformCallbacks, sessionToken, shutdown.Token));
var quickTeleportRuntimePlatform = new MacQuickTeleportRuntimePlatform(
    layout, server.PlatformCallbacks, sessionToken, shutdown.Token);
QuickTeleportRuntimePlatform.Configure(quickTeleportRuntimePlatform);
server.HotKeySettings.AttachUpdated((id, hotkey) =>
{
    if (id == "QuickTeleportTickHotkey")
        quickTeleportRuntimePlatform.UpdateTickHotkey(hotkey);
});
server.TriggerSettings.AttachQuickTeleportUpdated(quickTeleportRuntimePlatform.UpdateConfig);
BetterGenshinImpact.GameTask.AutoFight.Script.CombatCommandPlatform.Configure(
    new MacCombatCommandPlatform(globalMethodRuntime));
BetterGenshinImpact.GameTask.AutoFight.Script.CombatSceneProvider.Configure(
    new MacCombatSceneProvider());
var scriptServicePlatform = new MacScriptServicePlatform(
    layout, loggerFactory.CreateLogger("BetterGenshinImpact.Service.ScriptService"), scriptHostServices,
    server.PlatformCallbacks, sessionToken, shutdown.Token, captureRing, gameTaskManagerPlatform,
    foregroundInputCoordinator);
ScriptServicePlatform.Configure(scriptServicePlatform);
FarmingStatsRuntimePlatform.Configure(new MacFarmingStatsRuntimePlatform(
    layout, loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.FarmingPlan.FarmingStatsRecorder")));
server.AttachScriptServicePlatform(scriptServicePlatform);
ShellTaskPlatform.Configure(new MacShellTaskPlatform(foregroundInputCoordinator, shutdown.Token));
KeyMouseMacroPlatform.Configure(new MacKeyMouseMacroPlatform(
    server.PlatformCallbacks, sessionToken, shutdown.Token,
    loggerFactory.CreateLogger("BetterGenshinImpact.Core.Recorder.KeyMouseMacroPlayer"),
    foregroundInputCoordinator));
server.AttachKeyMouseScriptCoordinator(new KeyMouseScriptCoordinator(
    layout, loggerFactory.CreateLogger<KeyMouseScriptCoordinator>(), shutdown.Token));
var scriptGroupExecutionServices = new MacScriptGroupExecutionServices(
    layout, autoPickRuntimeState, semanticInputBackend, () => gameTaskManagerPlatform.SystemInfo,
    autoPickConfigProvider, paddleAutoPickRecognizer, yapAutoPickRecognizer);
ScriptGroupExecutionServices.Configure(scriptGroupExecutionServices);
var tpConfig = MacDispatcherRuntimePlatform.LoadUserConfig<
    BetterGenshinImpact.GameTask.AutoTrackPath.TpConfig>(layout, "tpConfig");
var autoLeyLineOutcropRuntimePlatform = new MacAutoLeyLineOutcropRuntimePlatform(
    () => gameTaskManagerPlatform.SystemInfo, imageRegionOcrService,
    autoFightRuntimePlatform, autoPickConfigProvider, tpConfig.MapScaleFactor,
    loggerFactory, server.PlatformCallbacks, sessionToken, shutdown.Token);
var autoStygianOnslaughtRuntimePlatform = new MacAutoStygianOnslaughtRuntimePlatform(
    () => gameTaskManagerPlatform.SystemInfo, imageRegionOcrService,
    autoPickConfigProvider, loggerFactory, server.PlatformCallbacks,
    sessionToken, shutdown.Token);
var autoGeniusInvokationRuntimePlatform = new MacAutoGeniusInvokationRuntimePlatform(
    layout, () => gameTaskManagerPlatform.SystemInfo,
    imageRegionOcrService, loggerFactory);
var autoFightConfig = MacDispatcherRuntimePlatform.LoadUserConfig<AutoFightConfig>(
    layout, "autoFightConfig");
var autoBossRuntimePlatform = new MacAutoBossRuntimePlatform(
    () => gameTaskManagerPlatform.SystemInfo, imageRegionOcrService, autoFightConfig,
    loggerFactory, server.PlatformCallbacks, sessionToken, shutdown.Token);
var autoBossPathExecutorFactory = new AutoBossPathExecutorFactory(
    scriptGroupExecutionServices,
    scriptGroupExecutionServices.CreateDefaultPartyConfig);
var dispatcherRuntimePlatform = new MacDispatcherRuntimePlatform(
    shutdown.Token, autoPickRuntimeState, semanticInputBackend,
    () => gameTaskManagerPlatform.SystemInfo, autoPickConfigProvider,
    paddleAutoPickRecognizer, yapAutoPickRecognizer, autoWoodRuntimePlatform,
    autoMusicGameRuntimePlatform, autoAlbumRuntimePlatform,
    useRedemptionCodeRuntimePlatform,
    autoDomainRuntimePlatform, autoBossRuntimePlatform,
    autoBossPathExecutorFactory, autoEatRuntimePlatform,
    autoLeyLineOutcropRuntimePlatform, autoStygianOnslaughtRuntimePlatform,
    autoGeniusInvokationRuntimePlatform,
    scriptGroupExecutionServices,
    imageRegionOcrService, layout, server.SoloTaskSettings,
    foregroundInputCoordinator, loggerFactory);
DispatcherRuntimePlatform.Configure(dispatcherRuntimePlatform);
server.AttachSoloTaskCoordinator(new SoloTaskCoordinator(
    dispatcherRuntimePlatform, server.SoloTaskSettings, shutdown.Token));
DesktopRegionInputPlatform.Configure(semanticInputBackend);
TaskRunnerPlatform.Configure(new MacTaskRunnerPlatform(
    server.PlatformCallbacks, sessionToken, shutdown.Token,
    loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.TaskRunner"),
    loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.RunnerContext"),
    foregroundInputCoordinator));
GameTaskManagerPlatform.Configure(gameTaskManagerPlatform);
OverlayDrawPlatform.Configure(new MacOverlayDrawPlatform(
    server.PlatformCallbacks, sessionToken, shutdown.Token));
GlobalMethod.Configure(globalMethodRuntime);
ScriptProjectHost.Configure(new MacScriptProjectHostInitializer(
    scriptGroupExecutionServices,
    server.PlatformCallbacks,
    sessionToken,
    shutdown.Token));
await server.RunAsync(shutdown.Token);
shutdown.Cancel();
if (parentLifetimeTask is not null)
{
    try
    {
        await parentLifetimeTask;
    }
    catch (OperationCanceledException) when (shutdown.IsCancellationRequested)
    {
    }
}
imageRegionOcrService.Dispose();
Microsoft.ML.OnnxRuntime.OrtEnv.Instance().Dispose();
