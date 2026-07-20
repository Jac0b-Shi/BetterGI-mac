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
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.FarmingPlan;
using BetterGenshinImpact.GameTask.QuickTeleport;
using BetterGenshinImpact.GameTask.AutoEat;
using BetterGenshinImpact.GameTask.GameLoading;
using BetterGenshinImpact.Service;
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

var root = Path.Combine("/tmp", "bgi-" + Guid.NewGuid().ToString("N"));
var layout = new RuntimeLayout(root);
OverlayDrawPlatform.Configure(new VerificationOverlayDrawPlatform());
layout.EnsureCreated();
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
var socketPath = Path.Combine(layout.RunPath, "verification.sock");
var sessionToken = Convert.ToHexString(Guid.NewGuid().ToByteArray());
using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(15));
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
      "hotKeyConfig": { "quickTeleportTickHotkey": "F6" },
      "autoEatConfig": { "enabled": true, "eatInterval": 1234 }
    }
    """);
var server = new CoreRpcServer(socketPath, sessionToken, layout);
using var loggerFactory = LoggerFactory.Create(builder => builder.AddSimpleConsole());
var artifactInitializationCount = 0;
server.AttachRuntimeArtifactInitializer(() =>
{
    artifactInitializationCount++;
    return new RuntimeArtifactStatus(0, 30, "verification-source-lock.json");
});
var scriptHostServices = new MacScriptHostServices(
    loggerFactory, server.PlatformCallbacks, sessionToken, cancellation.Token);
scriptHostServices.SetJsNotificationEnabled(true);
scriptHostServices.SetServerTimeZoneOffset(TimeSpan.FromHours(8));
scriptHostServices.SetCurrentProject(new ScriptGroupProject(upstreamProject) { AllowJsNotification = true });
ScriptHostServices.Configure(scriptHostServices);
server.AttachScriptHostServices(scriptHostServices);
var scriptServicePlatform = new MacScriptServicePlatform(
    layout, loggerFactory.CreateLogger("BetterGenshinImpact.Service.ScriptService"), scriptHostServices,
    server.PlatformCallbacks, sessionToken, cancellation.Token, new SharedCaptureRingReader(layout),
    new MacGameTaskManagerPlatform(server.PlatformCallbacks, sessionToken, cancellation.Token, loggerFactory));
Require(scriptServicePlatform.FarmingPlanEnabled,
    "macOS scheduler ignored the upstream farming-plan configuration");
Require(scriptServicePlatform.RestartPolicy is
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
Require(!scriptServicePlatform.IsDailyFarmingLimitReached(farmingSession, out _),
    "shared FarmingStatsRecorder reported a configured cap before it was reached");
FarmingStatsRecorder.RecordFarmingSession(new FarmingSession
{
    AllowFarmingCount = true,
    EliteMobCount = 8,
    PrimaryTarget = "elite"
}, new FarmingRouteInfo { GroupName = "验证组", ProjectName = "补足上限", FolderName = "fixture" });
Require(scriptServicePlatform.IsDailyFarmingLimitReached(new FarmingSession
    {
        AllowFarmingCount = true,
        EliteMobCount = 1,
        PrimaryTarget = "elite"
    }, out var farmingLimitMessage) && farmingLimitMessage.Contains("精英超上限", StringComparison.Ordinal),
    "shared FarmingStatsRecorder did not enforce the upstream daily elite cap");
ScriptServicePlatform.Configure(scriptServicePlatform);
server.AttachScriptServicePlatform(scriptServicePlatform);
TaskRunnerPlatform.Configure(new MacTaskRunnerPlatform(
    server.PlatformCallbacks, sessionToken, cancellation.Token,
    loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.TaskRunner"),
    loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.RunnerContext")));
TaskControlPlatform.Configure(new MacTaskControlPlatform(
    server.PlatformCallbacks, sessionToken, cancellation.Token, new SharedCaptureRingReader(layout),
    loggerFactory.CreateLogger("BetterGenshinImpact.GameTask.Common.TaskControl")));
using var imageRegionOcrService = new MacImageRegionOcrService(
    layout, loggerFactory.CreateLogger<BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory>());
var pathExecutorPlatform = new MacPathExecutorPlatform(
    layout, imageRegionOcrService, server.PlatformCallbacks, sessionToken, cancellation.Token);
PathExecutorPlatform.Configure(pathExecutorPlatform);
PathExecutorAutoSkipPlatform.Configure(new MacPathExecutorAutoSkipPlatform());
server.AttachPathExecutorPlatform(pathExecutorPlatform);
var navigationPlatform = new MacNavigationPlatform(
    server.PlatformCallbacks, sessionToken, cancellation.Token);
NavigationPlatform.Configure(navigationPlatform);
var verificationInputBackend = new MacSemanticInputBackend(
    server.PlatformCallbacks, sessionToken, cancellation.Token);
var verificationAutoPickConfig = new BetterGenshinImpact.GameTask.AutoPick.AutoPickConfig();
var verificationAutoPickConfigProvider = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    verificationAutoPickConfig, BetterGenshinImpact.Core.Recognition.PaddleOcrModelConfig.V5Auto, "zh-Hans");
ScriptGroupExecutionServices.Configure(new MacScriptGroupExecutionServices(
    layout,
    new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(
        () => RunnerContext.Instance.AutoPickTriggerStopCount),
    verificationInputBackend,
    () => throw new InvalidOperationException("Verification did not request AutoPick system metrics."),
    verificationAutoPickConfigProvider,
    imageRegionOcrService.CreatePaddleAutoPickTextRecognizer(),
    imageRegionOcrService.CreateYapAutoPickTextRecognizer(layout)));
var shellPlatform = new MacShellTaskPlatform(server.PlatformCallbacks, sessionToken, cancellation.Token);
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
            initializedJson.Value<int>("runtimeArtifactsVerified") == 30 &&
            artifactInitializationCount == 1,
        "core.initialize did not apply the ScriptService platform configuration");

    await using var callbackConnection = await ConnectAsync(socketPath, cancellation.Token);
    await callbackConnection.WriteRequestAsync(
        new RpcRequest("attach", "platform.attach", null, sessionToken), cancellation.Token);
    var attachResponse = await callbackConnection.ReadResponseAsync(cancellation.Token);
    Require(attachResponse?.Error is null, attachResponse?.Error?.Message ?? "platform.attach failed");
    var gameLoadingPlatform = new MacGameLoadingRuntimePlatform(
        layout,
        () => throw new InvalidOperationException("GameLoading verification did not request screen metrics."),
        loggerFactory, server.PlatformCallbacks, sessionToken, cancellation.Token);
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
    var quickTeleportPlatform = new MacQuickTeleportRuntimePlatform(
        layout, server.PlatformCallbacks, sessionToken, cancellation.Token);
    QuickTeleportRuntimePlatform.Configure(quickTeleportPlatform);
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
        server.PlatformCallbacks, sessionToken, cancellation.Token, new SharedCaptureRingReader(layout));
    globalRuntime.KeyPress("VK_F");
    new BetterGenshinImpact.Core.Script.Dependence.Notification().Send("verification notification");
    await callbackResponder;

    var taskControlResponder = Task.Run(async () =>
    {
        var expected = new Queue<(string Method, string? Action, string? KeyType)>([
            ("input.dispatch", "gameAction", "keyDown"),
            ("window.activate", null, null),
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
        layout,
        () => throw new InvalidOperationException("Verification did not request AutoSkip system metrics."),
        loggerFactory, imageRegionOcrService,
        server.PlatformCallbacks, sessionToken, cancellation.Token);
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
    var focusResponder = Task.Run(async () =>
    {
        var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("Exit-and-relogin focus callback ended unexpectedly.");
        Require(callback.Method == "window.activate",
            "Exit-and-relogin did not request real game-window activation.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
    }, cancellation.Token);
    reloginPlatform.FocusGameWindow();
    await focusResponder;
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
    ScriptProjectHost.Configure(new MacScriptProjectHostInitializer());
    using (var hostSurfaceEngine = new V8ScriptEngine(
               V8ScriptEngineFlags.UseCaseInsensitiveMemberBinding |
               V8ScriptEngineFlags.EnableTaskPromiseConversion))
    {
        new MacScriptProjectHostInitializer().Initialize(
            hostSurfaceEngine, Path.Combine(layout.UserPath, "JsScript"), [], null);
        var missingHostNames = Convert.ToString(hostSurfaceEngine.Evaluate("""
            ["keyMouseScript", "pathingScript", "genshin", "dispatcher", "RecognitionObject", "DesktopRegion", "GameCaptureRegion", "ImageRegion", "Region",
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
        loggerFactory.CreateLogger("MacroVerification"));
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
    var shellActivationResponder = Task.Run(async () =>
    {
        var callback = await callbackConnection.ReadRequestAsync(cancellation.Token)
            ?? throw new EndOfStreamException("Shell completion did not request window activation.");
        Require(callback.Method == "window.activate", "Shell completion emitted an unexpected callback.");
        await callbackConnection.WriteResponseAsync(
            RpcResponse.Success(callback.Id, new { acknowledged = true }), cancellation.Token);
    }, cancellation.Token);
    await shellProject.Run();
    await shellActivationResponder;
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

    var sourceRoot = Path.Combine(Directory.GetCurrentDirectory(), "BetterGenshinImpact", "GameTask");
    foreach (var relativeAsset in new[]
    {
        "Common/Element/Assets/1920x1080/paimon_menu.png",
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
                    ringPath = captureRingPath, frameId = 8UL, sequence = 2UL, slot = 0,
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

    var missingGroup = await ExchangeAsync(connection, "3", "scheduler.run", sessionToken,
        JObject.FromObject(new { groupName = "missing-group" }), cancellation.Token);
    Require(missingGroup.Error?.Code == "FileNotFoundException", "scheduler.run did not validate the authoritative Core catalog");
    await connection.DisposeAsync();

    await using var rejectedConnection = await ConnectAsync(socketPath, cancellation.Token);
    var rejected = await ExchangeAsync(rejectedConnection, "4", "core.handshake", "wrong", null, cancellation.Token);
    Require(rejected.Error?.Code == "Unauthorized", "invalid session token was accepted");

    Console.WriteLine("Core Host verification passed: duplex RPC, framing, 0600, OpenCV, ClearScript, real ScriptProject, real zsh execution, authoritative catalog save, scheduler pause/resume boundary, auth.");
}
finally
{
    cancellation.Cancel();
    try { await serverTask; } catch (OperationCanceledException) { }
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

sealed class VerificationOverlayDrawPlatform : IOverlayDrawPlatform
{
    public void SetRectangles(string name, ImageRegion source, IReadOnlyList<OpenCvSharp.Rect> rectangles) { }
    public void RemoveRectangles(string name) { }
    public void ClearAll() { }
}

sealed class VerificationTrigger : ITaskTrigger
{
    public string Name => "Verification Trigger";
    public bool IsEnabled { get; set; }
    public int Priority => 42;
    public bool IsExclusive => false;
    public void Init() { }
    public void OnCapture(CaptureContent content) { }
}

sealed class VerificationDispatcherRuntimePlatform(CancellationToken cancellationToken) : IDispatcherRuntimePlatform
{
    public CancellationToken GlobalCancellationToken { get; } = cancellationToken;
    public int AutoWoodRoundNum => throw new CapabilityUnavailableException("AutoWood");
    public int AutoWoodDailyMaxCount => throw new CapabilityUnavailableException("AutoWood");
    public string AutoBossStrategyName => throw new CapabilityUnavailableException("AutoBoss");
    public DispatcherAutoEatSettings AutoEatSettings => throw new CapabilityUnavailableException("AutoEat");
    public int ClearCount { get; private set; }
    public List<string> AddedNames { get; } = [];
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
    public Task<object?> ExecuteSoloTask(DispatcherSoloTaskRequest request,
        CancellationToken cancellationToken) => throw new CapabilityUnavailableException(request.Name);
    public Task<object?> RunParameterizedTask(string name, object parameter,
        CancellationToken cancellationToken) => throw new CapabilityUnavailableException(name);
}
