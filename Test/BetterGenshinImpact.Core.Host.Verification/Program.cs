using BetterGenshinImpact.Core.Host;
using BetterGenshinImpact.Core.Host.Protocol;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.Core.Script.Project;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Core.Script.Dependence.Model;
using BetterGenshinImpact.Core.Recorder;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.BgiVision;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.Common.Reward;
using BetterGenshinImpact.GameTask.Model.GameUI;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.GameTask.AutoPathing.Model.Enum;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoFight.Assets;
using BetterGenshinImpact.GameTask.AutoFight.Model;
using BetterGenshinImpact.GameTask.AutoTrackPath;
using BetterGenshinImpact.GameTask.AutoTrackPath.Model;
using BetterGenshinImpact.GameTask.Common.Element.Assets;
using BetterGenshinImpact.GameTask.Common.Map.Maps;
using BetterGenshinImpact.GameTask.FarmingPlan;
using BetterGenshinImpact.GameTask.QuickTeleport;
using BetterGenshinImpact.GameTask.AutoEat;
using BetterGenshinImpact.GameTask.GameLoading;
using BetterGenshinImpact.GameTask.MapMask;
using BetterGenshinImpact.GameTask.SkillCd;
using BetterGenshinImpact.Service;
using BetterGenshinImpact.Helpers;
using BetterGenshinImpact.GameTask.Shell;
using Microsoft.Extensions.Logging;
using Microsoft.ClearScript;
using Microsoft.ClearScript.JavaScript;
using Microsoft.ClearScript.V8;
using Newtonsoft.Json.Linq;
using System.Dynamic;
using System.Net.Sockets;
using System.Runtime.InteropServices;

if (!OperatingSystem.IsMacOS())
    throw new PlatformNotSupportedException("Core Host verification currently requires macOS.");

Require(ParentProcessLifetime.IsProcessAlive(Environment.ProcessId),
    "parent lifetime monitor did not recognize the current process");
var parentExitObserved = false;
using (var parentMonitorTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(1)))
{
    await new ParentProcessLifetime(int.MaxValue, TimeSpan.FromMilliseconds(1)).MonitorAsync(
        () => parentExitObserved = true,
        parentMonitorTimeout.Token);
}
Require(parentExitObserved,
    "parent lifetime monitor did not report a missing parent process");

var root = Path.Combine("/tmp", "bgi-" + Guid.NewGuid().ToString("N"));
var layout = new RuntimeLayout(root);
OverlayDrawPlatform.Configure(new VerificationOverlayDrawPlatform());
layout.EnsureCreated();
CopyDirectory(
    Path.Combine(Directory.GetCurrentDirectory(), "MacGI", "Sources", "MacGI", "Resources", "GameTask"),
    Path.Combine(layout.RootPath, "GameTask"));
var captureRingPath = Path.Combine(layout.RunPath, "capture-ring.bin");
const int captureHeaderSize = 128;
const int captureSlotCapacity = 16;
await using (var ring = new FileStream(captureRingPath, FileMode.Create, FileAccess.ReadWrite, FileShare.ReadWrite))
{
    ring.SetLength(captureHeaderSize + 2 * captureSlotCapacity);
    using var writer = new BinaryWriter(ring, System.Text.Encoding.UTF8, leaveOpen: true);
    writer.Write(System.Text.Encoding.ASCII.GetBytes("BGIRING1"));
    writer.Write(1u); writer.Write(2u); writer.Write((ulong)captureSlotCapacity);
    writer.Write(1u); writer.Write(2u); writer.Write(1u); writer.Write(8u);
    writer.Write(0x42475241u); writer.Write(0u); writer.Write((ulong)8); writer.Write((ulong)7);
    writer.Write(11); writer.Write(22); writer.Write(2u); writer.Write(1u); writer.Write((ulong)2);
    ring.Position = captureHeaderSize + captureSlotCapacity;
    writer.Write(new byte[] { 1, 2, 3, 255, 4, 5, 6, 255 });
}
File.SetUnixFileMode(captureRingPath, UnixFileMode.UserRead | UnixFileMode.UserWrite);
using (var captured = new SharedCaptureRingReader(layout).Read(JObject.FromObject(new
{
    ringPath = captureRingPath, frameId = 7UL, sequence = 2UL, slot = 1,
    width = 2, height = 1, stride = 8, pixelFormat = "BGRA8"
})).SrcMat)
{
    Require(captured.Width == 2 && captured.Height == 1 && captured.At<OpenCvSharp.Vec4b>(0, 1)[2] == 6,
        "shared capture ring did not preserve BGRA pixels and dimensions");
}
var groupPath = Path.Combine(layout.ScriptGroupPath, "狗粮+锄地.json");
await File.WriteAllTextAsync(groupPath, """
    {
      "index": 1,
      "name": "狗粮+锄地",
      "config": {
        "pathingConfig": {
          "enabled": true,
          "autoPickEnabled": true,
          "partyName": "战斗",
          "taskCycleConfig": {"enable": true, "boundaryTime": 4, "cycle": 3, "index": 2},
          "taskCompletionSkipRuleConfig": {"enable": true, "skipPolicy": "GroupPhysicalPathSkipPolicy", "boundaryTime": 4, "lastRunGapSeconds": -1},
          "preExecutionPriorityConfig": {"enabled": true, "groupNames": "每日", "maxRetryCount": 2},
          "autoFightConfig": {"strategyName": "万能战斗策略（萌新推荐）", "timeout": 120}
        },
        "shellConfig": {"disable": false, "timeout": 60, "noWindow": true, "output": true},
        "enableShellConfig": false
      },
      "projects": [{
        "name": "锄地一条龙",
        "folderName": "AutoHoeingOneDragon",
        "jsScriptSettingsObject": {"operationMode": "启用仅指定怪物模式", "targetMonsters": "愚人众特辖队，巡陆艇"},
        "index": 1,
        "type": "Javascript",
        "status": "Enabled",
        "schedule": "Daily",
        "runNum": 2,
        "allowJsNotification": true,
        "allowJsHTTPHash": ""
      }]
    }
    """);
var upstreamGroup = ScriptGroup.FromJson(await File.ReadAllTextAsync(groupPath));
Require(upstreamGroup.Name == "狗粮+锄地" && upstreamGroup.Projects.Count == 1,
    "upstream ScriptGroup did not deserialize the fixture");
Require(upstreamGroup.Projects[0].RunNum == 2 && upstreamGroup.Projects[0].GroupInfo == upstreamGroup,
    "upstream ScriptGroup lost RunNum or failed to restore GroupInfo");
var roundTrippedGroup = ScriptGroup.FromJson(upstreamGroup.ToJson());
Require(roundTrippedGroup.Config.PathingConfig.TaskCycleConfig.Cycle == 3 &&
        roundTrippedGroup.Config.PathingConfig.PreExecutionPriorityConfig.GroupNames == "每日",
    "upstream ScriptGroup round-trip lost scheduler configuration");
var scriptRoot = Path.Combine(root, "module-fixture");
Directory.CreateDirectory(Path.Combine(scriptRoot, "packages"));
await File.WriteAllTextAsync(Path.Combine(scriptRoot, "packages", "value.js"), "export const value = 40;");
var moduleMain = Path.Combine(scriptRoot, "main.js");
await File.WriteAllTextAsync(moduleMain, "import { value } from './packages/value.js'; globalThis.loaderResult = value + 2;");
using (var engine = new V8ScriptEngine(V8ScriptEngineFlags.EnableTaskPromiseConversion))
{
    var loader = new PackageDocumentLoader(scriptRoot);
    engine.DocumentSettings.Loader = loader;
    var source = await File.ReadAllTextAsync(moduleMain);
    var document = new DocumentInfo(new Uri(moduleMain)) { Category = ModuleCategory.Standard };
    _ = engine.Evaluate(document, loader.RewriteScriptCode(source, moduleMain));
    Require(Convert.ToInt32(engine.Script.loaderResult) == 42,
        "PackageDocumentLoader module import did not evaluate to 42");
}
var escapedMain = Path.Combine(scriptRoot, "escaped.js");
await File.WriteAllTextAsync(Path.Combine(root, "outside.js"), "export const outside = 1;");
await File.WriteAllTextAsync(escapedMain, "import { outside } from '../outside.js'; globalThis.escape = outside;");
using (var engine = new V8ScriptEngine())
{
    var loader = new PackageDocumentLoader(scriptRoot);
    engine.DocumentSettings.Loader = loader;
    var escapedCode = await File.ReadAllTextAsync(escapedMain);
    var document = new DocumentInfo(new Uri(escapedMain)) { Category = ModuleCategory.Standard };
    try
    {
        _ = engine.Evaluate(document, loader.RewriteScriptCode(escapedCode, escapedMain));
        throw new InvalidOperationException("PackageDocumentLoader accepted an import outside script root.");
    }
    catch (ScriptEngineException) { }
}
var manifestPath = Path.Combine(scriptRoot, "manifest.json");
await File.WriteAllTextAsync(manifestPath, """
    {"manifest_version":1,"name":"Core Fixture","version":"1.0.0","main":"main.js","settings_ui":"settings.json"}
    """);
await File.WriteAllTextAsync(Path.Combine(scriptRoot, "settings.json"), """
    [{"name":"targetMonsters","type":"multi-checkbox","label":"Target","options":["A","B"],"default":["A"]}]
    """);
var manifest = Manifest.FromJson(await File.ReadAllTextAsync(manifestPath));
manifest.Validate(scriptRoot);
var settings = manifest.LoadSettingItems(scriptRoot);
Require(settings.Count == 1 && settings[0].Name == "targetMonsters" && settings[0].Options?.SequenceEqual(["A", "B"]) == true,
    "upstream manifest/settings contract did not deserialize");
var runtimeProject = Path.Combine(layout.RootPath, "User", "JsScript", "CoreFixture");
Directory.CreateDirectory(runtimeProject);
await File.WriteAllTextAsync(Path.Combine(runtimeProject, "main.js"), "globalThis.test = true;");
await File.WriteAllTextAsync(Path.Combine(runtimeProject, "manifest.json"), await File.ReadAllTextAsync(manifestPath));
await File.WriteAllTextAsync(Path.Combine(runtimeProject, "settings.json"), await File.ReadAllTextAsync(Path.Combine(scriptRoot, "settings.json")));
Global.StartUpPath = layout.RootPath;
var upstreamProject = new ScriptProject("CoreFixture");
Require(upstreamProject.ProjectPath == runtimeProject && await upstreamProject.LoadCode() == "globalThis.test = true;",
    "upstream ScriptProject did not resolve User/JsScript under the runtime root");
await StageLockedRuntimeArtifactsAsync(layout.RootPath, CancellationToken.None);
var socketPath = Path.Combine(layout.RunPath, "verification.sock");
var sessionToken = Convert.ToHexString(Guid.NewGuid().ToByteArray());
using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(300));
await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "config.json"), """
    {
      "otherConfig": {
        "farmingPlanConfig": {
          "enabled": true,
          "dailyEliteCap": 10,
          "dailyMobCap": 20
        },
        "autoRestartConfig": {
          "enabled": true,
          "failureCount": 7,
          "restartGameTogether": true
        }
      },
      "genshinStartConfig": {
        "linkedStartEnabled": true,
        "autoEnterGameEnabled": false
      },
      "quickTeleportConfig": { "enabled": true, "hotkeyTpEnabled": true },
      "tpConfig": {
        "mapZoomEnabled": false,
        "reviveStatueOfTheSevenPointX": -575.6,
        "reviveStatueOfTheSevenPointY": 1859.34,
        "reviveStatueOfTheSevenArea": "苍风高地",
        "reviveStatueOfTheSevenCountry": "蒙德",
        "reviveStatueOfTheSeven": {
          "id": "3",
          "name": "七天神像-风",
          "type": "Goddess",
          "country": "蒙德",
          "areas": ["苍风高地"],
          "position": [1859.34, 258.0366, -575.6],
          "tranPosition": [1854.0525, 258.0366, -578.4359]
        },
        "hpRestoreDuration": 1
      },
      "hotKeyConfig": { "quickTeleportTickHotkey": "F6" },
      "autoEatConfig": { "enabled": true, "eatInterval": 1234 },
      "selectedOneDragonFlowConfigName": "selected-crafting"
    }
    """);
var oneDragonDirectory = Path.Combine(layout.UserPath, "OneDragon");
await File.WriteAllTextAsync(Path.Combine(oneDragonDirectory, "first.json"),
    """{"Name":"first-crafting","MinResinToKeep":20}""");
await File.WriteAllTextAsync(Path.Combine(oneDragonDirectory, "selected.json"),
    """{"Name":"selected-crafting","MinResinToKeep":80}""");
var server = new CoreRpcServer(socketPath, sessionToken, layout, NativeDependencySmoke.Run());
using var loggerFactory = LoggerFactory.Create(builder => builder.AddSimpleConsole());
var runtimeDispatcherIterations = 0;
var runtimeDispatcher = new MacTriggerDispatcher(
    loggerFactory.CreateLogger<MacTriggerDispatcher>(), cancellation.Token,
    async token =>
    {
        while (true)
        {
            await Task.Delay(10, token);
            Interlocked.Increment(ref runtimeDispatcherIterations);
        }
    });
server.AttachTriggerDispatcher(runtimeDispatcher);
var artifactInitializationCount = 0;
server.AttachRuntimeArtifactInitializer(() =>
{
    artifactInitializationCount++;
    return new RuntimeArtifactStatus(0, 34, "verification-source-lock.json");
});
var scriptHostServices = new MacScriptHostServices(
    loggerFactory, server.PlatformCallbacks, sessionToken, cancellation.Token);
scriptHostServices.SetJsNotificationEnabled(true);
scriptHostServices.SetServerTimeZoneOffset(TimeSpan.FromHours(8));
ServerTimeHelper.Initialize(new ServerTimeProvider(
    TimeProvider.System, () => scriptHostServices.ServerTimeZoneOffset));
scriptHostServices.SetCurrentProject(new ScriptGroupProject(upstreamProject) { AllowJsNotification = true });
ScriptHostServices.Configure(scriptHostServices);
server.AttachScriptHostServices(scriptHostServices);
var gameTaskManagerPlatform = new MacGameTaskManagerPlatform(
    layout, server.PlatformCallbacks, sessionToken, cancellation.Token, loggerFactory);
var foregroundInputCoordinator = new ForegroundInputCoordinator(
    server.PlatformCallbacks, sessionToken, cancellation.Token,
    focusProbe: () => true);
GameTaskManagerPlatform.Configure(gameTaskManagerPlatform);
BvRuntimePlatform.Configure(new MacBvRuntimePlatform(() => gameTaskManagerPlatform.SystemInfo));
var farmingScriptServicePlatform = new MacScriptServicePlatform(
    layout, loggerFactory.CreateLogger("BetterGenshinImpact.Service.ScriptService"), scriptHostServices,
    server.PlatformCallbacks, sessionToken, cancellation.Token, new SharedCaptureRingReader(layout),
    gameTaskManagerPlatform, foregroundInputCoordinator);
Require(farmingScriptServicePlatform.FarmingPlanEnabled,
    "macOS scheduler ignored the upstream farming-plan configuration");
Require(farmingScriptServicePlatform.RestartPolicy is
    { Enabled: true, FailureCount: 7, RestartGameTogether: true,
      LinkedStartEnabled: true, AutoEnterGameEnabled: false },
    "macOS scheduler did not load the upstream restart/start configuration");
FarmingStatsRuntimePlatform.Configure(new MacFarmingStatsRuntimePlatform(
    layout, loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.FarmingPlan.FarmingStatsRecorder")));
var farmingSession = new FarmingSession
{
    AllowFarmingCount = true,
    EliteMobCount = 2,
    NormalMobCount = 3,
    PrimaryTarget = "elite"
};
FarmingStatsRecorder.RecordFarmingSession(farmingSession, new FarmingRouteInfo
{
    GroupName = "验证组",
    ProjectName = "验证路径",
    FolderName = "fixture"
});
var recordedFarmingData = FarmingStatsRecorder.ReadDailyFarmingData();
Require(recordedFarmingData.TotalEliteMobCount == 2 &&
        recordedFarmingData.TotalNormalMobCount == 3 &&
        recordedFarmingData.Records is [{ GroupName: "验证组", ProjectName: "验证路径" }],
    "shared FarmingStatsRecorder did not persist the upstream counters and route record");
Require(!farmingScriptServicePlatform.IsDailyFarmingLimitReached(farmingSession, out _),
    "shared FarmingStatsRecorder reported a configured cap before it was reached");
FarmingStatsRecorder.RecordFarmingSession(new FarmingSession
{
    AllowFarmingCount = true,
    EliteMobCount = 8,
    PrimaryTarget = "elite"
}, new FarmingRouteInfo { GroupName = "验证组", ProjectName = "补足上限", FolderName = "fixture" });
Require(farmingScriptServicePlatform.IsDailyFarmingLimitReached(new FarmingSession
    {
        AllowFarmingCount = true,
        EliteMobCount = 1,
        PrimaryTarget = "elite"
    }, out var farmingLimitMessage) && farmingLimitMessage.Contains("精英超上限", StringComparison.Ordinal),
    "shared FarmingStatsRecorder did not enforce the upstream daily elite cap");
var executionConfig = System.Text.Json.Nodes.JsonNode
    .Parse(await File.ReadAllTextAsync(Path.Combine(layout.UserPath, "config.json")))!.AsObject();
executionConfig["otherConfig"]!["farmingPlanConfig"]!["enabled"] = false;
await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "config.json"), executionConfig.ToJsonString(ConfigJson.Options));
var scriptServicePlatform = new MacScriptServicePlatform(
    layout, loggerFactory.CreateLogger("BetterGenshinImpact.Service.ScriptService"), scriptHostServices,
    server.PlatformCallbacks, sessionToken, cancellation.Token, new SharedCaptureRingReader(layout),
    gameTaskManagerPlatform, foregroundInputCoordinator);
Require(!scriptServicePlatform.FarmingPlanEnabled,
    "Host Shell fixture must not enter the upstream farming-path cap check");
ScriptServicePlatform.Configure(scriptServicePlatform);
server.AttachScriptServicePlatform(scriptServicePlatform);
TaskRunnerPlatform.Configure(new MacTaskRunnerPlatform(
    server.PlatformCallbacks, sessionToken, cancellation.Token,
    loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.TaskRunner"),
    loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.RunnerContext"),
    foregroundInputCoordinator));
TaskControlPlatform.Configure(new MacTaskControlPlatform(
    server.PlatformCallbacks, sessionToken, cancellation.Token, new SharedCaptureRingReader(layout),
    loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.Common.TaskControl"),
    foregroundInputCoordinator));
var imageRegionOcrService = new MacImageRegionOcrService(
    layout, loggerFactory.CreateLogger<BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory>());
BetterGenshinImpact.Core.Recognition.OCR.ImageRegionOcrPlatform.Configure(imageRegionOcrService);
var autoFishingRuntimePlatform = new MacAutoFishingRuntimePlatform(
    layout, () => gameTaskManagerPlatform.SystemInfo, imageRegionOcrService, loggerFactory);
AutoFishingRuntimePlatform.Configure(autoFishingRuntimePlatform);
GenshinRuntimePlatform.Configure(new MacGenshinRuntimePlatform(
    () => gameTaskManagerPlatform.SystemInfo, autoFishingRuntimePlatform,
    imageRegionOcrService, loggerFactory, "TemplateMatch"));
AutoFightRuntimePlatform.Configure(new MacAutoFightRuntimePlatform(
    layout, () => gameTaskManagerPlatform.SystemInfo, imageRegionOcrService, loggerFactory));
var tpTaskPlatform = new MacTpTaskRuntimePlatform(
    layout, () => gameTaskManagerPlatform.SystemInfo);
TpTaskRuntimePlatform.Configure(tpTaskPlatform);
Require(tpTaskPlatform.TpConfig.ReviveStatueOfTheSeven is
        { Id: "3", Country: "蒙德", Level1Area: "苍风高地" } reviveStatue &&
        Math.Abs(reviveStatue.TranX - -578.4359) < 0.0001 &&
        Math.Abs(reviveStatue.TranY - 1854.0525) < 0.0001 &&
        Math.Abs(tpTaskPlatform.TpConfig.HpRestoreDuration - 1) < 0.0001,
    "macOS TpTask composition did not restore the upstream runtime-only statue object.");
TaskParameterPlatform.Configure(new MacTaskParameterPlatform(
    autoFishingRuntimePlatform.GameCultureInfoName));
var craftingBenchPlatform = new MacGoToCraftingBenchRuntimePlatform(layout, imageRegionOcrService);
GoToCraftingBenchRuntimePlatform.Configure(craftingBenchPlatform);
CraftMaterialRuntimePlatform.Configure(new MacCraftMaterialRuntimePlatform(
    loggerFactory.CreateLogger<CraftMaterialTask>()));
GridScreenRuntimePlatform.Configure(new MacGridScreenRuntimePlatform(
    () => gameTaskManagerPlatform.SystemInfo));
RewardResultRuntimePlatform.Configure(new MacRewardResultRuntimePlatform(
    imageRegionOcrService, loggerFactory.CreateLogger<RewardResultRecognizer>()));
Require(craftingBenchPlatform.SelectedConfigName == "selected-crafting" &&
        craftingBenchPlatform.LoadConfigs().Any(config =>
            config is { Name: "selected-crafting", MinResinToKeep: 80 }),
    "macOS crafting-bench platform did not read the real selected OneDragon configuration.");
var quickTeleportPlatform = new MacQuickTeleportRuntimePlatform(
    layout, server.PlatformCallbacks, sessionToken, cancellation.Token);
QuickTeleportRuntimePlatform.Configure(quickTeleportPlatform);
AutoSkipRuntimePlatform.Configure(new MacAutoSkipRuntimePlatform(
    () => gameTaskManagerPlatform.SystemInfo, loggerFactory, imageRegionOcrService,
    server.PlatformCallbacks, sessionToken, cancellation.Token, foregroundInputCoordinator,
    new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
        new BetterGenshinImpact.GameTask.AutoPick.AutoPickConfig(),
        BetterGenshinImpact.Core.Recognition.PaddleOcrModelConfig.V5Auto, "zh-Hans")));
AutoEatRuntimePlatform.Configure(new MacAutoEatRuntimePlatform(layout, loggerFactory));
var triggerGameLoadingPlatform = new MacGameLoadingRuntimePlatform(
    layout, () => gameTaskManagerPlatform.SystemInfo, loggerFactory,
    server.PlatformCallbacks, sessionToken, cancellation.Token, foregroundInputCoordinator);
GameLoadingRuntimePlatform.Configure(triggerGameLoadingPlatform);
MapMaskRuntimePlatform.Configure(new MacMapMaskRuntimePlatform(
    layout, loggerFactory, server.PlatformCallbacks, sessionToken, cancellation.Token));
SkillCdRuntimePlatform.Configure(new MacSkillCdRuntimePlatform(
    layout, () => gameTaskManagerPlatform.SystemInfo, loggerFactory,
    server.PlatformCallbacks, sessionToken, cancellation.Token));
var pathExecutorPlatform = new MacPathExecutorPlatform(
    layout, imageRegionOcrService, server.PlatformCallbacks, sessionToken, cancellation.Token);
PathExecutorPlatform.Configure(pathExecutorPlatform);
PathExecutorAutoSkipPlatform.Configure(new PathExecutorAutoSkipSessionFactory());
server.AttachPathExecutorPlatform(pathExecutorPlatform);
var navigationPlatform = new MacNavigationPlatform(
    server.PlatformCallbacks, sessionToken, cancellation.Token);
NavigationPlatform.Configure(navigationPlatform);
var verificationInputBackend = new MacSemanticInputBackend(
    foregroundInputCoordinator, cancellation.Token);
DesktopRegionInputPlatform.Configure(verificationInputBackend);
var verificationAutoPickConfig = new BetterGenshinImpact.GameTask.AutoPick.AutoPickConfig();
var verificationAutoPickConfigProvider = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    verificationAutoPickConfig, BetterGenshinImpact.Core.Recognition.PaddleOcrModelConfig.V5Auto, "zh-Hans");
var scriptGroupExecutionServices = new MacScriptGroupExecutionServices(
    layout,
    new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(
        () => RunnerContext.Instance.AutoPickTriggerStopCount),
    verificationInputBackend,
    () => throw new InvalidOperationException("Verification did not request AutoPick system metrics."),
    verificationAutoPickConfigProvider,
    imageRegionOcrService.CreatePaddleAutoPickTextRecognizer(),
    imageRegionOcrService.CreateYapAutoPickTextRecognizer(layout));
ScriptGroupExecutionServices.Configure(scriptGroupExecutionServices);
server.AttachPlatformAssetInitializer(() =>
{
    GameTaskManager.LoadInitialTriggers(
        verificationInputBackend, gameTaskManagerPlatform.SystemInfo,
        new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(
            () => RunnerContext.Instance.AutoPickTriggerStopCount),
        verificationAutoPickConfigProvider,
        imageRegionOcrService.CreatePaddleAutoPickTextRecognizer(),
        imageRegionOcrService.CreateYapAutoPickTextRecognizer(layout));
});
var shellPlatform = new MacShellTaskPlatform(foregroundInputCoordinator, cancellation.Token);
ShellTaskPlatform.Configure(shellPlatform);
var shellResult = await shellPlatform.ExecuteAsync(
    ShellTaskParam.BuildFromConfig(
        "printf 'shell-ok\\nsecond\\n'",
        new ShellConfig { Timeout = 10, Output = true, NoWindow = true }),
    waitForExit: true,
    cancellation.Token);
Require(shellResult.End && shellResult.Shell == "shell-ok" && shellResult.Output == "second\n",
    "macOS Shell platform did not execute zsh or preserve captured output ordering");
var serverTask = server.RunAsync(cancellation.Token);

try
{
    while (!File.Exists(socketPath))
        await Task.Delay(10, cancellation.Token);

    var mode = File.GetUnixFileMode(socketPath);
    Require(mode == (UnixFileMode.UserRead | UnixFileMode.UserWrite), $"socket mode was {mode}");

    await using var connection = await ConnectAsync(socketPath, cancellation.Token);
    var handshake = await ExchangeAsync(connection, "1", "core.handshake", sessionToken, null, cancellation.Token);
    Require(handshake.Error is null, handshake.Error?.Message ?? "handshake failed");
    var handshakeJson = JObject.FromObject(handshake.Result!);
    Require(handshakeJson.Value<int>("protocolVersion") == CoreRpcServer.ProtocolVersion, "protocol mismatch");
    Require(handshakeJson.Value<bool>("clearScriptReady"), "ClearScript V8 smoke failed");
    Require(handshakeJson.Value<string>("openCvVersion")?.StartsWith("4.13", StringComparison.Ordinal) == true,
        "OpenCV 4.13 smoke failed");
    var initialized = await ExchangeAsync(connection, "initialize", "core.initialize", sessionToken,
        JObject.FromObject(new
        {
            runtimeRoot = layout.RootPath,
            serverTimeZoneOffsetHours = 8,
            jsNotificationEnabled = true,
            mapMatchingMethod = "SIFT",
            autoFetchDispatchAdventurersGuildCountry = "璃月"
        }), cancellation.Token);
    Require(initialized.Error is null, initialized.Error?.Message ?? "core.initialize failed");
    var initializedJson = JObject.FromObject(initialized.Result!);
    Require(initializedJson.Value<bool>("scriptServicePlatformAttached") &&
            initializedJson.Value<string>("mapMatchingMethod") == "SIFT" &&
            initializedJson.Value<string>("autoFetchDispatchAdventurersGuildCountry") == "璃月" &&
            initializedJson.Value<bool>("runtimeArtifactsReady") &&
            initializedJson.Value<int>("runtimeArtifactsVerified") == 34 &&
            artifactInitializationCount == 1,
        "core.initialize did not apply the ScriptService platform configuration");
    foreach (var (width, height, expectedAssetScale, expectedScaleTo1080) in new[]
             {
                 (1280, 720, 1280d / 1920d, 1280d / 1920d),
                 (1920, 1080, 1d, 1d),
                 (2560, 1440, 1d, 2560d / 1920d),
             })
    {
        var systemInfo = MacGameTaskManagerPlatform.CreateSystemInfo(JObject.FromObject(new
        {
            captureWidth = width, captureHeight = height,
            workingAreaWidth = 2560, workingAreaHeight = 1440,
            captureX = 0, captureY = 0, processId = Environment.ProcessId
        }));
        Require(Math.Abs(systemInfo.AssetScale - expectedAssetScale) < 0.0001 &&
                Math.Abs(systemInfo.ScaleTo1080PRatio - expectedScaleTo1080) < 0.0001,
            $"macOS system info scale mismatch for {width}x{height}: " +
            $"asset={systemInfo.AssetScale}, to1080={systemInfo.ScaleTo1080PRatio}");
    }
    var runtimeBeforeAssets = await ExchangeAsync(
        connection, "runtime-start-before-assets", "runtime.start", sessionToken, null, cancellation.Token);
    Require(runtimeBeforeAssets.Error?.Code == "CapabilityUnavailable",
        "runtime.start succeeded before platform trigger assets were initialized");

    await using var callbackConnection = await ConnectAsync(socketPath, cancellation.Token);
    await callbackConnection.WriteRequestAsync(
        new RpcRequest("attach", "platform.attach", null, sessionToken), cancellation.Token);
    var attachResponse = await callbackConnection.ReadResponseAsync(cancellation.Token);
    Require(attachResponse?.Error is null, attachResponse?.Error?.Message ?? "platform.attach failed");
    using var initializationMetricsCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellation.Token);
    var initializationMetricsCount = 0;
    var initializationOverlayCount = 0;
    var initializationMetricsResponder = Task.Run(async () =>
    {
        try
        {
            while (true)
            {
                var callback = await callbackConnection.ReadRequestAsync(initializationMetricsCancellation.Token)
                    ?? throw new EndOfStreamException("Trigger initialization callback channel ended unexpectedly.");
                object result = callback.Method switch
                {
                    "window.metrics" => MetricsResult(),
                    "overlay.command" => OverlayResult(),
                    _ => throw new InvalidOperationException(
                        $"Trigger initialization sent unexpected callback {callback.Method}.")
                };
                await callbackConnection.WriteResponseAsync(
                    RpcResponse.Success(callback.Id, result), initializationMetricsCancellation.Token);
            }

            object MetricsResult()
            {
                initializationMetricsCount++;
                return new
                {
                    captureWidth = 1920,
                    captureHeight = 1080,
                    workingAreaWidth = 1920,
                    workingAreaHeight = 1080,
                    captureX = 0,
                    captureY = 0,
                    processId = Environment.ProcessId
                };
            }

            object OverlayResult()
            {
                initializationOverlayCount++;
                return new { acknowledged = true };
            }
        }
        catch (OperationCanceledException) when (initializationMetricsCancellation.IsCancellationRequested) { }
    }, initializationMetricsCancellation.Token);
    var initializedWithPlatform = await ExchangeAsync(
        connection, "initialize-with-platform", "core.initialize", sessionToken,
        JObject.FromObject(new { runtimeRoot = layout.RootPath }), cancellation.Token);
    Require(initializedWithPlatform.Error is null &&
            JObject.FromObject(initializedWithPlatform.Result!).Value<bool>("platformAssetsInitialized") &&
            initializationMetricsCount > 0 && initializationOverlayCount > 0,
        initializedWithPlatform.Error?.Message ?? "core.initialize did not initialize production trigger assets");
    var initialRuntimeStatus = await ExchangeAsync(
        connection, "runtime-status-stopped", "runtime.status", sessionToken, null, cancellation.Token);
    Require(initialRuntimeStatus.Error is null &&
            JObject.FromObject(initialRuntimeStatus.Result!).Value<bool>("running") == false,
        initialRuntimeStatus.Error?.Message ?? "runtime was not initially stopped");
    var runtimeStarted = await ExchangeAsync(
        connection, "runtime-start", "runtime.start", sessionToken, null, cancellation.Token);
    Require(runtimeStarted.Error is null &&
            JObject.FromObject(runtimeStarted.Result!).Value<bool>("running"),
        runtimeStarted.Error?.Message ?? "runtime.start did not start the trigger dispatcher");
    for (var attempt = 0; attempt < 100 && Volatile.Read(ref runtimeDispatcherIterations) == 0; attempt++)
        await Task.Delay(10, cancellation.Token);
    Require(Volatile.Read(ref runtimeDispatcherIterations) > 0,
        "runtime.start did not execute the trigger dispatcher loop");
    var triggerToPreserve = GameTaskManager.TriggerDictionary!.First();
    triggerToPreserve.Value.IsEnabled = false;
    var metricsBeforeRunningGeometryRefresh = Volatile.Read(ref initializationMetricsCount);
    var runningGeometryRefresh = await ExchangeAsync(
        connection, "runtime-refresh-geometry-running", "runtime.refreshGeometry",
        sessionToken, null, cancellation.Token);
    Require(runningGeometryRefresh.Error is null &&
            JObject.FromObject(runningGeometryRefresh.Result!).Value<bool>("assetsReloaded") &&
            JObject.FromObject(runningGeometryRefresh.Result!).Value<bool>("running") &&
            Volatile.Read(ref initializationMetricsCount) > metricsBeforeRunningGeometryRefresh &&
            GameTaskManager.TriggerDictionary!.TryGetValue(triggerToPreserve.Key, out var refreshedTrigger) &&
            refreshedTrigger is { IsEnabled: false },
        runningGeometryRefresh.Error?.Message ??
        "runtime.refreshGeometry did not reload assets, preserve trigger state, and restart a running dispatcher");
    var runtimeStopped = await ExchangeAsync(
        connection, "runtime-stop", "runtime.stop", sessionToken, null, cancellation.Token);
    Require(runtimeStopped.Error is null &&
            JObject.FromObject(runtimeStopped.Result!).Value<bool>("running") == false,
        runtimeStopped.Error?.Message ?? "runtime.stop did not stop the trigger dispatcher");
    var iterationsAfterStop = Volatile.Read(ref runtimeDispatcherIterations);
    await Task.Delay(50, cancellation.Token);
    Require(Volatile.Read(ref runtimeDispatcherIterations) == iterationsAfterStop,
        "trigger dispatcher continued capturing after runtime.stop acknowledged");
    var stoppedGeometryRefresh = await ExchangeAsync(
        connection, "runtime-refresh-geometry-stopped", "runtime.refreshGeometry",
        sessionToken, null, cancellation.Token);
    Require(stoppedGeometryRefresh.Error is null &&
            JObject.FromObject(stoppedGeometryRefresh.Result!).Value<bool>("assetsReloaded") &&
            !JObject.FromObject(stoppedGeometryRefresh.Result!).Value<bool>("running"),
        stoppedGeometryRefresh.Error?.Message ??
        "runtime.refreshGeometry restarted a dispatcher that was stopped");
    initializationMetricsCancellation.Cancel();
    await initializationMetricsResponder;
    var runtimeRestarted = await ExchangeAsync(
        connection, "runtime-restart", "runtime.start", sessionToken, null, cancellation.Token);
    Require(runtimeRestarted.Error is null &&
            JObject.FromObject(runtimeRestarted.Result!).Value<bool>("running"),
        runtimeRestarted.Error?.Message ?? "runtime did not restart after a completed stop");
    await ExchangeAsync(connection, "runtime-restop", "runtime.stop", sessionToken, null, cancellation.Token);
    var callbackRejectionResponder = Task.Run(async () =>
    {
        var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("Platform rejection callback channel ended unexpectedly.");
        Require(callback.Method == "verification.reject", "Core sent the wrong rejection verification callback.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Failure(callback.Id, "InputRejected", "verification dispatch failure"), cancellation.Token);
    }, cancellation.Token);
    try
    {
        await server.PlatformCallbacks.InvokeAsync(
            "verification.reject", null, sessionToken, cancellation.Token);
        throw new InvalidDataException("Platform callback rejection was accepted as success.");
    }
    catch (PlatformCallbackException exception)
    {
        Require(exception.Code == "InputRejected" && exception.Message == "verification dispatch failure",
            "Platform callback rejection lost its code or message.");
    }
    await callbackRejectionResponder;
    var callbackRecoveryResponder = Task.Run(async () =>
    {
        var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("Platform recovery callback channel ended unexpectedly.");
        Require(callback.Method == "verification.recover", "Core sent the wrong recovery verification callback.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
    }, cancellation.Token);
    var recoveredCallback = await server.PlatformCallbacks.InvokeAsync(
        "verification.recover", null, sessionToken, cancellation.Token);
    await callbackRecoveryResponder;
    Require(recoveredCallback?.Value<bool>("acknowledged") == true,
        "A platform business rejection detached the reusable callback channel.");
    var gameFocused = 0;
    var pausedInputCoordinator = new ForegroundInputCoordinator(
        server.PlatformCallbacks, sessionToken, cancellation.Token,
        TimeSpan.FromMilliseconds(5), () => Volatile.Read(ref gameFocused) != 0);
    var pausedInputTask = Task.Run(() => pausedInputCoordinator.Dispatch(
        JObject.FromObject(new { action = "keyPress", key = "F" }), cancellation.Token),
        cancellation.Token);
    await Task.Delay(50, cancellation.Token);
    Require(!pausedInputTask.IsCompleted,
        "macOS input did not pause while the selected game was unfocused");
    var resumedInputResponder = Task.Run(async () =>
    {
        var release = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("Focus-resume release callback was missing.");
        Require(release.Method == "input.dispatch" &&
                release.Params?.Value<string>("action") == "releaseAll",
            "focus resume did not release stale input state before continuing");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(release.Id, new { acknowledged = true }), cancellation.Token);

        var input = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("Focus-resume input callback was missing.");
        Require(input.Method == "input.dispatch" &&
                input.Params?.Value<string>("action") == "keyPress" &&
                input.Params?.Value<string>("key") == "F",
            "focus resume changed or reordered the pending input operation");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(input.Id, new { acknowledged = true }), cancellation.Token);
    }, cancellation.Token);
    Volatile.Write(ref gameFocused, 1);
    await pausedInputTask;
    await resumedInputResponder;

    Volatile.Write(ref gameFocused, 0);
    using var focusWaitCancellation = new CancellationTokenSource();
    var cancelledFocusWait = Task.Run(() => pausedInputCoordinator.WaitForGameFocus(
        focusWaitCancellation.Token), cancellation.Token);
    await Task.Delay(30, cancellation.Token);
    focusWaitCancellation.Cancel();
    try
    {
        await cancelledFocusWait;
        throw new InvalidDataException("Unfocused input wait ignored cancellation.");
    }
    catch (OperationCanceledException)
    {
    }
    Console.WriteLine("Foreground input passed: unfocused pause, cancellation and release-before-resume without window activation.");
    var productionTriggerList = await ExchangeAsync(
        connection, "production-trigger-list", "trigger.list", sessionToken, null, cancellation.Token);
    var productionTriggerNames = JArray.FromObject(productionTriggerList.Result!)
        .Select(item => item?["name"]?.Value<string>()).Where(name => name is not null).ToHashSet();
    Require(productionTriggerList.Error is null && productionTriggerNames.SetEquals(new[]
        { "GameLoading", "AutoPick", "QuickTeleport", "AutoSkip", "AutoFish", "AutoEat", "MapMask", "SkillCd" }),
        productionTriggerList.Error?.Message ?? "core.initialize did not register the exact production trigger set");
    var successfulTriggerFrames = 0;
    var isolatedDispatcher = new MacTriggerDispatcher(
        loggerFactory.CreateLogger<MacTriggerDispatcher>(), cancellation.Token);
    using (var triggerContent = new CaptureContent(
               new ImageRegion(new OpenCvSharp.Mat(8, 8, OpenCvSharp.MatType.CV_8UC4), 0, 0), 0, 50))
    {
        isolatedDispatcher.DispatchTriggers(
        [
            new VerificationTrigger("Failing Trigger", _ => throw new InvalidOperationException("verification trigger failure")),
            new VerificationTrigger("Successful Trigger", _ => successfulTriggerFrames++)
        ], triggerContent);
    }
    Require(successfulTriggerFrames == 1,
        "one failing macOS trigger stopped later triggers from processing the same frame");

    using var restartDispatcherCancellation = new CancellationTokenSource();
    var dispatcherRuns = 0;
    var restartableDispatcher = new MacTriggerDispatcher(
        loggerFactory.CreateLogger<MacTriggerDispatcher>(), restartDispatcherCancellation.Token,
        async token =>
        {
            if (Interlocked.Increment(ref dispatcherRuns) == 1)
                throw new InvalidOperationException("verification dispatcher failure");
            await Task.Delay(Timeout.Infinite, token);
        });
    restartableDispatcher.Start();
    for (var attempt = 0; attempt < 100 && restartableDispatcher.IsRunning; attempt++)
        await Task.Delay(10, cancellation.Token);
    Require(!restartableDispatcher.IsRunning && dispatcherRuns == 1,
        "faulted macOS trigger dispatcher did not expose a restartable stopped state");
    restartableDispatcher.Start();
    for (var attempt = 0; attempt < 100 && dispatcherRuns < 2; attempt++)
        await Task.Delay(10, cancellation.Token);
    Require(restartableDispatcher.IsRunning && dispatcherRuns == 2,
        "macOS trigger dispatcher did not restart after a prior loop failure");
    restartDispatcherCancellation.Cancel();
    var gameLoadingPlatform = new MacGameLoadingRuntimePlatform(
        layout,
        () => throw new InvalidOperationException("GameLoading verification did not request screen metrics."),
        loggerFactory, server.PlatformCallbacks, sessionToken, cancellation.Token,
        foregroundInputCoordinator);
    var gameLoadingResponder = Task.Run(async () =>
    {
        foreach (var expectedMethod in new[] { "window.metrics", "url.canOpen", "window.biliLogin" })
        {
            var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("GameLoading callback channel ended unexpectedly.");
            Require(callback.Method == expectedMethod,
                $"GameLoading expected {expectedMethod}, got {callback.Method}.");
            object result = expectedMethod switch
            {
                "window.metrics" => new { dpiScale = 2d },
                "url.canOpen" => new { available = false },
                _ => new { type = "agreement" }
            };
            await callbackConnection.WriteResponseAsync(
                RpcResponse.Success(callback.Id, result), cancellation.Token);
        }
    }, cancellation.Token);
    Require(!gameLoadingPlatform.Config.AutoEnterGameEnabled &&
            gameLoadingPlatform.DpiScale == 2d &&
            !gameLoadingPlatform.IsPlaytimeTrackingAvailable() &&
            gameLoadingPlatform.GetBiliLoginWindowType() == BiliLoginWindowType.Agreement,
        "GameLoading macOS platform lost upstream config, DPI, URL or Bili-window semantics.");
    await gameLoadingResponder;
    var quickTeleportQuery = Task.Run(async () =>
    {
        var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("QuickTeleport hotkey callback channel ended unexpectedly.");
        Require(callback.Method == "input.query" &&
                callback.Params?.Value<string>("action") == "isKeyDown" &&
                callback.Params?.Value<string>("key") == "F6",
            "QuickTeleport did not preserve the configured raw hotkey query.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(callback.Id, new { isDown = true }), cancellation.Token);
    }, cancellation.Token);
    Require(quickTeleportPlatform.Config.Enabled && quickTeleportPlatform.Config.HotkeyTpEnabled &&
            quickTeleportPlatform.TickHotkey == "F6" && quickTeleportPlatform.IsTickHotkeyPressed(),
        "QuickTeleport macOS platform did not load upstream config or report hotkey state.");
    await quickTeleportQuery;
    var callbackResponder = Task.Run(async () =>
    {
        for (var index = 0; index < 2; index++)
        {
            var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("Core did not send the platform callback.");
            if (index == 0)
            {
                Require(callback.Method == "input.dispatch", "Core sent an unexpected input callback method");
                Require(callback.Params?.Value<string>("action") == "keyPress" &&
                        callback.Params?.Value<string>("key") == "VK_F",
                    "Core platform callback lost semantic input parameters");
            }
            else
            {
                Require(callback.Method == "notification.emit", "Core sent an unexpected notification callback method");
                Require(callback.Params?.Value<string>("kind") == "success" &&
                        callback.Params?.Value<string>("message") == "verification notification",
                    "Core platform callback lost notification semantics");
            }
            await callbackConnection.WriteResponseAsync(
                RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
        }
    }, cancellation.Token);
    var globalRuntime = new MacGlobalMethodRuntime(
        server.PlatformCallbacks, sessionToken, cancellation.Token, new SharedCaptureRingReader(layout),
        foregroundInputCoordinator);
    globalRuntime.KeyPress("VK_F");
    new BetterGenshinImpact.Core.Script.Dependence.Notification().Send("verification notification");
    await callbackResponder;

    var taskControlResponder = Task.Run(async () =>
    {
        var expected = new Queue<(string Method, string? Action, string? KeyType)>([
            ("input.dispatch", "gameAction", "keyDown"),
            ("input.dispatch", "gameAction", "keyUp"),
            ("input.query", "isGameActionDown", null)
        ]);
        while (expected.Count > 0)
        {
            var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("TaskControl callback channel ended unexpectedly.");
            var item = expected.Dequeue();
            Require(callback.Method == item.Method, $"TaskControl expected {item.Method}, got {callback.Method}.");
            if (item.Method == "input.query")
            {
                Require(callback.Params?.Value<string>("action") == item.Action &&
                        callback.Params?.Value<string>("gameAction") == "moveForward",
                    "TaskControl key-state query lost BetterGI game action semantics.");
                await callbackConnection.WriteResponseAsync(
                    RpcResponse.Success(callback.Id, new { isDown = true }), cancellation.Token);
                continue;
            }
            if (item.Action is not null)
            {
                Require(callback.Params?.Value<string>("action") == item.Action &&
                        callback.Params?.Value<string>("gameAction") == "moveForward" &&
                        callback.Params?.Value<string>("keyType") == item.KeyType,
                    "TaskControl did not preserve BetterGI GIActions/KeyType semantics.");
            }
            await callbackConnection.WriteResponseAsync(
                RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
        }
    }, cancellation.Token);
    await TaskControl.SimulateHoldActionAsync(
        BetterGenshinImpact.Core.Simulator.Extensions.GIActions.MoveForward, 1, cancellation.Token);
    Require(TaskControl.IsActionKeyDown(
            BetterGenshinImpact.Core.Simulator.Extensions.GIActions.MoveForward),
        "TaskControl did not return the real platform key state.");
    await taskControlResponder;
    var rawKeyResponder = Task.Run(async () =>
    {
        var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("TaskControl raw-key callback channel ended unexpectedly.");
        Require(callback.Method == "input.dispatch" &&
                callback.Params?.Value<string>("action") == "keyPress" &&
                callback.Params?.Value<int>("windowsVirtualKey") == 0x75,
            "TaskControl did not preserve the requested F6 virtual key.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
    }, cancellation.Token);
    TaskControlPlatform.Current.PressKey(0x75);
    await rawKeyResponder;
    var autoEatPlatform = new MacAutoEatRuntimePlatform(layout, loggerFactory);
    Require(autoEatPlatform.Config.Enabled && autoEatPlatform.Config.EatInterval == 1234,
        "macOS AutoEat did not load the upstream trigger configuration.");
    var autoEatResponder = Task.Run(async () =>
    {
        var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("AutoEat input callback channel ended unexpectedly.");
        Require(callback.Method == "input.dispatch" &&
                callback.Params?.Value<string>("action") == "gameAction" &&
                callback.Params?.Value<string>("gameAction") == "quickUseGadget" &&
                callback.Params?.Value<string>("keyType") == "keyPress",
            "macOS AutoEat did not preserve the upstream QuickUseGadget action.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
    }, cancellation.Token);
    autoEatPlatform.SimulateAction(GIActions.QuickUseGadget);
    await autoEatResponder;
    var autoSkipPlatform = new MacAutoSkipRuntimePlatform(
        () => throw new InvalidOperationException("Verification did not request AutoSkip system metrics."),
        loggerFactory, imageRegionOcrService,
        server.PlatformCallbacks, sessionToken, cancellation.Token, foregroundInputCoordinator,
        verificationAutoPickConfigProvider);
    var autoSkipResponder = Task.Run(async () =>
    {
        var input = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("AutoSkip input callback channel ended unexpectedly.");
        Require(input.Method == "input.dispatch" &&
                input.Params?.Value<string>("action") == "keyPress" &&
                input.Params?.Value<string>("key") == "Space",
            "macOS AutoSkip did not route the upstream space key through acknowledged input.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(input.Id, new { acknowledged = true }), cancellation.Token);

        var dialog = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("AutoSkip dialog callback channel ended unexpectedly.");
        Require(dialog.Method == "dialog.request" &&
                dialog.Params?.Value<string>("kind") == "error" &&
                dialog.Params?.Value<string>("message") == "verification error",
            "macOS AutoSkip did not forward the upstream error dialog.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(dialog.Id, new { acknowledged = true }), cancellation.Token);
    }, cancellation.Token);
    autoSkipPlatform.PressBackgroundKey(BetterGenshinImpact.Platform.Abstractions.BgiKey.Space);
    autoSkipPlatform.ReportError("verification error");
    await autoSkipResponder;
    var audioSamples = new List<float>();
    var audioCallbacks = server.PlatformCallbacks;
    var audioCaptureTask = Task.Run(() =>
    {
        using var capture = new MacProcessAudioSampleCapture(
            4242, audioCallbacks, sessionToken, cancellation.Token);
        capture.ReadAvailableSamples(audioSamples);
        capture.DiscardAvailableSamples();
    }, cancellation.Token);
    foreach (var expectedMethod in new[] { "audio.start", "audio.read", "audio.discard", "audio.stop" })
    {
        var audio = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("AutoSkip audio callback channel ended unexpectedly.");
        Require(audio.Method == expectedMethod,
            $"macOS AutoSkip audio expected {expectedMethod}, got {audio.Method}.");
        object result = expectedMethod == "audio.read"
            ? new
            {
                sampleFormat = "float32le",
                sampleCount = 2,
                samplesBase64 = Convert.ToBase64String(
                    MemoryMarshal.AsBytes<float>(new float[] { 0.25f, -0.5f }).ToArray())
            }
            : new { acknowledged = true };
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(audio.Id, result), cancellation.Token);
    }
    await audioCaptureTask;
    Require(audioSamples.SequenceEqual([0.25f, -0.5f]),
        "macOS AutoSkip audio transport did not preserve float32 PCM samples.");
    Console.WriteLine("AutoSkip audio passed: upstream C# waiter/VAD with macOS process PCM callbacks and no Swift business fallback.");

    var processControlResponder = Task.Run(async () =>
    {
        foreach (var expectedMethod in new[] { "game.close", "application.restart" })
        {
            var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("Process-control callback channel ended unexpectedly.");
            Require(callback.Method == expectedMethod,
                $"scheduler expected {expectedMethod}, got {callback.Method}.");
            if (expectedMethod == "application.restart")
            {
                Require(callback.Params?.Value<string>("taskProgressName") == "next-project",
                    "application.restart lost the upstream task progress name.");
            }
            await callbackConnection.WriteResponseAsync(
                RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
        }
    }, cancellation.Token);
    scriptServicePlatform.CloseGame();
    scriptServicePlatform.RestartApplication("next-project");
    await processControlResponder;

    var reloginPlatform = new MacExitAndReloginPlatform();
    reloginPlatform.FocusGameWindow();
    Require(!reloginPlatform.TryLoginThirdParty(cancellation.Token),
        "macOS incorrectly reported the Windows-only Bilibili channel login as available.");
    Console.WriteLine("Shared TaskControl passed: hold action, focus check, key-up ordering, raw key and platform key-state query.");

    var pathingPlatformResponder = Task.Run(async () =>
    {
        var metrics = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("PathExecutor did not request window metrics.");
        Require(metrics.Method == "window.metrics", "PathExecutor requested unexpected window data.");
        await callbackConnection.WriteResponseAsync(RpcResponse.Success(metrics.Id, new
        {
            width = 1920,
            height = 1080
        }), cancellation.Token);

        var current = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("PathExecutor did not publish current pathing.");
        Require(current.Method == "pathing.current" &&
                current.Params?.Value<string>("name") == "Verification Route" &&
                current.Params?.Value<int>("waypointCount") == 1,
            "PathExecutor current-route callback lost upstream task metadata.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(current.Id, new { acknowledged = true }), cancellation.Token);

        var dpiMetrics = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("Real PathExecutor did not request DPI metrics.");
        Require(dpiMetrics.Method == "window.metrics",
            "Real PathExecutor constructor requested unexpected DPI data.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(dpiMetrics.Id, new { dpiScale = 1.0 }), cancellation.Token);

        var executorDpiMetrics = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("PathExecutor camera did not request DPI metrics.");
        Require(executorDpiMetrics.Method == "window.metrics",
            "PathExecutor camera requested unexpected DPI data.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(executorDpiMetrics.Id, new { dpiScale = 1.0 }), cancellation.Token);

        var position = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("Navigation did not publish its matched position.");
        Require(position.Method == "pathing.position" &&
                position.Params?.Value<float>("x") == 123.5f &&
                position.Params?.Value<float>("y") == -42.25f,
            "Navigation position callback lost the upstream OpenCV coordinates.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(position.Id, new { acknowledged = true }), cancellation.Token);
    }, cancellation.Token);
    Require(pathExecutorPlatform.GetGameScreenSize() == (1920, 1080),
        "PathExecutor platform did not preserve the real game window size.");
    pathExecutorPlatform.PublishCurrentPathing(new PathingTask
    {
        Info = new PathingTaskInfo { Name = "Verification Route", Author = "BetterGI" },
        Positions = [new Waypoint { X = 1, Y = 2 }]
    });
    var composedPathExecutor = ScriptGroupExecutionServices.Current.CreatePathExecutor(cancellation.Token);
    Require(composedPathExecutor is PathExecutor,
        "ScriptGroup Pathing branch did not create the real upstream PathExecutor.");
    Require(ScriptGroupExecutionServices.Current.DefaultPartyConfig is not null,
        "ScriptGroup Pathing branch did not expose the Core-owned default party config.");
    navigationPlatform.PublishCurrentPosition(new OpenCvSharp.Point2f(123.5f, -42.25f));
    await pathingPlatformResponder;
    Console.WriteLine("PathExecutor platform passed: real ScriptGroup executor, window metrics, Core-owned config, current-route metadata and Navigation callbacks.");

    GlobalMethod.Configure(globalRuntime);
    var dispatcherRuntime = new VerificationDispatcherRuntimePlatform(cancellation.Token);
    DispatcherRuntimePlatform.Configure(dispatcherRuntime);
    server.AttachSoloTaskCoordinator(new SoloTaskCoordinator(dispatcherRuntime, cancellation.Token));
    ScriptProjectHost.Configure(new MacScriptProjectHostInitializer(scriptGroupExecutionServices));
    using (var hostSurfaceEngine = new V8ScriptEngine(
               V8ScriptEngineFlags.UseCaseInsensitiveMemberBinding |
               V8ScriptEngineFlags.EnableTaskPromiseConversion))
    {
        new MacScriptProjectHostInitializer(scriptGroupExecutionServices).Initialize(
            hostSurfaceEngine, Path.Combine(layout.UserPath, "JsScript"), [], null);
        var missingHostNames = Convert.ToString(hostSurfaceEngine.Evaluate("""
            ["keyMouseScript", "pathingScript", "genshin", "dispatcher", "RecognitionObject", "BvPage", "BvLocator", "BvImage", "DesktopRegion", "GameCaptureRegion", "ImageRegion", "Region",
             "CombatScenes", "Avatar", "OpenCvSharp", "AutoFightParam", "AutoSkipConfig",
             "RealtimeTimer", "SoloTask", "CancellationTokenSource", "CancellationToken"].filter(name => typeof globalThis[name] === "undefined").join(",")
            """));
        Require(string.IsNullOrEmpty(missingHostNames),
            $"macOS ClearScript host surface is missing: {missingHostNames}");
        hostSurfaceEngine.Execute("dispatcher.addTimer(new RealtimeTimer('AutoPick')); dispatcher.getLinkedCancellationToken();");
    }
    Require(dispatcherRuntime.ClearCount == 1 && dispatcherRuntime.AddedNames.SequenceEqual(["AutoPick"]),
        "ClearScript dispatcher did not preserve AddTimer clear-then-add semantics");
    var sharedDispatcher = new Dispatcher(new object());
    try
    {
        await sharedDispatcher.RunTask(new SoloTask("AutoDomain"));
        throw new InvalidOperationException("Dispatcher accepted an unavailable task as successful.");
    }
    catch (CapabilityUnavailableException)
    {
    }
    var realFixtureSource = Path.Combine(AppContext.BaseDirectory, "Fixtures", "ExitGameMultipleMode");
    var realFixtureTarget = Path.Combine(layout.UserPath, "JsScript", "ExitGameMultipleMode");
    CopyDirectory(realFixtureSource, realFixtureTarget);
    var realProject = new ScriptProject("ExitGameMultipleMode");
    var realGroupProject = new ScriptGroupProject(realProject) { AllowJsNotification = true };
    scriptHostServices.SetCurrentProject(realGroupProject);
    dynamic realSettings = new ExpandoObject();
    realSettings.Modes = "Alt+F4";
    var expectedInputs = new[]
    {
        (Action: "keyDown", Key: "MENU"),
        (Action: "keyDown", Key: "F4"),
        (Action: "keyUp", Key: "MENU"),
        (Action: "keyUp", Key: "F4")
    };
    var scriptInputResponder = Task.Run(async () =>
    {
        foreach (var expected in expectedInputs)
        {
            var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("Real script did not send the expected input callback.");
            Require(callback.Method == "input.dispatch", "Real script sent a non-input callback.");
            Require(callback.Params?.Value<string>("action") == expected.Action &&
                    callback.Params?.Value<string>("key") == expected.Key,
                $"Real script input order mismatch; expected {expected.Action}:{expected.Key}.");
            await callbackConnection.WriteResponseAsync(
                RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
        }
    }, cancellation.Token);
    realGroupProject.JsScriptSettingsObject = realSettings;
    await realGroupProject.Run();
    await scriptInputResponder;
    Console.WriteLine("Real BetterGI script passed: ExitGameMultipleMode Alt+F4 emitted keyDown/keyUp in upstream order.");

    var macroPlatform = new MacKeyMouseMacroPlatform(
        server.PlatformCallbacks, sessionToken, cancellation.Token,
        loggerFactory.CreateLogger("MacroVerification"), foregroundInputCoordinator);
    KeyMouseMacroPlatform.Configure(macroPlatform);
    var macroCallbackResponder = Task.Run(async () =>
    {
        var expectedInputActions = new Queue<(string Action, int? Key)>([
            ("keyDown", 0x57), ("keyUp", 0x57),
            ("moveMouseToVirtualDesktop", null), ("mouseDown", null),
            ("moveMouseToVirtualDesktop", null), ("mouseUp", null)
        ]);
        while (expectedInputActions.Count > 0)
        {
            var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("Macro playback callback ended unexpectedly.");
            object result;
            if (callback.Method == "window.metrics")
            {
                result = new
                {
                    captureX = 0, captureY = 0, captureWidth = 1920, captureHeight = 1080,
                    workingAreaWidth = 1920, workingAreaHeight = 1080, dpiScale = 1.0
                };
            }
            else if (callback.Method == "window.activate")
            {
                result = new { acknowledged = true };
            }
            else
            {
                Require(callback.Method == "input.dispatch", "Macro emitted a non-input callback.");
                var expected = expectedInputActions.Dequeue();
                Require(callback.Params?.Value<string>("action") == expected.Action,
                    $"Macro action order mismatch; expected {expected.Action}.");
                if (expected.Key.HasValue)
                    Require(callback.Params?.Value<int>("windowsVirtualKey") == expected.Key.Value,
                        "Macro Windows virtual key was not preserved.");
                result = new { acknowledged = true };
            }
            await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, result), cancellation.Token);
        }
    }, cancellation.Token);
    var macroJson = """
        {"info":{"name":"verification","x":0,"y":0,"width":1920,"height":1080,"recordDpi":1},
         "macroEvents":[
           {"type":0,"keyCode":87,"time":0},{"type":1,"keyCode":87,"time":0},
           {"type":4,"mouseX":100,"mouseY":200,"mouseButton":"Left","time":0},
           {"type":5,"mouseX":100,"mouseY":200,"mouseButton":"Left","time":0}]}
        """;
    var macroFileName = "verification.json";
    await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "KeyMouseScript", macroFileName), macroJson);
    var macroProject = ScriptGroupProject.BuildKeyMouseProject(macroFileName);
    await macroProject.Run();
    await macroCallbackResponder;
    Console.WriteLine("Real BetterGI KeyMouse playback passed: timing/parser/adaptation and acknowledged input order.");

    var shellMarker = Path.Combine(root, "shell-project.marker");
    var shellProject = ScriptGroupProject.BuildShellProject($"printf shell-project > '{shellMarker}'");
    var shellGroup = new ScriptGroup { Name = "Shell verification" };
    shellGroup.Config.EnableShellConfig = true;
    shellGroup.Config.ShellConfig.Output = true;
    shellGroup.AddProject(shellProject);
    await shellProject.Run();
    Require(await File.ReadAllTextAsync(shellMarker) == "shell-project",
        "ScriptGroupProject.Run did not execute its real Shell branch.");

    var catalog = await ExchangeAsync(connection, "2", "catalog.listScriptGroups", sessionToken, null, cancellation.Token);
    var documents = JArray.FromObject(catalog.Result!);
    Require(documents.Count == 1, "catalog did not return the fixture group");
    Require(documents[0]?["projects"]?[0]?["runNum"]?.Value<int>() == 2 &&
            documents[0]?["projects"]?[0]?["status"]?.Value<string>() == "Enabled",
        "catalog did not expose the Core-owned ScriptGroup UI summary");
    var initialDocument = await ExchangeAsync(connection, "catalog-initial", "catalog.getScriptGroup", sessionToken,
        JObject.FromObject(new { name = "狗粮+锄地" }), cancellation.Token);
    Require(initialDocument.Error is null, initialDocument.Error?.Message ?? "catalog.getScriptGroup failed");
    var savedDocument = (JObject)JObject.FromObject(initialDocument.Result!)["document"]!.DeepClone();
    savedDocument["projects"]![0]!["runNum"] = 3;
    var saved = await ExchangeAsync(connection, "catalog-save", "catalog.saveScriptGroup", sessionToken,
        JObject.FromObject(new { name = "狗粮+锄地", document = savedDocument }), cancellation.Token);
    Require(saved.Error is null && JObject.FromObject(saved.Result!)["document"]?["projects"]?[0]?["runNum"]?.Value<int>() == 3,
        saved.Error?.Message ?? "catalog.saveScriptGroup did not return the normalized upstream document");
    var reloaded = await ExchangeAsync(connection, "catalog-reload", "catalog.getScriptGroup", sessionToken,
        JObject.FromObject(new { name = "狗粮+锄地" }), cancellation.Token);
    Require(reloaded.Error is null && JObject.FromObject(reloaded.Result!)["document"]?["projects"]?[0]?["runNum"]?.Value<int>() == 3,
        reloaded.Error?.Message ?? "catalog.saveScriptGroup did not persist through the authoritative Core catalog");
    var disabledProject = await ExchangeAsync(
        connection, "catalog-disable-project", "catalog.setScriptGroupProjectEnabled", sessionToken,
        JObject.FromObject(new { name = "狗粮+锄地", projectIndex = 1, enabled = false }), cancellation.Token);
    Require(disabledProject.Error is null &&
            JObject.FromObject(disabledProject.Result!)["projects"]?[0]?["status"]?.Value<string>() == "Disabled",
        disabledProject.Error?.Message ?? "Core did not disable the selected script-group project");
    var disabledDocument = await ExchangeAsync(
        connection, "catalog-disabled-document", "catalog.getScriptGroup", sessionToken,
        JObject.FromObject(new { name = "狗粮+锄地" }), cancellation.Token);
    var disabledProjectDocument = JObject.FromObject(disabledDocument.Result!)["document"]?["projects"]?[0];
    Require(disabledDocument.Error is null &&
            disabledProjectDocument?["status"]?.Value<string>() == "Disabled" &&
            disabledProjectDocument?["runNum"]?.Value<int>() == 3 &&
            disabledProjectDocument?["jsScriptSettingsObject"]?["targetMonsters"]?.Value<string>() == "愚人众特辖队，巡陆艇",
        disabledDocument.Error?.Message ?? "project status update lost upstream ScriptGroup fields");
    var reenabledProject = await ExchangeAsync(
        connection, "catalog-reenable-project", "catalog.setScriptGroupProjectEnabled", sessionToken,
        JObject.FromObject(new { name = "狗粮+锄地", projectIndex = 1, enabled = true }), cancellation.Token);
    Require(reenabledProject.Error is null &&
            JObject.FromObject(reenabledProject.Result!)["projects"]?[0]?["status"]?.Value<string>() == "Enabled",
        reenabledProject.Error?.Message ?? "Core did not re-enable the selected script-group project");

    var projects = await ExchangeAsync(connection, "projects", "catalog.listScriptProjects", sessionToken, null, cancellation.Token);
    var projectDocuments = JArray.FromObject(projects.Result!);
    Require(projectDocuments.Any(document => document?["folderName"]?.Value<string>() == "CoreFixture") &&
            projectDocuments.Any(document => document?["folderName"]?.Value<string>() == "ExitGameMultipleMode"),
        "script-project catalog did not return the upstream manifest fixture");
    var coreFixtureDocument = projectDocuments.First(document => document?["folderName"]?.Value<string>() == "CoreFixture");
    Require(coreFixtureDocument?["name"]?.Value<string>() == "Core Fixture" &&
            coreFixtureDocument?["version"]?.Value<string>() == "1.0.0",
        "script-project catalog did not return Core-owned display metadata");
    var coreFixtureDetails = await ExchangeAsync(
        connection, "project-details", "catalog.getScriptProject", sessionToken,
        JObject.FromObject(new { folderName = "CoreFixture" }), cancellation.Token);
    Require(coreFixtureDetails.Error is null &&
            JObject.FromObject(coreFixtureDetails.Result!)["settings"]?[0]?["name"]?.Value<string>() == "targetMonsters",
        coreFixtureDetails.Error?.Message ?? "script-project details lost upstream settings metadata");

    GameTaskManager.TriggerDictionary = new System.Collections.Concurrent.ConcurrentDictionary<string, ITaskTrigger>();
    GameTaskManager.TriggerDictionary["Verification"] = new VerificationTrigger();
    var triggerList = await ExchangeAsync(
        connection, "trigger-list", "trigger.list", sessionToken, null, cancellation.Token);
    var triggerDocuments = JArray.FromObject(triggerList.Result!);
    Require(triggerList.Error is null && triggerDocuments.Count == 1 &&
            triggerDocuments[0]?["name"]?.Value<string>() == "Verification" &&
            triggerDocuments[0]?["enabled"]?.Value<bool>() == false,
        triggerList.Error?.Message ?? "trigger.list did not expose the shared GameTaskManager registry");
    var triggerEnable = await ExchangeAsync(
        connection, "trigger-enable", "trigger.setEnabled", sessionToken,
        JObject.FromObject(new { name = "Verification", enabled = true }), cancellation.Token);
    Require(triggerEnable.Error is null && GameTaskManager.TriggerDictionary["Verification"].IsEnabled,
        triggerEnable.Error?.Message ?? "trigger.setEnabled did not mutate the shared trigger instance");
    var missingTrigger = await ExchangeAsync(
        connection, "trigger-missing", "trigger.setEnabled", sessionToken,
        JObject.FromObject(new { name = "Missing", enabled = true }), cancellation.Token);
    Require(missingTrigger.Error?.Code == "CapabilityUnavailable",
        "trigger.setEnabled did not reject an uncomposed trigger explicitly");

    Require(JArray.FromObject(handshakeJson["capabilities"]!).Any(value => value?.Value<string>() == "scheduler.run"),
        "handshake did not advertise the real scheduler.run chain");
    Require(JArray.FromObject(handshakeJson["capabilities"]!).Any(value => value?.Value<string>() == "trigger-control"),
        "handshake did not advertise Core-owned trigger control");

    var schedulerMarker = Path.Combine(root, "scheduler.marker");
    var schedulerGroup = new ScriptGroup { Name = "SchedulerShell" };
    schedulerGroup.Config.EnableShellConfig = true;
    schedulerGroup.Config.ShellConfig.Output = true;
    schedulerGroup.AddProject(ScriptGroupProject.BuildShellProject($"sleep 1; printf scheduler-real > '{schedulerMarker}'"));
    await File.WriteAllTextAsync(
        Path.Combine(layout.ScriptGroupPath, schedulerGroup.Name + ".json"), schedulerGroup.ToJson());
    var cancelledSchedulerMarker = Path.Combine(root, "scheduler-cancelled.marker");
    var cancelledSchedulerGroup = new ScriptGroup { Name = "SchedulerShellCancelled" };
    cancelledSchedulerGroup.Config.EnableShellConfig = true;
    cancelledSchedulerGroup.Config.ShellConfig.Output = false;
    cancelledSchedulerGroup.AddProject(ScriptGroupProject.BuildShellProject(
        $"printf scheduler-cancelled > '{cancelledSchedulerMarker}'; sleep 30"));
    await File.WriteAllTextAsync(
        Path.Combine(layout.ScriptGroupPath, cancelledSchedulerGroup.Name + ".json"),
        cancelledSchedulerGroup.ToJson());
    var rejectedSchedulerProjectPath = Path.Combine(
        layout.UserPath, "JsScript", "SchedulerInputRejected");
    Directory.CreateDirectory(rejectedSchedulerProjectPath);
    await File.WriteAllTextAsync(Path.Combine(rejectedSchedulerProjectPath, "manifest.json"),
        """{"manifest_version":1,"name":"Scheduler Input Rejected","version":"1.0.0","main":"main.js"}""");
    await File.WriteAllTextAsync(Path.Combine(rejectedSchedulerProjectPath, "main.js"),
        "keyPress('F');");
    var rejectedSchedulerGroup = new ScriptGroup { Name = "SchedulerInputRejected" };
    rejectedSchedulerGroup.AddProject(new ScriptGroupProject(
        new ScriptProject("SchedulerInputRejected")));
    await File.WriteAllTextAsync(
        Path.Combine(layout.ScriptGroupPath, rejectedSchedulerGroup.Name + ".json"), rejectedSchedulerGroup.ToJson());
    var lockedSchedulerMarker = Path.Combine(root, "scheduler-locked.marker");
    var lockedSchedulerGroup = new ScriptGroup { Name = "SchedulerShellLocked" };
    lockedSchedulerGroup.Config.EnableShellConfig = true;
    lockedSchedulerGroup.AddProject(
        ScriptGroupProject.BuildShellProject($"printf scheduler-locked > '{lockedSchedulerMarker}'"));
    await File.WriteAllTextAsync(
        Path.Combine(layout.ScriptGroupPath, lockedSchedulerGroup.Name + ".json"), lockedSchedulerGroup.ToJson());
    var sourceRoot = Path.Combine(Directory.GetCurrentDirectory(), "BetterGenshinImpact", "GameTask");
    foreach (var relativeAsset in new[]
    {
        "Common/Element/Assets/1920x1080/paimon_menu.png",
        "Common/Element/Assets/1920x1080/party_btn_choose_view.png",
        "Common/Element/Assets/1920x1080/party_btn_delete.png",
        "Common/Element/Assets/1920x1080/primogem.png",
        "AutoFight/Assets/1920x1080/confirm.png",
        "GameLoading/Assets/1920x1080/girl_moon.png",
        "GameLoading/Assets/1920x1080/welkin_moon_logo.png"
    })
    {
        var destination = Path.Combine(layout.RootPath, "GameTask", relativeAsset);
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        File.Copy(Path.Combine(sourceRoot, relativeAsset), destination, true);
    }

    const int schedulerWidth = 1920, schedulerHeight = 1080, schedulerStride = schedulerWidth * 4;
    var schedulerCapacity = (long)schedulerStride * schedulerHeight;
    using (var frame = new OpenCvSharp.Mat(schedulerHeight, schedulerWidth, OpenCvSharp.MatType.CV_8UC4, OpenCvSharp.Scalar.Black))
    using (var paimon = OpenCvSharp.Cv2.ImRead(
        Path.Combine(sourceRoot, "Common/Element/Assets/1920x1080/paimon_menu.png"), OpenCvSharp.ImreadModes.Color))
    using (var paimonBgra = new OpenCvSharp.Mat())
    {
        OpenCvSharp.Cv2.CvtColor(paimon, paimonBgra, OpenCvSharp.ColorConversionCodes.BGR2BGRA);
        using (var target = new OpenCvSharp.Mat(frame, new OpenCvSharp.Rect(24, 20, paimon.Width, paimon.Height)))
            paimonBgra.CopyTo(target);
        var pixels = new byte[checked((int)schedulerCapacity)];
        System.Runtime.InteropServices.Marshal.Copy(frame.Data, pixels, 0, pixels.Length);
        await using var ring = new FileStream(captureRingPath, FileMode.Create, FileAccess.ReadWrite, FileShare.ReadWrite);
        ring.SetLength(captureHeaderSize + 2 * schedulerCapacity);
        using var writer = new BinaryWriter(ring, System.Text.Encoding.UTF8, leaveOpen: true);
        writer.Write(System.Text.Encoding.ASCII.GetBytes("BGIRING1"));
        writer.Write(1u); writer.Write(2u); writer.Write((ulong)schedulerCapacity);
        writer.Write(0u); writer.Write((uint)schedulerWidth); writer.Write((uint)schedulerHeight); writer.Write((uint)schedulerStride);
        writer.Write(0x42475241u); writer.Write(0u); writer.Write((ulong)pixels.Length); writer.Write(8UL);
        writer.Write(0); writer.Write(0); writer.Write(2u); writer.Write(1u); writer.Write(2UL);
        ring.Position = captureHeaderSize;
        writer.Write(pixels);
    }
    File.SetUnixFileMode(captureRingPath, UnixFileMode.UserRead | UnixFileMode.UserWrite);

    var genshinFixturePath = Path.Combine(layout.UserPath, "JsScript", "GenshinReturnMainUi");
    Directory.CreateDirectory(genshinFixturePath);
    await File.WriteAllTextAsync(Path.Combine(genshinFixturePath, "manifest.json"), """
        {"name":"Genshin ReturnMainUi","version":"1.0.0","description":"verification","authors":[{"name":"BetterGI"}],"main":"main.js","settings":[],"library":[]}
        """);
    await File.WriteAllTextAsync(
        Path.Combine(genshinFixturePath, "main.js"), "export {}; await genshin.returnMainUi();");
    var genshinCaptureResponder = Task.Run(async () =>
    {
        var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("genshin.returnMainUi did not request a real capture.");
        Require(callback.Method == "capture.request",
            $"genshin.returnMainUi emitted unexpected callback {callback.Method} before recognizing main UI.");
        await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
        {
            ringPath = captureRingPath, frameId = 8UL, sequence = 2UL, slot = 0,
            width = schedulerWidth, height = schedulerHeight, stride = schedulerStride, pixelFormat = "BGRA8"
        }), cancellation.Token);
    }, cancellation.Token);
    await new ScriptProject("GenshinReturnMainUi").ExecuteAsync();
    await genshinCaptureResponder;
    Console.WriteLine("Real BetterGI genshin.returnMainUi passed: ClearScript, upstream task, capture ring and Paimon recognition.");

    var battlePassFixturePath = Path.Combine(layout.UserPath, "JsScript", "GenshinClaimBattlePassRewards");
    Directory.CreateDirectory(battlePassFixturePath);
    await File.WriteAllTextAsync(Path.Combine(battlePassFixturePath, "manifest.json"), """
        {"name":"Genshin ClaimBattlePassRewards","version":"1.0.0","description":"verification","authors":[{"name":"BetterGI"}],"main":"main.js","settings":[],"library":[]}
        """);
    await File.WriteAllTextAsync(Path.Combine(battlePassFixturePath, "main.js"),
        "export {}; await genshin.claimBattlePassRewards();");
    var battlePassCaptureCount = 0;
    var battlePassMetricsCount = 0;
    var battlePassActivationCount = 0;
    var battlePassInputs = new List<string>();
    var battlePassResponder = Task.Run(async () =>
    {
        while (battlePassCaptureCount < 5 || battlePassInputs.Count < 7)
        {
            var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("genshin.claimBattlePassRewards callback channel ended unexpectedly.");
            switch (callback.Method)
            {
                case "window.activate":
                    battlePassActivationCount++;
                    await callbackConnection.WriteResponseAsync(
                        RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
                    break;
                case "window.metrics":
                    battlePassMetricsCount++;
                    await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                    {
                        captureX = 0, captureY = 0, captureWidth = schedulerWidth,
                        captureHeight = schedulerHeight, workingAreaWidth = schedulerWidth,
                        workingAreaHeight = schedulerHeight, dpiScale = 1.0, processId = 1
                    }), cancellation.Token);
                    break;
                case "capture.request":
                    battlePassCaptureCount++;
                    await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                    {
                        ringPath = captureRingPath, frameId = 8UL, sequence = 2UL, slot = 0,
                        width = schedulerWidth, height = schedulerHeight, stride = schedulerStride,
                        pixelFormat = "BGRA8"
                    }), cancellation.Token);
                    break;
                case "input.dispatch":
                {
                    var action = callback.Params?.Value<string>("action") ?? "";
                    var detail = action switch
                    {
                        "gameAction" => callback.Params?.Value<string>("gameAction") + ":" +
                                        callback.Params?.Value<string>("keyType"),
                        "moveMouseToScreen" => callback.Params?.Value<int>("x") + "," +
                                               callback.Params?.Value<int>("y"),
                        "mouseDown" or "mouseUp" => callback.Params?.Value<string>("button") ?? "",
                        _ => ""
                    };
                    battlePassInputs.Add($"{action}:{detail}");
                    await callbackConnection.WriteResponseAsync(
                        RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
                    break;
                }
                default:
                    throw new InvalidDataException(
                        $"genshin.claimBattlePassRewards emitted unexpected callback {callback.Method}.");
            }
        }
    }, cancellation.Token);
    await new ScriptProject("GenshinClaimBattlePassRewards").ExecuteAsync();
    await battlePassResponder;
    Require(battlePassCaptureCount == 5,
        $"genshin.claimBattlePassRewards capture sequence changed: {battlePassCaptureCount}.");
    Require(battlePassMetricsCount == 4,
        $"genshin.claimBattlePassRewards metrics sequence changed: {battlePassMetricsCount}.");
    Require(battlePassActivationCount == 0,
        "genshin.claimBattlePassRewards forced the game window to the foreground.");
    Require(battlePassInputs.SequenceEqual([
            "gameAction:openBattlePassScreen:keyPress",
            "moveMouseToScreen:960,45", "mouseDown:left", "mouseUp:left",
            "moveMouseToScreen:858,45", "mouseDown:left", "mouseUp:left"
        ]),
        "genshin.claimBattlePassRewards input sequence changed: " + string.Join(",", battlePassInputs));
    Console.WriteLine(
        "Real BetterGI genshin.claimBattlePassRewards passed: ClearScript, upstream OCR flow and acknowledged semantic input.");

    var craftingBenchRouteDirectory = Path.Combine(
        layout.RootPath, "GameTask", "Common", "Element", "Assets", "Json");
    Directory.CreateDirectory(craftingBenchRouteDirectory);
    await File.WriteAllTextAsync(Path.Combine(craftingBenchRouteDirectory, "合成台_验证.json"),
        """{"info":{"name":"合成台_验证","type":"collect"},"positions":[]}""");
    var craftingBenchFixturePath = Path.Combine(layout.UserPath, "JsScript", "GenshinGoToCraftingBench");
    Directory.CreateDirectory(craftingBenchFixturePath);
    await File.WriteAllTextAsync(Path.Combine(craftingBenchFixturePath, "manifest.json"), """
        {"name":"Genshin GoToCraftingBench","version":"1.0.0","description":"verification","authors":[{"name":"BetterGI"}],"main":"main.js","settings":[],"library":[]}
        """);
    await File.WriteAllTextAsync(Path.Combine(craftingBenchFixturePath, "main.js"),
        "export {}; await genshin.goToCraftingBench('验证');");
    using (var talkFrame = new OpenCvSharp.Mat(
               schedulerHeight, schedulerWidth, OpenCvSharp.MatType.CV_8UC3, OpenCvSharp.Scalar.Black))
    using (var disabledUi = OpenCvSharp.Cv2.ImRead(
               Path.Combine(sourceRoot, "AutoSkip/Assets/1920x1080/disabled_ui.png"),
               OpenCvSharp.ImreadModes.Color))
    {
        using (var target = new OpenCvSharp.Mat(
                   talkFrame, new OpenCvSharp.Rect(100, 30, disabledUi.Width, disabledUi.Height)))
            disabledUi.CopyTo(target);
        using var talkRegion = new ImageRegion(talkFrame.Clone(), 0, 0);
        Require(BetterGenshinImpact.GameTask.Common.BgiVision.Bv.IsInTalkUi(talkRegion),
            "crafting-bench fixture did not match the upstream talk-UI recognizer.");
        await WriteCaptureRingFrameAsync(captureRingPath, talkFrame, 9UL);
    }
    var craftingBenchMetricsCount = 0;
    var craftingBenchCaptureCount = 0;
    var craftingBenchActivationCount = 0;
    using var craftingBenchResponseCancellation =
        CancellationTokenSource.CreateLinkedTokenSource(cancellation.Token);
    var craftingBenchResponder = Task.Run(async () =>
    {
        try
        {
            while (true)
            {
                var callback = await callbackConnection.ReadRequestAsync(craftingBenchResponseCancellation.Token)
                    ?? throw new EndOfStreamException("genshin.goToCraftingBench callback channel ended unexpectedly.");
                if (callback.Method == "window.metrics")
                {
                    craftingBenchMetricsCount++;
                    await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                    {
                        captureX = 0, captureY = 0, captureWidth = schedulerWidth,
                        captureHeight = schedulerHeight, workingAreaWidth = schedulerWidth,
                        workingAreaHeight = schedulerHeight, dpiScale = 1.0, processId = 1
                    }), craftingBenchResponseCancellation.Token);
                    continue;
                }
                if (callback.Method == "window.activate")
                {
                    craftingBenchActivationCount++;
                    await callbackConnection.WriteResponseAsync(
                        RpcResponse.Success(callback.Id, new { acknowledged = true }),
                        craftingBenchResponseCancellation.Token);
                    continue;
                }
                Require(callback.Method == "capture.request",
                    $"genshin.goToCraftingBench emitted unexpected callback {callback.Method}.");
                craftingBenchCaptureCount++;
                await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                {
                    ringPath = captureRingPath, frameId = 9UL, sequence = 2UL, slot = 0,
                    width = schedulerWidth, height = schedulerHeight, stride = schedulerStride,
                    pixelFormat = "BGRA8"
                }), craftingBenchResponseCancellation.Token);
            }
        }
        catch (OperationCanceledException) when (craftingBenchResponseCancellation.IsCancellationRequested)
        {
        }
    }, craftingBenchResponseCancellation.Token);
    try
    {
        await new ScriptProject("GenshinGoToCraftingBench").ExecuteAsync();
    }
    finally
    {
        await craftingBenchResponseCancellation.CancelAsync();
    }
    await craftingBenchResponder;
    Require(craftingBenchMetricsCount >= 1,
        "genshin.goToCraftingBench bypassed PathExecutor game metrics.");
    Require(craftingBenchActivationCount == 0,
        "genshin.goToCraftingBench forced the game window to the foreground.");
    Require(craftingBenchCaptureCount == 1,
        $"genshin.goToCraftingBench talk-UI capture sequence changed: {craftingBenchCaptureCount}.");
    Console.WriteLine(
        "Real BetterGI genshin.goToCraftingBench passed: ClearScript, route loading, PathExecutor and talk-UI recognition.");

    var craftMaterialFixturePath = Path.Combine(layout.UserPath, "JsScript", "GenshinCraftMaterial");
    Directory.CreateDirectory(craftMaterialFixturePath);
    await File.WriteAllTextAsync(Path.Combine(craftMaterialFixturePath, "manifest.json"), """
        {"name":"Genshin CraftMaterial","version":"1.0.0","description":"verification","authors":[{"name":"BetterGI"}],"main":"main.js","settings":[],"library":[]}
        """);
    await File.WriteAllTextAsync(Path.Combine(craftMaterialFixturePath, "main.js"),
        "export {}; await genshin.craftMaterial('测试材料', 0, '角色与武器培养素材');");
    Exception? craftMaterialException = null;
    try
    {
        await new ScriptProject("GenshinCraftMaterial").ExecuteAsync();
    }
    catch (Exception exception)
    {
        craftMaterialException = exception;
    }
    Require(craftMaterialException is not null &&
            craftMaterialException.ToString().Contains("大于 0", StringComparison.Ordinal) &&
            !craftMaterialException.ToString().Contains("CapabilityUnavailable", StringComparison.Ordinal),
        "genshin.craftMaterial did not reach the upstream argument validation: " + craftMaterialException);
    Console.WriteLine(
        "Real BetterGI genshin.craftMaterial passed: ClearScript reached the upstream task and preserved validation errors.");
    using (var restoredFrame = new OpenCvSharp.Mat(
               schedulerHeight, schedulerWidth, OpenCvSharp.MatType.CV_8UC3, OpenCvSharp.Scalar.Black))
    using (var restoredPaimon = OpenCvSharp.Cv2.ImRead(
               Path.Combine(sourceRoot, "Common/Element/Assets/1920x1080/paimon_menu.png"),
               OpenCvSharp.ImreadModes.Color))
    {
        using (var target = new OpenCvSharp.Mat(
                   restoredFrame, new OpenCvSharp.Rect(24, 20, restoredPaimon.Width, restoredPaimon.Height)))
            restoredPaimon.CopyTo(target);
        await WriteCaptureRingFrameAsync(captureRingPath, restoredFrame, 8UL);
    }

    var bvExpectedInputs = new Queue<string>([
        "keyDown", "keyUp", "keyPress", "inputText", "moveMouseBy",
        "mouseClick:left", "mouseClick:right", "mouseClick:middle", "verticalScroll"
    ]);
    var bvResponder = Task.Run(async () =>
    {
        var metrics = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("BvImage did not request system metrics.");
        Require(metrics.Method == "window.metrics", "BvImage requested unexpected system data.");
        await callbackConnection.WriteResponseAsync(RpcResponse.Success(metrics.Id, new
        {
            captureWidth = schedulerWidth, captureHeight = schedulerHeight,
            workingAreaWidth = schedulerWidth, workingAreaHeight = schedulerHeight,
            captureX = 0, captureY = 0, processId = 1
        }), cancellation.Token);

        var capture = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("BvLocator did not request a real capture.");
        Require(capture.Method == "capture.request", "BvLocator emitted an unexpected capture callback.");
        await callbackConnection.WriteResponseAsync(RpcResponse.Success(capture.Id, new
        {
            ringPath = captureRingPath, frameId = 8UL, sequence = 2UL, slot = 0,
            width = schedulerWidth, height = schedulerHeight, stride = schedulerStride, pixelFormat = "BGRA8"
        }), cancellation.Token);

        while (bvExpectedInputs.Count > 0)
        {
            var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("Bv input callback channel ended unexpectedly.");
            Require(callback.Method == "input.dispatch", $"Bv input emitted unexpected callback {callback.Method}.");
            var action = callback.Params?.Value<string>("action") ?? "";
            var actual = callback.Params?.Value<string>("button") is { } button
                ? $"{action}:{button}"
                : action;
            Require(actual == bvExpectedInputs.Dequeue(), $"Bv input order changed at {actual}.");
            await callbackConnection.WriteResponseAsync(
                RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
        }
    }, cancellation.Token);
    using (var bvEngine = new V8ScriptEngine(
               V8ScriptEngineFlags.UseCaseInsensitiveMemberBinding |
               V8ScriptEngineFlags.EnableTaskPromiseConversion))
    {
        new MacScriptProjectHostInitializer(scriptGroupExecutionServices).Initialize(
            bvEngine, Path.Combine(layout.UserPath, "JsScript"), [], null);
        var bvFound = bvEngine.Evaluate("""
            const page = new BvPage();
            const found = page.getByImage(new BvImage("Common/Element:paimon_menu.png")).isExist();
            page.keyboard.keyDown(87).keyUp(87).keyPress(70).textEntry("A");
            page.mouse.moveMouseBy(3, -2).leftButtonClick().rightButtonClick().middleButtonClick().verticalScroll(1);
            found;
            """);
        Require(bvFound is true, "BvLocator did not find the real Paimon template through ClearScript.");
    }
    await bvResponder;
    Require(bvExpectedInputs.Count == 0, "Bv input proxy did not dispatch every acknowledged action.");
    Console.WriteLine("Bv host surface passed: upstream image/locator plus acknowledged keyboard and mouse proxies.");

    var genshinMetricsResponder = Task.Run(async () =>
    {
        for (var requestIndex = 0; requestIndex < 3; requestIndex++)
        {
            var metrics = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("genshin screen properties did not request window metrics.");
            Require(metrics.Method == "window.metrics",
                $"genshin screen properties emitted unexpected callback {metrics.Method}.");
            await callbackConnection.WriteResponseAsync(RpcResponse.Success(metrics.Id, new
            {
                captureWidth = 1920, captureHeight = 1080,
                workingAreaWidth = 2560, workingAreaHeight = 1440,
                captureX = 100, captureY = 50, processId = 1, dpiScale = 1.25
            }), cancellation.Token);
        }
    }, cancellation.Token);
    using (var metricsEngine = new V8ScriptEngine(V8ScriptEngineFlags.UseCaseInsensitiveMemberBinding))
    {
        new MacScriptProjectHostInitializer(scriptGroupExecutionServices).Initialize(
            metricsEngine, Path.Combine(layout.UserPath, "JsScript"), [], null);
        var metricsJson = Convert.ToString(metricsEngine.Evaluate("""
            JSON.stringify({ width: genshin.width, height: genshin.height, dpi: genshin.screenDpiScale });
            """)) ?? throw new InvalidOperationException("genshin screen properties returned no value.");
        var metrics = JObject.Parse(metricsJson);
        Require(metrics.Value<int>("width") == 1920 && metrics.Value<int>("height") == 1080 &&
                Math.Abs(metrics.Value<double>("dpi") - 1.25) < 0.001,
            $"genshin screen properties returned unexpected values: {metricsJson}");
    }
    await genshinMetricsResponder;
    Console.WriteLine("Real BetterGI genshin screen properties passed: ClearScript values came from macOS window.metrics callbacks.");

    var mapFixturePosition = new OpenCvSharp.Point2f(-4251.583984375f, -4785.17578125f);
    await StageMapBack3Async(layout.RootPath, cancellation.Token);
    using (var mapFrame = BuildGroundTruthNavigationFrame(
               layout.RootPath, MapAssets.Get(1920, 1080).MimiMapRect, mapFixturePosition))
    using (var paimon = OpenCvSharp.Cv2.ImRead(
               Path.Combine(sourceRoot, "Common/Element/Assets/1920x1080/paimon_menu.png"),
               OpenCvSharp.ImreadModes.Color))
    {
        using (var paimonTarget = new OpenCvSharp.Mat(
                   mapFrame, new OpenCvSharp.Rect(24, 20, paimon.Width, paimon.Height)))
            paimon.CopyTo(paimonTarget);
        await WriteCaptureRingFrameAsync(captureRingPath, mapFrame, 9UL);
    }
    var genshinMapResponder = Task.Run(async () =>
    {
        var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("genshin.getPositionFromMap did not request a real capture.");
        Require(callback.Method == "capture.request",
            $"genshin.getPositionFromMap emitted unexpected callback {callback.Method}.");
        await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
        {
            ringPath = captureRingPath, frameId = 9UL, sequence = 2UL, slot = 0,
            width = schedulerWidth, height = schedulerHeight, stride = schedulerStride, pixelFormat = "BGRA8"
        }), cancellation.Token);
        var position = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("genshin.getPositionFromMap did not publish its matched position.");
        Require(position.Method == "pathing.position",
            $"genshin.getPositionFromMap emitted unexpected callback {position.Method} after capture.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(position.Id, new { acknowledged = true }), cancellation.Token);
    }, cancellation.Token);
    using (var mapEngine = new V8ScriptEngine(
               V8ScriptEngineFlags.UseCaseInsensitiveMemberBinding |
               V8ScriptEngineFlags.EnableTaskPromiseConversion))
    {
        new MacScriptProjectHostInitializer(scriptGroupExecutionServices).Initialize(
            mapEngine, Path.Combine(layout.UserPath, "JsScript"), [], null);
        var positionJson = Convert.ToString(mapEngine.Evaluate("""
            const position = genshin.getPositionFromMapWithMatchingMethod("Teyvat", "TemplateMatch", 0);
            JSON.stringify({ x: position.x, y: position.y });
            """)) ?? throw new InvalidOperationException("genshin.getPositionFromMap returned no value.");
        var position = JObject.Parse(positionJson);
        var deltaX = Math.Abs(position.Value<float>("x") - mapFixturePosition.X);
        var deltaY = Math.Abs(position.Value<float>("y") - mapFixturePosition.Y);
        Require(deltaX <= 75 && deltaY <= 75,
            $"genshin.getPositionFromMap returned ({position["x"]},{position["y"]}) for fixture " +
            $"({mapFixturePosition.X},{mapFixturePosition.Y}).");
    }
    await genshinMapResponder;
    Console.WriteLine("Real BetterGI genshin.getPositionFromMap passed: ClearScript, capture ring and upstream TemplateMatch navigation.");

    const double teleportX = -1642.421;
    const double teleportY = 2163.664;
    using (var bigMapFrame = BuildGroundTruthBigMapFrame(
               layout.RootPath, sourceRoot, teleportX, teleportY))
    using (var teleportFrame = bigMapFrame.Clone())
    using (var mainUiFrame = new OpenCvSharp.Mat(
               schedulerHeight, schedulerWidth, OpenCvSharp.MatType.CV_8UC3, OpenCvSharp.Scalar.Black))
    using (var forceTeleportPartyFrame = OpenCvSharp.Cv2.ImRead(
               Path.Combine(AppContext.BaseDirectory, "Fixtures", "AutoFight", "别人进我世界_2人.png"),
               OpenCvSharp.ImreadModes.Color))
    using (var teleportButton = OpenCvSharp.Cv2.ImRead(
               Path.Combine(sourceRoot, "QuickTeleport/Assets/1920x1080/GoTeleport.png"),
               OpenCvSharp.ImreadModes.Color))
    using (var paimon = OpenCvSharp.Cv2.ImRead(
               Path.Combine(sourceRoot, "Common/Element/Assets/1920x1080/paimon_menu.png"),
               OpenCvSharp.ImreadModes.Color))
    {
        using (var target = new OpenCvSharp.Mat(teleportFrame,
                   new OpenCvSharp.Rect(1500, 1008, teleportButton.Width, teleportButton.Height)))
            teleportButton.CopyTo(target);
        using (var target = new OpenCvSharp.Mat(mainUiFrame,
                   new OpenCvSharp.Rect(24, 20, paimon.Width, paimon.Height)))
            paimon.CopyTo(target);

        var teleportFixturePath = Path.Combine(layout.UserPath, "JsScript", "GenshinTeleport");
        Directory.CreateDirectory(teleportFixturePath);
        await File.WriteAllTextAsync(Path.Combine(teleportFixturePath, "manifest.json"), """
            {"name":"Genshin Teleport","version":"1.0.0","description":"verification","authors":[{"name":"BetterGI"}],"main":"main.js","settings":[],"library":[]}
            """);
        var teleportScript = "export {}; await genshin.tp(" +
            teleportX.ToString(System.Globalization.CultureInfo.InvariantCulture) + "," +
            teleportY.ToString(System.Globalization.CultureInfo.InvariantCulture) +
            ", \"Teyvat\", true);";
        await File.WriteAllTextAsync(Path.Combine(teleportFixturePath, "main.js"), teleportScript);

        var teleportCaptureCount = 0;
        var teleportMetricsCount = 0;
        var teleportActivationCount = 0;
        var teleportInputActions = new List<string>();
        var teleportResponder = Task.Run(async () =>
        {
            while (teleportCaptureCount < 8)
            {
                var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                    ?? throw new EndOfStreamException("genshin.tp callback channel ended unexpectedly.");
                if (callback.Method == "window.metrics")
                {
                    teleportMetricsCount++;
                    await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                    {
                        captureX = 0, captureY = 0, captureWidth = schedulerWidth, captureHeight = schedulerHeight,
                        workingAreaWidth = schedulerWidth, workingAreaHeight = schedulerHeight,
                        dpiScale = 1.0, processId = 1
                    }), cancellation.Token);
                    continue;
                }
                if (callback.Method == "window.activate")
                {
                    teleportActivationCount++;
                    await callbackConnection.WriteResponseAsync(
                        RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
                    continue;
                }
                if (callback.Method == "capture.request")
                {
                    teleportCaptureCount++;
                    var frame = teleportCaptureCount switch
                    {
                        <= 6 => bigMapFrame,
                        7 => teleportFrame,
                        8 => mainUiFrame,
                        _ => throw new InvalidOperationException()
                    };
                    await WriteCaptureRingFrameAsync(captureRingPath, frame, (ulong)(10 + teleportCaptureCount));
                    await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                    {
                        ringPath = captureRingPath, frameId = (ulong)(10 + teleportCaptureCount),
                        sequence = 2UL, slot = 0, width = schedulerWidth, height = schedulerHeight,
                        stride = schedulerStride, pixelFormat = "BGRA8"
                    }), cancellation.Token);
                    continue;
                }

                Require(callback.Method == "input.dispatch",
                    $"genshin.tp emitted unexpected callback {callback.Method}.");
                teleportInputActions.Add(callback.Params?.Value<string>("action") ?? "");
                await callbackConnection.WriteResponseAsync(
                    RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
            }
        }, cancellation.Token);
        await new ScriptProject("GenshinTeleport").ExecuteAsync();
        await teleportResponder;
        Require(teleportCaptureCount == 8,
            $"genshin.tp capture sequence changed: {teleportCaptureCount}.");
        Require(teleportMetricsCount == 3 && teleportActivationCount == 0,
            $"genshin.tp platform sequence changed: metrics={teleportMetricsCount}, " +
            $"activations={teleportActivationCount}.");
        Require(teleportInputActions.SequenceEqual([
                "releaseAll",
                "moveMouseToScreen", "mouseDown", "mouseUp",
                "keyPress"
            ]),
            $"genshin.tp input sequence changed: {string.Join(",", teleportInputActions)}.");

        var forceTeleportCaptureCount = 0;
        var forceTeleportSetupCaptureCount = 0;
        var forceTeleportMetricsCount = 0;
        var forceTeleportActivationCount = 0;
        var forceTeleportInputDetails = new List<string>();
        var forceTeleportCurrentPathing = false;
        using var forceTeleportResponderCancellation =
            CancellationTokenSource.CreateLinkedTokenSource(cancellation.Token);
        var forceTeleportResponder = Task.Run(async () =>
        {
            var mapOpened = false;
            try
            {
                while (true)
                {
                    var callback = await callbackConnection.ReadRequestAsync(forceTeleportResponderCancellation.Token)
                        ?? throw new EndOfStreamException("force_tp callback channel ended unexpectedly.");
                    if (callback.Method == "window.metrics")
                    {
                        forceTeleportMetricsCount++;
                        await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                        {
                            width = schedulerWidth, height = schedulerHeight,
                            captureX = 0, captureY = 0, captureWidth = schedulerWidth, captureHeight = schedulerHeight,
                            workingAreaWidth = schedulerWidth, workingAreaHeight = schedulerHeight,
                            dpiScale = 1.0, processId = 1
                        }), forceTeleportResponderCancellation.Token);
                        continue;
                    }
                    if (callback.Method == "pathing.current")
                    {
                        forceTeleportCurrentPathing =
                            callback.Params?.Value<string>("name") == "Force TP Verification" &&
                            callback.Params?.Value<int>("waypointCount") == 1;
                        await callbackConnection.WriteResponseAsync(
                            RpcResponse.Success(callback.Id, new { acknowledged = true }),
                            forceTeleportResponderCancellation.Token);
                        continue;
                    }
                    if (callback.Method == "window.activate")
                    {
                        forceTeleportActivationCount++;
                        await callbackConnection.WriteResponseAsync(
                            RpcResponse.Success(callback.Id, new { acknowledged = true }),
                            forceTeleportResponderCancellation.Token);
                        continue;
                    }
                    if (callback.Method == "capture.request")
                    {
                        OpenCvSharp.Mat frame;
                        ulong frameId;
                        if (!mapOpened)
                        {
                            forceTeleportSetupCaptureCount++;
                            frame = forceTeleportPartyFrame;
                            frameId = (ulong)(20 + forceTeleportSetupCaptureCount);
                        }
                        else
                        {
                            forceTeleportCaptureCount++;
                            frame = forceTeleportCaptureCount switch
                            {
                                <= 6 => bigMapFrame,
                                7 => teleportFrame,
                                8 => mainUiFrame,
                                _ => throw new InvalidOperationException()
                            };
                            frameId = (ulong)(30 + forceTeleportCaptureCount);
                        }
                        await WriteCaptureRingFrameAsync(captureRingPath, frame, frameId);
                        await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                        {
                            ringPath = captureRingPath, frameId,
                            sequence = 2UL, slot = 0, width = schedulerWidth, height = schedulerHeight,
                            stride = schedulerStride, pixelFormat = "BGRA8"
                        }), forceTeleportResponderCancellation.Token);
                        continue;
                    }

                    Require(callback.Method == "input.dispatch",
                        $"force_tp emitted unexpected callback {callback.Method}.");
                    var action = callback.Params?.Value<string>("action") ?? "";
                    var gameAction = callback.Params?.Value<string>("gameAction");
                    var keyType = callback.Params?.Value<string>("keyType");
                    forceTeleportInputDetails.Add(gameAction is null
                        ? action
                        : $"{action}:{gameAction}:{keyType}");
                    mapOpened |= callback.Params?.Value<string>("gameAction") == "openMap";
                    await callbackConnection.WriteResponseAsync(
                        RpcResponse.Success(callback.Id, new { acknowledged = true }),
                        forceTeleportResponderCancellation.Token);
                }
            }
            catch (OperationCanceledException) when (forceTeleportResponderCancellation.IsCancellationRequested) { }
        }, cancellation.Token);
        var forceTeleportTask = new PathingTask
        {
            Info = new PathingTaskInfo
            {
                Name = "Force TP Verification",
                MapName = "Teyvat",
                MapMatchMethod = "TemplateMatch"
            },
            Positions =
            [
                new Waypoint
                {
                    X = teleportX,
                    Y = teleportY,
                    Type = WaypointType.Teleport.Code,
                    MoveMode = MoveModeEnum.Walk.Code,
                    Action = ActionEnum.ForceTp.Code
                }
            ]
        };
        var forceTeleportExecutor = new PathExecutor(
            cancellation.Token, PathExecutorPlatform.Current, PathExecutorAutoSkipPlatform.Current,
            ScriptGroupExecutionServices.Current)
        {
            PartyConfig = new PathingPartyConfig
            {
                SkipPartySwitch = true,
                MainAvatarIndex = string.Empty,
                GuardianAvatarIndex = string.Empty,
                AutoRunEnabled = false,
                AutoSkipEnabled = false,
                UseGadgetIntervalMs = 0
            }
        };
        await forceTeleportExecutor.Pathing(forceTeleportTask);
        forceTeleportResponderCancellation.Cancel();
        await forceTeleportResponder;

        var navigationInstance = typeof(Navigation)
            .GetField("_instance", System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic)
            ?.GetValue(null) ?? throw new InvalidOperationException("Navigation instance was not available.");
        var previousX = (float)(navigationInstance.GetType()
            .GetField("_prevX", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
            ?.GetValue(navigationInstance) ?? throw new InvalidOperationException("Navigation previous X was not available."));
        var previousY = (float)(navigationInstance.GetType()
            .GetField("_prevY", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
            ?.GetValue(navigationInstance) ?? throw new InvalidOperationException("Navigation previous Y was not available."));
        var expectedPreviousPosition = MapManager.GetMap("Teyvat", "TemplateMatch")
            .ConvertGenshinMapCoordinatesToImageCoordinates(
                new OpenCvSharp.Point2f((float)teleportX, (float)teleportY));
        Require(forceTeleportExecutor.SuccessEnd && forceTeleportCurrentPathing,
            "PathExecutor did not complete and publish the real force_tp route.");
        Require(forceTeleportSetupCaptureCount == 6 && forceTeleportCaptureCount == 8 &&
                forceTeleportMetricsCount == 9 &&
                forceTeleportActivationCount == 0,
            $"force_tp platform sequence changed: setupCaptures={forceTeleportSetupCaptureCount}, " +
            $"teleportCaptures={forceTeleportCaptureCount}, " +
            $"metrics={forceTeleportMetricsCount}, activations={forceTeleportActivationCount}.");
        Require(forceTeleportInputDetails.SequenceEqual([
                "releaseAll", "gameAction:openMap:keyPress",
                "moveMouseToScreen", "mouseDown", "mouseUp",
                "keyPress",
                "gameAction:moveForward:keyUp", "mouseUp"
            ]),
            $"force_tp input sequence changed: {string.Join(",", forceTeleportInputDetails)}.");
        Require(Math.Abs(previousX - expectedPreviousPosition.X) < 0.01f &&
                Math.Abs(previousY - expectedPreviousPosition.Y) < 0.01f,
            $"force_tp did not seed Navigation from the route coordinate: ({previousX},{previousY}).");
    }
    Console.WriteLine("Real BetterGI genshin.tp passed: big-map SIFT, target click, teleport button and main-UI completion.");
    Console.WriteLine("Real BetterGI force_tp passed: PathExecutor control flow, forced route coordinate and Navigation cache.");

    const double statueX = -575.6;
    const double statueY = 1859.34;
    using (var statueMapFrame = BuildGroundTruthBigMapFrame(
               layout.RootPath, sourceRoot, statueX, statueY))
    using (var statueTeleportFrame = statueMapFrame.Clone())
    using (var statueMainUiFrame = new OpenCvSharp.Mat(
               schedulerHeight, schedulerWidth, OpenCvSharp.MatType.CV_8UC3, OpenCvSharp.Scalar.Black))
    using (var teleportButton = OpenCvSharp.Cv2.ImRead(
               Path.Combine(sourceRoot, "QuickTeleport/Assets/1920x1080/GoTeleport.png"),
               OpenCvSharp.ImreadModes.Color))
    using (var paimon = OpenCvSharp.Cv2.ImRead(
               Path.Combine(sourceRoot, "Common/Element/Assets/1920x1080/paimon_menu.png"),
               OpenCvSharp.ImreadModes.Color))
    {
        using (var target = new OpenCvSharp.Mat(statueTeleportFrame,
                   new OpenCvSharp.Rect(1500, 1008, teleportButton.Width, teleportButton.Height)))
            teleportButton.CopyTo(target);
        using (var target = new OpenCvSharp.Mat(statueMainUiFrame,
                   new OpenCvSharp.Rect(24, 20, paimon.Width, paimon.Height)))
            paimon.CopyTo(target);

        var statueFixturePath = Path.Combine(layout.UserPath, "JsScript", "GenshinStatueTeleport");
        Directory.CreateDirectory(statueFixturePath);
        await File.WriteAllTextAsync(Path.Combine(statueFixturePath, "manifest.json"), """
            {"name":"Genshin Statue Teleport","version":"1.0.0","description":"verification","authors":[{"name":"BetterGI"}],"main":"main.js","settings":[],"library":[]}
            """);
        await File.WriteAllTextAsync(Path.Combine(statueFixturePath, "main.js"),
            "export {}; await genshin.tpToStatueOfTheSeven();");

        var statueCaptureCount = 0;
        var statueMetricsCount = 0;
        var statueActivationCount = 0;
        var statueInputActions = new List<string>();
        var statueResponder = Task.Run(async () =>
        {
            while (statueCaptureCount < 9)
            {
                var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                    ?? throw new EndOfStreamException("genshin.tpToStatueOfTheSeven callback channel ended unexpectedly.");
                if (callback.Method == "window.metrics")
                {
                    statueMetricsCount++;
                    await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                    {
                        captureX = 0, captureY = 0, captureWidth = schedulerWidth, captureHeight = schedulerHeight,
                        workingAreaWidth = schedulerWidth, workingAreaHeight = schedulerHeight,
                        dpiScale = 1.0, processId = 1
                    }), cancellation.Token);
                    continue;
                }
                if (callback.Method == "window.activate")
                {
                    statueActivationCount++;
                    await callbackConnection.WriteResponseAsync(
                        RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
                    continue;
                }
                if (callback.Method == "capture.request")
                {
                    statueCaptureCount++;
                    var frame = statueCaptureCount switch
                    {
                        <= 7 => statueMapFrame,
                        8 => statueTeleportFrame,
                        9 => statueMainUiFrame,
                        _ => throw new InvalidOperationException()
                    };
                    await WriteCaptureRingFrameAsync(captureRingPath, frame, (ulong)(30 + statueCaptureCount));
                    await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                    {
                        ringPath = captureRingPath, frameId = (ulong)(30 + statueCaptureCount),
                        sequence = 2UL, slot = 0, width = schedulerWidth, height = schedulerHeight,
                        stride = schedulerStride, pixelFormat = "BGRA8"
                    }), cancellation.Token);
                    continue;
                }

                Require(callback.Method == "input.dispatch",
                    $"genshin.tpToStatueOfTheSeven emitted unexpected callback {callback.Method}.");
                statueInputActions.Add(callback.Params?.Value<string>("action") ?? "");
                await callbackConnection.WriteResponseAsync(
                    RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
            }
        }, cancellation.Token);
        var statueStartedAt = System.Diagnostics.Stopwatch.GetTimestamp();
        await new ScriptProject("GenshinStatueTeleport").ExecuteAsync();
        var statueElapsed = System.Diagnostics.Stopwatch.GetElapsedTime(statueStartedAt);
        await statueResponder;
        Require(statueCaptureCount == 9 && statueMetricsCount == 3 && statueActivationCount == 0,
            $"genshin.tpToStatueOfTheSeven platform sequence changed: captures={statueCaptureCount}, " +
            $"metrics={statueMetricsCount}, activations={statueActivationCount}.");
        Require(statueInputActions.SequenceEqual([
                "releaseAll",
                "moveMouseToScreen", "mouseDown", "mouseUp",
                "keyPress"
            ]),
            "genshin.tpToStatueOfTheSeven input sequence changed: " +
            string.Join(",", statueInputActions));
        Require(statueElapsed >= TimeSpan.FromMilliseconds(900),
            $"genshin.tpToStatueOfTheSeven skipped the configured restore wait: {statueElapsed}.");
    }
    Console.WriteLine("Real BetterGI genshin.tpToStatueOfTheSeven passed: configured statue, teleport and restore wait.");

    using (var movementStartFrame = BuildGroundTruthNavigationFrame(
               layout.RootPath, MapAssets.Get(1920, 1080).MimiMapRect, mapFixturePosition))
    {
        BetterGenshinImpact.GameTask.AutoPathing.Navigation.Reset();
        var movementPositionProbe = Task.Run(async () =>
        {
            var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("ShouldMove position probe callback channel ended unexpectedly.");
            Require(callback.Method == "pathing.position",
                $"ShouldMove position probe emitted unexpected callback {callback.Method}.");
            await callbackConnection.WriteResponseAsync(
                RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
        }, cancellation.Token);
        OpenCvSharp.Point2f movementRecognizedImagePosition;
        using (var movementPositionRegion = new ImageRegion(movementStartFrame.Clone(), 0, 0))
            movementRecognizedImagePosition = BetterGenshinImpact.GameTask.AutoPathing.Navigation.GetPosition(
                movementPositionRegion, "Teyvat", "TemplateMatch");
        await movementPositionProbe;
        var movementMap = BetterGenshinImpact.GameTask.Common.Map.Maps.MapManager.GetMap(
            "Teyvat", "TemplateMatch");
        var movementRecognizedGamePosition = movementMap.ConvertImageCoordinatesToGenshinMapCoordinates(
            movementRecognizedImagePosition)
            ?? throw new InvalidOperationException("ShouldMove position probe escaped the staged map layer.");
        using var movementOrientationFrame = movementStartFrame.Clone();
        var movementCameraOrientation = BetterGenshinImpact.GameTask.Common.Map.CameraOrientation.Compute(
            movementOrientationFrame);
        var movementRadians = (movementCameraOrientation + 180d) * Math.PI / 180d;
        var movementDirectionX = Math.Cos(movementRadians);
        var movementDirectionY = Math.Sin(movementRadians);
        var movementStatueX = movementRecognizedGamePosition.X + movementDirectionX * 100d;
        var movementStatueY = movementRecognizedGamePosition.Y + movementDirectionY * 100d;
        var movementTargetGroundTruth = new OpenCvSharp.Point2f(
            mapFixturePosition.X + (float)(movementDirectionX * 95d),
            mapFixturePosition.Y + (float)(movementDirectionY * 95d));
        var movementTargetGame = new OpenCvSharp.Point2f(
            movementRecognizedGamePosition.X + (float)(movementDirectionX * 95d),
            movementRecognizedGamePosition.Y + (float)(movementDirectionY * 95d));
        var movementTargetImage = movementMap.ConvertGenshinMapCoordinatesToImageCoordinates(movementTargetGame);

        tpTaskPlatform.TpConfig.ShouldMove = true;
        tpTaskPlatform.TpConfig.HpRestoreDuration = 1;
        tpTaskPlatform.TpConfig.ReviveStatueOfTheSevenPointX = movementStatueX;
        tpTaskPlatform.TpConfig.ReviveStatueOfTheSevenPointY = movementStatueY;
        tpTaskPlatform.TpConfig.ReviveStatueOfTheSeven = new GiTpPosition
        {
            Id = "host-should-move",
            Name = "Host ShouldMove Statue",
            Type = "Goddess",
            Country = "verification",
            Areas = ["movement"],
            Position = [(decimal)movementStatueY, 0m, (decimal)movementStatueX],
            TranPosition = [
                (decimal)movementRecognizedGamePosition.Y, 0m, (decimal)movementRecognizedGamePosition.X
            ]
        };

        using var movementMapFrame = BuildGroundTruthBigMapFrame(
            layout.RootPath, sourceRoot, movementStatueX, movementStatueY);
        using var movementTeleportFrame = movementMapFrame.Clone();
        using var movementMainUiFrame = new OpenCvSharp.Mat(
            schedulerHeight, schedulerWidth, OpenCvSharp.MatType.CV_8UC3, OpenCvSharp.Scalar.Black);
        using var movementTargetFrame = BuildGroundTruthNavigationFrame(
            layout.RootPath, MapAssets.Get(1920, 1080).MimiMapRect, movementTargetGroundTruth);
        using var movementTeleportButton = OpenCvSharp.Cv2.ImRead(
            Path.Combine(sourceRoot, "QuickTeleport/Assets/1920x1080/GoTeleport.png"),
            OpenCvSharp.ImreadModes.Color);
        using var movementPaimon = OpenCvSharp.Cv2.ImRead(
            Path.Combine(sourceRoot, "Common/Element/Assets/1920x1080/paimon_menu.png"),
            OpenCvSharp.ImreadModes.Color);
        using (var target = new OpenCvSharp.Mat(movementTeleportFrame,
                   new OpenCvSharp.Rect(1500, 1008, movementTeleportButton.Width, movementTeleportButton.Height)))
            movementTeleportButton.CopyTo(target);
        using (var target = new OpenCvSharp.Mat(movementMainUiFrame,
                   new OpenCvSharp.Rect(24, 20, movementPaimon.Width, movementPaimon.Height)))
            movementPaimon.CopyTo(target);

        var movementFixturePath = Path.Combine(layout.UserPath, "JsScript", "GenshinStatueShouldMove");
        Directory.CreateDirectory(movementFixturePath);
        await File.WriteAllTextAsync(Path.Combine(movementFixturePath, "manifest.json"), """
            {"name":"Genshin Statue ShouldMove","version":"1.0.0","description":"verification","authors":[{"name":"BetterGI"}],"main":"main.js","settings":[],"library":[]}
            """);
        await File.WriteAllTextAsync(Path.Combine(movementFixturePath, "main.js"),
            "export {}; await genshin.tpToStatueOfTheSeven();");

        var movementCaptureCount = 0;
        var movementMetricsCount = 0;
        var movementActivationCount = 0;
        var movementPositionCount = 0;
        var movementStateQueryCount = 0;
        var movementInputs = new List<string>();
        OpenCvSharp.Mat? movementOrientationAlignedFrame = null;
        var movementResponder = Task.Run(async () =>
        {
            var dropObserved = false;
            var moveForwardPressed = false;
            while (!dropObserved)
            {
                var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                    ?? throw new EndOfStreamException("genshin statue ShouldMove callback channel ended unexpectedly.");
                switch (callback.Method)
                {
                    case "window.metrics":
                        movementMetricsCount++;
                        await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                        {
                            captureX = 0, captureY = 0, captureWidth = schedulerWidth,
                            captureHeight = schedulerHeight, workingAreaWidth = schedulerWidth,
                            workingAreaHeight = schedulerHeight, dpiScale = 1.0, processId = 1
                        }), cancellation.Token);
                        break;
                    case "window.activate":
                        movementActivationCount++;
                        await callbackConnection.WriteResponseAsync(
                            RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
                        break;
                    case "capture.request":
                    {
                        movementCaptureCount++;
                        var frame = movementCaptureCount switch
                        {
                            <= 7 => movementMapFrame,
                            8 => movementTeleportFrame,
                            9 => movementMainUiFrame,
                            10 => movementStartFrame,
                            _ when !moveForwardPressed => movementOrientationAlignedFrame
                                ?? throw new InvalidOperationException(
                                    "ShouldMove requested rotation before publishing its localized position."),
                            _ => movementTargetFrame
                        };
                        await WriteCaptureRingFrameAsync(
                            captureRingPath, frame, (ulong)(50 + movementCaptureCount));
                        await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                        {
                            ringPath = captureRingPath, frameId = (ulong)(50 + movementCaptureCount),
                            sequence = 2UL, slot = 0, width = schedulerWidth, height = schedulerHeight,
                            stride = schedulerStride, pixelFormat = "BGRA8"
                        }), cancellation.Token);
                        break;
                    }
                    case "pathing.position":
                        movementPositionCount++;
                        int? targetOrientationForFrame = null;
                        if (movementCaptureCount >= 10 && !moveForwardPressed &&
                            movementOrientationAlignedFrame is null)
                        {
                            var actualPosition = new OpenCvSharp.Point2f(
                                callback.Params?.Value<float>("x") ?? 0f,
                                callback.Params?.Value<float>("y") ?? 0f);
                            targetOrientationForFrame = BetterGenshinImpact.GameTask.AutoPathing.Navigation
                                .GetTargetOrientation(
                                    new Waypoint { X = movementTargetImage.X, Y = movementTargetImage.Y },
                                    actualPosition);
                        }
                        await callbackConnection.WriteResponseAsync(
                            RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
                        if (targetOrientationForFrame is { } targetOrientation)
                        {
                            movementOrientationAlignedFrame = BuildOrientationAlignedFrame(
                                movementStartFrame, MapAssets.Get(1920, 1080).MimiMapRect, targetOrientation);
                        }
                        break;
                    case "input.query":
                        Require(callback.Params?.Value<string>("action") == "isGameActionDown" &&
                                callback.Params?.Value<string>("gameAction") == "moveForward",
                            "ShouldMove queried an unexpected input state.");
                        movementStateQueryCount++;
                        await callbackConnection.WriteResponseAsync(
                            RpcResponse.Success(callback.Id, new { isDown = true }), cancellation.Token);
                        break;
                    case "input.dispatch":
                    {
                        var action = callback.Params?.Value<string>("action") ?? "";
                        var gameAction = callback.Params?.Value<string>("gameAction");
                        var keyType = callback.Params?.Value<string>("keyType");
                        movementInputs.Add(gameAction is null ? action : $"{action}:{gameAction}:{keyType}");
                        moveForwardPressed = moveForwardPressed ||
                                             gameAction == "moveForward" && keyType == "keyDown";
                        dropObserved = gameAction == "drop" && keyType == "keyPress";
                        await callbackConnection.WriteResponseAsync(
                            RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
                        break;
                    }
                    default:
                        throw new InvalidOperationException(
                            $"genshin statue ShouldMove emitted unexpected callback {callback.Method}.");
                }
            }
        }, cancellation.Token);

        var movementStartedAt = System.Diagnostics.Stopwatch.GetTimestamp();
        var movementScriptTask = Task.Run(
            () => new ScriptProject("GenshinStatueShouldMove").ExecuteAsync(), cancellation.Token);
        Require(await Task.WhenAny(movementScriptTask, Task.Delay(TimeSpan.FromSeconds(30), cancellation.Token)) ==
                movementScriptTask,
            "genshin statue ShouldMove did not complete within 30 seconds.");
        await movementScriptTask;
        var movementElapsed = System.Diagnostics.Stopwatch.GetElapsedTime(movementStartedAt);
        await movementResponder;
        movementOrientationAlignedFrame?.Dispose();
        Require(movementMetricsCount == 5 && movementActivationCount == 0,
            $"ShouldMove platform sequence changed: metrics={movementMetricsCount}, " +
            $"activations={movementActivationCount}.");
        Require(movementCaptureCount >= 12 && movementPositionCount >= 2,
            $"ShouldMove did not consume teleport plus movement frames: captures={movementCaptureCount}, " +
            $"positions={movementPositionCount}.");
        Require(movementStateQueryCount >= 1,
            "ShouldMove did not query the real MoveForward platform state.");
        Require(movementInputs.Contains("gameAction:moveForward:keyDown") &&
                movementInputs.Contains("gameAction:moveForward:keyUp") &&
                movementInputs.Last() == "gameAction:drop:keyPress",
            "ShouldMove did not execute forward down/up followed by Drop: " + string.Join(",", movementInputs));
        Require(movementElapsed >= TimeSpan.FromMilliseconds(900),
            $"ShouldMove skipped the configured restore wait: {movementElapsed}.");
        Console.WriteLine(
            "Real BetterGI statue ShouldMove passed: coherent minimap localization, MoveTo and final Drop RPC.");
    }
    tpTaskPlatform.TpConfig.ShouldMove = false;

    var nearestGoddess = MapLazyAssets.Get().GoddessPositions["293"];
    const double nearestCenterX = -4028.888;
    const double nearestCenterY = -4435.686;
    Require(Math.Abs(nearestGoddess.X - nearestCenterX) < 0.001 &&
            Math.Abs(nearestGoddess.Y - nearestCenterY) < 0.001,
        "source-locked tp.json ID=293 no longer resolves to the expected Seirai Island statue.");
    var nearestDeltaX = nearestGoddess.X - nearestGoddess.TranX;
    var nearestDeltaY = nearestGoddess.Y - nearestGoddess.TranY;
    var nearestDistance = Math.Sqrt(nearestDeltaX * nearestDeltaX + nearestDeltaY * nearestDeltaY);
    var nearestTargetGame = new OpenCvSharp.Point2f(
        (float)(nearestGoddess.X - nearestDeltaX * 5d / nearestDistance),
        (float)(nearestGoddess.Y - nearestDeltaY * 5d / nearestDistance));
    var nearestMap = BetterGenshinImpact.GameTask.Common.Map.Maps.MapManager.GetMap(
        "Teyvat", "TemplateMatch");
    var nearestTargetImage = nearestMap.ConvertGenshinMapCoordinatesToImageCoordinates(nearestTargetGame);
    using (var nearestCenterFrame = BuildGroundTruthBigMapFrame(
               layout.RootPath, sourceRoot, nearestCenterX, nearestCenterY))
    using (var nearestTeleportFrame = nearestCenterFrame.Clone())
    using (var nearestMainUiFrame = new OpenCvSharp.Mat(
               schedulerHeight, schedulerWidth, OpenCvSharp.MatType.CV_8UC3, OpenCvSharp.Scalar.Black))
    using (var nearestMovementStartFrame = BuildGroundTruthNavigationFrame(
               layout.RootPath, MapAssets.Get(1920, 1080).MimiMapRect,
               new OpenCvSharp.Point2f((float)nearestGoddess.TranX, (float)nearestGoddess.TranY)))
    using (var nearestMovementTargetFrame = BuildGroundTruthNavigationFrame(
               layout.RootPath, MapAssets.Get(1920, 1080).MimiMapRect, nearestTargetGame))
    using (var nearestTeleportButton = OpenCvSharp.Cv2.ImRead(
               Path.Combine(sourceRoot, "QuickTeleport/Assets/1920x1080/GoTeleport.png"),
               OpenCvSharp.ImreadModes.Color))
    using (var nearestPaimon = OpenCvSharp.Cv2.ImRead(
               Path.Combine(sourceRoot, "Common/Element/Assets/1920x1080/paimon_menu.png"),
               OpenCvSharp.ImreadModes.Color))
    {
        using (var target = new OpenCvSharp.Mat(nearestTeleportFrame,
                   new OpenCvSharp.Rect(1500, 1008, nearestTeleportButton.Width, nearestTeleportButton.Height)))
            nearestTeleportButton.CopyTo(target);
        using (var target = new OpenCvSharp.Mat(nearestMainUiFrame,
                   new OpenCvSharp.Rect(24, 20, nearestPaimon.Width, nearestPaimon.Height)))
            nearestPaimon.CopyTo(target);

        tpTaskPlatform.TpConfig.IsReviveInNearestStatueOfTheSeven = true;
        tpTaskPlatform.TpConfig.HpRestoreDuration = 1;
        var nearestFixturePath = Path.Combine(layout.UserPath, "JsScript", "GenshinNearestStatue");
        Directory.CreateDirectory(nearestFixturePath);
        await File.WriteAllTextAsync(Path.Combine(nearestFixturePath, "manifest.json"), """
            {"name":"Genshin Nearest Statue","version":"1.0.0","description":"verification","authors":[{"name":"BetterGI"}],"main":"main.js","settings":[],"library":[]}
            """);
        await File.WriteAllTextAsync(Path.Combine(nearestFixturePath, "main.js"),
            "export {}; await genshin.tpToStatueOfTheSeven();");

        BetterGenshinImpact.GameTask.AutoPathing.Navigation.Reset();
        var nearestCaptureCount = 0;
        var nearestMetricsCount = 0;
        var nearestActivationCount = 0;
        var nearestPositionCount = 0;
        var nearestStateQueryCount = 0;
        var nearestInputs = new List<string>();
        var nearestClicks = new List<OpenCvSharp.Point>();
        OpenCvSharp.Mat? nearestOrientationFrame = null;
        var nearestResponder = Task.Run(async () =>
        {
            var dropObserved = false;
            var moveForwardPressed = false;
            while (!dropObserved)
            {
                var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                    ?? throw new EndOfStreamException("nearest-statue callback channel ended unexpectedly.");
                switch (callback.Method)
                {
                    case "window.metrics":
                        nearestMetricsCount++;
                        await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                        {
                            captureX = 0, captureY = 0, captureWidth = schedulerWidth,
                            captureHeight = schedulerHeight, workingAreaWidth = schedulerWidth,
                            workingAreaHeight = schedulerHeight, dpiScale = 1.0, processId = 1
                        }), cancellation.Token);
                        break;
                    case "window.activate":
                        nearestActivationCount++;
                        await callbackConnection.WriteResponseAsync(
                            RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
                        break;
                    case "capture.request":
                    {
                        nearestCaptureCount++;
                        var frame = nearestCaptureCount switch
                        {
                            <= 8 => nearestCenterFrame,
                            9 => nearestTeleportFrame,
                            10 => nearestMainUiFrame,
                            11 => nearestMovementStartFrame,
                            _ when !moveForwardPressed => nearestOrientationFrame
                                ?? throw new InvalidOperationException(
                                    "nearest-statue movement requested rotation before position publication."),
                            _ => nearestMovementTargetFrame
                        };
                        await WriteCaptureRingFrameAsync(
                            captureRingPath, frame, (ulong)(80 + nearestCaptureCount));
                        await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
                        {
                            ringPath = captureRingPath, frameId = (ulong)(80 + nearestCaptureCount),
                            sequence = 2UL, slot = 0, width = schedulerWidth, height = schedulerHeight,
                            stride = schedulerStride, pixelFormat = "BGRA8"
                        }), cancellation.Token);
                        break;
                    }
                    case "pathing.position":
                    {
                        nearestPositionCount++;
                        int? targetOrientationForFrame = null;
                        if (nearestCaptureCount >= 11 && !moveForwardPressed && nearestOrientationFrame is null)
                        {
                            var actualPosition = new OpenCvSharp.Point2f(
                                callback.Params?.Value<float>("x") ?? 0f,
                                callback.Params?.Value<float>("y") ?? 0f);
                            targetOrientationForFrame = BetterGenshinImpact.GameTask.AutoPathing.Navigation
                                .GetTargetOrientation(
                                    new Waypoint { X = nearestTargetImage.X, Y = nearestTargetImage.Y },
                                    actualPosition);
                        }
                        await callbackConnection.WriteResponseAsync(
                            RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
                        if (targetOrientationForFrame is { } targetOrientation)
                            nearestOrientationFrame = BuildOrientationAlignedFrame(
                                nearestMovementStartFrame, MapAssets.Get(1920, 1080).MimiMapRect, targetOrientation);
                        break;
                    }
                    case "input.query":
                        Require(callback.Params?.Value<string>("action") == "isGameActionDown" &&
                                callback.Params?.Value<string>("gameAction") == "moveForward",
                            "nearest-statue movement queried an unexpected input state.");
                        nearestStateQueryCount++;
                        await callbackConnection.WriteResponseAsync(
                            RpcResponse.Success(callback.Id, new { isDown = true }), cancellation.Token);
                        break;
                    case "input.dispatch":
                    {
                        var action = callback.Params?.Value<string>("action") ?? "";
                        var gameAction = callback.Params?.Value<string>("gameAction");
                        var keyType = callback.Params?.Value<string>("keyType");
                        nearestInputs.Add(gameAction is null ? action : $"{action}:{gameAction}:{keyType}");
                        if (action == "moveMouseToScreen")
                            nearestClicks.Add(new OpenCvSharp.Point(
                                callback.Params?.Value<int>("x") ?? -1,
                                callback.Params?.Value<int>("y") ?? -1));
                        moveForwardPressed = moveForwardPressed ||
                                             gameAction == "moveForward" && keyType == "keyDown";
                        dropObserved = gameAction == "drop" && keyType == "keyPress";
                        await callbackConnection.WriteResponseAsync(
                            RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
                        break;
                    }
                    default:
                        throw new InvalidOperationException(
                            $"nearest-statue branch emitted unexpected callback {callback.Method}.");
                }
            }
        }, cancellation.Token);

        var nearestStartedAt = System.Diagnostics.Stopwatch.GetTimestamp();
        var nearestScriptTask = Task.Run(
            () => new ScriptProject("GenshinNearestStatue").ExecuteAsync(), cancellation.Token);
        Require(await Task.WhenAny(nearestScriptTask, Task.Delay(TimeSpan.FromSeconds(30), cancellation.Token)) ==
                nearestScriptTask,
            "nearest-statue script did not complete within 30 seconds.");
        await nearestScriptTask;
        var nearestElapsed = System.Diagnostics.Stopwatch.GetElapsedTime(nearestStartedAt);
        await nearestResponder;
        nearestOrientationFrame?.Dispose();
        Require(nearestCaptureCount >= 13 && nearestMetricsCount == 5 && nearestActivationCount == 0,
            $"nearest-statue platform sequence changed: captures={nearestCaptureCount}, " +
            $"metrics={nearestMetricsCount}, activations={nearestActivationCount}.");
        Require(nearestPositionCount >= 2 && nearestStateQueryCount >= 1,
            $"nearest-statue movement did not publish/query state: positions={nearestPositionCount}, " +
            $"queries={nearestStateQueryCount}.");
        Require(nearestClicks.Count == 1 &&
                Math.Abs(nearestClicks[0].X - 960) <= 10 && Math.Abs(nearestClicks[0].Y - 540) <= 10 &&
                nearestInputs.Contains("keyPress"),
            "nearest-statue selected unexpected target/confirmation input: " +
            string.Join(",", nearestClicks.Select(point => $"({point.X},{point.Y})")));
        Require(nearestInputs.Contains("gameAction:moveForward:keyDown") &&
                nearestInputs.Contains("gameAction:moveForward:keyUp") &&
                nearestInputs.Last() == "gameAction:drop:keyPress",
            "nearest-statue branch did not finish MoveTo and Drop: " + string.Join(",", nearestInputs));
        Require(nearestElapsed >= TimeSpan.FromMilliseconds(900),
            $"nearest-statue branch skipped restore wait: {nearestElapsed}.");
        Console.WriteLine(
            "Real BetterGI nearest-statue branch passed: big-map center SIFT, tp.json selection, MoveTo and Drop.");
    }
    tpTaskPlatform.TpConfig.IsReviveInNearestStatueOfTheSeven = false;

    using (var partyFrame = new OpenCvSharp.Mat(
               schedulerHeight, schedulerWidth, OpenCvSharp.MatType.CV_8UC3, OpenCvSharp.Scalar.Black))
    using (var partyButton = OpenCvSharp.Cv2.ImRead(
               Path.Combine(sourceRoot, "Common/Element/Assets/1920x1080/party_btn_choose_view.png"),
               OpenCvSharp.ImreadModes.Color))
    using (var paimon = OpenCvSharp.Cv2.ImRead(
               Path.Combine(sourceRoot, "Common/Element/Assets/1920x1080/paimon_menu.png"),
               OpenCvSharp.ImreadModes.Color))
    {
        using (var partyButtonTarget = new OpenCvSharp.Mat(
                   partyFrame, new OpenCvSharp.Rect(50, 1000, partyButton.Width, partyButton.Height)))
            partyButton.CopyTo(partyButtonTarget);
        using (var paimonTarget = new OpenCvSharp.Mat(
                   partyFrame, new OpenCvSharp.Rect(24, 20, paimon.Width, paimon.Height)))
            paimon.CopyTo(paimonTarget);
        OpenCvSharp.Cv2.PutText(partyFrame, "Team", new OpenCvSharp.Point(100, 1026),
            OpenCvSharp.HersheyFonts.HersheySimplex, 0.75, OpenCvSharp.Scalar.White, 2,
            OpenCvSharp.LineTypes.AntiAlias);
        using var partyBgra = new OpenCvSharp.Mat();
        OpenCvSharp.Cv2.CvtColor(partyFrame, partyBgra, OpenCvSharp.ColorConversionCodes.BGR2BGRA);
        using var partyRegion = new ImageRegion(partyBgra.Clone(), 0, 0);
        Require(BetterGenshinImpact.GameTask.Common.BgiVision.Bv.IsInPartyViewUi(partyRegion),
            "Synthetic party frame did not match the upstream party-view template.");
        using var partyViewButton = partyRegion.Find(ElementRecognition.Get("PartyBtnChooseView", partyRegion));
        var partyName = partyRegion.Find(new RecognitionObject
        {
            RecognitionType = RecognitionTypes.Ocr,
            RegionOfInterest = new OpenCvSharp.Rect(
                partyViewButton.Right, partyViewButton.Top, 350, partyViewButton.Height)
        }).Text;
        Require(partyName.Contains("Team", StringComparison.OrdinalIgnoreCase),
            $"Locked Paddle OCR did not read the party fixture name: '{partyName}'.");
        await WriteCaptureRingFrameAsync(captureRingPath, partyFrame, 10UL);
    }
    using (var partyRingRegion = new SharedCaptureRingReader(layout).Read(JObject.FromObject(new
           {
               ringPath = captureRingPath, frameId = 10UL, sequence = 2UL, slot = 0,
               width = schedulerWidth, height = schedulerHeight, stride = schedulerStride, pixelFormat = "BGRA8"
           })))
    {
        Require(BetterGenshinImpact.GameTask.Common.BgiVision.Bv.IsInPartyViewUi(partyRingRegion),
            "Party frame lost the upstream party-view template after the BGRA capture ring round-trip.");
    }
    var switchPartyFixturePath = Path.Combine(layout.UserPath, "JsScript", "GenshinSwitchParty");
    Directory.CreateDirectory(switchPartyFixturePath);
    await File.WriteAllTextAsync(Path.Combine(switchPartyFixturePath, "manifest.json"), """
        {"name":"Genshin SwitchParty","version":"1.0.0","description":"verification","authors":[{"name":"BetterGI"}],"main":"main.js","settings":[],"library":[]}
        """);
    await File.WriteAllTextAsync(Path.Combine(switchPartyFixturePath, "main.js"), """
        export {};
        if (!(await genshin.switchParty("Team"))) throw new Error("switchParty returned false");
        """);
    var switchPartyMetricsCount = 0;
    var switchPartyCaptureCount = 0;
    var switchPartyActivationCount = 0;
    var switchPartyResponder = Task.Run(async () =>
    {
        while (switchPartyCaptureCount < 2)
        {
            var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("genshin.switchParty callback channel ended unexpectedly.");
            object response = callback.Method switch
            {
                "window.metrics" => RecordSwitchPartyMetrics(
                    ref switchPartyMetricsCount, schedulerWidth, schedulerHeight),
                "capture.request" => RecordSwitchPartyCapture(
                    ref switchPartyCaptureCount, captureRingPath,
                    schedulerWidth, schedulerHeight, schedulerStride),
                "window.activate" => RecordAcknowledgement(ref switchPartyActivationCount),
                _ => throw new InvalidDataException(
                    $"genshin.switchParty emitted unexpected callback {callback.Method}.")
            };
            await callbackConnection.WriteResponseAsync(
                RpcResponse.Success(callback.Id, response), cancellation.Token);
        }
    }, cancellation.Token);
    await new ScriptProject("GenshinSwitchParty").ExecuteAsync();
    await switchPartyResponder;
    Require(switchPartyMetricsCount == 1 && switchPartyCaptureCount == 2 &&
            switchPartyActivationCount == 0,
        $"genshin.switchParty callbacks changed: metrics={switchPartyMetricsCount}, " +
        $"captures={switchPartyCaptureCount}, activations={switchPartyActivationCount}.");
    Console.WriteLine("Real BetterGI genshin.switchParty passed: ClearScript, party-view template and locked Paddle OCR.");

    var avatarOcrFallbackFixture = Path.Combine(
        AppContext.BaseDirectory, "Fixtures", "AutoFight", "别人进我世界_2人.png");
    Require(File.Exists(avatarOcrFallbackFixture),
        "Avatar OCR fallback fixture is missing: " + avatarOcrFallbackFixture);
    var avatarOcrFallbackHash = Convert.ToHexString(
        System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(avatarOcrFallbackFixture)))
        .ToLowerInvariant();
    Require(avatarOcrFallbackHash == "9f11e9762332f7dddcd3e926dbc7c4d7330e43d083d060ca929b2382e7c04b2f",
        "Avatar OCR fallback fixture hash changed: " + avatarOcrFallbackHash);
    var avatarOcrMetricsResponder = Task.Run(async () =>
    {
        var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("Avatar OCR fallback did not request window metrics.");
        Require(callback.Method == "window.metrics",
            "Avatar OCR fallback emitted unexpected callback: " + callback.Method);
        await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, new
        {
            captureX = 0, captureY = 0, captureWidth = 1920, captureHeight = 1080,
            workingAreaWidth = 1920, workingAreaHeight = 1080, dpiScale = 1.0, processId = 1
        }), cancellation.Token);
    }, cancellation.Token);
    using (var avatarOcrFallbackFrame = OpenCvSharp.Cv2.ImRead(
               avatarOcrFallbackFixture, OpenCvSharp.ImreadModes.Color))
    using (var avatarOcrFallbackRegion = new ImageRegion(avatarOcrFallbackFrame, 0, 0))
    using (var avatarOcrFallbackScenes = new ForcedAvatarOcrFallbackCombatScenes(
               imageRegionOcrService.CreateYoloPredictor(
                   BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.BgiAvatarSide),
               AutoFightAssets.Get(1920, 1080),
               loggerFactory.CreateLogger<CombatScenes>(),
               new HostVerificationSystemInfo())
               .InitializeTeam(avatarOcrFallbackRegion, new AutoFightConfig()))
    {
        var fallbackNames = avatarOcrFallbackScenes.GetAvatars()
            .Select(avatar => avatar.Name).ToArray();
        Require(fallbackNames.SequenceEqual(["阿蕾奇诺", "钟离"]),
            "Avatar OCR fallback did not recognize the real sidebar names: " +
            string.Join(",", fallbackNames));
    }
    await avatarOcrMetricsResponder;
    Console.WriteLine(
        "Real Avatar OCR fallback passed: forced YOLO failure, pinned game screenshot and locked Paddle OCR.");

    var schedulerStates = new List<string>();
    var schedulerResponder = Task.Run(async () =>
    {
        while (!schedulerStates.Any(state => state is "completed" or "failed" or "cancelled"))
        {
            var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("Scheduler callback channel ended unexpectedly.");
            object result = callback.Method switch
            {
                "window.metrics" => new
                {
                    captureX = 0, captureY = 0, captureWidth = schedulerWidth, captureHeight = schedulerHeight,
                    workingAreaWidth = schedulerWidth, workingAreaHeight = schedulerHeight,
                    dpiScale = 1.0, processId = 1
                },
                "capture.request" => new
                {
                    ringPath = captureRingPath, frameId = 10UL, sequence = 2UL, slot = 0,
                    width = schedulerWidth, height = schedulerHeight, stride = schedulerStride, pixelFormat = "BGRA8"
                },
                "scheduler.event" => RecordSchedulerState(callback.Params, schedulerStates),
                "window.activate" or "input.dispatch" or "notification.emit" => new { acknowledged = true },
                _ => throw new InvalidDataException($"Unexpected scheduler callback: {callback.Method}")
            };
            await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, result), cancellation.Token);
        }
    }, cancellation.Token);
    var schedulerRun = await ExchangeAsync(connection, "scheduler-real", "scheduler.run", sessionToken,
        JObject.FromObject(new { groupName = schedulerGroup.Name }), cancellation.Token);
    Require(schedulerRun.Error is null, schedulerRun.Error?.Message ?? "scheduler.run failed");
    var schedulerTaskId = JObject.FromObject(schedulerRun.Result!).Value<string>("taskId")
        ?? throw new InvalidDataException("scheduler.run omitted taskId");
    var schedulerPause = await ExchangeAsync(connection, "scheduler-pause", "scheduler.pause", sessionToken,
        JObject.FromObject(new { taskId = schedulerTaskId }), cancellation.Token);
    Require(schedulerPause.Error is null && JObject.FromObject(schedulerPause.Result!).Value<string>("state") == "paused",
        schedulerPause.Error?.Message ?? "scheduler.pause failed");
    var schedulerResume = await ExchangeAsync(connection, "scheduler-resume", "scheduler.resume", sessionToken,
        JObject.FromObject(new { taskId = schedulerTaskId }), cancellation.Token);
    Require(schedulerResume.Error is null && JObject.FromObject(schedulerResume.Result!).Value<string>("state") == "running",
        schedulerResume.Error?.Message ?? "scheduler.resume failed");
    await schedulerResponder;
    Require(await File.ReadAllTextAsync(schedulerMarker) == "scheduler-real",
        "scheduler RPC did not execute the real ScriptService Shell branch");
    Require(schedulerStates.FirstOrDefault() == "running" && schedulerStates.Contains("paused") &&
            schedulerStates.LastOrDefault() == "completed",
        "scheduler events did not preserve running/paused/resumed/completed lifecycle");

    var cancelledSchedulerStates = new List<string>();
    var cancelledSchedulerReleaseAllCount = 0;
    var cancelledSchedulerResponder = Task.Run(async () =>
    {
        while (!cancelledSchedulerStates.Contains("cancelled"))
        {
            var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("Cancelled scheduler callback channel ended unexpectedly.");
            object result = callback.Method switch
            {
                "window.metrics" => new
                {
                    captureX = 0, captureY = 0, captureWidth = schedulerWidth,
                    captureHeight = schedulerHeight, workingAreaWidth = schedulerWidth,
                    workingAreaHeight = schedulerHeight, dpiScale = 1.0, processId = 1
                },
                "capture.request" => new
                {
                    ringPath = captureRingPath, frameId = 10UL, sequence = 2UL, slot = 0,
                    width = schedulerWidth, height = schedulerHeight, stride = schedulerStride,
                    pixelFormat = "BGRA8"
                },
                "scheduler.event" => RecordSchedulerState(callback.Params, cancelledSchedulerStates),
                "input.dispatch" => RecordReleaseAll(callback.Params, ref cancelledSchedulerReleaseAllCount),
                "window.activate" or "notification.emit" => new { acknowledged = true },
                _ => throw new InvalidDataException(
                    $"Unexpected cancelled scheduler callback: {callback.Method}")
            };
            await callbackConnection.WriteResponseAsync(
                RpcResponse.Success(callback.Id, result), cancellation.Token);
        }
    }, cancellation.Token);
    var cancelledSchedulerRun = await ExchangeAsync(
        connection, "scheduler-cancelled", "scheduler.run", sessionToken,
        JObject.FromObject(new { groupName = cancelledSchedulerGroup.Name }), cancellation.Token);
    Require(cancelledSchedulerRun.Error is null,
        cancelledSchedulerRun.Error?.Message ?? "cancelled scheduler.run failed");
    var cancelledSchedulerTaskId = JObject.FromObject(cancelledSchedulerRun.Result!).Value<string>("taskId")
        ?? throw new InvalidDataException("cancelled scheduler.run omitted taskId");
    Require(await WaitForFileAsync(cancelledSchedulerMarker, TimeSpan.FromSeconds(5), cancellation.Token),
        "scheduler.stop verification did not enter the real Shell project before cancellation");
    var schedulerStop = await ExchangeAsync(
        connection, "scheduler-stop", "scheduler.stop", sessionToken,
        JObject.FromObject(new { taskId = cancelledSchedulerTaskId }), cancellation.Token);
    Require(schedulerStop.Error is null &&
            JObject.FromObject(schedulerStop.Result!).Value<string>("state") == "stopping",
        schedulerStop.Error?.Message ?? "scheduler.stop failed");
    await cancelledSchedulerResponder;
    Require(await File.ReadAllTextAsync(cancelledSchedulerMarker) == "scheduler-cancelled",
        "scheduler.stop verification did not preserve the Shell entry marker");
    Require(cancelledSchedulerReleaseAllCount == 1,
        $"scheduler.stop dispatched releaseAll {cancelledSchedulerReleaseAllCount} times instead of once");
    Require(cancelledSchedulerStates.FirstOrDefault() == "running" &&
            cancelledSchedulerStates.LastOrDefault() == "cancelled",
        "scheduler.stop did not preserve running/cancelled lifecycle");

    var rejectedSchedulerStates = new List<string>();
    var rejectedSchedulerInputCount = 0;
    var rejectedSchedulerResponder = Task.Run(async () =>
    {
        while (!rejectedSchedulerStates.Contains("failed"))
        {
            var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                ?? throw new EndOfStreamException("Rejected scheduler callback channel ended unexpectedly.");
            if (callback.Method == "input.dispatch")
            {
                rejectedSchedulerInputCount++;
                var response = rejectedSchedulerInputCount == 1
                    ? RpcResponse.Failure(callback.Id, "InputRejected", "verification input failure")
                    : RpcResponse.Success(callback.Id, new { acknowledged = true });
                await callbackConnection.WriteResponseAsync(response, cancellation.Token);
                continue;
            }

            object result = callback.Method switch
            {
                "window.metrics" => new
                {
                    captureX = 0, captureY = 0, captureWidth = schedulerWidth, captureHeight = schedulerHeight,
                    workingAreaWidth = schedulerWidth, workingAreaHeight = schedulerHeight,
                    dpiScale = 1.0, processId = 1
                },
                "capture.request" => new
                {
                    ringPath = captureRingPath, frameId = 10UL, sequence = 2UL, slot = 0,
                    width = schedulerWidth, height = schedulerHeight, stride = schedulerStride, pixelFormat = "BGRA8"
                },
                "scheduler.event" => RecordSchedulerState(callback.Params, rejectedSchedulerStates),
                "notification.emit" => new { acknowledged = true },
                _ => throw new InvalidDataException($"Unexpected rejected scheduler callback: {callback.Method}")
            };
            await callbackConnection.WriteResponseAsync(RpcResponse.Success(callback.Id, result), cancellation.Token);
        }
    }, cancellation.Token);
    var rejectedSchedulerRun = await ExchangeAsync(
        connection, "scheduler-rejected", "scheduler.run", sessionToken,
        JObject.FromObject(new { groupName = rejectedSchedulerGroup.Name }), cancellation.Token);
    Require(rejectedSchedulerRun.Error is null, rejectedSchedulerRun.Error?.Message ?? "rejected scheduler.run failed");
    await rejectedSchedulerResponder;
    Require(rejectedSchedulerInputCount >= 1 &&
            rejectedSchedulerStates.FirstOrDefault() == "running" &&
            rejectedSchedulerStates.LastOrDefault() == "failed",
        "scheduler did not publish failed after a platform input rejection");

    var lockedSchedulerStates = new List<string>();
    await TaskRunnerPlatform.Current.TaskSemaphore.WaitAsync(cancellation.Token);
    try
    {
        var lockedSchedulerResponder = Task.Run(async () =>
        {
            while (!lockedSchedulerStates.Contains("failed"))
            {
                var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
                    ?? throw new EndOfStreamException("Locked scheduler callback channel ended unexpectedly.");
                object result = callback.Method switch
                {
                    "window.metrics" => new
                    {
                        captureX = 0, captureY = 0, captureWidth = schedulerWidth,
                        captureHeight = schedulerHeight, workingAreaWidth = schedulerWidth,
                        workingAreaHeight = schedulerHeight, dpiScale = 1.0, processId = 1
                    },
                    "window.activate" => new { acknowledged = true },
                    "capture.request" => new
                    {
                        ringPath = captureRingPath, frameId = 10UL, sequence = 2UL, slot = 0,
                        width = schedulerWidth, height = schedulerHeight, stride = schedulerStride,
                        pixelFormat = "BGRA8"
                    },
                    "scheduler.event" => RecordSchedulerState(callback.Params, lockedSchedulerStates),
                    _ => throw new InvalidDataException($"Unexpected locked scheduler callback: {callback.Method}")
                };
                await callbackConnection.WriteResponseAsync(
                    RpcResponse.Success(callback.Id, result), cancellation.Token);
            }
        }, cancellation.Token);
        var lockedSchedulerRun = await ExchangeAsync(
            connection, "scheduler-locked", "scheduler.run", sessionToken,
            JObject.FromObject(new { groupName = lockedSchedulerGroup.Name }), cancellation.Token);
        Require(lockedSchedulerRun.Error is null, lockedSchedulerRun.Error?.Message ?? "locked scheduler.run failed");
        await lockedSchedulerResponder;
    }
    finally
    {
        TaskRunnerPlatform.Current.TaskSemaphore.Release();
    }
    Require(!File.Exists(lockedSchedulerMarker) &&
            lockedSchedulerStates.FirstOrDefault() == "running" &&
            lockedSchedulerStates.LastOrDefault() == "failed",
        "scheduler reported success or executed the project after task-lock rejection");

    var missingGroup = await ExchangeAsync(connection, "3", "scheduler.run", sessionToken,
        JObject.FromObject(new { groupName = "missing-group" }), cancellation.Token);
    Require(missingGroup.Error?.Code == "FileNotFoundException", "scheduler.run did not validate the authoritative Core catalog");

    var soloList = await ExchangeAsync(connection, "solo-list", "solo.list", sessionToken, null, cancellation.Token);
    Require(soloList.Error is null && soloList.Result is JArray soloItems &&
            soloItems.Where(item => item.Value<string>("name") is "AutoFishing" or "AutoWood" or "AutoFight" or "AutoCook" or "AutoMusicGame")
                .All(item => item.Value<bool>("available")) &&
            soloItems.Where(item => item.Value<string>("name") is not ("AutoFishing" or "AutoWood" or "AutoFight" or "AutoCook" or "AutoMusicGame"))
                .All(item => !item.Value<bool>("available")),
        "solo.list did not expose the truthful Core capability catalog");
    var soloStart = await ExchangeAsync(connection, "solo-start", "solo.start", sessionToken,
        JObject.FromObject(new { name = "AutoFishing" }), cancellation.Token);
    var soloTaskId = (soloStart.Result as JObject)?.Value<string>("taskId");
    Require(soloStart.Error is null && !string.IsNullOrEmpty(soloTaskId) &&
            dispatcherRuntime.FishingStartCount == 1,
        "solo.start did not execute the shared AutoFishing dispatcher request");
    var soloStop = await ExchangeAsync(connection, "solo-stop", "solo.stop", sessionToken,
        JObject.FromObject(new { taskId = soloTaskId }), cancellation.Token);
    Require(soloStop.Error is null, soloStop.Error?.Message ?? "solo.stop failed");
    for (var attempt = 0; attempt < 20 && !dispatcherRuntime.FishingCancelled; attempt++)
        await Task.Delay(25, cancellation.Token);
    var soloStatus = await ExchangeAsync(connection, "solo-status", "solo.status", sessionToken, null, cancellation.Token);
    Require(dispatcherRuntime.FishingCancelled &&
            (soloStatus.Result as JObject)?.Value<string>("state") == "cancelled",
        "solo.stop did not cancel the active Core AutoFishing task");
    var cookStart = await ExchangeAsync(connection, "cook-start", "solo.start", sessionToken,
        JObject.FromObject(new { name = "AutoCook" }), cancellation.Token);
    var cookTaskId = (cookStart.Result as JObject)?.Value<string>("taskId");
    Require(cookStart.Error is null && !string.IsNullOrEmpty(cookTaskId) &&
            dispatcherRuntime.CookStartCount == 1,
        "solo.start did not execute the shared AutoCook dispatcher request");
    var cookStop = await ExchangeAsync(connection, "cook-stop", "solo.stop", sessionToken,
        JObject.FromObject(new { taskId = cookTaskId }), cancellation.Token);
    Require(cookStop.Error is null, cookStop.Error?.Message ?? "solo.stop AutoCook failed");
    for (var attempt = 0; attempt < 20 && !dispatcherRuntime.CookCancelled; attempt++)
        await Task.Delay(25, cancellation.Token);
    Require(dispatcherRuntime.CookCancelled,
        "solo.stop did not cancel the active Core AutoCook task");
    var woodStart = await ExchangeAsync(connection, "wood-start", "solo.start", sessionToken,
        JObject.FromObject(new { name = "AutoWood" }), cancellation.Token);
    var woodTaskId = (woodStart.Result as JObject)?.Value<string>("taskId");
    Require(woodStart.Error is null && !string.IsNullOrEmpty(woodTaskId) &&
            dispatcherRuntime.WoodStartCount == 1 &&
            dispatcherRuntime.LastWoodRoundNum == 0 &&
            dispatcherRuntime.LastWoodDailyMaxCount == 2000,
        "solo.start did not execute the shared AutoWood dispatcher request with upstream defaults");
    var woodStop = await ExchangeAsync(connection, "wood-stop", "solo.stop", sessionToken,
        JObject.FromObject(new { taskId = woodTaskId }), cancellation.Token);
    Require(woodStop.Error is null, woodStop.Error?.Message ?? "solo.stop AutoWood failed");
    for (var attempt = 0; attempt < 20 && !dispatcherRuntime.WoodCancelled; attempt++)
        await Task.Delay(25, cancellation.Token);
    Require(dispatcherRuntime.WoodCancelled,
        "solo.stop did not cancel the active Core AutoWood task");
    var musicStart = await ExchangeAsync(connection, "music-start", "solo.start", sessionToken,
        JObject.FromObject(new { name = "AutoMusicGame" }), cancellation.Token);
    var musicTaskId = (musicStart.Result as JObject)?.Value<string>("taskId");
    Require(musicStart.Error is null && !string.IsNullOrEmpty(musicTaskId) &&
            dispatcherRuntime.MusicStartCount == 1,
        "solo.start did not execute the shared AutoMusicGame dispatcher request");
    var musicStop = await ExchangeAsync(connection, "music-stop", "solo.stop", sessionToken,
        JObject.FromObject(new { taskId = musicTaskId }), cancellation.Token);
    Require(musicStop.Error is null, musicStop.Error?.Message ?? "solo.stop AutoMusicGame failed");
    for (var attempt = 0; attempt < 20 && !dispatcherRuntime.MusicCancelled; attempt++)
        await Task.Delay(25, cancellation.Token);
    Require(dispatcherRuntime.MusicCancelled,
        "solo.stop did not cancel the active Core AutoMusicGame task");
    var fightStart = await ExchangeAsync(connection, "fight-start", "solo.start", sessionToken,
        JObject.FromObject(new { name = "AutoFight" }), cancellation.Token);
    var fightTaskId = (fightStart.Result as JObject)?.Value<string>("taskId");
    Require(fightStart.Error is null && !string.IsNullOrEmpty(fightTaskId) &&
            dispatcherRuntime.FightStartCount == 1,
        "solo.start did not execute the shared AutoFight dispatcher request");
    var fightStop = await ExchangeAsync(connection, "fight-stop", "solo.stop", sessionToken,
        JObject.FromObject(new { taskId = fightTaskId }), cancellation.Token);
    Require(fightStop.Error is null, fightStop.Error?.Message ?? "solo.stop AutoFight failed");
    for (var attempt = 0; attempt < 20 && !dispatcherRuntime.FightCancelled; attempt++)
        await Task.Delay(25, cancellation.Token);
    Require(dispatcherRuntime.FightCancelled,
        "solo.stop did not cancel the active Core AutoFight task");
    await connection.DisposeAsync();

    await using var rejectedConnection = await ConnectAsync(socketPath, cancellation.Token);
    var rejected = await ExchangeAsync(rejectedConnection, "4", "core.handshake", "wrong", null, cancellation.Token);
    Require(rejected.Error?.Code == "Unauthorized", "invalid session token was accepted");

    Console.WriteLine("Core Host verification passed: duplex RPC, framing, 0600, OpenCV, ClearScript, real ScriptProject, real zsh execution, authoritative catalog save, scheduler pause/resume boundary, auth.");
}
finally
{
    GameTaskManager.ClearTriggers();
    GameTaskManager.ReloadAssets();
    cancellation.Cancel();
    try { await serverTask; } catch (OperationCanceledException) { }
    imageRegionOcrService.Dispose();
    Microsoft.ML.OnnxRuntime.OrtEnv.Instance().Dispose();
    Directory.Delete(root, true);
}

static object RecordSchedulerState(JObject? parameters, List<string> states)
{
    var state = parameters?.Value<string>("state")
        ?? throw new InvalidDataException("scheduler.event omitted state.");
    states.Add(state);
    if (parameters?["error"] is JObject error)
        Console.WriteLine($"Scheduler {state}: {error.Value<string>("code")}: {error.Value<string>("message")}");
    return new { acknowledged = true };
}

static object RecordSwitchPartyMetrics(ref int count, int width, int height)
{
    count++;
    return new
    {
        captureWidth = width, captureHeight = height,
        workingAreaWidth = width, workingAreaHeight = height,
        captureX = 0, captureY = 0, processId = 1
    };
}

static object RecordSwitchPartyCapture(
    ref int count, string captureRingPath, int width, int height, int stride)
{
    count++;
    return new
    {
        ringPath = captureRingPath, frameId = 10UL, sequence = 2UL, slot = 0,
        width, height, stride, pixelFormat = "BGRA8"
    };
}

static object RecordAcknowledgement(ref int count)
{
    count++;
    return new { acknowledged = true };
}

static object RecordReleaseAll(JObject? parameters, ref int count)
{
    Require(parameters?.Value<string>("action") == "releaseAll",
        "scheduler.stop emitted an unexpected input action");
    count++;
    return new { acknowledged = true };
}

static async Task<bool> WaitForFileAsync(
    string path, TimeSpan timeout, CancellationToken cancellationToken)
{
    var deadline = DateTime.UtcNow + timeout;
    while (DateTime.UtcNow < deadline)
    {
        if (File.Exists(path))
            return true;
        await Task.Delay(25, cancellationToken);
    }
    return File.Exists(path);
}

static async Task<FramedJsonConnection> ConnectAsync(string socketPath, CancellationToken cancellationToken)
{
    var socket = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
    await socket.ConnectAsync(new UnixDomainSocketEndPoint(socketPath), cancellationToken);
    return new FramedJsonConnection(socket);
}

static async Task<RpcResponse> ExchangeAsync(
    FramedJsonConnection connection,
    string id,
    string method,
    string token,
    JObject? parameters,
    CancellationToken cancellationToken)
{
    await connection.WriteRequestAsync(new RpcRequest(id, method, parameters, token), cancellationToken);
    return await connection.ReadResponseAsync(cancellationToken)
        ?? throw new EndOfStreamException("Core closed the RPC connection without a response.");
}

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

static void CopyDirectory(string source, string destination)
{
    if (!Directory.Exists(source)) throw new DirectoryNotFoundException(source);
    Directory.CreateDirectory(destination);
    foreach (var file in Directory.EnumerateFiles(source))
        File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), overwrite: true);
    foreach (var directory in Directory.EnumerateDirectories(source))
        CopyDirectory(directory, Path.Combine(destination, Path.GetFileName(directory)));
}

static async Task StageMapBack3Async(string runtimeRoot, CancellationToken cancellationToken)
{
    var sourceLockPath = Path.Combine(
        Directory.GetCurrentDirectory(), "BetterGenshinImpact.Core", "Manifest", "model-artifacts.source-lock.json");
    var source = BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader
        .LoadSourceLock(sourceLockPath).Sources.Single();
    var localArchive = Path.Combine(
        Directory.GetCurrentDirectory(), "artifacts", "provenance-audit", "release-0.62.0",
        "downloads", "BetterGI_v0.62.0.7z");
    if (File.Exists(localArchive))
        source.Url = new Uri(localArchive).AbsoluteUri;
    var license = new BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader.LicenseEvidenceEntry
    {
        SpdxId = "GPL-3.0",
        Source = "BetterGI release 0.62.0 map layer data",
        RedistributionStatus = "allowed"
    };
    BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader.ArtifactEntry Artifact(
        string destination, string member, long size, string sha256) => new()
    {
        DestinationRelativePath = destination,
        SourceId = source.Id,
        MemberPath = member,
        SizeBytes = size,
        Sha256 = sha256,
        Transformation = "relocate",
        LicenseEvidence = license
    };
    var mapLock = new BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader.SourceLock
    {
        SchemaVersion = 1,
        ArtifactSetVersion = "0.62.0",
        Sources = [source],
        Artifacts =
        [
            Artifact("Assets/Map/Teyvat/mapback_info.json", "BetterGI/Assets/Map/Teyvat/mapback_info.json", 705,
                "7adf428edd494f8c6445a3e6f66a889f579b6ba0578a148d4cbf0bc1ddb135ea"),
            Artifact("Assets/Map/Teyvat/MapBack_3_color.webp", "BetterGI/Assets/Map/Teyvat/MapBack_3_color.webp", 149064,
                "e64715356c3e6e84646d4022533c4c7a709c57cfc93b92213a4cfc8d52b90fc4"),
            Artifact("Assets/Map/Teyvat/MapBack_3_gray.webp", "BetterGI/Assets/Map/Teyvat/MapBack_3_gray.webp", 1302572,
                "1bfafc57afbda3d0dd4a89a301d2ae645f47df3ad456eb63c856adc0193d1379"),
            Artifact("Assets/Map/Teyvat/Teyvat_0_256.png", "BetterGI/Assets/Map/Teyvat/Teyvat_0_256.png", 3671250,
                "3fcce29d0951117e7a0ff8c707537255f8aa980f1227718b27f84ed9b209ca7c"),
            Artifact("Assets/Map/Teyvat/Teyvat_0_256_SIFT.kp.bin", "BetterGI/Assets/Map/Teyvat/Teyvat_0_256_SIFT.kp.bin", 856128,
                "6a0f18b74adfa4c00a21c95f0a7ff4f32087b0495b19f75972723367ac85dc73"),
            Artifact("Assets/Map/Teyvat/Teyvat_0_256_SIFT.mat.png", "BetterGI/Assets/Map/Teyvat/Teyvat_0_256_SIFT.mat.png", 3451880,
                "70e10ebb9f2ace54dd878037742651be38e2d40af473dc7625202e3318f97221")
        ]
    };
    var temporaryLockPath = Path.Combine(Path.GetTempPath(), $"bgi-host-map-{Guid.NewGuid():N}.json");
    try
    {
        await File.WriteAllTextAsync(temporaryLockPath, System.Text.Json.JsonSerializer.Serialize(
            mapLock, new System.Text.Json.JsonSerializerOptions
            {
                PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
            }), cancellationToken);
        using var downloader = new BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader();
        var result = await downloader.EnsureInstalledAsync(
            temporaryLockPath, runtimeRoot, cancellationToken,
            Path.Combine(Path.GetTempPath(), "bgi-release-archive-cache"));
        Require(result.Success, "MapBack_3 source-lock install failed: " + string.Join("; ", result.Errors));
    }
    finally
    {
        File.Delete(temporaryLockPath);
    }

    var descriptorPath = Path.Combine(runtimeRoot, "Assets", "Map", "Teyvat", "mapback_info.json");
    using var descriptor = System.Text.Json.JsonDocument.Parse(await File.ReadAllTextAsync(
        descriptorPath, cancellationToken));
    var mapBack3 = descriptor.RootElement.EnumerateArray()
        .Single(entry => entry.GetProperty("LayerId").GetString() == "MapBack_3");
    await File.WriteAllTextAsync(descriptorPath, "[" + mapBack3.GetRawText() + "]", cancellationToken);
}

static async Task StageLockedRuntimeArtifactsAsync(string runtimeRoot, CancellationToken cancellationToken)
{
    var sourceLockPath = Path.Combine(
        Directory.GetCurrentDirectory(), "BetterGenshinImpact.Core", "Manifest", "model-artifacts.source-lock.json");
    var completeLock = BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader.LoadSourceLock(sourceLockPath);
    var runtimeArtifactPaths = new HashSet<string>(StringComparer.Ordinal)
    {
        "Assets/Model/Common/avatar_side_classify_sim.onnx",
        "Assets/Model/PaddleOCR/Det/V5/ppocr_det_v5.onnx",
        "Assets/Model/PaddleOCR/Rec/V5/ppocr_rec_v5.onnx",
        "Assets/Model/PaddleOCR/Rec/V5/inference.yml",
        "Assets/Model/PaddleOCR/test_pp_ocr.png"
    };
    var runtimeArtifactLock = new BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader.SourceLock
    {
        SchemaVersion = completeLock.SchemaVersion,
        ArtifactSetVersion = completeLock.ArtifactSetVersion,
        Sources = completeLock.Sources,
        Artifacts = completeLock.Artifacts
            .Where(artifact => runtimeArtifactPaths.Contains(artifact.DestinationRelativePath)).ToList()
    };
    Require(runtimeArtifactLock.Artifacts.Count == runtimeArtifactPaths.Count,
        $"Runtime source-lock selection returned {runtimeArtifactLock.Artifacts.Count} " +
        $"of {runtimeArtifactPaths.Count} artifacts.");
    var temporaryLockPath = Path.Combine(Path.GetTempPath(), $"bgi-host-runtime-{Guid.NewGuid():N}.json");
    try
    {
        await File.WriteAllTextAsync(temporaryLockPath, System.Text.Json.JsonSerializer.Serialize(
            runtimeArtifactLock, new System.Text.Json.JsonSerializerOptions
            {
                PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
            }), cancellationToken);
        using var downloader = new BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader();
        var result = await downloader.EnsureInstalledAsync(
            temporaryLockPath, runtimeRoot, cancellationToken,
            Path.Combine(Path.GetTempPath(), "bgi-release-archive-cache"));
        Require(result.Success, "Locked runtime artifact install failed: " + string.Join("; ", result.Errors));
    }
    finally
    {
        File.Delete(temporaryLockPath);
    }
}

static OpenCvSharp.Mat BuildGroundTruthNavigationFrame(
    string runtimeRoot, OpenCvSharp.Rect minimapRect, OpenCvSharp.Point2f genshinPosition)
{
    using var coarseMap = OpenCvSharp.Cv2.ImRead(
        Path.Combine(runtimeRoot, "Assets", "Map", "Teyvat", "MapBack_3_color.webp"),
        OpenCvSharp.ImreadModes.Color);
    Require(!coarseMap.Empty(), "MapBack_3 fixture image did not decode.");
    const double layerLeft = 8.0;
    const double layerTop = -1016.0;
    var centerX = (int)Math.Round((layerLeft - genshinPosition.X) / 5.0);
    var centerY = (int)Math.Round((layerTop - genshinPosition.Y) / 5.0);
    var cropRect = new OpenCvSharp.Rect(centerX - 26, centerY - 26, 52, 52);
    using var coarsePatch = new OpenCvSharp.Mat(coarseMap, cropRect);
    using var patch = new OpenCvSharp.Mat();
    OpenCvSharp.Cv2.Resize(coarsePatch, patch, new OpenCvSharp.Size(156, 156),
        interpolation: OpenCvSharp.InterpolationFlags.Cubic);
    using var minimap = new OpenCvSharp.Mat(
        minimapRect.Height, minimapRect.Width, OpenCvSharp.MatType.CV_8UC3, OpenCvSharp.Scalar.Black);
    using (var center = new OpenCvSharp.Mat(minimap, new OpenCvSharp.Rect(28, 28, 156, 156)))
        patch.CopyTo(center);
    var frame = new OpenCvSharp.Mat(1080, 1920, OpenCvSharp.MatType.CV_8UC3, OpenCvSharp.Scalar.Black);
    using (var target = new OpenCvSharp.Mat(frame, minimapRect))
        minimap.CopyTo(target);
    return frame;
}

static OpenCvSharp.Mat BuildOrientationAlignedFrame(
    OpenCvSharp.Mat source, OpenCvSharp.Rect minimapRect, int targetOrientation)
{
    OpenCvSharp.Mat? bestFrame = null;
    var bestDifference = double.MaxValue;
    for (var rotation = -180; rotation < 180; rotation += 5)
    {
        using var candidate = source.Clone();
        using var sourceMinimap = new OpenCvSharp.Mat(source, minimapRect);
        using var targetMinimap = new OpenCvSharp.Mat(candidate, minimapRect);
        using var rotationMatrix = OpenCvSharp.Cv2.GetRotationMatrix2D(
            new OpenCvSharp.Point2f(sourceMinimap.Width / 2f, sourceMinimap.Height / 2f), rotation, 1d);
        OpenCvSharp.Cv2.WarpAffine(sourceMinimap, targetMinimap, rotationMatrix, sourceMinimap.Size(),
            OpenCvSharp.InterpolationFlags.Linear, OpenCvSharp.BorderTypes.Reflect101);
        using var orientationInput = new OpenCvSharp.Mat();
        OpenCvSharp.Cv2.CvtColor(candidate, orientationInput, OpenCvSharp.ColorConversionCodes.BGR2BGRA);
        var actual = BetterGenshinImpact.GameTask.Common.Map.CameraOrientation.Compute(orientationInput);
        var difference = Math.Abs((actual - targetOrientation + 540d) % 360d - 180d);
        if (difference >= bestDifference) continue;
        bestDifference = difference;
        bestFrame?.Dispose();
        bestFrame = candidate.Clone();
    }

    Require(bestFrame is not null && bestDifference < 5d,
        $"Unable to synthesize a coherent minimap orientation: target={targetOrientation}, diff={bestDifference:F2}.");
    return bestFrame!;
}

static OpenCvSharp.Mat BuildGroundTruthBigMapFrame(
    string runtimeRoot, string sourceRoot, double genshinX, double genshinY)
{
    using var fullMap = OpenCvSharp.Cv2.ImRead(
        Path.Combine(runtimeRoot, "Assets", "Map", "Teyvat", "Teyvat_0_256.png"),
        OpenCvSharp.ImreadModes.Color);
    Require(!fullMap.Empty(), "Teyvat_0_256 big-map fixture image did not decode.");
    var centerX = (int)Math.Round(4096 - genshinX / 4);
    var centerY = (int)Math.Round(2048 - genshinY / 4);
    var cropRect = new OpenCvSharp.Rect(centerX - 240, centerY - 135, 480, 270);
    Require(cropRect.X >= 0 && cropRect.Y >= 0 && cropRect.Right <= fullMap.Width &&
            cropRect.Bottom <= fullMap.Height,
        $"Big-map fixture crop {cropRect} is outside {fullMap.Size()}.");
    using var crop = new OpenCvSharp.Mat(fullMap, cropRect);
    var frame = new OpenCvSharp.Mat();
    OpenCvSharp.Cv2.Resize(crop, frame, new OpenCvSharp.Size(1920, 1080),
        interpolation: OpenCvSharp.InterpolationFlags.Cubic);
    using var scaleButton = OpenCvSharp.Cv2.ImRead(
        Path.Combine(sourceRoot, "QuickTeleport/Assets/1920x1080/MapScaleButton.png"),
        OpenCvSharp.ImreadModes.Color);
    Require(!scaleButton.Empty(), "MapScaleButton fixture image did not decode.");
    using (var target = new OpenCvSharp.Mat(frame,
               new OpenCvSharp.Rect(30, 456, scaleButton.Width, scaleButton.Height)))
        scaleButton.CopyTo(target);
    return frame;
}

static async Task WriteCaptureRingFrameAsync(string captureRingPath, OpenCvSharp.Mat bgrFrame, ulong frameId)
{
    using var bgraFrame = new OpenCvSharp.Mat();
    OpenCvSharp.Cv2.CvtColor(bgrFrame, bgraFrame, OpenCvSharp.ColorConversionCodes.BGR2BGRA);
    var stride = checked(bgraFrame.Width * 4);
    var capacity = checked((long)stride * bgraFrame.Height);
    var pixels = new byte[checked((int)capacity)];
    Marshal.Copy(bgraFrame.Data, pixels, 0, pixels.Length);
    await using var ring = new FileStream(captureRingPath, FileMode.Create, FileAccess.ReadWrite, FileShare.ReadWrite);
    ring.SetLength(128 + 2 * capacity);
    using var writer = new BinaryWriter(ring, System.Text.Encoding.UTF8, leaveOpen: true);
    writer.Write(System.Text.Encoding.ASCII.GetBytes("BGIRING1"));
    writer.Write(1u); writer.Write(2u); writer.Write((ulong)capacity);
    writer.Write(0u); writer.Write((uint)bgraFrame.Width); writer.Write((uint)bgraFrame.Height); writer.Write((uint)stride);
    writer.Write(0x42475241u); writer.Write(0u); writer.Write((ulong)pixels.Length); writer.Write(frameId);
    writer.Write(0); writer.Write(0); writer.Write(2u); writer.Write(1u); writer.Write(2UL);
    ring.Position = 128;
    writer.Write(pixels);
}

sealed class VerificationOverlayDrawPlatform : IOverlayDrawPlatform
{
    public void SetRectangles(string name, Region source, IReadOnlyList<OpenCvSharp.Rect> rectangles) { }
    public void RemoveRectangles(string name) { }
    public void ClearAll() { }
}

sealed class VerificationTrigger(string name = "Verification Trigger", Action<CaptureContent>? onCapture = null) : ITaskTrigger
{
    public string Name { get; } = name;
    public bool IsEnabled { get; set; }
    public int Priority => 42;
    public bool IsExclusive => false;
    public void Init() { }
    public void OnCapture(CaptureContent content) => onCapture?.Invoke(content);
}

sealed class VerificationDispatcherRuntimePlatform(CancellationToken cancellationToken) : IDispatcherRuntimePlatform
{
    public CancellationToken GlobalCancellationToken { get; } = cancellationToken;
    public int AutoWoodRoundNum => 0;
    public int AutoWoodDailyMaxCount => 2000;
    public string AutoBossStrategyName => throw new CapabilityUnavailableException("AutoBoss");
    public DispatcherAutoEatSettings AutoEatSettings => throw new CapabilityUnavailableException("AutoEat");
    public int ClearCount { get; private set; }
    public List<string> AddedNames { get; } = [];
    public int FishingStartCount { get; private set; }
    public bool FishingCancelled { get; private set; }
    public int CookStartCount { get; private set; }
    public bool CookCancelled { get; private set; }
    public int FightStartCount { get; private set; }
    public bool FightCancelled { get; private set; }
    public int WoodStartCount { get; private set; }
    public bool WoodCancelled { get; private set; }
    public int? LastWoodRoundNum { get; private set; }
    public int? LastWoodDailyMaxCount { get; private set; }
    public int MusicStartCount { get; private set; }
    public bool MusicCancelled { get; private set; }
    public void ClearTriggers() => ClearCount++;
    public bool AddTrigger(string name, object? config)
    {
        AddedNames.Add(name);
        return true;
    }
    public bool GetTcgStrategy(out string content) =>
        throw new CapabilityUnavailableException("AutoGeniusInvokation");
    public bool GetFightStrategy(string? strategyName, out string path) =>
        throw new CapabilityUnavailableException("AutoDomain");
    public async Task<object?> ExecuteSoloTask(DispatcherSoloTaskRequest request,
        CancellationToken cancellationToken)
    {
        if (request is not (DispatcherFishingTaskRequest or DispatcherWoodTaskRequest or DispatcherFightTaskRequest or DispatcherCookTaskRequest or DispatcherMusicGameTaskRequest))
            throw new CapabilityUnavailableException(request.Name);
        if (request is DispatcherFishingTaskRequest) FishingStartCount++;
        else if (request is DispatcherWoodTaskRequest wood)
        {
            WoodStartCount++;
            LastWoodRoundNum = wood.RoundNum;
            LastWoodDailyMaxCount = wood.DailyMaxCount;
        }
        else if (request is DispatcherFightTaskRequest fight)
        {
            if (fight.Config is not null)
                throw new InvalidDataException("Solo AutoFight unexpectedly supplied script-group configuration.");
            FightStartCount++;
        }
        else if (request is DispatcherMusicGameTaskRequest) MusicStartCount++;
        else CookStartCount++;
        try
        {
            await Task.Delay(Timeout.Infinite, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            if (request is DispatcherFishingTaskRequest) FishingCancelled = true;
            else if (request is DispatcherWoodTaskRequest) WoodCancelled = true;
            else if (request is DispatcherFightTaskRequest) FightCancelled = true;
            else if (request is DispatcherMusicGameTaskRequest) MusicCancelled = true;
            else CookCancelled = true;
            throw;
        }
        return null;
    }
    public Task<object?> RunParameterizedTask(string name, object parameter,
        CancellationToken cancellationToken) => throw new CapabilityUnavailableException(name);
}

sealed class ForcedAvatarOcrFallbackCombatScenes(
    BetterGenshinImpact.Core.Recognition.ONNX.BgiYoloPredictor predictor,
    AutoFightAssets autoFightAssets,
    Microsoft.Extensions.Logging.ILogger logger,
    ISystemInfo systemInfo)
    : CombatScenes(predictor, autoFightAssets, logger, systemInfo)
{
    public override (string, string) ClassifyAvatarCnName(
        SixLabors.ImageSharp.Image<SixLabors.ImageSharp.PixelFormats.Rgb24> image,
        int index) => throw new InvalidOperationException($"forced classifier failure for avatar {index}");
}

sealed class HostVerificationSystemInfo : ISystemInfo
{
    public System.Drawing.Size DisplaySize { get; } = new(1920, 1080);
    public BetterGenshinImpact.Platform.Abstractions.BgiRect GameScreenSize { get; } = new(0, 0, 1920, 1080);
    public double AssetScale => 1;
    public double ZoomOutMax1080PRatio => 1;
    public double ScaleTo1080PRatio => 1;
    public BetterGenshinImpact.Platform.Abstractions.BgiRect CaptureAreaRect { get; set; } = new(0, 0, 1920, 1080);
    public BetterGenshinImpact.Platform.Abstractions.BgiRect ScaleMax1080PCaptureRect { get; set; } = new(0, 0, 1920, 1080);
    public System.Diagnostics.Process? GameProcess => null;
    public string GameProcessName => "Verification";
    public int GameProcessId => 1;
    public DesktopRegion DesktopRectArea { get; } = new(1920, 1080);
}
