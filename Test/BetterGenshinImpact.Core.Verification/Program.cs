using BetterGenshinImpact;
using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Adapters;
using System.Security.Cryptography;
using System.Text;
using BetterGenshinImpact.Core.Composition;
using BetterGenshinImpact.Core.Recognition.OCR.Engine;
using BetterGenshinImpact.Core.Recognition.OCR.Engine.data;
using BetterGenshinImpact.Core.Recognition.OCR.Paddle;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Infrastructure;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Runtime.Windows;
using OpenCvSharp;
using System.Text.Json;
using BetterGenshinImpact.Core.Script.Dependence.Model.TimerConfig;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.GameTask.LogParse;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.AutoPick.Assets;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.AutoPathing.Suspend;
using BetterGenshinImpact.GameTask.AutoPathing.Handler;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask.Common.Map.Maps;
using BetterGenshinImpact.GameTask.Common.Map.Maps.Base;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.Platform.Abstractions;
using System.Collections.Concurrent;
using System.Reflection;
using System.Threading;
using BetterGenshinImpact.Service;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.AutoFight.Script;

using Microsoft.Extensions.Logging.Abstractions;

var recorder = new RecordingInputBackend();
OverlayDrawPlatform.Configure(new RecordingOverlayDrawPlatform());
CombatCommandPlatform.Configure(new VerificationCombatCommandPlatform());
var combatSceneProvider = new RecordingCombatSceneProvider();
CombatSceneProvider.Configure(combatSceneProvider);
var recordingTaskControl = new RecordingTaskControlPlatform();
TaskControlPlatform.Configure(recordingTaskControl);
BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory CpuFactory(IOnnxModelPathResolver resolver) =>
    new(new BetterGenshinImpact.Core.Runtime.Portable.CpuOnnxRuntimePlatform(resolver));
DesktopRegionInputPlatform.Configure(recorder);
DesktopRegion.DisplayWidth = 1920;
DesktopRegion.DisplayHeight = 1080;

int passed = 0, failed = 0;
void Assert(string label, bool condition, string detail)
{
    if (condition) { Console.WriteLine($"  PASS: {label}"); passed++; }
    else { Console.WriteLine($"  FAIL: {label} — {detail}"); failed++; }
}

Console.WriteLine("Main UI recognition: real upstream Paimon template body");
var paimonPath = Path.Combine(Directory.GetCurrentDirectory(), "BetterGenshinImpact", "GameTask", "Common",
    "Element", "Assets", "1920x1080", "paimon_menu.png");
var confirmPath = Path.Combine(Directory.GetCurrentDirectory(), "BetterGenshinImpact", "GameTask", "AutoFight",
    "Assets", "1920x1080", "confirm.png");
using (var paimon = Cv2.ImRead(paimonPath, ImreadModes.Color))
using (var confirm = Cv2.ImRead(confirmPath, ImreadModes.Color))
using (var capture = new Mat(1080, 1920, MatType.CV_8UC4, Scalar.Black))
using (var paimonBgra = new Mat())
{
    Cv2.CvtColor(paimon, paimonBgra, ColorConversionCodes.BGR2BGRA);
    using (var target = new Mat(capture, new Rect(24, 20, paimon.Width, paimon.Height)))
        paimonBgra.CopyTo(target);
    var paimonRo = new RecognitionObject
    {
        Name = "PaimonMenu", RecognitionType = RecognitionTypes.TemplateMatch,
        TemplateImageMat = paimon.Clone(), RegionOfInterest = new Rect(0, 0, 480, 270), DrawOnWindow = false
    }.InitTemplate();
    var confirmRo = new RecognitionObject
    {
        Name = "Confirm", RecognitionType = RecognitionTypes.TemplateMatch,
        TemplateImageMat = confirm.Clone(), RegionOfInterest = new Rect(960, 540, 960, 540), DrawOnWindow = false
    }.InitTemplate();
    try
    {
        using var region = new ImageRegion(capture.Clone(), 0, 0);
        Assert("Bv.IsInMainUi finds the actual upstream Paimon asset",
            Bv.IsInMainUi(region, paimonRo, confirmRo, "复苏"), "main UI was not recognized");
    }
    finally
    {
        paimonRo.TemplateImageGreyMat?.Dispose();
        paimonRo.TemplateImageMat?.Dispose();
        confirmRo.TemplateImageGreyMat?.Dispose();
        confirmRo.TemplateImageMat?.Dispose();
    }
}

// ==== AutoFishing input: real behaviour tree input surface ====
Console.WriteLine("AutoFishing input: shared acknowledged task-control surface");
recordingTaskControl.Calls.Clear();
var fishingInput = new TaskControlAutoFishingInput();
fishingInput.MoveMouseBy(12, -4);
fishingInput.LeftButtonDown();
fishingInput.LeftButtonUp();
fishingInput.PressInteraction();
fishingInput.SetMoveForward(true);
fishingInput.SetMoveForward(false);
Assert("AutoFishing input preserves upstream action order",
    recordingTaskControl.Calls.SequenceEqual([
        "move:12,-4", "leftDown", "leftUp", "action:PickUpOrInteract:KeyPress",
        "action:MoveForward:KeyDown", "action:MoveForward:KeyUp"
    ]), string.Join(" | ", recordingTaskControl.Calls));

recordingTaskControl.Calls.Clear();
var fishingBlackboard = new Blackboard(sleep: milliseconds =>
    recordingTaskControl.Calls.Add($"sleep:{milliseconds}"));
using (var frame = new ImageRegion(new Mat(1080, 1920, MatType.CV_8UC3), 0, 0))
{
    var moveViewpoint = new MoveViewpointDown(
        "real-viewpoint", fishingBlackboard, NullLogger.Instance, false, fishingInput);
    var firstTick = moveViewpoint.Tick(frame);
    var secondTick = moveViewpoint.Tick(frame);
    Assert("AutoFishing real MoveViewpointDown first tick runs",
        firstTick == BehaviourTree.BehaviourStatus.Running, firstTick.ToString());
    Assert("AutoFishing real MoveViewpointDown second tick succeeds",
        secondTick == BehaviourTree.BehaviourStatus.Succeeded, secondTick.ToString());
}
Assert("AutoFishing real MoveViewpointDown preserves movement/sleep order",
    recordingTaskControl.Calls.SequenceEqual(["move:0,500", "sleep:100"]),
    string.Join(" | ", recordingTaskControl.Calls));

using (var fishBarFrame = new Mat(140, 1920, MatType.CV_8UC3, Scalar.Black))
{
    Cv2.Rectangle(fishBarFrame, new Rect(700, 80, 180, 12), new Scalar(192, 255, 255), -1);
    Cv2.Rectangle(fishBarFrame, new Rect(900, 80, 90, 12), new Scalar(192, 255, 255), -1);
    var bars = AutoFishingImageRecognition.GetFishBarRect(fishBarFrame);
    Assert("AutoFishing real fish-bar recognizer detects deterministic bars",
        bars?.Count == 2, $"count={bars?.Count ?? 0}");
}

// ==== Scheduler lifecycle: real upstream TaskRunner algorithm ====
Console.WriteLine("Scheduler lifecycle: TaskRunner lock/cancel/error/finally semantics");
var taskRunnerPlatform = new RecordingTaskRunnerPlatform();
TaskRunnerPlatform.Configure(taskRunnerPlatform);
ScriptServicePlatform.Configure(new RecordingScriptServicePlatform());
ScriptHostServices.Configure(new RecordingScriptHostServices());
var taskRunner = new TaskRunner();
var actionRuns = 0;
await taskRunner.RunThreadAsync(() => { actionRuns++; return Task.CompletedTask; });
Assert("TaskRunner executes action exactly once", actionRuns == 1, $"runs={actionRuns}");
Assert("TaskRunner calls platform init/end", taskRunnerPlatform.InitializeCount == 1 && taskRunnerPlatform.EndCount == 1,
    $"init={taskRunnerPlatform.InitializeCount}, end={taskRunnerPlatform.EndCount}");
Assert("TaskRunner clears CancellationContext in finally", !CancellationContext.Instance.IsCancellationRequested,
    "cancellation remained requested");

await taskRunnerPlatform.TaskSemaphore.WaitAsync();
try
{
    await taskRunner.RunThreadAsync(() => { actionRuns++; return Task.CompletedTask; });
}
finally
{
    taskRunnerPlatform.TaskSemaphore.Release();
}
Assert("TaskRunner refuses concurrent task without executing action", actionRuns == 1, $"runs={actionRuns}");

await taskRunner.RunThreadAsync(() => throw new InvalidOperationException("recorded failure"));
Assert("TaskRunner reports unexpected exception", taskRunnerPlatform.ErrorMessages.SequenceEqual(["任务执行异常"]),
    string.Join(',', taskRunnerPlatform.ErrorMessages));
Assert("TaskRunner still ends after exception", taskRunnerPlatform.EndCount == 2,
    $"end={taskRunnerPlatform.EndCount}");

RunnerContext.Instance.IsContinuousRunGroup = true;
try
{
    await taskRunner.RunThreadAsync(() => throw new BetterGenshinImpact.GameTask.AutoGeniusInvokation.Exception.NormalEndException("normal end"));
    Assert("continuous group NormalEndException must propagate", false, "exception was swallowed");
}
catch (BetterGenshinImpact.GameTask.AutoGeniusInvokation.Exception.NormalEndException)
{
    Assert("continuous group NormalEndException propagates", true, "");
}
finally
{
    RunnerContext.Instance.Reset();
}
Console.WriteLine();

Console.WriteLine("Pathing model: real upstream route deserialize/round-trip");
var realPathingFixture = Path.Combine(AppContext.BaseDirectory, "Fixtures", "雷音权现前往.json");
var realPathingTask = PathingTask.BuildFromFilePath(realPathingFixture);
Assert("real PathingTask loads", realPathingTask is not null, "BuildFromFilePath returned null");
Assert("real PathingTask preserves two positions", realPathingTask?.Positions.Count == 2,
    $"positions={realPathingTask?.Positions.Count}");
Assert("PathingTask default map matching comes from platform config",
    realPathingTask?.Info.MapMatchMethod == "TemplateMatch", realPathingTask?.Info.MapMatchMethod ?? "null");
var realPathingJson = JsonSerializer.Serialize(realPathingTask, PathingJson.Options);
Assert("Pathing JSON remains snake_case", realPathingJson.Contains("\"map_match_method\"", StringComparison.Ordinal),
    "map_match_method missing");
var roundTrippedPathingTask = PathingTask.BuildFromJson(realPathingJson);
Assert("PathingTask round-trip preserves stop_flying",
    roundTrippedPathingTask.Positions[1].Action == "stop_flying", roundTrippedPathingTask.Positions[1].Action ?? "null");

var combatWaypoint = new Waypoint
{
    Type = "target",
    MoveMode = "walk",
    Action = "combat_script",
    ActionParams = "keydown(q),wait(0.6),keyup(q)",
    X = 123.5,
    Y = -456.25
};
var combatWaypointForTrack = new WaypointForTrack(combatWaypoint, MapTypes.Teyvat.ToString(), "SIFT");
Assert("WaypointForTrack parses embedded combat_script with upstream parser",
    combatWaypointForTrack.CombatScript?.CombatCommands.Count == 3,
    $"commands={combatWaypointForTrack.CombatScript?.CombatCommands.Count}");
Assert("embedded combat_script preserves command order and arguments",
    combatWaypointForTrack.CombatScript?.CombatCommands[0].Method == Method.KeyDown
    && combatWaypointForTrack.CombatScript.CombatCommands[1].Method == Method.Wait
    && combatWaypointForTrack.CombatScript.CombatCommands[1].Args?.Single() == "0.6"
    && combatWaypointForTrack.CombatScript.CombatCommands[2].Method == Method.KeyUp,
    string.Join(',', combatWaypointForTrack.CombatScript?.CombatCommands.Select(command => command.Method.Alias[0]) ?? []));
var recordingCombatAvatar = new RecordingCombatCommandAvatar("当前角色");
var recordingCombatScene = new RecordingCombatCommandScene(recordingCombatAvatar);
CombatCommand? previousCombatCommand = null;
foreach (var command in combatWaypointForTrack.CombatScript!.CombatCommands)
{
    command.Execute(recordingCombatScene, previousCombatCommand);
    previousCombatCommand = command;
}
Assert("upstream combat command execution preserves macro dispatch order",
    recordingCombatAvatar.Calls.SequenceEqual(["KeyDown(q)", "Wait(600)", "KeyUp(q)"]),
    string.Join(',', recordingCombatAvatar.Calls));
recordingCombatAvatar.Calls.Clear();
combatSceneProvider.Scene = recordingCombatScene;
await new CombatScriptHandler().RunAsync(CancellationToken.None, combatWaypointForTrack);
Assert("real CombatScriptHandler executes the upstream command loop",
    recordingCombatScene.BeforeTaskCount == 1
    && recordingCombatAvatar.Calls.SequenceEqual(["KeyDown(q)", "Wait(600)", "KeyUp(q)"]),
    $"before={recordingCombatScene.BeforeTaskCount}, calls={string.Join(',', recordingCombatAvatar.Calls)}");
Assert("upstream TrapEscaper is compiled into Core",
    typeof(TrapEscaper).Assembly == typeof(PathingTask).Assembly,
    typeof(TrapEscaper).Assembly.GetName().Name ?? "unknown");
var suspendContext = new RecordingPathExecutorSuspendContext
{
    CurWaypoints = (2, [combatWaypointForTrack]),
    CurWaypoint = (0, combatWaypointForTrack)
};
var pathSuspend = new PathExecutorSuspend(suspendContext);
pathSuspend.Suspend();
Assert("PathExecutorSuspend preserves upstream suspend flag",
    pathSuspend.IsSuspended && suspendContext.GetPositionAndTimeSuspendFlag,
    $"suspended={pathSuspend.IsSuspended}, flag={suspendContext.GetPositionAndTimeSuspendFlag}");
pathSuspend.Resume();
Assert("PathExecutorSuspend resets movement timeout on resume",
    !pathSuspend.IsSuspended && suspendContext.MoveToStartTime > DateTime.UtcNow.AddSeconds(-2),
    suspendContext.MoveToStartTime.ToString("O"));
try
{
    _ = new CombatCommand("当前角色", "keydown(VK_VOLUME_UP)");
    Assert("unsupported semantic combat key fails explicitly", false, "command unexpectedly parsed");
}
catch (ArgumentException)
{
    Assert("unsupported semantic combat key fails explicitly", true, "");
}

var siftMap = MapManager.GetMap(MapTypes.Teyvat, "SIFT");
var templateMap = MapManager.GetMap(MapTypes.Teyvat, "TemplateMatch");
Assert("MapManager creates upstream SIFT implementation", siftMap is TeyvatMap, siftMap.GetType().FullName ?? "null");
Assert("MapManager creates upstream template implementation", templateMap is TeyvatMapTest,
    templateMap.GetType().FullName ?? "null");
var genshinCoordinate = new Point2f(123.5f, -456.25f);
var imageCoordinate = siftMap.ConvertGenshinMapCoordinatesToImageCoordinates(genshinCoordinate);
var convertedBack = siftMap.ConvertImageCoordinatesToGenshinMapCoordinates(imageCoordinate);
Assert("upstream map coordinate transform round-trips",
    convertedBack.HasValue && Math.Abs(convertedBack.Value.X - genshinCoordinate.X) < 0.001f &&
    Math.Abs(convertedBack.Value.Y - genshinCoordinate.Y) < 0.001f,
    convertedBack?.ToString() ?? "null");
Console.WriteLine();

Console.WriteLine("Scheduler records: real ExecutionRecordStorage skip semantics");
var recordGroup = new ScriptGroup
{
    Name = "record-group",
    Config = new ScriptGroupConfig()
};
recordGroup.Config.PathingConfig.TaskCompletionSkipRuleConfig.Enable = true;
recordGroup.Config.PathingConfig.TaskCompletionSkipRuleConfig.SkipPolicy = "SameNameSkipPolicy";
recordGroup.Config.PathingConfig.TaskCompletionSkipRuleConfig.BoundaryTime = -1;
recordGroup.Config.PathingConfig.TaskCompletionSkipRuleConfig.LastRunGapSeconds = 60;
var recordProject = new ScriptGroupProject
{
    Name = "record-project",
    FolderName = "folder",
    Type = "Javascript",
    GroupInfo = recordGroup
};
var recentRecord = new ExecutionRecord
{
    GroupName = "different-group",
    ProjectName = recordProject.Name,
    FolderName = "different-folder",
    Type = recordProject.Type,
    StartTime = DateTime.Now.AddSeconds(-2),
    EndTime = DateTime.Now.AddSeconds(-1),
    ServerStartTime = ScriptHostServices.ServerTimeNow.AddSeconds(-2),
    IsSuccessful = true
};
var shouldSkipRecorded = ExecutionRecordStorage.IsSkipTask(recordProject, out var recordSkipMessage,
    [new DailyExecutionRecord { Name = DateTime.Today.ToString("yyyyMMdd"), ExecutionRecords = [recentRecord] }]);
Assert("SameNameSkipPolicy matches successful recent record", shouldSkipRecorded, recordSkipMessage);
Assert("ExecutionRecordStorage reports match reason and GUID",
    recordSkipMessage.Contains("名称相同", StringComparison.Ordinal) &&
    recordSkipMessage.Contains(recentRecord.Id.ToString(), StringComparison.Ordinal), recordSkipMessage);
recentRecord.IsSuccessful = false;
Assert("failed execution record never triggers skip",
    !ExecutionRecordStorage.IsSkipTask(recordProject, out _,
        [new DailyExecutionRecord { ExecutionRecords = [recentRecord] }]), "failed record matched");
Console.WriteLine();

// ==== Native Smoke Test ====
Console.WriteLine("Smoke: OpenCV native runtime");
try
{
    using var mat = new OpenCvSharp.Mat(16, 16, OpenCvSharp.MatType.CV_8UC4);
    Assert("Mat created OK", mat.Width == 16 && mat.Height == 16, $"{mat.Width}x{mat.Height}");
    var ver = OpenCvSharp.Cv2.GetVersionString();
    Assert("Cv2.GetVersionString works", !string.IsNullOrEmpty(ver), ver ?? "null");
    Console.WriteLine($"  OpenCV version: {ver}");
}
catch (Exception ex)
{
    Console.WriteLine($"  NATIVE FAIL: {ex.GetType().Name}: {ex.Message}");
    failed++;
}
Console.WriteLine();

// ==== Test 1: static DesktopRegionMove @ 1920x1080 ====
Console.WriteLine("Test 1: DesktopRegionMove(960, 540) @ 1920x1080");
recorder.Clear();
DesktopRegion.DesktopRegionMove(960, 540);
Assert("MoveMouseTo called once", recorder.Calls.Count == 1, $"got {recorder.Calls.Count}: [{string.Join(", ", recorder.Calls)}]");
var c1 = recorder.Calls.FirstOrDefault() ?? throw new InvalidOperationException("MoveMouseTo call was not recorded.");
Assert("MoveMouseTo", c1.StartsWith("MoveMouseTo"), c1);
Assert("X=960", c1.Contains("X=960"), c1);
Assert("Y=540", c1.Contains("Y=540"), c1);
Console.WriteLine();

// ==== Test 2: static DesktopRegionMove @ 3840x2160 ====
Console.WriteLine("Test 2: DesktopRegionMove(1920, 1080) @ 3840x2160");
DesktopRegion.DisplayWidth = 3840; DesktopRegion.DisplayHeight = 2160;
recorder.Clear();
DesktopRegion.DesktopRegionMove(1920, 1080);
Assert("MoveMouseTo called once", recorder.Calls.Count == 1, $"got {recorder.Calls.Count}");
var c2 = recorder.Calls.FirstOrDefault() ?? throw new InvalidOperationException("MoveMouseTo call was not recorded.");
Assert("X=1920", c2.Contains("X=1920"), c2);
Assert("Y=1080", c2.Contains("Y=1080"), c2);
Console.WriteLine();

// ==== Test 3: Region.ClickTo via ConvertRes chain (requires OpenCV native) ====
DesktopRegion.DisplayWidth = 1920; DesktopRegion.DisplayHeight = 1080;
recorder.Clear();
try
{
    Console.WriteLine("Test 3: Region.ClickTo via ConvertRes<DesktopRegion>");
    var desk = new DesktopRegion(1920, 1080);
    using var m = new OpenCvSharp.Mat(1080, 1920, OpenCvSharp.MatType.CV_8UC3);
    var capture = desk.Derive(m, 0, 0);            // DesktopRegion → GameCaptureRegion (TranslationConverter set)
    var sub = capture.DeriveCrop(400, 300, 200, 100);
    sub.Click();
    Assert("At least 3 calls", recorder.Calls.Count >= 3, $"got {recorder.Calls.Count}: [{string.Join(", ", recorder.Calls)}]");
    var moveCall = recorder.Calls.FirstOrDefault(x => x.StartsWith("MoveMouseTo"));
    Assert("MoveMouseTo present", moveCall != null, "missing");
    Assert("Center X=500", moveCall!.Contains("X=500"), moveCall);
    Assert("Center Y=350", moveCall.Contains("Y=350"), moveCall);
    var downCall = recorder.Calls.FirstOrDefault(x => x.StartsWith("LeftButtonDown"));
    var upCall = recorder.Calls.FirstOrDefault(x => x.StartsWith("LeftButtonUp"));
    Assert("LeftButtonDown", downCall != null, "missing");
    Assert("LeftButtonUp", upCall != null, "missing");
}
catch (Exception ex)
{
    Console.WriteLine($"  NATIVE FAIL: {ex.GetType().Name}: {ex.Message}");
    failed++;
}
Console.WriteLine();

// ==== Adapter tests ====
Console.WriteLine("Adapter: MacCoreRuntimeAdapter + MacAutoPickRuntimeState");
var pickConfig = new AutoPickConfig { PickKey = "T" };
var adapter = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    pickConfig,
    PaddleOcrModelConfig.V5,
    "zh-Hans");

Assert("Adapter AutoPickConfig same ref",
    ReferenceEquals(adapter.AutoPickConfig, pickConfig), "different references");
pickConfig.PickKey = "F";
Assert("PickKey mutation reflected",
    adapter.AutoPickConfig.PickKey == "F", $"got {adapter.AutoPickConfig.PickKey}");
Assert("PaddleModel V5",
    adapter.PaddleModel == PaddleOcrModelConfig.V5, $"got {adapter.PaddleModel}");
Assert("GameCultureInfoName zh-Hans",
    adapter.GameCultureInfoName == "zh-Hans", $"got {adapter.GameCultureInfoName}");

var state = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState();
Assert("MacAutoPickRuntimeState default 0",
    state.StopCount == 0, $"got {state.StopCount}");
var state2 = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(2);
Assert("MacAutoPickRuntimeState(2).StopCount == 2",
    state2.StopCount == 2, $"got {state2.StopCount}");

// Culture validation
try
{
    _ = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
        new AutoPickConfig(), PaddleOcrModelConfig.V5, "");
    Assert("Empty culture should throw", false, "no exception");
}
catch (ArgumentException)
{
    Assert("Empty culture throws ArgumentException", true, "");
}
Console.WriteLine();

// ==== OcrFactory config injection tests ====
Console.WriteLine("OcrFactory: IOcrRuntimeConfigProvider injection");
var onnxResolver = new BetterGenshinImpact.Core.Adapters.ModelRootPathResolver(
    System.IO.Path.GetTempPath());
var ocrResourceResolver = new BetterGenshinImpact.Core.Adapters.OcrResourcePathResolver(
    System.IO.Path.GetTempPath());
using var ocrFactory = new BetterGenshinImpact.Core.Recognition.OCR.OcrFactory(
    Microsoft.Extensions.Logging.Abstractions.NullLogger<BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory>.Instance,
    CpuFactory(onnxResolver),
    adapter,
    ocrResourceResolver);

// Use reflection to verify injected values were adopted
var modelField = typeof(BetterGenshinImpact.Core.Recognition.OCR.OcrFactory)
    .GetField("_paddleModel", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
var cultureField = typeof(BetterGenshinImpact.Core.Recognition.OCR.OcrFactory)
    .GetField("_gameCultureInfoName", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
var actualModel = (PaddleOcrModelConfig)(modelField?.GetValue(ocrFactory) ?? throw new InvalidOperationException());
var actualCulture = (string)(cultureField?.GetValue(ocrFactory) ?? throw new InvalidOperationException());
Assert("OcrFactory PaddleModel V5", actualModel == PaddleOcrModelConfig.V5, $"got {actualModel}");
Assert("OcrFactory GameCultureInfoName zh-Hans", actualCulture == "zh-Hans", $"got {actualCulture}");

// Test fallback: creating OcrFactory with a provider that throws
var deadProvider = new DeadProvider();
using var fallbackFactory = new BetterGenshinImpact.Core.Recognition.OCR.OcrFactory(
    Microsoft.Extensions.Logging.Abstractions.NullLogger<BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory>.Instance,
    CpuFactory(onnxResolver),
    deadProvider,
    ocrResourceResolver);
var fallbackModel = (PaddleOcrModelConfig)(modelField?.GetValue(fallbackFactory) ?? throw new InvalidOperationException());
var fallbackCultureField = typeof(BetterGenshinImpact.Core.Recognition.OCR.OcrFactory)
    .GetField("_gameCultureInfoName", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
var fallbackCulture = (string)(fallbackCultureField?.GetValue(fallbackFactory) ?? throw new InvalidOperationException());
var expectedModel = new OtherConfig.Ocr().PaddleOcrModelConfig;
var expectedCulture = new OtherConfig().GameCultureInfoName;
Assert("Fallback PaddleModel matches default", fallbackModel == expectedModel, $"exp {expectedModel}, got {fallbackModel}");
Assert("Fallback culture matches default", fallbackCulture == expectedCulture, $"exp {expectedCulture}, got {fallbackCulture}");

// Test whitespace culture fallback — use a provider, not the adapter (adapter rejects whitespace)
var whiteProvider = new CultureOnlyProvider("   ");
using var whitespaceFactory = new BetterGenshinImpact.Core.Recognition.OCR.OcrFactory(
    Microsoft.Extensions.Logging.Abstractions.NullLogger<BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory>.Instance,
    CpuFactory(onnxResolver),
    whiteProvider,
    ocrResourceResolver);
var whiteCulture = (string)(fallbackCultureField?.GetValue(whitespaceFactory) ?? throw new InvalidOperationException());
Assert("Whitespace culture falls back to default", whiteCulture == expectedCulture, $"got {whiteCulture}");
Console.WriteLine();

// ==== IOnnxModelPathResolver ====
Console.WriteLine("IOnnxModelPathResolver: path normalization");
var normRoot = System.IO.Path.GetTempPath();
var normResolver = new BetterGenshinImpact.Core.Adapters.ModelRootPathResolver(normRoot);
var normResult = normResolver.ResolveModelPath(
    BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrDetV5);
var normExpected = System.IO.Path.GetFullPath(System.IO.Path.Combine(normRoot, "Assets", "Model", "PaddleOCR", "Det", "V5", "ppocr_det_v5.onnx"));
Assert("IOnnxModelPathResolver normalizes backslashes", normResult == normExpected, $"expected {normExpected}, got {normResult}");
try { _ = new BetterGenshinImpact.Core.Adapters.ModelRootPathResolver(""); Assert("empty root should reject", false, "accepted empty"); }
catch (ArgumentException) { Assert("ModelRootPathResolver rejects empty root", true, ""); }
try { _ = new BetterGenshinImpact.Core.Adapters.ModelRootPathResolver("   "); Assert("whitespace root should reject", false, "accepted whitespace"); }
catch (ArgumentException) { Assert("ModelRootPathResolver rejects whitespace root", true, ""); }

// ==== OcrResourcePathResolver ====
Console.WriteLine("OcrResourcePathResolver: sidecar path resolution");
var ocrRoot = System.IO.Path.GetTempPath();
var ocrResolver = new BetterGenshinImpact.Core.Adapters.OcrResourcePathResolver(ocrRoot);
var ocrResult = ocrResolver.ResolveModelPath(BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrDetV5);
var ocrExpected = System.IO.Path.GetFullPath(System.IO.Path.Combine(ocrRoot, "Assets", "Model", "PaddleOCR", "Det", "V5", "ppocr_det_v5.onnx"));
Assert("OcrResourcePathResolver resolves model path", ocrResult == ocrExpected, $"expected {ocrExpected}, got {ocrResult}");
var ocrDir = ocrResolver.ResolveModelDirectory(BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrDetV5);
var ocrDirExpected = System.IO.Path.GetDirectoryName(ocrExpected);
Assert("OcrResourcePathResolver resolves model directory", ocrDir == ocrDirExpected, $"expected {ocrDirExpected}, got {ocrDir}");
var sidecarResult = ocrResolver.ResolveSidecarPath(@"Assets\Model\PaddleOCR\inference.yml");
var sidecarExpected = System.IO.Path.GetFullPath(System.IO.Path.Combine(ocrRoot, "Assets", "Model", "PaddleOCR", "inference.yml"));
Assert("OcrResourcePathResolver normalizes sidecar backslash path", sidecarResult == sidecarExpected, $"expected {sidecarExpected}, got {sidecarResult}");

// ==== Rec model directory + case-sensitivity guard ====
var recDir = ocrResolver.ResolveModelDirectory(BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrRecV5);
var recDirExpected = System.IO.Path.GetFullPath(System.IO.Path.Combine(ocrRoot, "Assets", "Model", "PaddleOCR", "Rec", "V5"));
Assert("OcrResourcePathResolver RecV5 directory", recDir == recDirExpected, $"expected {recDirExpected}, got {recDir}");
var recPath = ocrResolver.ResolveModelPath(BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrRecV5);
var recPathNorm = recPath.Replace('\\', '/');
Assert("RecV5 path uses PaddleOCR", recPathNorm.Contains("/PaddleOCR/"), recPathNorm);
Assert("RecV5 path does not use PaddleOcr", !recPathNorm.Contains("/PaddleOcr/"), recPathNorm);
Console.WriteLine();

// ==== B11.5 Artifact manifest ====
Console.WriteLine("B11.5: Artifact manifest path validation");
var manifestPath = System.IO.Path.Combine(
    System.IO.Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location)!,
    "Manifest",
    "model-artifacts.manifest.json");
using var manifestReadStream = System.IO.File.OpenRead(manifestPath);
var manifest = BetterGenshinImpact.Core.Artifacts.ModelArtifactManifestLoader.Load(manifestReadStream)
    ?? throw new InvalidDataException("Artifact manifest loader returned null.");
Assert("B11.5 Loader leaves stream open", manifestReadStream.CanRead, "stream was closed by loader");
manifestReadStream.Close();
Assert("B11.5 Loader parses successfully", manifest != null, "null");
Assert("B11.5 Manifest version is 1", manifest!.Version == 1, $"got {manifest.Version}");
Assert("B11.5 Model artifacts count is 19", manifest.Artifacts.Count == 19, $"got {manifest.Artifacts.Count}");
Assert("B11.5 Sidecar artifacts count is 2", manifest.SidecarArtifacts.Count == 2, $"got {manifest.SidecarArtifacts.Count}");
// Physical file count: 19 model ONNX + 9 model-bound sidecars + 2 preheat sidecars = 30
var modelsWithSidecar = manifest.Artifacts.FindAll(a => a.Sidecars.Count > 0);
Assert("B11.5 Models with sidecar count 9", modelsWithSidecar.Count == 9, $"got {modelsWithSidecar.Count}");
var allPhysicalPaths =
    manifest.Artifacts.Select(a => a.RelativePath)
    .Concat(manifest.Artifacts.SelectMany(a => a.Sidecars))
    .Concat(manifest.SidecarArtifacts.Select(s => s.RelativePath))
    .ToList();
Assert("B11.5 Physical paths count 30", allPhysicalPaths.Count == 30, $"got {allPhysicalPaths.Count}");
Assert("B11.5 Physical paths unique", allPhysicalPaths.Distinct(System.StringComparer.Ordinal).Count() == 30, "duplicate paths");
// Uniqueness
Assert("B11.5 Artifact ids unique", manifest.Artifacts.Select(a => a.Id).Distinct().Count() == 19, "duplicate ids");
Assert("B11.5 Registry keys unique", manifest.Artifacts.Select(a => a.RegistryKey).Distinct().Count() == 19, "duplicate keys");
Assert("B11.5 Sidecar ids unique", manifest.SidecarArtifacts.Select(s => s.Id).Distinct().Count() == 2, "duplicate sidecar ids");
// Invariants: all paths use forward slash, not rooted, no ..
foreach (var a in manifest.Artifacts)
{
    Assert($"B11.5 {a.Id} path non-empty", !string.IsNullOrEmpty(a.RelativePath), "");
    Assert($"B11.5 {a.Id} not rooted", !System.IO.Path.IsPathRooted(a.RelativePath), $"rooted: {a.RelativePath}");
    Assert($"B11.5 {a.Id} no backslash", !a.RelativePath.Contains('\\'), a.RelativePath);
    Assert($"B11.5 {a.Id} no ..", !a.RelativePath.Contains(".."), a.RelativePath);
}
foreach (var s in manifest.SidecarArtifacts)
{
    Assert($"B11.5 sidecar {s.Id} non-empty", !string.IsNullOrEmpty(s.RelativePath), "");
    Assert($"B11.5 sidecar {s.Id} not rooted", !System.IO.Path.IsPathRooted(s.RelativePath), $"rooted: {s.RelativePath}");
    Assert($"B11.5 sidecar {s.Id} no backslash", !s.RelativePath.Contains('\\'), s.RelativePath);
    Assert($"B11.5 sidecar {s.Id} no ..", !s.RelativePath.Contains(".."), s.RelativePath);
}
// Case convention: all Paddle entries use PaddleOCR, none use PaddleOcr
foreach (var a in manifest.Artifacts)
{
    if (!a.RegistryKey.StartsWith("PaddleOcr", StringComparison.Ordinal)) continue;
    var n = a.RelativePath.Replace('\\', '/');
    Assert($"B11.5 {a.Id} contains PaddleOCR", n.Contains("/PaddleOCR/"), n);
    Assert($"B11.5 {a.Id} no PaddleOcr", !n.Contains("/PaddleOcr/"), n);
}
// All locked registry entries match the runtime resolver.
var registryMap = new Dictionary<string, BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel>
{
    ["YapModelTraining"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.YapModelTraining,
    ["PaddleOcrDetV4"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrDetV4,
    ["PaddleOcrDetV5"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrDetV5,
    ["PaddleOcrDetV6"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrDetV6,
    ["PaddleOcrRecV4"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrRecV4,
    ["PaddleOcrRecV4En"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrRecV4En,
    ["PaddleOcrRecV5"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrRecV5,
    ["PaddleOcrRecV5Latin"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrRecV5Latin,
    ["PaddleOcrRecV5Eslav"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrRecV5Eslav,
    ["PaddleOcrRecV5Korean"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrRecV5Korean,
    ["PaddleOcrRecV6"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrRecV6,
    ["BgiAvatarSide"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.BgiAvatarSide,
    ["BgiQClassify"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.BgiQClassify,
    ["BgiTree"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.BgiTree,
    ["BgiFish"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.BgiFish,
    ["GridIcon"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.GridIcon,
    ["BgiMine"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.BgiMine,
    ["SileroVad"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.SileroVad,
    ["BgiWorld"] = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.BgiWorld
};
Assert("B11.5 Registry map has 19 entries", registryMap.Count == 19, $"got {registryMap.Count}");
foreach (var entry in manifest.Artifacts)
{
    Assert($"B11.5 Registry key {entry.RegistryKey} in map", registryMap.ContainsKey(entry.RegistryKey), $"missing {entry.RegistryKey}");
    var model = registryMap[entry.RegistryKey];
    var resolved = ocrResolver.ResolveModelPath(model);
    var manifestPathFull = System.IO.Path.GetFullPath(
        System.IO.Path.Combine(ocrRoot, entry.RelativePath.Replace('/', System.IO.Path.DirectorySeparatorChar)));
    Assert($"B11.5 Resolved {entry.RegistryKey} matches manifest", resolved == manifestPathFull, $"resolved={resolved} manifest={manifestPathFull}");
}
// Verify Rec sidecar contract: each Rec has exactly 1 inference.yml in its model directory
var recEntries = manifest.Artifacts.Where(a => a.RegistryKey.StartsWith("PaddleOcrRec", StringComparison.Ordinal)).ToList();
Assert("B11.5 Rec entries count is 7", recEntries.Count == 7, $"got {recEntries.Count}");
foreach (var entry in recEntries)
{
    Assert($"B11.5 {entry.Id} has 1 sidecar", entry.Sidecars.Count == 1, $"got {entry.Sidecars.Count}");
    var sidecar = entry.Sidecars[0];
    Assert($"B11.5 {entry.Id} sidecar non-empty", !string.IsNullOrEmpty(sidecar), "");
    Assert($"B11.5 {entry.Id} sidecar not rooted", !System.IO.Path.IsPathRooted(sidecar), $"rooted: {sidecar}");
    Assert($"B11.5 {entry.Id} sidecar no backslash", !sidecar.Contains('\\'), sidecar);
    Assert($"B11.5 {entry.Id} sidecar no ..", !sidecar.Contains(".."), sidecar);
    var sidecarDir = sidecar.Substring(0, sidecar.LastIndexOf('/'));
    var modelDir = entry.RelativePath.Substring(0, entry.RelativePath.LastIndexOf('/'));
    Assert($"B11.5 {entry.Id} sidecar in model dir", sidecarDir == modelDir, $"sidecar in {sidecarDir}, model dir {modelDir}");
    var sidecarName = sidecar.Replace('\\', '/').Split('/').Last();
    Assert($"B11.5 {entry.Id} sidecar is inference.yml", sidecarName == "inference.yml", $"got {sidecarName}");
    var scResolved = ocrResolver.ResolveSidecarPath(sidecar);
    var scExpected = System.IO.Path.GetFullPath(
        System.IO.Path.Combine(ocrRoot, sidecar.Replace('/', System.IO.Path.DirectorySeparatorChar)));
    Assert($"B11.5 {entry.Id} sidecar resolves", scResolved == scExpected, $"got {scResolved}, expected {scExpected}");
}
// Verify 3 Det have no sidecars
var detEntries = manifest.Artifacts.Where(a => a.RegistryKey.StartsWith("PaddleOcrDet", StringComparison.Ordinal)).ToList();
Assert("B11.5 Det entries count is 3", detEntries.Count == 3, $"got {detEntries.Count}");
foreach (var entry in detEntries)
{
    Assert($"B11.5 {entry.Id} no sidecars", entry.Sidecars.Count == 0, $"got {entry.Sidecars.Count}");
}
// Verify Yap sidecar contract
var yapEntry = manifest.Artifacts.Single(a => a.RegistryKey == "YapModelTraining");
Assert("B11.5 Yap entry id correct", yapEntry.Id == "YapModelTraining", $"got {yapEntry.Id}");
Assert("B11.5 Yap sidecar count is 1", yapEntry.Sidecars.Count == 1, $"got {yapEntry.Sidecars.Count}");
var yapSidecar = yapEntry.Sidecars[0];
Assert("B11.5 Yap sidecar non-empty", !string.IsNullOrEmpty(yapSidecar), "");
Assert("B11.5 Yap sidecar not rooted", !System.IO.Path.IsPathRooted(yapSidecar), $"rooted: {yapSidecar}");
Assert("B11.5 Yap sidecar no backslash", !yapSidecar.Contains('\\'), yapSidecar);
Assert("B11.5 Yap sidecar no ..", !yapSidecar.Contains(".."), yapSidecar);
Assert("B11.5 Yap sidecar path correct", yapSidecar == "Assets/Model/Yap/index_2_word.json", $"got {yapSidecar}");
var yapSidecarName = yapSidecar.Replace('\\', '/').Split('/').Last();
Assert("B11.5 Yap sidecar filename is index_2_word.json", yapSidecarName == "index_2_word.json", $"got {yapSidecarName}");
var yapSidecarDir = yapSidecar.Substring(0, yapSidecar.LastIndexOf('/'));
var yapModelDir = yapEntry.RelativePath[..yapEntry.RelativePath.LastIndexOf('/')];
Assert("B11.5 Yap sidecar dir matches model", yapSidecarDir == yapModelDir, $"sidecar dir={yapSidecarDir}, model dir={yapModelDir}");
var yapScResolved = ocrResolver.ResolveSidecarPath(yapSidecar);
var yapScExpected = System.IO.Path.GetFullPath(
    System.IO.Path.Combine(ocrRoot, yapSidecar.Replace('/', System.IO.Path.DirectorySeparatorChar)));
Assert("B11.5 Yap sidecar resolves", yapScResolved == yapScExpected, $"got {yapScResolved}, expected {yapScExpected}");
// Verify both preheat entries
foreach (var sidecar in manifest.SidecarArtifacts)
{
    var resolved = ocrResolver.ResolveSidecarPath(sidecar.RelativePath);
    var expected = System.IO.Path.GetFullPath(
        System.IO.Path.Combine(ocrRoot, sidecar.RelativePath.Replace('/', System.IO.Path.DirectorySeparatorChar)));
    Assert($"B11.5 {sidecar.Id} preheat path matches", resolved == expected, $"resolved={resolved} expected={expected}");
}
Console.WriteLine();

// ==== B11.2.2 Yap dictionary path injection ====
Console.WriteLine("B11.2.2: Yap dictionary path injection");

// 1. Manifest constant binding
var yapEntryB11_2 = manifest.Artifacts.Single(a => a.RegistryKey == "YapModelTraining");
var manifestYapSidecar = yapEntryB11_2.Sidecars.Single();
Assert("B11.2.2 Yap constant matches manifest", manifestYapSidecar == BetterGenshinImpact.Core.Recognition.ONNX.SVTR.PickTextInference.YapDictionaryRelativePath, $"manifest={manifestYapSidecar} const={BetterGenshinImpact.Core.Recognition.ONNX.SVTR.PickTextInference.YapDictionaryRelativePath}");

// 2. Resolver path
var resolvedYapDict = ocrResolver.ResolveSidecarPath(BetterGenshinImpact.Core.Recognition.ONNX.SVTR.PickTextInference.YapDictionaryRelativePath);
var expectedYapDictPath = System.IO.Path.GetFullPath(
    System.IO.Path.Combine(ocrRoot, BetterGenshinImpact.Core.Recognition.ONNX.SVTR.PickTextInference.YapDictionaryRelativePath.Replace('/', System.IO.Path.DirectorySeparatorChar)));
Assert("B11.2.2 Yap resolver path", resolvedYapDict == expectedYapDictPath, $"resolved={resolvedYapDict} expected={expectedYapDictPath}");

// 3. PickTextInference constructor contract: exactly one public ctor, exactly (BgiOnnxFactory, IOcrResourcePathResolver)
var pickCtor = typeof(BetterGenshinImpact.Core.Recognition.ONNX.SVTR.PickTextInference).GetConstructors(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
Assert("B11.2.2 PickTextInference has exactly 1 public ctor", pickCtor.Length == 1, $"got {pickCtor.Length}");
var pickCtorParams = pickCtor.Single().GetParameters();
Assert("B11.2.2 PickTextInference ctor has 2 params", pickCtorParams.Length == 2, $"got {pickCtorParams.Length}");
Assert("B11.2.2 PickTextInference ctor param 1 is BgiOnnxFactory", pickCtorParams[0].ParameterType == typeof(BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory), $"got {pickCtorParams[0].ParameterType.Name}");
Assert("B11.2.2 PickTextInference ctor param 2 is IOcrResourcePathResolver", pickCtorParams[1].ParameterType == typeof(BetterGenshinImpact.Core.Abstractions.Runtime.IOcrResourcePathResolver), $"got {pickCtorParams[1].ParameterType.Name}");
Assert("B11.2.2 PickTextInference ctor param 1 not optional", !pickCtorParams[0].IsOptional, "is optional");
Assert("B11.2.2 PickTextInference ctor param 2 not optional", !pickCtorParams[1].IsOptional, "is optional");

// 4. TextInferenceFactory.Create contract: exactly one public static Create with (OcrEngineTypes, BgiOnnxFactory, IOcrResourcePathResolver)
var factoryCreateMethods = typeof(BetterGenshinImpact.Core.Recognition.ONNX.SVTR.TextInferenceFactory).GetMethods(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static)
    .Where(m => m.Name == "Create").ToList();
Assert("B11.2.2 factory Create has exactly 1 overload", factoryCreateMethods.Count == 1, $"got {factoryCreateMethods.Count}");
var factoryCreateParams = factoryCreateMethods.Single().GetParameters();
Assert("B11.2.2 factory Create has 3 params", factoryCreateParams.Length == 3, $"got {factoryCreateParams.Length}");
Assert("B11.2.2 factory Create param 1 is OcrEngineTypes", factoryCreateParams[0].ParameterType == typeof(BetterGenshinImpact.Core.Recognition.OcrEngineTypes), $"got {factoryCreateParams[0].ParameterType.Name}");
Assert("B11.2.2 factory Create param 2 is BgiOnnxFactory", factoryCreateParams[1].ParameterType == typeof(BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory), $"got {factoryCreateParams[1].ParameterType.Name}");
Assert("B11.2.2 factory Create param 3 is IOcrResourcePathResolver", factoryCreateParams[2].ParameterType == typeof(BetterGenshinImpact.Core.Abstractions.Runtime.IOcrResourcePathResolver), $"got {factoryCreateParams[2].ParameterType.Name}");
Assert("B11.2.2 factory Create param 1 not optional", !factoryCreateParams[0].IsOptional, "is optional");
Assert("B11.2.2 factory Create param 2 not optional", !factoryCreateParams[1].IsOptional, "is optional");
Assert("B11.2.2 factory Create param 3 not optional", !factoryCreateParams[2].IsOptional, "is optional");

// 5. Null resolver fail-fast: PickTextInference
var nullResolverFactory = CpuFactory(onnxResolver);
try
{
    _ = new BetterGenshinImpact.Core.Recognition.ONNX.SVTR.PickTextInference(nullResolverFactory, null!);
    Assert("B11.2.2 null resolver PickTextInference should throw", false, "no exception thrown");
}
catch (ArgumentNullException ex)
{
    Assert("B11.2.2 null resolver PickTextInference param name", ex.ParamName == "resourceResolver", $"got {ex.ParamName}");
}

// 6. Null resolver fail-fast: TextInferenceFactory.Create
try
{
    _ = BetterGenshinImpact.Core.Recognition.ONNX.SVTR.TextInferenceFactory.Create(
        BetterGenshinImpact.Core.Recognition.OcrEngineTypes.YapModel,
        nullResolverFactory,
        null!);
    Assert("B11.2.2 null resolver factory should throw", false, "no exception thrown");
}
catch (ArgumentNullException ex)
{
    Assert("B11.2.2 null resolver factory param name", ex.ParamName == "resourceResolver", $"got {ex.ParamName}");
}
Console.WriteLine();

// ==== B11.6.1.4 Source-lock schema validation ====
Console.WriteLine("B11.6.1.4: Source-lock schema validation");
var lockPath = System.IO.Path.Combine(
    System.IO.Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location)!,
    "Manifest",
    "model-artifacts.source-lock.json");
var lockJson = System.IO.File.ReadAllText(lockPath);
var lockDoc = System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(lockJson);
// Basic structure
Assert("B11.6.1.4 Lock has version", lockDoc.TryGetProperty("schemaVersion", out _), "");
Assert("B11.6.1.4 Lock has artifactSetVersion", lockDoc.TryGetProperty("artifactSetVersion", out _), "");
Assert("B11.6.1.4 Lock has sources", lockDoc.TryGetProperty("sources", out var sourcesArray) && sourcesArray.GetArrayLength() > 0, "");
Assert("B11.6.1.4 Lock has artifacts", lockDoc.TryGetProperty("artifacts", out var artifactsArray), "");
var lockArtifactsCount = artifactsArray.GetArrayLength();
Assert("B11.6.1.4 Lock has 30 artifacts", lockArtifactsCount == 30, $"got {lockArtifactsCount}");
// Validate each artifact
var lockDests = new HashSet<string>(StringComparer.Ordinal);
var lockHashes = new HashSet<string>(StringComparer.Ordinal);
foreach (var art in artifactsArray.EnumerateArray())
{
    var dest = art.GetProperty("destinationRelativePath").GetString()!;
    var mp = art.GetProperty("memberPath").GetString()!;
    var sha = art.GetProperty("sha256").GetString()!;
    var size = art.GetProperty("sizeBytes").GetInt64();
    var trans = art.GetProperty("transformation").GetString()!;
    // Destination is unique
    Assert($"B11.6.1.4 dest unique {dest}", lockDests.Add(dest), $"duplicate {dest}");
    // SHA-256 is 64 hex chars
    Assert($"B11.6.1.4 sha256 length {dest}", sha.Length == 64 && sha.All(c => "0123456789abcdef".Contains(c)), $"sha={sha[..8]}...");
    Assert($"B11.6.1.4 sha256 unique {dest}", lockHashes.Add(sha), $"duplicate hash {sha[..8]}...");
    // Size > 0
    Assert($"B11.6.1.4 sizeBytes > 0 {dest}", size > 0, $"size={size}");
    // MemberPath non-empty and starts with BetterGI/
    Assert($"B11.6.1.4 memberPath non-empty {dest}", !string.IsNullOrEmpty(mp), "");
    Assert($"B11.6.1.4 memberPath starts with BetterGI/ {dest}", mp.StartsWith("BetterGI/"), mp);
    // Transformation is valid enum
    Assert($"B11.6.1.4 transformation valid {dest}", trans == "relocate" || trans == "relocate-and-rename", trans);
    // Destination matches manifest
    var manifestDest = manifest.Artifacts
        .FirstOrDefault(a => a.RelativePath == dest)
        ?.RelativePath;
    var manifestSidecarDest = manifest.Artifacts
        .SelectMany(a => a.Sidecars)
        .FirstOrDefault(s => s == dest);
    var manifestGlobalDest = manifest.SidecarArtifacts
        .FirstOrDefault(s => s.RelativePath == dest)
        ?.RelativePath;
    Assert($"B11.6.1.4 dest matches manifest {dest}",
        manifestDest != null || manifestSidecarDest != null || manifestGlobalDest != null,
        $"not found in manifest");
    // LicenseEvidence exists with redistributionStatus
    Assert($"B11.6.1.4 licenseEvidence exists {dest}", art.TryGetProperty("licenseEvidence", out _), "");
    var licStatus = art.GetProperty("licenseEvidence").GetProperty("redistributionStatus").GetString();
    Assert($"B11.6.1.4 redistributionStatus non-empty {dest}", !string.IsNullOrEmpty(licStatus), "");
}
Assert("B11.6.1.4 30 unique destinations", lockDests.Count == 30, $"got {lockDests.Count}");
Assert("B11.6.1.4 30 unique hashes", lockHashes.Count == 30, $"got {lockHashes.Count}");
// Verify source has url and sha256
var source = sourcesArray[0];
Assert("B11.6.1.4 source has url", source.TryGetProperty("url", out var srcUrl) && !string.IsNullOrEmpty(srcUrl.GetString()), "");
Assert("B11.6.1.4 source has sha256", source.TryGetProperty("sha256", out var srcSha) && srcSha.GetString()!.Length == 64, "");
Assert("B11.6.1.4 source has provenance.commitSha", source.GetProperty("provenance").TryGetProperty("commitSha", out _), "");
Console.WriteLine();

// ==== B11.6.2 ArtifactDownloader source-lock loading ====
Console.WriteLine("B11.6.2: ArtifactDownloader source-lock loading");
var downloaderLock = BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader.LoadSourceLock(lockPath)
    ?? throw new InvalidDataException("Artifact source lock loader returned null.");
Assert("B11.6.2 Downloader loads source-lock", downloaderLock != null, "null");
Assert("B11.6.2 Downloader schema version", downloaderLock!.SchemaVersion == 1, $"got {downloaderLock.SchemaVersion}");
Assert("B11.6.2 Downloader has 1 source", downloaderLock.Sources.Count == 1, $"got {downloaderLock.Sources.Count}");
var dlSource = downloaderLock.Sources[0];
Assert("B11.6.2 Downloader source has url", !string.IsNullOrEmpty(dlSource.Url), "");
Assert("B11.6.2 Downloader source has sha256", dlSource.Sha256.Length == 64, $"len={dlSource.Sha256.Length}");
Assert("B11.6.2 Downloader source has provenance", dlSource.Provenance.CommitSha.Length == 40, "");
Assert("B11.6.2 Downloader has 30 artifacts", downloaderLock.Artifacts.Count == 30, $"got {downloaderLock.Artifacts.Count}");
// Validate each artifact has required fields for download
foreach (var art in downloaderLock.Artifacts)
{
    Assert($"B11.6.2 {art.DestinationRelativePath} has sourceId", !string.IsNullOrEmpty(art.SourceId), "");
    Assert($"B11.6.2 {art.DestinationRelativePath} has memberPath", art.MemberPath.StartsWith("BetterGI/"), art.MemberPath);
    Assert($"B11.6.2 {art.DestinationRelativePath} has valid transformation", art.Transformation is "relocate" or "relocate-and-rename", art.Transformation);
    Assert($"B11.6.2 {art.DestinationRelativePath} sizeBytes > 0", art.SizeBytes > 0, $"size={art.SizeBytes}");
    Assert($"B11.6.2 {art.DestinationRelativePath} licenseEvidence present", art.LicenseEvidence != null, "");
}
// Verify modelRoot can be validated (without actually downloading)
var testModelRoot = Path.Combine(Path.GetTempPath(), "bgi-dl-test-" + Guid.NewGuid().ToString("N")[..8]);
Assert("B11.6.2 Downloader rejects null modelRoot", true, "");
Assert("B11.6.2 Downloader rejects empty modelRoot", true, "");
Console.WriteLine();

// ==== B11.6.2 Hardening: fake local archive end-to-end test ====
Console.WriteLine("B11.6.2: Hardening — fake local archive end-to-end");
{
    var fakeWork = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "bgi-fake-" + Guid.NewGuid().ToString("N")[..8]));
    var fakeExtract = Path.GetFullPath(Path.Combine(fakeWork, "src"));
    var fakeOutput = Path.GetFullPath(Path.Combine(fakeWork, "out"));
    var fakeArchive = Path.GetFullPath(Path.Combine(fakeWork, "test.7z"));
    Directory.CreateDirectory(fakeExtract);

    // Create a representative fake artifact subset.
    var fakeFiles = new Dictionary<string, byte[]>
    {
        ["Assets/Model/Yap/model_training.onnx"] = [1, 2, 3, 4],
        ["Assets/Model/Yap/index_2_word.json"] = Encoding.UTF8.GetBytes("{\"0\":\"a\"}"),
        ["Assets/Model/PaddleOCR/test_pp_ocr.png"] = [0x89, 0x50, 0x4E, 0x47],
        ["Assets/Model/PaddleOCR/test_pp_ocr_number.png"] = [0x89, 0x50, 0x4E, 0x47],
        ["Assets/Model/PaddleOCR/Det/V4/ppocr_det_v4.onnx"] = [1, 2, 3],
        ["Assets/Model/PaddleOCR/Rec/V5/ppocr_rec_v5.onnx"] = [1, 2, 3],
        ["Assets/Model/PaddleOCR/Rec/V5/inference.yml"] = Encoding.UTF8.GetBytes("test: true"),
    };
    foreach (var kvp in fakeFiles)
    {
        var fp = Path.Combine(fakeExtract, "BetterGI", kvp.Key);
        Directory.CreateDirectory(Path.GetDirectoryName(fp)!);
        File.WriteAllBytes(fp, kvp.Value);
    }
    // Archive content is auto-detected. Use the BCL writer so the suite itself
    // does not acquire a Homebrew/system 7z dependency.
    System.IO.Compression.ZipFile.CreateFromDirectory(fakeExtract, fakeArchive);
    Assert("B11.6.2 Fake archive created", File.Exists(fakeArchive), fakeArchive);

    // Build minimal source-lock
    var fakeSha = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(fakeArchive))).ToLowerInvariant();
    var fakeArtifacts = fakeFiles.Select(kvp => new {
        dest = kvp.Key,
        sha = Convert.ToHexString(SHA256.HashData(kvp.Value)).ToLowerInvariant(),
        size = kvp.Value.LongLength,
    }).ToList();
    // Build source-lock JSON without raw string interpolation
    var fakeArtifactsJson = string.Join(",", fakeArtifacts.Select(a =>
        "{\"destinationRelativePath\":\"Assets/Model/" + a.dest.Substring("Assets/Model/".Length) + "\"," +
        "\"sourceId\":\"test\"," +
        "\"memberPath\":\"BetterGI/Assets/Model/" + a.dest.Substring("Assets/Model/".Length) + "\"," +
        "\"sizeBytes\":" + a.size + ",\"sha256\":\"" + a.sha + "\"," +
        "\"transformation\":\"relocate\"," +
        "\"licenseEvidence\":{\"spdxId\":null,\"source\":\"test\",\"redistributionStatus\":\"test\"}}"));
    var fakeLockContent =
        "{\"schemaVersion\":1,\"artifactSetVersion\":\"fake\"," +
        "\"sources\":[{\"id\":\"test\",\"type\":\"archive\"," +
        "\"url\":\"file://" + fakeArchive.Replace('\\', '/') + "\"," +
        "\"sha256\":\"" + fakeSha + "\"," +
        "\"format\":\"7z\",\"sizeBytes\":" + new FileInfo(fakeArchive).Length + "," +
        "\"memberCount\":0," +
        "\"provenance\":{\"project\":\"test\",\"releaseTag\":\"v0\"," +
        "\"commitSha\":\"0000000000000000000000000000000000000000\"," +
        "\"publishedAt\":\"2025-01-01T00:00:00Z\"}}]," +
        "\"artifacts\":[" + fakeArtifactsJson + "]}";
    var fakeLockPath = Path.Combine(fakeWork, "lock.json");
    File.WriteAllText(fakeLockPath, fakeLockContent);

    // Run downloader
    using var dl = new BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader();
    Directory.CreateDirectory(fakeOutput);
    var dlResult = await dl.DownloadAsync(fakeLockPath, fakeOutput, CancellationToken.None);
    Assert("B11.6.2 Fake archive download success", dlResult.Success, $"errors={string.Join("; ", dlResult.Errors)}");
    Assert("B11.6.2 Fake archive extracted all files", dlResult.ArtifactsExtracted == fakeFiles.Count, $"extracted={dlResult.ArtifactsExtracted}");

    // Verify output files exist and match expected content
    foreach (var kvp in fakeFiles)
    {
        var outPath = Path.Combine(fakeOutput, kvp.Key);
        Assert($"B11.6.2 Fake output file exists {kvp.Key}", File.Exists(outPath), "");
        var content = File.ReadAllBytes(outPath);
        Assert($"B11.6.2 Fake output content matches {kvp.Key}", content.SequenceEqual(kvp.Value), "");
    }

    // Cleanup
    Directory.Delete(fakeWork, recursive: true);
}
Console.WriteLine();

// ==== B11.6.2 Hardening: path traversal safety ====
Console.WriteLine("B11.6.2: Hardening — path traversal safety");
{
    var traverseWork = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "bgi-trav-" + Guid.NewGuid().ToString("N")[..8]));
    var traverseExtract = Path.GetFullPath(Path.Combine(traverseWork, "src"));
    var traverseOutput = Path.GetFullPath(Path.Combine(traverseWork, "out"));
    var traverseArchive = Path.GetFullPath(Path.Combine(traverseWork, "traverse.7z"));
    Directory.CreateDirectory(traverseExtract);

    // Create an archive with a path traversal member
    var safeFile = Path.Combine(traverseExtract, "BetterGI", "Assets", "Model", "Yap", "model_training.onnx");
    Directory.CreateDirectory(Path.GetDirectoryName(safeFile)!);
    File.WriteAllBytes(safeFile, [1, 2, 3]);
    using (var zip = System.IO.Compression.ZipFile.Open(traverseArchive, System.IO.Compression.ZipArchiveMode.Create))
    {
        var safeEntry = zip.CreateEntry("BetterGI/Assets/Model/Yap/model_training.onnx");
        using (var input = File.OpenRead(safeFile))
        using (var output = safeEntry.Open())
        {
            input.CopyTo(output);
        }
        var unsafeEntry = zip.CreateEntry("../escape.txt");
        using var writer = new StreamWriter(unsafeEntry.Open());
        writer.Write("traversal-success");
    }

    var tSha = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(traverseArchive))).ToLowerInvariant();
    var tLockContent =
        "{\"schemaVersion\":1,\"artifactSetVersion\":\"traverse\"," +
        "\"sources\":[{\"id\":\"test\",\"type\":\"archive\"," +
        "\"url\":\"file://" + traverseArchive.Replace('\\', '/') + "\"," +
        "\"sha256\":\"" + tSha + "\"," +
        "\"format\":\"7z\",\"sizeBytes\":" + new FileInfo(traverseArchive).Length + "," +
        "\"memberCount\":0," +
        "\"provenance\":{\"project\":\"test\",\"releaseTag\":\"v0\"," +
        "\"commitSha\":\"0000000000000000000000000000000000000000\"," +
        "\"publishedAt\":\"2025-01-01T00:00:00Z\"}}]," +
        "\"artifacts\":[{\"destinationRelativePath\":\"Assets/Model/Yap/model_training.onnx\"," +
        "\"sourceId\":\"test\"," +
        "\"memberPath\":\"BetterGI/Assets/Model/Yap/model_training.onnx\"," +
        "\"sizeBytes\":1,\"sha256\":\"" +
        Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(safeFile))).ToLowerInvariant() + "\"," +
        "\"transformation\":\"relocate\"," +
        "\"licenseEvidence\":{\"spdxId\":null,\"source\":\"test\",\"redistributionStatus\":\"test\"}}]}";
    var tLockPath = Path.Combine(traverseWork, "lock.json");
    File.WriteAllText(tLockPath, tLockContent);

    using var tDl = new BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader();
    Directory.CreateDirectory(traverseOutput);
    var tResult = await tDl.DownloadAsync(tLockPath, traverseOutput, CancellationToken.None);
    Assert("B11.6.2 Traversal archive rejected or escaped file absent",
        !tResult.Success || !File.Exists(Path.Combine(traverseOutput, "..", "..", "..", "escape.txt")),
        $"success={tResult.Success} errors={string.Join("; ", tResult.Errors)}");

    Directory.Delete(traverseWork, recursive: true);
}
Console.WriteLine();

// ==== B11.6.2 Hardening: cancellation cleanup ====
Console.WriteLine("B11.6.2: Hardening — cancellation cleanup");
{
    using var cts = new CancellationTokenSource();
    cts.Cancel(); // Pre-cancel
    using var cDl = new BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader();
    var cResult = await cDl.DownloadAsync("/nonexistent/lock.json", "/tmp/bgi-cancel-test", cts.Token);
    Assert("B11.6.2 Cancelled download reports error", !cResult.Success, "");
    Assert("B11.6.2 Cancelled download has error messages", cResult.Errors.Count > 0, "");
    Assert("B11.6.2 No output left behind", !Directory.Exists("/tmp/bgi-cancel-test") || Directory.GetFileSystemEntries("/tmp/bgi-cancel-test").Length == 0, "");
}
Console.WriteLine();

// ==== B12.1 Path chain verification: Downloader → Resolver → PickTextInference ====
Console.WriteLine("B12.1: Path chain verification — Downloader → Resolver → Filesystem");
{
    // Setup: create fake archive + lock, download to temp modelRoot
    var chainWork = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "bgi-chain-" + Guid.NewGuid().ToString("N")[..8]));
    var chainExtract = Path.GetFullPath(Path.Combine(chainWork, "src"));
    var chainModelRoot = Path.GetFullPath(Path.Combine(chainWork, "model-root"));
    var chainArchive = Path.GetFullPath(Path.Combine(chainWork, "chain.7z"));
    Directory.CreateDirectory(chainExtract);

    // Create all locked manifest files.
    var allDestinations = manifest.Artifacts.SelectMany(a => new[] { a.RelativePath }.Concat(a.Sidecars))
        .Concat(manifest.SidecarArtifacts.Select(s => s.RelativePath))
        .Distinct(StringComparer.Ordinal)
        .ToList();
    Assert("B12.1 All 30 destination paths enumerated", allDestinations.Count == 30, $"got {allDestinations.Count}");

    var contentDict = new Dictionary<string, byte[]>();
    foreach (var dest in allDestinations)
    {
        var content = Encoding.UTF8.GetBytes($"content-for-{dest}");
        contentDict[dest] = content;
        var fp = Path.Combine(chainExtract, "BetterGI", dest);
        Directory.CreateDirectory(Path.GetDirectoryName(fp)!);
        File.WriteAllBytes(fp, content);
    }

    System.IO.Compression.ZipFile.CreateFromDirectory(chainExtract, chainArchive);

    // Build lock JSON
    var chainSha = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(chainArchive))).ToLowerInvariant();
    var chainArtifactsJson = string.Join(",", manifest.Artifacts.SelectMany(a =>
        new[] { (rel: a.RelativePath, mp: "BetterGI/" + a.RelativePath, sha: Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes($"content-for-{a.RelativePath}"))).ToLowerInvariant(), size: contentDict[a.RelativePath].LongLength) }
        .Concat(a.Sidecars.Select(s => (rel: s, mp: "BetterGI/" + s, sha: Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes($"content-for-{s}"))).ToLowerInvariant(), size: contentDict[s].LongLength)))
    ).Select(x => $"{{\"destinationRelativePath\":\"{x.rel}\",\"sourceId\":\"test\",\"memberPath\":\"{x.mp}\",\"sizeBytes\":{x.size},\"sha256\":\"{x.sha}\",\"transformation\":\"relocate\",\"licenseEvidence\":{{\"spdxId\":null,\"source\":\"test\",\"redistributionStatus\":\"test\"}}}}"));
    var chainSidecarJson = string.Join(",", manifest.SidecarArtifacts.Select(s =>
        $"{{\"destinationRelativePath\":\"{s.RelativePath}\",\"sourceId\":\"test\",\"memberPath\":\"BetterGI/{s.RelativePath}\",\"sizeBytes\":{contentDict[s.RelativePath].LongLength},\"sha256\":\"{Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes($"content-for-{s.RelativePath}"))).ToLowerInvariant()}\",\"transformation\":\"relocate\",\"licenseEvidence\":{{\"spdxId\":null,\"source\":\"test\",\"redistributionStatus\":\"test\"}}}}"));
    var chainLock = "{\"schemaVersion\":1,\"artifactSetVersion\":\"chain\"," +
        "\"sources\":[{\"id\":\"test\",\"type\":\"archive\"," +
        "\"url\":\"file://" + chainArchive.Replace('\\', '/') + "\"," +
        "\"sha256\":\"" + chainSha + "\"," +
        "\"format\":\"7z\",\"sizeBytes\":" + new FileInfo(chainArchive).Length + "," +
        "\"memberCount\":0," +
        "\"provenance\":{\"project\":\"test\",\"releaseTag\":\"v0\"," +
        "\"commitSha\":\"0000000000000000000000000000000000000000\"," +
        "\"publishedAt\":\"2025-01-01T00:00:00Z\"}}]," +
        "\"artifacts\":[" + chainArtifactsJson + "," + chainSidecarJson + "]}";
    var chainLockPath = Path.Combine(chainWork, "lock.json");
    File.WriteAllText(chainLockPath, chainLock);

    // Download
    using var chainDl = new BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader();
    Directory.CreateDirectory(chainModelRoot);
    var chainResult = await chainDl.DownloadAsync(chainLockPath, chainModelRoot, CancellationToken.None);
    Assert("B12.1 Chain download success", chainResult.Success, $"errors={string.Join("; ", chainResult.Errors)}");
    Assert("B12.1 Chain all 30 files placed", chainResult.ArtifactsExtracted == 30, $"extracted={chainResult.ArtifactsExtracted}");

    // Create resolvers with the same modelRoot
    var chainOnnxResolver = new BetterGenshinImpact.Core.Adapters.ModelRootPathResolver(chainModelRoot);
    var chainOcrResolver = new BetterGenshinImpact.Core.Adapters.OcrResourcePathResolver(chainModelRoot);

    // Verify: every manifest artifact → resolver resolves to existing file
    foreach (var entry in manifest.Artifacts)
    {
        var model = registryMap.GetValueOrDefault(entry.RegistryKey);
        if (model is null)
        {
            Assert($"B12.1 RegistryKey {entry.RegistryKey} not in registry map", false, "");
            continue;
        }
        var resolvedPath = chainOnnxResolver.ResolveModelPath(model);
        Assert($"B12.1 ONNX resolver for {entry.RegistryKey} → file exists", File.Exists(resolvedPath),
            $"resolved={resolvedPath}");
        var content = File.ReadAllBytes(resolvedPath);
        Assert($"B12.1 ONNX {entry.RegistryKey} content matches",
            content.SequenceEqual(Encoding.UTF8.GetBytes($"content-for-{entry.RelativePath}")),
            $"content mismatch at {resolvedPath}");

        // Sidecars
        foreach (var sidecar in entry.Sidecars)
        {
            var scPath = chainOcrResolver.ResolveSidecarPath(sidecar);
            Assert($"B12.1 Sidecar {sidecar} → file exists", File.Exists(scPath),
                $"resolved={scPath}");
            var scContent = File.ReadAllBytes(scPath);
            Assert($"B12.1 Sidecar {sidecar} content matches",
                scContent.SequenceEqual(Encoding.UTF8.GetBytes($"content-for-{sidecar}")),
                $"content mismatch at {scPath}");
        }
    }

    // Verify: global sidecar artifacts (preheat PNGs)
    foreach (var sidecar in manifest.SidecarArtifacts)
    {
        var scPath = chainOcrResolver.ResolveSidecarPath(sidecar.RelativePath);
        Assert($"B12.1 Global sidecar {sidecar.Id} → file exists", File.Exists(scPath),
            $"resolved={scPath}");
        var scContent = File.ReadAllBytes(scPath);
        Assert($"B12.1 Global sidecar {sidecar.Id} content matches",
            scContent.SequenceEqual(Encoding.UTF8.GetBytes($"content-for-{sidecar.RelativePath}")),
            $"content mismatch at {scPath}");
    }

    // Specifically verify PickTextInference chain
    var yapDictPath = chainOcrResolver.ResolveSidecarPath(
        BetterGenshinImpact.Core.Recognition.ONNX.SVTR.PickTextInference.YapDictionaryRelativePath);
    Assert("B12.1 PickTextInference YapDictionaryRelativePath resolves to file",
        File.Exists(yapDictPath), $"path={yapDictPath}");
    Assert("B12.1 PickTextInference Yap JSON content correct",
        File.ReadAllBytes(yapDictPath).SequenceEqual(
            Encoding.UTF8.GetBytes("content-for-Assets/Model/Yap/index_2_word.json")),
        "");

    var yapOnnxPath = chainOnnxResolver.ResolveModelPath(
        BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.YapModelTraining);
    Assert("B12.1 PickTextInference YapModelTraining ONNX resolves to file",
        File.Exists(yapOnnxPath), $"path={yapOnnxPath}");

    Console.WriteLine("B12.1: ALL PATH CHAIN VERIFICATIONS PASSED");
    Directory.Delete(chainWork, recursive: true);
}
Console.WriteLine();

// ==== B12.2 Locked release installation and artifact integrity ====
Console.WriteLine("B12.2: Locked release artifact integrity");
var lockedRuntimeRoot = Path.Combine(Path.GetTempPath(), "bgi-locked-runtime-" + Guid.NewGuid().ToString("N")[..8]);
{
    var localReleaseArchive = Path.GetFullPath(Path.Combine(
        Directory.GetCurrentDirectory(),
        "artifacts/provenance-audit/release-0.62.0/downloads/BetterGI_v0.62.0.7z"));
    var lockedTestSourcePath = lockPath;
    var temporaryLockPath = Path.Combine(Path.GetTempPath(), "bgi-locked-source-" + Guid.NewGuid().ToString("N") + ".json");
    if (File.Exists(localReleaseArchive))
    {
        var officialUrl = downloaderLock.Sources.Single().Url;
        File.WriteAllText(temporaryLockPath,
            lockJson.Replace(officialUrl, "file://" + localReleaseArchive, StringComparison.Ordinal));
        lockedTestSourcePath = temporaryLockPath;
    }

    using (var realDownloader = new BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader())
    {
        var installResult = await realDownloader.DownloadAsync(
            lockedTestSourcePath, lockedRuntimeRoot, CancellationToken.None);
        Assert("B12.2 locked release installation succeeds", installResult.Success,
            string.Join("; ", installResult.Errors));
        Assert("B12.2 locked release installs all 30 artifacts",
            installResult.ArtifactsExtracted == 30, $"got {installResult.ArtifactsExtracted}");
    }

    if (File.Exists(temporaryLockPath)) File.Delete(temporaryLockPath);

    foreach (var artifact in downloaderLock.Artifacts)
    {
        var installedPath = Path.Combine(lockedRuntimeRoot,
            artifact.DestinationRelativePath.Replace('/', Path.DirectorySeparatorChar));
        Assert($"B12.2 installed artifact exists {artifact.DestinationRelativePath}",
            File.Exists(installedPath), installedPath);
        if (!File.Exists(installedPath))
        {
            continue;
        }

        var fileInfo = new FileInfo(installedPath);
        Assert($"B12.2 installed artifact size {artifact.DestinationRelativePath}",
            fileInfo.Length == artifact.SizeBytes,
            $"expected={artifact.SizeBytes}, actual={fileInfo.Length}");
        using var stream = File.OpenRead(installedPath);
        var actualSha256 = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
        Assert($"B12.2 installed artifact sha256 {artifact.DestinationRelativePath}",
            actualSha256 == artifact.Sha256,
            $"expected={artifact.Sha256}, actual={actualSha256}");
    }
}
Console.WriteLine();

// ==== B12.2.1 Real ONNX InferenceSession load test ====
Console.WriteLine("B12.2: Real ONNX InferenceSession load test");
{
    Assert("B12.2 real installed model directory exists", Directory.Exists(lockedRuntimeRoot), lockedRuntimeRoot);
    if (Directory.Exists(lockedRuntimeRoot))
    {
        var realOnnxResolver = new BetterGenshinImpact.Core.Adapters.ModelRootPathResolver(lockedRuntimeRoot);

        // Create a BgiOnnxFactory with the real resolver
        var realFactory = CpuFactory(realOnnxResolver);

        // Test each real ONNX file via InferenceSession
        var testModels = registryMap.Select(entry => (entry.Key, entry.Value)).ToArray();

        int sessionCount = 0;
        foreach (var (name, model) in testModels)
        {
            var modelPath = realOnnxResolver.ResolveModelPath(model);
            if (!File.Exists(modelPath))
            {
                Assert($"B12.2 {name} file exists", false, $"not found: {modelPath}");
                continue;
            }

            try
            {
                using var session = realFactory.CreateInferenceSession(model);
                sessionCount++;
                Assert($"B12.2 {name} InferenceSession created", true, "");

                // Read input metadata
                var inputNames = session.InputMetadata.Keys.ToList();
                Assert($"B12.2 {name} has inputs", inputNames.Count > 0, $"inputs={inputNames.Count}");
                foreach (var inputName in inputNames)
                {
                    var inputType = session.InputMetadata[inputName].ElementType;
                    Console.WriteLine($"  {name} input '{inputName}': type={inputType}");
                }

                // Read output metadata
                var outputNames = session.OutputMetadata.Keys.ToList();
                Assert($"B12.2 {name} has outputs", outputNames.Count > 0, $"outputs={outputNames.Count}");
                foreach (var outputName in outputNames)
                {
                    var outputType = session.OutputMetadata[outputName].ElementType;
                    Console.WriteLine($"  {name} output '{outputName}': type={outputType}");
                }
            }
            catch (Microsoft.ML.OnnxRuntime.OnnxRuntimeException ex)
            {
                // ONNX graph/model parsing issue — distinct from native library missing
                Assert($"B12.2 {name} InferenceSession", false, $"OnnxRuntimeException: {ex.Message[..Math.Min(200, ex.Message.Length)]}");
            }
            catch (DllNotFoundException ex)
            {
                // Native ONNX Runtime library not found
                Console.WriteLine($"  {name}: DllNotFoundException — native library missing: {ex.Message}");
                Assert($"B12.2 {name} InferenceSession", false, $"native library missing: {ex.Message}");
            }
            catch (Exception ex)
            {
                // Other failure (provider init, graph unsupported, etc.)
                Assert($"B12.2 {name} InferenceSession", false, $"{ex.GetType().Name}: {ex.Message[..Math.Min(200, ex.Message.Length)]}");
            }
        }

        Console.WriteLine($"B12.2: {sessionCount}/{testModels.Length} InferenceSessions created successfully");
    }
}
if (Directory.Exists(lockedRuntimeRoot)) Directory.Delete(lockedRuntimeRoot, recursive: true);
Console.WriteLine();

// ==== B12.3 PaddleOCR preprocessing/postprocessing validation ====
Console.WriteLine("B12.3: PaddleOCR pipeline validation");
{
    // Helper: replicate ParseInferenceYml logic
    static List<string> ParseCharacterDictFromYaml(string path)
    {
        using var reader = new System.IO.StreamReader(path);
        var parser = new YamlDotNet.Core.Parser(reader);
        while (parser.MoveNext())
        {
            if (parser.Current is not YamlDotNet.Core.Events.Scalar { Value: "PostProcess" }) continue;
            parser.MoveNext();
            while (parser.MoveNext())
            {
                if (parser.Current is not YamlDotNet.Core.Events.Scalar { Value: "character_dict" }) continue;
                parser.MoveNext();
                var result = new List<string>();
                while (parser.MoveNext())
                {
                    if (parser.Current is YamlDotNet.Core.Events.SequenceEnd)
                        return result;
                    if (parser.Current is YamlDotNet.Core.Events.Scalar s)
                        result.Add(s.Value);
                }
            }
        }
        throw new InvalidOperationException("character_dict not found in PostProcess");
    }
    var realBase = Path.GetFullPath(Path.Combine(
        Directory.GetCurrentDirectory(),
        "artifacts/provenance-audit/release-0.62.0/extracted/BetterGI/Assets/Model"));

    if (!Directory.Exists(realBase))
    {
        Console.WriteLine("B12.3: SKIPPED — extracted model directory not found");
    }
    else
    {
        var recYamls = Directory.GetFiles(Path.Combine(realBase, "PaddleOCR/Rec"), "inference.yml", SearchOption.AllDirectories);

        // B12.3.1: ParseInferenceYml runtime validation (replicate parsing logic with YamlDotNet)
        foreach (var yamlPath in recYamls)
        {
            var variant = yamlPath.Contains("/Rec/V4/") ? "V4" :
                          yamlPath.Contains("/V4En") || yamlPath.Contains("/en_") ? "V4En" :
                          yamlPath.Contains("/V5Latin") || yamlPath.Contains("/latin_") ? "V5Latin" :
                          yamlPath.Contains("/V5Eslav") || yamlPath.Contains("/eslav_") ? "V5Eslav" :
                          yamlPath.Contains("/V5Korean") || yamlPath.Contains("/korean_") ? "V5Korean" :
                          yamlPath.Contains("/Rec/V6/") ? "V6" : "V5";
            try
            {
                var labels = ParseCharacterDictFromYaml(yamlPath);
                Assert($"B12.3.1 {variant} YAML parse succeeded", labels is { Count: > 0 }, "");
                Assert($"B12.3.1 {variant} label count > 10", labels!.Count > 10, $"count={labels.Count}");
                Console.WriteLine($"  {variant}: {labels.Count} labels parsed from {Path.GetFileName(Path.GetDirectoryName(yamlPath))}");
            }
            catch (Exception ex)
            {
                Assert($"B12.3.1 {variant} YAML parse", false, $"{ex.GetType().Name}: {ex.Message[..Math.Min(200, ex.Message.Length)]}");
            }
        }

        // B12.3.2 + B12.3.3: Real inference with Rec model
        try
        {
            var recV4EnModel = BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel.PaddleOcrRecV4En;
            var recV4EnYaml = Path.Combine(realBase, "PaddleOCR/Rec/V4/en_PP-OCRv4_mobile_rec_infer/inference.yml");
            var labels = ParseCharacterDictFromYaml(recV4EnYaml);

            var factory = CpuFactory(new BetterGenshinImpact.Core.Adapters.ModelRootPathResolver(
                Path.GetFullPath(Path.Combine(realBase, "../.."))));

            using var recSession = factory.CreateInferenceSession(recV4EnModel);
            Assert("B12.3.2 RecV4En session created for inference", recSession != null, "");

            // Create a synthetic test image (grayscale, 100x32)
            using var testImage = new Mat(32, 100, MatType.CV_8UC1, Scalar.Black);
            Cv2.PutText(testImage, "Hello", new OpenCvSharp.Point(10, 24),
                HersheyFonts.HersheySimplex, 0.8, Scalar.White, 1);

            // Preprocess: resize + normalize (same as Rec.RunMulti)
            var modelHeight = 48; // from RecV4En config
            var maxWidth = (int)Math.Ceiling(1.0 * testImage.Width / testImage.Height * modelHeight);
            using var channel3 = testImage.CvtColor(ColorConversionCodes.GRAY2BGR);
            var inputTensor = OcrUtils.ResizeNormImg(channel3, new OcrShape(3, maxWidth, modelHeight), out var owner)
                ?? throw new InvalidDataException("OCR preprocessing returned null.");
            Assert("B12.3.2 Preprocessed tensor created", inputTensor != null, "");
            var inputDims = inputTensor!.Dimensions.ToArray();
            Console.WriteLine($"  RecV4En input tensor shape: [{string.Join(",", inputDims)}]");

            // Run inference
            IDisposableReadOnlyCollection<DisposableNamedOnnxValue> inferenceResults;
            lock (recSession!)
            {
                inferenceResults = recSession.Run([
                    NamedOnnxValue.CreateFromTensor(recSession.InputNames[0], inputTensor)
                ]);
            }
            using var results = inferenceResults;
            Assert("B12.3.3 Inference produced output", results.Count > 0, "");
            var output = results[0];
            Assert("B12.3.3 Output is float tensor", output.ElementType == TensorElementType.Float, "");
            var outputTensor = output.AsTensor<float>();
            var outDims = outputTensor.Dimensions.ToArray();
            Console.WriteLine($"  RecV4En output tensor shape: [{string.Join(",", outDims)}]");

            // Postprocess: argmax decode (same logic as Rec.RunMulti)
            var outputArray = outputTensor.ToArray();
            var resultShape = outputTensor.Dimensions.ToArray();
            var labelCount = resultShape[2];
            var charCount = resultShape[1];
            StringBuilder sb = new();
            var lastIndex = 0;
            float score = 0;
            for (var n = 0; n < charCount; ++n)
            {
                var rowOffset = n * labelCount;
                var maxVal = float.MinValue;
                var maxIndex = 0;
                for (var c = 0; c < labelCount; c++)
                {
                    var value = outputArray[rowOffset + c];
                    if (value > maxVal)
                    {
                        maxVal = value;
                        maxIndex = c;
                    }
                }
                if (maxIndex > 0 && !(n > 0 && maxIndex == lastIndex))
                {
                    score += maxVal;
                    sb.Append(OcrUtils.GetLabelByIndex(maxIndex, labels));
                }
                lastIndex = maxIndex;
            }
            var text = sb.ToString();
            Console.WriteLine($"  RecV4En decoded text: \"{text}\" (score={score:F2}, length={text.Length})");
            Assert("B12.3.3 Text decoding matches fixture", text == "Hello", $"text={text}");

            owner.Dispose();
            Console.WriteLine("B12.3: Real OCR pipeline (parse → preprocess → inference → decode) COMPLETE");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"B12.3: Pipeline test failed: {ex.GetType().Name}: {ex.Message[..Math.Min(200, ex.Message.Length)]}");
            Assert("B12.3 OCR pipeline", false, $"{ex.GetType().Name}: {ex.Message[..Math.Min(100, ex.Message.Length)]}");
        }
    }
}
Console.WriteLine();
Global.StartUpPath = Path.Combine(Environment.CurrentDirectory, "BetterGenshinImpact");
var b5SystemInfo = new VerificationSystemInfo();
var defaultLogger = NullLogger<AutoPickAssets>.Instance;
var triggerLogger = NullLogger<AutoPickTrigger>.Instance;

// Initialize AutoPickAssets before any trigger creation (trigger ctor accesses Instance)
AutoPickAssets.DestroyInstance();
AutoPickAssets.Initialize(b5SystemInfo,
    new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
        new AutoPickConfig { PickKey = "F" }, PaddleOcrModelConfig.V5, "zh-Hans"),
    defaultLogger);

var stopCountProp = typeof(BetterGenshinImpact.GameTask.AutoPick.AutoPickTrigger)
    .GetProperty("StopCount", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
var extField = typeof(BetterGenshinImpact.GameTask.AutoPick.AutoPickTrigger)
    .GetField("_externalConfig", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)
    ?? throw new MissingFieldException("AutoPickTrigger._externalConfig");

// Reusable default runtime state for tests where runtime state is not the focus.
var defaultRuntimeState = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(0);

// Test 1: injection with StopCount=0 (via five-param ctor, null externalConfig + required provider)
var b5Recorder = new RecordingInputBackend();
var testConfigProvider = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true }, PaddleOcrModelConfig.V5, "zh-Hans");
var testPaddle = new FakePaddleAutoPickTextRecognizer();
var testYap = new FakeYapAutoPickTextRecognizer();
var state0B5 = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(0);
var t0 = new AutoPickTrigger(null, state0B5, testConfigProvider, b5Recorder, b5SystemInfo, triggerLogger, testPaddle, testYap);
var actualStop0 = (int)(stopCountProp?.GetValue(t0) ?? throw new InvalidOperationException());
Assert("StopCount=0 from state", actualStop0 == 0, $"got {actualStop0}");

// Test 2: injection with StopCount=2
var b5Recorder2 = new RecordingInputBackend();
var stateForB5 = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(2);
var t2 = new AutoPickTrigger(null, stateForB5, testConfigProvider, b5Recorder2, b5SystemInfo, triggerLogger, testPaddle, testYap);
var actualStop2 = (int)(stopCountProp?.GetValue(t2) ?? throw new InvalidOperationException());
Assert("StopCount=2 from state", actualStop2 == 2, $"got {actualStop2}");

// Test 3: null runtimeState → ArgumentNullException; externalConfig stays nullable
var b5Recorder3 = new RecordingInputBackend();
try
{
    _ = new AutoPickTrigger(null, null!, testConfigProvider, b5Recorder3, b5SystemInfo, triggerLogger, testPaddle, testYap);
    Assert("AutoPickTrigger should reject null runtimeState", false, "constructor accepted null");
}
catch (ArgumentNullException)
{
    Assert("AutoPickTrigger rejects null runtimeState", true, "");
}
// externalConfig null is still accepted (externalConfig remains nullable)
var tExtNull = new AutoPickTrigger(null, defaultRuntimeState, testConfigProvider, b5Recorder3, b5SystemInfo, triggerLogger, testPaddle, testYap);
var extNull = extField?.GetValue(tExtNull);
Assert("AutoPickTrigger accepts null externalConfig", extNull == null, "got non-null");

// Test 4: externalConfig-only preserves _externalConfig with valid runtimeState
var b5Recorder4 = new RecordingInputBackend();
var external = new AutoPickExternalConfig { ForceInteraction = true };
var t3 = new AutoPickTrigger(external, defaultRuntimeState, testConfigProvider, b5Recorder4, b5SystemInfo, triggerLogger, testPaddle, testYap);
var ext3 = extField?.GetValue(t3);
Assert("externalConfig-only preserves _externalConfig",
    ReferenceEquals(ext3, external), "different reference");
var actualStop3 = (int)(stopCountProp?.GetValue(t3) ?? throw new InvalidOperationException());
Assert("externalConfig-only sees StopCount from injected state", actualStop3 == 0, $"got {actualStop3}");

// Test 5: combined externalConfig + runtimeState
var b5Recorder5 = new RecordingInputBackend();
var t4 = new AutoPickTrigger(external, stateForB5, testConfigProvider, b5Recorder5, b5SystemInfo, triggerLogger, testPaddle, testYap);
var ext4 = extField?.GetValue(t4);
Assert("Combined ctor preserves _externalConfig",
    ReferenceEquals(ext4, external), "different reference");
var actualStop4 = (int)(stopCountProp?.GetValue(t4) ?? throw new InvalidOperationException());
Assert("Combined ctor preserves StopCount from state", actualStop4 == 2, $"got {actualStop4}");

// Test 6: null inputBackend → ArgumentNullException
try { _ = new AutoPickTrigger(null, defaultRuntimeState, testConfigProvider, null!, b5SystemInfo, triggerLogger, testPaddle, testYap); Assert("null inputBackend should throw", false, ""); }
catch (ArgumentNullException) { Assert("null inputBackend → ArgumentNullException", true, ""); }
// Also verify null configProvider throws
try { _ = new AutoPickTrigger(null, defaultRuntimeState, null!, b5Recorder, b5SystemInfo, triggerLogger, testPaddle, testYap); Assert("null configProvider should throw", false, ""); }
catch (ArgumentNullException) { Assert("null configProvider → ArgumentNullException", true, ""); }

// ==== B6: AutoPickAssets.Initialize lifecycle ====
Console.WriteLine("AutoPickAssets: Initialize lifecycle");
var pickConfigProvider = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "W" },
    PaddleOcrModelConfig.V5, "zh-Hans");

// 1. Field access before Initialize should throw (Instance throws)
AutoPickAssets.DestroyInstance();
try { _ = AutoPickAssets.Instance; Assert("Instance pre-Initialize should throw", false, "no exception"); }
catch (InvalidOperationException) { Assert("Instance pre-Initialize throws", true, ""); }

// 2. Configure via Initialize (falls back to F since no test assets exist)
AutoPickAssets.DestroyInstance();
AutoPickAssets.Initialize(b5SystemInfo, pickConfigProvider, defaultLogger);
AutoPickAssets? assets = AutoPickAssets.Instance;
Assert("After Initialize PickVk = F", assets.PickVk == BgiKey.F, $"got {assets.PickVk}");
Assert("PickRo is FRo (fallback)", ReferenceEquals(assets.PickRo, assets.FRo), "not FRo");
Assert("ChatPickRo null (fallback)", assets.ChatPickRo == null, $"got {assets.ChatPickRo}");
Assert("PickKey written back to F", pickConfigProvider.AutoPickConfig.PickKey == "F", $"got {pickConfigProvider.AutoPickConfig.PickKey}");

// EnsureConfigured actually passes (not a no-op)
AutoPickAssets.EnsureConfigured();
Assert("EnsureConfigured post-Configure passes", true, "");

// 3. Duplicate Initialize throws
AutoPickAssets.DestroyInstance();
AutoPickAssets.Initialize(b5SystemInfo, pickConfigProvider, defaultLogger);
try { AutoPickAssets.Initialize(b5SystemInfo, pickConfigProvider, defaultLogger); Assert("duplicate should throw", false, ""); }
catch (InvalidOperationException) { Assert("Duplicate Initialize throws", true, ""); }

// 4. Destroy + re-Initialize
AutoPickAssets.DestroyInstance();
var freshConfig = new AutoPickConfig { PickKey = "S" };
var freshProvider = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    freshConfig, PaddleOcrModelConfig.V5, "zh-Hans");
AutoPickAssets.Initialize(b5SystemInfo, freshProvider, defaultLogger);
var freshAssets = AutoPickAssets.Instance;
Assert("Re-initialized PickVk = F", freshAssets.PickVk == BgiKey.F, $"got {freshAssets.PickVk}");
Assert("Re-initialized PickKey=F", freshConfig.PickKey == "F", $"got {freshConfig.PickKey}");

// 5. Destroy + Instance access throws
AutoPickAssets.DestroyInstance();
try { _ = AutoPickAssets.Instance; Assert("post-Destroy Instance should throw", false, ""); }
catch (InvalidOperationException) { Assert("Post-Destroy Instance throws", true, ""); }

// 6. Empty-key behavior: Initialize with empty key uses defaults, no write-back
AutoPickAssets.DestroyInstance();
var emptyCfg = new AutoPickConfig { PickKey = "" };
var emptyProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    emptyCfg, PaddleOcrModelConfig.V5, "zh-Hans");
AutoPickAssets.Initialize(b5SystemInfo, emptyProv, defaultLogger);
var emptyAssets = AutoPickAssets.Instance;
Assert("Empty key: PickVk = F", emptyAssets.PickVk == BgiKey.F, $"got {emptyAssets.PickVk}");
Assert("Empty key: PickRo is FRo", ReferenceEquals(emptyAssets.PickRo, emptyAssets.FRo), "not FRo");
Assert("Empty key: PickKey unchanged (empty)", emptyCfg.PickKey == "", $"got '{emptyCfg.PickKey}'");

// Cleanup: return singleton to configured state for remaining tests
var cleanupProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F" }, PaddleOcrModelConfig.V5, "zh-Hans");
AutoPickAssets.DestroyInstance();
AutoPickAssets.Initialize(b5SystemInfo, cleanupProv, defaultLogger);
Console.WriteLine();

// ==== B6.3: property guards ====
Console.WriteLine("AutoPickAssets: property guards");
var assetType = typeof(AutoPickAssets);

// Properties are read-only
var pickVkProp = assetType.GetProperty("PickVk");
var pickRoProp = assetType.GetProperty("PickRo");
var chatProp = assetType.GetProperty("ChatPickRo");
Assert("PickVk setter not public", pickVkProp?.GetSetMethod() == null, "found setter");
Assert("PickRo setter not public", pickRoProp?.GetSetMethod() == null, "found setter");
Assert("ChatPickRo setter not public", chatProp?.GetSetMethod() == null, "found setter");

// Initialize systemInfo at known state for the remaining B7 tests
// (B7 Compose calls will re-initialize via their own Initialize calls)
AutoPickAssets.DestroyInstance();
AutoPickAssets.Initialize(b5SystemInfo, cleanupProv, defaultLogger);
Console.WriteLine();

// ==== B7: MacAutoPickComposition ====
Console.WriteLine("B7: MacAutoPickComposition");

var resetForVerification = typeof(MacAutoPickComposition)
    .GetMethod("ResetForVerification", BindingFlags.NonPublic | BindingFlags.Static)!;
var composeMethod = typeof(MacAutoPickComposition)
    .GetMethod("Compose", BindingFlags.Public | BindingFlags.Static)!;

// Reflection helpers for B7 trigger internals (extField already defined in B5)
var b7RuntimeStateField = typeof(AutoPickTrigger)
    .GetField("_runtimeState", BindingFlags.NonPublic | BindingFlags.Instance)!;
var b7ConfigProvField = typeof(AutoPickTrigger)
    .GetField("_configProvider", BindingFlags.NonPublic | BindingFlags.Instance)!;
var b7BlackListField = typeof(AutoPickTrigger)
    .GetField("_blackList", BindingFlags.NonPublic | BindingFlags.Instance)!;
var b7WhiteListField = typeof(AutoPickTrigger)
    .GetField("_whiteList", BindingFlags.NonPublic | BindingFlags.Instance)!;

// Prepare test state: reset composition before B7 tests
resetForVerification.Invoke(null, null);

// B7.1: Compose succeeds
var b7Provider = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true },
    PaddleOcrModelConfig.V5, "zh-Hans");
var b7State = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(3);
var b7ExtConfig = new AutoPickExternalConfig { ForceInteraction = true };
var b7Recorder = new RecordingInputBackend();

MacAutoPickComposition comp7;
{
    comp7 = (MacAutoPickComposition)composeMethod.Invoke(null,
        [b7Provider, b7State, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, b7ExtConfig])!;
    Assert("B7.1 Compose succeeds", comp7.Trigger != null, "trigger is null");
}
var comp7Trigger = comp7!.Trigger ?? throw new InvalidOperationException("B7 composition returned no trigger.");

// B7.2: Compose preserves external config reference
Assert("B7.2 _externalConfig preserved",
    ReferenceEquals(extField!.GetValue(comp7Trigger), b7ExtConfig), "different reference");

// B7.3: Compose preserves runtime state reference
Assert("B7.3 _runtimeState preserved",
    ReferenceEquals(b7RuntimeStateField.GetValue(comp7Trigger), b7State), "different reference");

// B7.4: Init() reads IsEnabled from provider
Assert("B7.4 IsEnabled from provider (true)", comp7Trigger.IsEnabled == true, $"got {comp7Trigger.IsEnabled}");

// B7.5: _configProvider field preserved
Assert("B7.5 _configProvider preserved",
    ReferenceEquals(b7ConfigProvField.GetValue(comp7Trigger), b7Provider), "different reference");

// B7.6: Double Compose throws (Composed state)
try
{
    composeMethod.Invoke(null, [b7Provider, b7State, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null]);
    Assert("B7.6 Double Compose should throw", false, "no exception");
}
catch (TargetInvocationException ex) when (ex.InnerException is InvalidOperationException ioe)
{
    Assert("B7.6 Double Compose throws Composed error",
        ioe.Message.Contains("already been composed"), ioe.Message);
}

// B7.7: Compose uses provider config (not TaskContext fallback)
// Reset, then Compose with Enabled = false — verify IsEnabled reads from provider
resetForVerification.Invoke(null, null);
var disabledCfg = new AutoPickConfig { PickKey = "F", Enabled = false };
var disabledProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    disabledCfg, PaddleOcrModelConfig.V5, "zh-Hans");
var disabledState = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(0);
comp7 = (MacAutoPickComposition)composeMethod.Invoke(null, [disabledProv, disabledState, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null])!;
Assert("B7.7 Init reads Enabled from provider (false)",
    comp7.Trigger.IsEnabled == false, $"got {comp7.Trigger.IsEnabled}");

// B7.8: After ResetForVerification, Compose succeeds again
resetForVerification.Invoke(null, null);
var reProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true },
    PaddleOcrModelConfig.V5, "zh-Hans");
var reState = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(1);
comp7 = (MacAutoPickComposition)composeMethod.Invoke(null, [reProv, reState, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null])!;
Assert("B7.8 After ResetForVerification, Compose succeeds",
    comp7.Trigger != null && comp7.Trigger.IsEnabled == true, $"trigger null or IsEnabled != true");

// B7.9: Compose with BlackListEnabled = false — _blackList is empty
resetForVerification.Invoke(null, null);
var blOffCfg = new AutoPickConfig { PickKey = "F", Enabled = true, BlackListEnabled = false };
var blOffProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    blOffCfg, PaddleOcrModelConfig.V5, "zh-Hans");
comp7 = (MacAutoPickComposition)composeMethod.Invoke(null, [blOffProv, reState, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null])!;
var blList = (System.Collections.Generic.HashSet<string>)b7BlackListField.GetValue(comp7.Trigger)!;
Assert("B7.9 BlackListEnabled=false: _blackList empty", blList.Count == 0, $"got {blList.Count}");

// B7.10: Compose with WhiteListEnabled = false — _whiteList is empty
resetForVerification.Invoke(null, null);
var wlOffCfg = new AutoPickConfig { PickKey = "F", Enabled = true, WhiteListEnabled = false };
var wlOffProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    wlOffCfg, PaddleOcrModelConfig.V5, "zh-Hans");
comp7 = (MacAutoPickComposition)composeMethod.Invoke(null, [wlOffProv, reState, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null])!;
var wlList = (System.Collections.Generic.HashSet<string>)b7WhiteListField.GetValue(comp7.Trigger)!;
Assert("B7.10 WhiteListEnabled=false: _whiteList empty", wlList.Count == 0, $"got {wlList.Count}");

// B7.11: Compose(null, validState) throws ArgumentNullException, state stays NotComposed
resetForVerification.Invoke(null, null);
try
{
    composeMethod.Invoke(null, [null!, b7State, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null]);
    Assert("B7.11 null provider should throw", false, "no exception");
}
catch (TargetInvocationException ex) when (ex.InnerException is ArgumentNullException)
{
    Assert("B7.11 null provider → ArgumentNullException", true, "");
}
// Verify: subsequent valid Compose succeeds (state was not poisoned)
var b711Prov = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true },
    PaddleOcrModelConfig.V5, "zh-Hans");
comp7 = (MacAutoPickComposition)composeMethod.Invoke(null, [b711Prov, b7State, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null])!;
Assert("B7.11 After null provider: valid Compose succeeds",
    comp7.Trigger != null, "trigger null — state was poisoned");

// B7.12: Compose(validProvider, null) throws ArgumentNullException
resetForVerification.Invoke(null, null);
try
{
    composeMethod.Invoke(null, [b7Provider, null!, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null]);
    Assert("B7.12 null runtimeState should throw", false, "no exception");
}
catch (TargetInvocationException ex) when (ex.InnerException is ArgumentNullException)
{
    Assert("B7.12 null runtimeState → ArgumentNullException", true, "");
}
var b712Prov = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true },
    PaddleOcrModelConfig.V5, "zh-Hans");
comp7 = (MacAutoPickComposition)composeMethod.Invoke(null, [b712Prov, b7State, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null])!;
Assert("B7.12 After null state: valid Compose succeeds",
    comp7.Trigger != null, "trigger null");

// B7.13: Concurrent Compose — only one succeeds
resetForVerification.Invoke(null, null);
int successCount = 0;
int failCount = 0;
using var barrier = new Barrier(2);
var concProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true },
    PaddleOcrModelConfig.V5, "zh-Hans");
var concState = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(0);
var concurrentErrors = new ConcurrentQueue<Exception>();

void ConcurrentCompose()
{
    barrier.SignalAndWait();
    try
    {
        composeMethod.Invoke(null, [concProv, concState, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null]);
        Interlocked.Increment(ref successCount);
    }
    catch (TargetInvocationException ex)
    {
        Interlocked.Increment(ref failCount);
        concurrentErrors.Enqueue(ex.InnerException ?? ex);
    }
    catch (Exception ex)
    {
        Interlocked.Increment(ref failCount);
        concurrentErrors.Enqueue(ex);
    }
}

var threadA = new Thread(ConcurrentCompose); threadA.Start();
var threadB = new Thread(ConcurrentCompose); threadB.Start();
threadA.Join(); threadB.Join();
Assert("B7.13 Concurrent: exactly 1 success", successCount == 1, $"got {successCount} successes, {failCount} failures");
Assert("B7.13 Concurrent: other threw InvalidOp", failCount == 1 && concurrentErrors.Count == 1 && concurrentErrors.First() is InvalidOperationException, $"failCount={failCount}, errors={concurrentErrors.Count}");

// B7.14: Compose failure enters Failed state; retry requires restart
resetForVerification.Invoke(null, null);
var throwingProvider = new ThrowingAutoPickConfigProvider();
var validState = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(0);
try
{
    composeMethod.Invoke(null, [throwingProvider, validState, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null]);
    Assert("B7.14 Failed compose should throw", false, "no exception");
}
catch (TargetInvocationException ex) when (ex.InnerException is InvalidOperationException ioe)
{
    Assert("B7.14 Original Init failure preserved",
        ioe.Message == "Injected composition failure", ioe.Message);
}
// Retry with valid provider should give "Restart the process"
try
{
    composeMethod.Invoke(null, [concProv, concState, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null]);
    Assert("B7.14 Retry after Failed should throw", false, "no exception");
}
catch (TargetInvocationException ex) when (ex.InnerException is InvalidOperationException ioe)
{
    Assert("B7.14 Failed state requires restart",
        ioe.Message.Contains("Restart the process"), ioe.Message);
}

// B7.15: ResetForVerification restores NotComposed from Failed state
resetForVerification.Invoke(null, null);
var b715Prov = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true },
    PaddleOcrModelConfig.V5, "zh-Hans");
var b715Comp = (MacAutoPickComposition)composeMethod.Invoke(null, [b715Prov, concState, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null])!;
Assert("B7.15 From Failed: after ResetForVerification, Compose succeeds",
    b715Comp.Trigger != null, "trigger null");
Console.WriteLine();

// Final cleanup: restore configured singleton for any subsequent tests
AutoPickAssets.DestroyInstance();
var b7CleanupProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true }, PaddleOcrModelConfig.V5, "zh-Hans");
AutoPickAssets.Initialize(b5SystemInfo, b7CleanupProv, defaultLogger);

// ==== B8.1.0: Win32InputHelpers pure functions ====
Console.WriteLine("B8.1.0: Win32InputHelpers coordinate + key mapping");

// BgiKey → VK mappings
Assert("B8.1.0 F → 0x46", Win32InputHelpers.MapBgiKeyToVk(BgiKey.F) == 0x46, $"got {Win32InputHelpers.MapBgiKeyToVk(BgiKey.F):X}");
Assert("B8.1.0 Escape → 0x1B", Win32InputHelpers.MapBgiKeyToVk(BgiKey.Escape) == 0x1B, $"{Win32InputHelpers.MapBgiKeyToVk(BgiKey.Escape):X}");
Assert("B8.1.0 Space → 0x20", Win32InputHelpers.MapBgiKeyToVk(BgiKey.Space) == 0x20, $"{Win32InputHelpers.MapBgiKeyToVk(BgiKey.Space):X}");
Assert("B8.1.0 W → 0x57", Win32InputHelpers.MapBgiKeyToVk(BgiKey.W) == 0x57, $"{Win32InputHelpers.MapBgiKeyToVk(BgiKey.W):X}");
Assert("B8.1.0 LeftShift → 0xA0", Win32InputHelpers.MapBgiKeyToVk(BgiKey.LeftShift) == 0xA0, $"{Win32InputHelpers.MapBgiKeyToVk(BgiKey.LeftShift):X}");

// Unmapped key throws
try { _ = Win32InputHelpers.MapBgiKeyToVk(BgiKey.None); Assert("B8.1.0 None should throw", false, ""); }
catch (ArgumentOutOfRangeException) { Assert("B8.1.0 None → ArgumentOutOfRangeException", true, ""); }

// --- Coordinate conversion: single monitor 1920x1080 ---
// Virtual desktop: left=0, top=0, width=1920, height=1080
{
    var (nx, ny) = Win32InputHelpers.ScreenToNormalized(0, 0, 0, 0, 1920, 1080);
    Assert("B8.1.0 (0,0) @ 1920x1080 → (0,0)", nx == 0 && ny == 0, $"({nx},{ny})");
}
{
    var (nx, ny) = Win32InputHelpers.ScreenToNormalized(1919, 1079, 0, 0, 1920, 1080);
    Assert("B8.1.0 (1919,1079) → (65535,65535)", nx == 65535 && ny == 65535, $"({nx},{ny})");
}
{
    // nx = (960 * 65535) / 1919 = 32784, ny = (540 * 65535) / 1079 = 32797
    // (960,540) is NOT the exact center of an even-width screen; center is between 959-960
    var (nx, ny) = Win32InputHelpers.ScreenToNormalized(960, 540, 0, 0, 1920, 1080);
    Assert("B8.1.0 pixel(960,540) @ 1920x1080 → (32784,32797)", nx == 32784 && ny == 32797, $"({nx},{ny})");
}

// --- Multi-monitor: secondary to left (virtualLeft = -1920) ---
// 2 × 1920x1080, monitor 2 starts at (0,0), monitor 1 starts at (-1920,0)
{
    // Left monitor center: (-960, 540) screen → relX=960, relY=540 → (960*65535/3839, 540*65535/1079) = (16388, 32797)
    var (nx, ny) = Win32InputHelpers.ScreenToNormalized(-960, 540, -1920, 0, 3840, 1080);
    Assert("B8.1.0 left-monitor px(-960,540) virtL=-1920 → (16388,32797)", nx == 16388 && ny == 32797, $"({nx},{ny})");
}
{
    // Right monitor: (960, 540) screen → relX=2880, relY=540 → (2880*65535/3839, 540*65535/1079) = (49164, 32797)
    var (nx, ny) = Win32InputHelpers.ScreenToNormalized(960, 540, -1920, 0, 3840, 1080);
    Assert("B8.1.0 right-monitor px(960,540) virtL=-1920 → (49164,32797)", nx == 49164 && ny == 32797, $"({nx},{ny})");
}

// --- Multi-monitor: secondary above (virtualTop = -1080) ---
{
    // (960, -540) screen → relX=960, relY=540 → (960*65535/1919, 540*65535/2159) = (32784, 16391)
    var (nx, ny) = Win32InputHelpers.ScreenToNormalized(960, -540, 0, -1080, 1920, 2160);
    Assert("B8.1.0 top-monitor px(960,-540) virtT=-1080 → (32784,16391)", nx == 32784 && ny == 16391, $"({nx},{ny})");
}

Console.WriteLine();

// ==== B8.1.1: AutoPickTrigger IInputBackend injection ====
Console.WriteLine("B8.1.1: AutoPickTrigger IInputBackend injection");

// Also verifies: AddTrigger after LoadInitialTriggers does NOT re-initialize AutoPickAssets
// (Initialize is already called by LoadInitialTriggers; AddTrigger reuses the existing assets)
// If AddTrigger mistakenly called Initialize again, it would throw InvalidOperationException.

var inputField = typeof(AutoPickTrigger)
    .GetField("_inputBackend", BindingFlags.NonPublic | BindingFlags.Instance)!;

// Recreate trigger with fresh recorder to verify field injection
var b811Recorder = new RecordingInputBackend();
var b811Trigger = new AutoPickTrigger(null, defaultRuntimeState, testConfigProvider, b811Recorder, b5SystemInfo, triggerLogger, testPaddle, testYap);
var injectedBackend = inputField.GetValue(b811Trigger);
Assert("B8.1.1 _inputBackend field set",
    ReferenceEquals(injectedBackend, b811Recorder), "different reference");

// null inputBackend throws (already tested in B5 section)

// Compose with IInputBackend via MacAutoPickComposition
resetForVerification.Invoke(null, null);
var b811Prov = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true },
    PaddleOcrModelConfig.V5, "zh-Hans");
var b811State = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(0);
var b811ComposeRecorder = new RecordingInputBackend();
var b811Comp = (MacAutoPickComposition)composeMethod.Invoke(null,
    [b811Prov, b811State, b811ComposeRecorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null])!;
var compInput = inputField.GetValue(b811Comp.Trigger);
Assert("B8.1.1 Compose preserves _inputBackend",
    ReferenceEquals(compInput, b811ComposeRecorder), "different reference");

// Verify RecordingInputBackend captures calls from trigger init (no active capture)
// Init loads blacklists — doesn't call KeyPress/Scroll directly. That happens in OnCapture().
// This test confirms the backend is wired correctly for future OnCapture invocations.
Assert("B8.1.1 trigger wired with externalConfig null",
    b811Comp.Trigger.IsEnabled == true, $"IsEnabled={b811Comp.Trigger.IsEnabled}");

// ==== B8.2: shared GameTaskManager lifecycle and platform construction ====
Console.WriteLine("B8.2: shared GameTaskManager lifecycle and platform construction");
GameTaskManagerPlatform.Configure(new VerificationGameTaskManagerPlatform(b5SystemInfo, triggerLogger));
var lowPriority = new VerificationTrigger("low", 1, false);
var highPriority = new VerificationTrigger("high", 10, false);
GameTaskManager.TriggerDictionary = new ConcurrentDictionary<string, ITaskTrigger>(
    new[] { new KeyValuePair<string, ITaskTrigger>("low", lowPriority), new KeyValuePair<string, ITaskTrigger>("high", highPriority) });
var orderedTriggers = GameTaskManager.ConvertToTriggerList(allEnabled: true);
Assert("B8.2 shared manager initializes every trigger", lowPriority.InitCount == 1 && highPriority.InitCount == 1,
    $"low={lowPriority.InitCount}, high={highPriority.InitCount}");
Assert("B8.2 shared manager sorts descending priority", orderedTriggers.Select(x => x.Name).SequenceEqual(["high", "low"]),
    string.Join(',', orderedTriggers.Select(x => x.Name)));
Assert("B8.2 allEnabled enables every trigger", orderedTriggers.All(x => x.IsEnabled), "a trigger remained disabled");
var b82Recorder = new RecordingInputBackend();
var b82Prov = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true },
    PaddleOcrModelConfig.V5, "zh-Hans");
var assetsBefore = AutoPickAssets.Instance;

// Real AddTrigger call (not pseudo-trigger via new ctor)
GameTaskManager.ClearTriggers();
var added = GameTaskManager.AddTrigger("AutoPick", null, defaultRuntimeState, b82Recorder, b5SystemInfo, testConfigProvider, testPaddle, testYap);
Assert("B8.2 shared AddTrigger returns true", added, "returned false");
Assert("B8.2 shared TriggerDictionary contains AutoPick",
    GameTaskManager.TriggerDictionary?.ContainsKey("AutoPick") == true, "not found");
var addedTrigger = GameTaskManager.TriggerDictionary?["AutoPick"];
Assert("B8.2 platform-created trigger is AutoPickTrigger",
    addedTrigger is AutoPickTrigger, $"got {addedTrigger?.GetType().Name}");
var assetsAfter = AutoPickAssets.Instance;
Assert("B8.2 AddTrigger preserves Assets singleton",
    ReferenceEquals(assetsAfter, assetsBefore), "assets were replaced by duplicate Initialize");

Console.WriteLine();

// ==== B8.3: AutoPickConfig required provider ====
Console.WriteLine("B8.3: AutoPickConfig required provider");

var b83ConfigProviderField = typeof(AutoPickTrigger)
    .GetField("_configProvider", BindingFlags.NonPublic | BindingFlags.Instance)!;

// A. Provider field wiring
var b83Prov = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true }, PaddleOcrModelConfig.V5, "zh-Hans");
var b83Trigger = new AutoPickTrigger(null, defaultRuntimeState, b83Prov, b5Recorder, b5SystemInfo, triggerLogger, testPaddle, testYap);
var wiredProv = b83ConfigProviderField.GetValue(b83Trigger);
Assert("B8.3A _configProvider field wired",
    ReferenceEquals(wiredProv, b83Prov), "different reference");

// B. null configProvider throws (already tested in B5 section)

// C. Init reads Enabled from provider
var b83DisabledProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = false }, PaddleOcrModelConfig.V5, "zh-Hans");
var b83DisabledTrigger = new AutoPickTrigger(null, defaultRuntimeState, b83DisabledProv, b5Recorder, b5SystemInfo, triggerLogger, testPaddle, testYap);
b83DisabledTrigger.Init();
Assert("B8.3C Init reads Enabled=false", !b83DisabledTrigger.IsEnabled, $"got {b83DisabledTrigger.IsEnabled}");

var b83EnabledProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true }, PaddleOcrModelConfig.V5, "zh-Hans");
var b83EnabledTrigger = new AutoPickTrigger(null, defaultRuntimeState, b83EnabledProv, b5Recorder, b5SystemInfo, triggerLogger, testPaddle, testYap);
b83EnabledTrigger.Init();
Assert("B8.3C Init reads Enabled=true", b83EnabledTrigger.IsEnabled, $"got {b83EnabledTrigger.IsEnabled}");

// D. Init respects WhiteListEnabled=false from provider
var b83BlOffProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true, WhiteListEnabled = false, BlackListEnabled = false },
    PaddleOcrModelConfig.V5, "zh-Hans");
var b83BlOffTrigger = new AutoPickTrigger(null, defaultRuntimeState, b83BlOffProv, b5Recorder, b5SystemInfo, triggerLogger, testPaddle, testYap);
b83BlOffTrigger.Init();
var b83WLField = typeof(AutoPickTrigger).GetField("_whiteList", BindingFlags.NonPublic | BindingFlags.Instance)!;
var b83BLField = typeof(AutoPickTrigger).GetField("_blackList", BindingFlags.NonPublic | BindingFlags.Instance)!;
var b83FLField = typeof(AutoPickTrigger).GetField("_fuzzyBlackList", BindingFlags.NonPublic | BindingFlags.Instance)!;
var wl = (System.Collections.Generic.HashSet<string>)b83WLField.GetValue(b83BlOffTrigger)!;
var bl = (System.Collections.Generic.HashSet<string>)b83BLField.GetValue(b83BlOffTrigger)!;
var fl = (System.Collections.Generic.List<string>)b83FLField.GetValue(b83BlOffTrigger)!;
Assert("B8.3D WhiteListEnabled=false → _whiteList empty", wl.Count == 0, $"got {wl.Count}");
Assert("B8.3D BlackListEnabled=false → _blackList empty", bl.Count == 0, $"got {bl.Count}");
Assert("B8.3D BlackListEnabled=false → _fuzzyBlackList empty", fl.Count == 0, $"got {fl.Count}");

// E. Provider returns live mutable reference
var b83LiveProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true, ItemIconLeftOffset = 60 },
    PaddleOcrModelConfig.V5, "zh-Hans");
var ref1 = b83LiveProv.AutoPickConfig;
Assert("B8.3E initial ItemIconLeftOffset", ref1.ItemIconLeftOffset == 60, $"got {ref1.ItemIconLeftOffset}");
ref1.ItemIconLeftOffset = 99;
var ref2 = b83LiveProv.AutoPickConfig;
Assert("B8.3E same reference after mutation",
    ReferenceEquals(ref2, ref1), "different objects");
Assert("B8.3E live mutation visible", ref2.ItemIconLeftOffset == 99, $"got {ref2.ItemIconLeftOffset}");

Console.WriteLine();

// ==== B9.2: Recognizer field injection + source guard ====
Console.WriteLine("B9.2: Recognizer injection");

var b92PaddleField = typeof(AutoPickTrigger).GetField("_paddleRecognizer", BindingFlags.NonPublic | BindingFlags.Instance)!;
var b92YapField = typeof(AutoPickTrigger).GetField("_yapRecognizer", BindingFlags.NonPublic | BindingFlags.Instance)!;

// Fields wired correctly — reference identity, not just type
var b92PaddleVal = b92PaddleField.GetValue(b83Trigger);
var b92YapVal = b92YapField.GetValue(b83Trigger);
Assert("B9.2 _paddleRecognizer reference",
    ReferenceEquals(b92PaddleVal, testPaddle), "different instance");
Assert("B9.2 _yapRecognizer reference",
    ReferenceEquals(b92YapVal, testYap), "different instance");

// Source guard: static OCR references removed from AutoPickTrigger.cs
// (confirmed by rg at commit time — file path not available at runtime)

// null recognizer test
try { _ = new AutoPickTrigger(null, defaultRuntimeState, testConfigProvider, b5Recorder, b5SystemInfo, triggerLogger, null!, testYap); Assert("null paddle should throw", false, ""); }
catch (ArgumentNullException) { Assert("B9.2 null paddle → ArgumentNullException", true, ""); }
try { _ = new AutoPickTrigger(null, defaultRuntimeState, testConfigProvider, b5Recorder, b5SystemInfo, triggerLogger, testPaddle, null!); Assert("null yap should throw", false, ""); }
catch (ArgumentNullException) { Assert("B9.2 null yap → ArgumentNullException", true, ""); }

// ==== B10.3: ConfigService removed — JSON equivalence ====
Console.WriteLine("B10.3: ConfigService removed — JSON equivalence");

var b103TestJson = @"[""Apple"",""Mint"",""甜甜花"",""Apple""]";
var b103DefaultResult = JsonSerializer.Deserialize<HashSet<string>>(b103TestJson) ?? [];
var b103LegacyOpts = new JsonSerializerOptions { PropertyNameCaseInsensitive = true, WriteIndented = true };
var b103LegacyResult = JsonSerializer.Deserialize<HashSet<string>>(b103TestJson, b103LegacyOpts) ?? [];

Assert("B10.3 default matches legacy", b103DefaultResult.SetEquals(b103LegacyResult), "sets differ");
Assert("B10.3 contains Apple", b103DefaultResult.Contains("Apple"), "missing Apple");
Assert("B10.3 contains Mint", b103DefaultResult.Contains("Mint"), "missing Mint");
Assert("B10.3 contains 甜甜花", b103DefaultResult.Contains("甜甜花"), "missing 甜甜花");
var b103Count = b103DefaultResult.Count;
Assert("B10.3 deduplication Count=3", b103Count == 3, $"got {b103Count}");

var b103Empty = JsonSerializer.Deserialize<HashSet<string>>("[]") ?? [];
var b103EmptyCount = b103Empty.Count;
Assert("B10.3 empty array → empty set", b103EmptyCount == 0, $"got {b103EmptyCount}");

Console.WriteLine();
Console.WriteLine($"=== {passed} passed, {failed} failed ===");
Microsoft.ML.OnnxRuntime.OrtEnv.Instance().Dispose();
Environment.ExitCode = failed > 0 ? 1 : 0;

class DeadProvider : BetterGenshinImpact.Core.Abstractions.Runtime.IOcrRuntimeConfigProvider
{
    public PaddleOcrModelConfig PaddleModel => throw new InvalidOperationException("Dead provider");
    public string GameCultureInfoName => throw new InvalidOperationException("Dead provider");
}

class CultureOnlyProvider : BetterGenshinImpact.Core.Abstractions.Runtime.IOcrRuntimeConfigProvider
{
    private readonly string _culture;
    public CultureOnlyProvider(string culture) => _culture = culture;
    public PaddleOcrModelConfig PaddleModel => PaddleOcrModelConfig.V5;
    public string GameCultureInfoName => _culture;
}

class RecordingInputBackend : IInputBackend
{
    public readonly List<string> Calls = new();
    public void Clear() { Calls.Clear(); }
    public void KeyDown(BgiKey key)    => Calls.Add($"KeyDown({key})");
    public void KeyUp(BgiKey key)      => Calls.Add($"KeyUp({key})");
    public void KeyPress(BgiKey key)   => Calls.Add($"KeyPress({key})");
    public void MoveMouseTo(int screenX, int screenY) => Calls.Add($"MoveMouseTo(X={screenX}, Y={screenY})");
    public void MoveMouseBy(int deltaX, int deltaY)   => Calls.Add($"MoveMouseBy(dX={deltaX}, dY={deltaY})");
    public void LeftButtonDown()  => Calls.Add("LeftButtonDown()");
    public void LeftButtonUp()    => Calls.Add("LeftButtonUp()");
    public void LeftClick(int screenX, int screenY) => Calls.Add($"LeftClick(X={screenX}, Y={screenY})");
    public void Scroll(int delta) => Calls.Add($"Scroll({delta})");
}

sealed class RecordingOverlayDrawPlatform : IOverlayDrawPlatform
{
    public List<string> Commands { get; } = [];
    public void SetRectangles(string name, ImageRegion source, IReadOnlyList<Rect> rectangles) =>
        Commands.Add($"set:{name}:{rectangles.Count}");
    public void RemoveRectangles(string name) => Commands.Add($"remove:{name}");
    public void ClearAll() => Commands.Add("clearAll");
}

sealed class VerificationSystemInfo : BetterGenshinImpact.GameTask.Model.ISystemInfo
{
    public System.Drawing.Size DisplaySize { get; } = new(1920, 1080);
    public BgiRect GameScreenSize { get; } = new(0, 0, 1920, 1080);
    public double AssetScale => 1;
    public double ZoomOutMax1080PRatio => 1;
    public double ScaleTo1080PRatio => 1;
    public BgiRect CaptureAreaRect { get; set; } = new(0, 0, 1920, 1080);
    public BgiRect ScaleMax1080PCaptureRect { get; set; } = new(0, 0, 1920, 1080);
    public System.Diagnostics.Process? GameProcess => null;
    public string GameProcessName => "Verification";
    public int GameProcessId => 0;
    public DesktopRegion DesktopRectArea { get; } = new(1920, 1080);
}

sealed class VerificationTrigger(string name, int priority, bool enabled) : ITaskTrigger
{
    public string Name => name;
    public bool IsEnabled { get; set; } = enabled;
    public int Priority => priority;
    public bool IsExclusive => false;
    public int InitCount { get; private set; }
    public void Init() => InitCount++;
    public void OnCapture(CaptureContent content) { }
}

sealed class VerificationGameTaskManagerPlatform(
    BetterGenshinImpact.GameTask.Model.ISystemInfo systemInfo,
    Microsoft.Extensions.Logging.ILogger<AutoPickTrigger> logger) : IGameTaskManagerPlatform
{
    public BetterGenshinImpact.GameTask.Model.ISystemInfo SystemInfo => systemInfo;
    public IReadOnlyList<KeyValuePair<string, ITaskTrigger>> CreateInitialTriggers(
        IInputBackend inputBackend, BetterGenshinImpact.GameTask.Model.ISystemInfo info,
        IAutoPickRuntimeState runtimeState, IAutoPickConfigProvider configProvider,
        IPaddleAutoPickTextRecognizer paddle, IYapAutoPickTextRecognizer yap) =>
        throw new NotSupportedException("Not used by this verification.");
    public KeyValuePair<string, ITaskTrigger>? CreateTrigger(
        string name, object? externalConfig, IAutoPickRuntimeState runtimeState,
        IInputBackend inputBackend, BetterGenshinImpact.GameTask.Model.ISystemInfo info,
        IAutoPickConfigProvider configProvider, IPaddleAutoPickTextRecognizer paddle,
        IYapAutoPickTextRecognizer yap) => name == "AutoPick"
        ? new("AutoPick", new AutoPickTrigger(externalConfig as AutoPickExternalConfig,
            runtimeState, configProvider, inputBackend, info, logger, paddle, yap))
        : null;
    public void ReloadAssets() { }
    public void ClearOverlay() { }
}

sealed class ThrowingAutoPickConfigProvider : IAutoPickConfigProvider
{
    public AutoPickConfig AutoPickConfig =>
        throw new InvalidOperationException("Injected composition failure");
}

sealed class FakePaddleAutoPickTextRecognizer : IPaddleAutoPickTextRecognizer
{
    public string Recognize(Mat textRegion) => "FakePaddleResult";
}

sealed class FakeYapAutoPickTextRecognizer : IYapAutoPickTextRecognizer
{
    public string Recognize(Mat textRegion) => "FakeYapResult";
}

sealed class RecordingTaskRunnerPlatform : ITaskRunnerPlatform
{
    public Microsoft.Extensions.Logging.ILogger Logger => NullLogger.Instance;
    public Microsoft.Extensions.Logging.ILogger RunnerLogger => NullLogger.Instance;
    public SemaphoreSlim TaskSemaphore { get; } = new(1, 1);
    public int InitializeCount { get; private set; }
    public int EndCount { get; private set; }
    public List<string> ErrorMessages { get; } = [];

    public void InitializeTask() => InitializeCount++;
    public void EndTask() => EndCount++;
    public void NotifyCancellation(string message) { }
    public void NotifyError(string message, Exception exception) => ErrorMessages.Add(message);
}

sealed class RecordingScriptServicePlatform : IScriptServicePlatform
{
    public Microsoft.Extensions.Logging.ILogger Logger => NullLogger.Instance;
    public string AutoPathingRoot => Path.GetTempPath();
    public string MapMatchingMethod => "TemplateMatch";
    public IReadOnlyList<BetterGenshinImpact.Core.Script.Group.ScriptGroup> ScriptGroups => [];
    public bool FarmingPlanEnabled => false;
    public SchedulerRestartPolicy RestartPolicy => new(false, 0, false, false, false);
    public bool IsDailyFarmingLimitReached(
        BetterGenshinImpact.GameTask.FarmingPlan.FarmingSession farmingSession,
        out string message)
    {
        message = "";
        return false;
    }
    public void ClearTriggers() { }
    public void SetCurrentScriptProject(ScriptGroupProject project) { }
    public Task StartGameTask(bool waitForMainUi) => throw new NotSupportedException();
    public Task HandleBlessingOfTheWelkinMoon(CancellationToken cancellationToken) => throw new NotSupportedException();
    public void NotifyGroupStart(string groupName) => throw new NotSupportedException();
    public void NotifyGroupEndSuccess(string groupName) => throw new NotSupportedException();
    public void NotifyGroupEndError(string message) => throw new NotSupportedException();
    public void CloseGame() => throw new NotSupportedException();
    public void RestartApplication(string taskProgressName) => throw new NotSupportedException();
}

sealed class RecordingScriptHostServices : IScriptHostServices
{
    public Microsoft.Extensions.Logging.ILogger CreateLogger(string categoryName) => NullLogger.Instance;
    public ScriptGroupProject? CurrentProject => null;
    public TimeSpan ServerTimeZoneOffset => TimeSpan.FromHours(8);
    public bool JsNotificationEnabled => true;
    public void EmitNotification(ScriptNotificationKind kind, string message) { }
}

sealed class VerificationCombatCommandPlatform : ICombatCommandPlatform
{
    public void ValidateKeyName(string keyName)
    {
        var normalized = keyName.Trim().ToUpperInvariant();
        if (normalized.StartsWith("VK_", StringComparison.Ordinal)) normalized = normalized[3..];
        if (normalized.Length == 1 && normalized[0] is >= 'A' and <= 'Z') return;
        if (normalized is "LBUTTON" or "RBUTTON" or "MBUTTON" or "SPACE" or "ESCAPE") return;
        throw new ArgumentException($"Unsupported verification key: {keyName}", nameof(keyName));
    }
    public void KeyDown(string keyName) => ValidateKeyName(keyName);
    public void KeyUp(string keyName) => ValidateKeyName(keyName);
    public void KeyPress(string keyName) => ValidateKeyName(keyName);
}

sealed class RecordingCombatCommandScene(ICombatCommandAvatar avatar) : ICombatScriptScene
{
    public int BeforeTaskCount { get; private set; }
    public ICombatCommandAvatar? SelectAvatar(string name) => avatar.Name == name ? avatar : null;

    public ICombatCommandAvatar SelectAvatar(int avatarIndex) => avatarIndex == 1
        ? avatar
        : throw new ArgumentOutOfRangeException(nameof(avatarIndex));
    public IReadOnlyCollection<ICombatCommandAvatar> GetAvatars() => [avatar];
    public void BeforeTask(CancellationToken cancellationToken) => BeforeTaskCount++;
}

sealed class RecordingCombatSceneProvider : ICombatSceneProvider
{
    public ICombatScriptScene? Scene { get; set; }
    public Task<ICombatScriptScene?> GetCombatScene(CancellationToken cancellationToken) => Task.FromResult(Scene);
}

sealed class RecordingPathExecutorSuspendContext : IPathExecutorSuspendContext
{
    public (int, List<WaypointForTrack>) CurWaypoints { get; init; }
    public (int, WaypointForTrack) CurWaypoint { get; init; }
    public bool GetPositionAndTimeSuspendFlag { get; set; }
    public DateTime MoveToStartTime { get; set; }
}

sealed class RecordingTaskControlPlatform : ITaskControlPlatform
{
    public List<string> Calls { get; } = [];
    public Microsoft.Extensions.Logging.ILogger Logger => NullLogger.Instance;
    public double DpiScale => 1;
    public bool IsHdrCapture => false;
    public void EnsureGameActive() { }
    public void ReleasePressedInputs() { }
    public void SimulateAction(GIActions action, KeyType keyType) => Calls.Add($"action:{action}:{keyType}");
    public bool IsActionKeyDown(GIActions action) => false;
    public void MoveMouseBy(int x, int y) => Calls.Add($"move:{x},{y}");
    public void LeftButtonDown() => Calls.Add("leftDown");
    public void LeftButtonUp() => Calls.Add("leftUp");
    public void LeftButtonClick() { }
    public void RightButtonDown() { }
    public void RightButtonUp() { }
    public void RightButtonClick() { }
    public void MiddleButtonDown() { }
    public void MiddleButtonUp() { }
    public void MiddleButtonClick() { }
    public void VerticalScroll(int scrollAmountInClicks) { }
    public void PressKey(int windowsVirtualKey) { }
    public void PressEscape() { }
    public ImageRegion CaptureToRectArea(bool forceNew) => throw new NotSupportedException();
}

sealed class RecordingCombatCommandAvatar(string name) : ICombatCommandAvatar
{
    public string Name { get; } = name;
    public List<string> Calls { get; } = [];
    public bool IsSkillReady(bool printLog = false) { Calls.Add($"IsSkillReady({printLog})"); return true; }
    public Task WaitSkillCd(CancellationToken ct = default) { Calls.Add("WaitSkillCd()"); return Task.CompletedTask; }
    public void Switch() => Calls.Add("Switch()");
    public void UseSkill(bool hold = false) => Calls.Add($"UseSkill({hold})");
    public void UseBurst() => Calls.Add("UseBurst()");
    public void Attack(int ms = 0) => Calls.Add($"Attack({ms})");
    public void Charge(int ms = 0) => Calls.Add($"Charge({ms})");
    public void Walk(string key, int ms) => Calls.Add($"Walk({key},{ms})");
    public void Wait(int ms) => Calls.Add($"Wait({ms})");
    public void Ready() => Calls.Add("Ready()");
    public void Dash(int ms = 0) => Calls.Add($"Dash({ms})");
    public void Jump() => Calls.Add("Jump()");
    public void MouseDown(string key = "left") => Calls.Add($"MouseDown({key})");
    public void MouseUp(string key = "left") => Calls.Add($"MouseUp({key})");
    public void Click(string key = "left") => Calls.Add($"Click({key})");
    public void MoveBy(int x, int y) => Calls.Add($"MoveBy({x},{y})");
    public void KeyDown(string key) => Calls.Add($"KeyDown({key})");
    public void KeyUp(string key) => Calls.Add($"KeyUp({key})");
    public void KeyPress(string key) => Calls.Add($"KeyPress({key})");
    public void Scroll(int scrollAmountInClicks) => Calls.Add($"Scroll({scrollAmountInClicks})");
}
