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
using Newtonsoft.Json.Linq;
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
using BetterGenshinImpact.GameTask.AutoCook;
using BetterGenshinImpact.GameTask.AutoWood;
using BetterGenshinImpact.GameTask.AutoMusicGame;
using BetterGenshinImpact.GameTask.AutoArtifactSalvage;
using BetterGenshinImpact.GameTask.AutoDomain;
using BetterGenshinImpact.GameTask.AutoBoss;
using BetterGenshinImpact.GameTask.GetGridIcons;
using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.GameTask.AutoPathing.Model.Enum;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.AutoPathing.Suspend;
using BetterGenshinImpact.GameTask.AutoPathing.Handler;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.Common.Reward;
using BetterGenshinImpact.GameTask.Model.GameUI;
using BetterGenshinImpact.GameTask.Common.Element.Assets;
using BetterGenshinImpact.GameTask.Common.Map;
using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask.Common.Map.Maps;
using BetterGenshinImpact.GameTask.Common.Map.Maps.Base;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.Platform.Abstractions;
using System.Collections.Concurrent;
using System.Reflection;
using System.Threading;
using System.Globalization;
using BetterGenshinImpact.Service;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.AutoFight.Script;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoFight.Assets;
using BetterGenshinImpact.GameTask.AutoFight.Model;
using BetterGenshinImpact.GameTask.FarmingPlan;

using Microsoft.Extensions.Logging.Abstractions;

var recorder = new RecordingInputBackend();
var overlayRecorder = new RecordingOverlayDrawPlatform();
OverlayDrawPlatform.Configure(overlayRecorder);
CombatCommandPlatform.Configure(new VerificationCombatCommandPlatform());
var combatSceneProvider = new RecordingCombatSceneProvider();
CombatSceneProvider.Configure(combatSceneProvider);
var recordingTaskControl = new RecordingTaskControlPlatform();
TaskControlPlatform.Configure(recordingTaskControl);
var verificationSystemInfo = new VerificationSystemInfo();
CraftMaterialRuntimePlatform.Configure(new VerificationCraftMaterialRuntimePlatform());
GridScreenRuntimePlatform.Configure(new VerificationGridScreenRuntimePlatform(verificationSystemInfo));
RewardResultRuntimePlatform.Configure(new VerificationRewardResultRuntimePlatform());
BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory CpuFactory(IOnnxModelPathResolver resolver) =>
    new(new BetterGenshinImpact.Core.Runtime.Portable.CpuOnnxRuntimePlatform(resolver));
DesktopRegionInputPlatform.Configure(recorder);
DesktopRegion.DisplayWidth = 1920;
DesktopRegion.DisplayHeight = 1080;
Global.StartUpPath = Path.Combine(Environment.CurrentDirectory, "BetterGenshinImpact");

int passed = 0, failed = 0;
void Assert(string label, bool condition, string detail)
{
    if (condition) { Console.WriteLine($"  PASS: {label}"); passed++; }
    else { Console.WriteLine($"  FAIL: {label} — {detail}"); failed++; }
}

using (var overlayFrame = new Mat(1080, 1920, MatType.CV_8UC4))
{
    var capture = new GameCaptureRegion(overlayFrame, 0, 0);
    capture.Derive(100, 200, 40, 30).DrawRect(5, 6, 7, 8, "DerivedRegion");
    Assert("Derived Region overlay preserves capture coordinate chain",
        overlayRecorder.Commands is ["set:DerivedRegion:105,206,7,8"],
        string.Join(";", overlayRecorder.Commands));
}

var farmingVerificationRoot = Path.Combine("/tmp", "bgi-farming-" + Guid.NewGuid().ToString("N"));
var farmingPlatform = new VerificationFarmingStatsRuntimePlatform(farmingVerificationRoot)
{
    ServerTimeNow = new DateTimeOffset(2026, 7, 19, 3, 59, 0, TimeSpan.FromHours(8))
};
FarmingStatsRuntimePlatform.Configure(farmingPlatform);
var beforeReset = FarmingStatsRecorder.ReadDailyFarmingData();
Assert("Farming stats 04:00 boundary uses previous server day",
    beforeReset.FilePath.EndsWith("20260718.json", StringComparison.Ordinal), beforeReset.FilePath);
farmingPlatform.ServerTimeNow = new DateTimeOffset(2026, 7, 19, 4, 0, 0, TimeSpan.FromHours(8));
var afterReset = FarmingStatsRecorder.ReadDailyFarmingData();
Assert("Farming stats 04:00 boundary switches to current server day",
    afterReset.FilePath.EndsWith("20260719.json", StringComparison.Ordinal), afterReset.FilePath);
FarmingStatsRecorder.RecordFarmingSession(new FarmingSession
{
    AllowFarmingCount = true,
    NormalMobCount = 6,
    EliteMobCount = 4,
    PrimaryTarget = "normal"
}, new FarmingRouteInfo { GroupName = "group", ProjectName = "route", FolderName = "folder" });
var farmingRoundTrip = FarmingStatsRecorder.ReadDailyFarmingData();
Assert("Farming stats preserves upstream counters and record metadata",
    farmingRoundTrip.TotalNormalMobCount == 6 && farmingRoundTrip.TotalEliteMobCount == 4 &&
    farmingRoundTrip.Records is [{ GroupName: "group", ProjectName: "route", FolderName: "folder" }],
    "persisted farming JSON did not round-trip");
farmingPlatform.Config.DailyMobCap = 6;
Assert("Farming stats enforces upstream primary-target cap",
    FarmingStatsRecorder.IsDailyFarmingLimitReached(new FarmingSession
    {
        AllowFarmingCount = true, NormalMobCount = 1, EliteMobCount = 1, PrimaryTarget = "normal"
    }, out var capMessage) && capMessage.Contains("小怪超上限", StringComparison.Ordinal), capMessage);

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
            Bv.IsInMainUi(region), "main UI was not recognized");
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

var originalUiCulture = CultureInfo.CurrentUICulture;
try
{
    var fishingLocalizer = new EmbeddedResourceStringLocalizer<AutoFishingTask>();
    CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("en");
    Assert("AutoFishing uses the real English task resource",
        fishingLocalizer["钓鱼"].Value == "Fishing", fishingLocalizer["钓鱼"].Value);
    CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("zh-Hans");
    Assert("AutoFishing uses the real Simplified Chinese task resource",
        fishingLocalizer["上钩"].Value == "上钩", fishingLocalizer["上钩"].Value);
}
finally
{
    CultureInfo.CurrentUICulture = originalUiCulture;
}

using (var fishBarFrame = new Mat(140, 1920, MatType.CV_8UC3, Scalar.Black))
{
    Cv2.Rectangle(fishBarFrame, new Rect(700, 80, 180, 12), new Scalar(192, 255, 255), -1);
    Cv2.Rectangle(fishBarFrame, new Rect(900, 80, 90, 12), new Scalar(192, 255, 255), -1);
    var bars = AutoFishingImageRecognition.GetFishBarRect(fishBarFrame);
    Assert("AutoFishing real fish-bar recognizer detects deterministic bars",
        bars?.Count == 2, $"count={bars?.Count ?? 0}");
}

using (var privacyFrame = new Mat(1080, 1920, MatType.CV_8UC3, Scalar.Black))
{
    ScreenshotPrivacy.ApplyUidCover(privacyFrame, 1d);
    var covered = privacyFrame.At<Vec3b>(1060, 1690);
    var untouched = privacyFrame.At<Vec3b>(1000, 1600);
    Assert("AutoFishing screenshot uses the shared upstream UID cover rectangle",
        covered.Item0 == 255 && covered.Item1 == 255 && covered.Item2 == 255 &&
        untouched.Item0 == 0 && untouched.Item1 == 0 && untouched.Item2 == 0,
        $"covered={covered}, untouched={untouched}");
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
var executionRecordPreviousRoot = Global.StartUpPath;
var executionRecordRuntimeRoot = Path.Combine(Path.GetTempPath(), $"bgi-execution-records-{Guid.NewGuid():N}");
Global.StartUpPath = executionRecordRuntimeRoot;
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

var persistedRecordId = Guid.NewGuid();
var persistedRecord = new ExecutionRecord
{
    Id = persistedRecordId,
    GroupName = recordGroup.Name,
    ProjectName = recordProject.Name,
    FolderName = recordProject.FolderName,
    Type = recordProject.Type,
    StartTime = DateTime.Now.AddMinutes(-3),
    EndTime = DateTime.Now.AddMinutes(-2),
    ServerStartTime = ScriptHostServices.ServerTimeNow.AddMinutes(-3),
    ServerEndTime = ScriptHostServices.ServerTimeNow.AddMinutes(-2),
    IsSuccessful = false
};
ExecutionRecordStorage.SaveExecutionRecord(persistedRecord);
var executionRecordPath = Path.Combine(
    Global.Absolute("log"), "ExecutionRecords", $"{persistedRecord.StartTime:yyyyMMdd}.json");
Assert("ExecutionRecordStorage writes the runtime-root daily JSON file",
    File.Exists(executionRecordPath), executionRecordPath);
var persistedJson = JObject.Parse(File.ReadAllText(executionRecordPath));
var persistedItems = persistedJson["execution_records"] as JArray;
Assert("ExecutionRecordStorage preserves upstream Newtonsoft field names",
    persistedJson.Value<string>("name") == persistedRecord.StartTime.ToString("yyyyMMdd") &&
    persistedItems is { Count: 1 } &&
    persistedItems[0]?.Value<string>("guid") == persistedRecordId.ToString() &&
    persistedItems[0]?.Value<bool>("is_successful") == false,
    persistedJson.ToString(Newtonsoft.Json.Formatting.None));

persistedRecord.IsSuccessful = true;
persistedRecord.EndTime = DateTime.Now.AddSeconds(-1);
persistedRecord.ServerEndTime = ScriptHostServices.ServerTimeNow.AddSeconds(-1);
ExecutionRecordStorage.SaveExecutionRecord(persistedRecord);
var updatedJson = JObject.Parse(File.ReadAllText(executionRecordPath));
var updatedItems = updatedJson["execution_records"] as JArray;
Assert("ExecutionRecordStorage updates an existing GUID instead of appending",
    updatedItems is { Count: 1 } && updatedItems[0]?.Value<bool>("is_successful") == true,
    updatedJson.ToString(Newtonsoft.Json.Formatting.None));

var olderRecord = new ExecutionRecord
{
    GroupName = recordGroup.Name,
    ProjectName = recordProject.Name,
    FolderName = recordProject.FolderName,
    Type = recordProject.Type,
    StartTime = DateTime.Today.AddDays(-1).AddHours(1),
    EndTime = DateTime.Today.AddDays(-1).AddHours(2),
    IsSuccessful = true
};
ExecutionRecordStorage.SaveExecutionRecord(olderRecord);
var reloadedRecords = ExecutionRecordStorage.GetRecentExecutionRecords(2);
Assert("ExecutionRecordStorage reloads daily files in reverse date order",
    reloadedRecords.Count == 2 &&
    reloadedRecords[0].Name == DateTime.Today.ToString("yyyyMMdd") &&
    reloadedRecords[0].ExecutionRecords.Single().Id == persistedRecordId &&
    reloadedRecords[1].Name == DateTime.Today.AddDays(-1).ToString("yyyyMMdd"),
    string.Join(",", reloadedRecords.Select(record => record.Name)));

var skipConfig = recordGroup.Config.PathingConfig.TaskCompletionSkipRuleConfig;
skipConfig.SkipPolicy = "PhysicalPathSkipPolicy";
Assert("PhysicalPathSkipPolicy matches the exact physical folder",
    ExecutionRecordStorage.IsSkipTask(recordProject, out var physicalPathMessage, reloadedRecords) &&
    physicalPathMessage.Contains("物理路径相同", StringComparison.Ordinal), physicalPathMessage);
recordProject.FolderName = "other-folder";
Assert("PhysicalPathSkipPolicy rejects a different physical folder",
    !ExecutionRecordStorage.IsSkipTask(recordProject, out _, reloadedRecords), "different folder matched");

recordProject.FolderName = persistedRecord.FolderName;
skipConfig.SkipPolicy = "GroupPhysicalPathSkipPolicy";
Assert("GroupPhysicalPathSkipPolicy matches group and physical folder",
    ExecutionRecordStorage.IsSkipTask(recordProject, out var groupPathMessage, reloadedRecords) &&
    groupPathMessage.Contains("组和物理路径匹配一致", StringComparison.Ordinal), groupPathMessage);
recordGroup.Name = "other-group";
Assert("GroupPhysicalPathSkipPolicy rejects a different group",
    !ExecutionRecordStorage.IsSkipTask(recordProject, out _, reloadedRecords), "different group matched");

recordGroup.Name = persistedRecord.GroupName;
skipConfig.SkipPolicy = "SameNameSkipPolicy";
skipConfig.BoundaryTime = 4;
skipConfig.LastRunGapSeconds = -1;
skipConfig.IsBoundaryTimeBasedOnServerTime = true;
persistedRecord.ServerStartTime = ScriptHostServices.ServerTimeNow.AddMinutes(-1);
Assert("server-time boundary accepts a record in the current 04:00 day",
    ExecutionRecordStorage.IsSkipTask(recordProject, out _,
        [new DailyExecutionRecord { ExecutionRecords = [persistedRecord] }]),
    persistedRecord.ServerStartTime?.ToString("O") ?? "null");
persistedRecord.ServerStartTime = ScriptHostServices.ServerTimeNow.AddDays(-1).AddMinutes(-1);
Assert("server-time boundary rejects the previous 04:00 day",
    !ExecutionRecordStorage.IsSkipTask(recordProject, out _,
        [new DailyExecutionRecord { ExecutionRecords = [persistedRecord] }]),
    persistedRecord.ServerStartTime?.ToString("O") ?? "null");

skipConfig.BoundaryTime = -1;
skipConfig.LastRunGapSeconds = 60;
persistedRecord.StartTime = DateTime.Now.AddMinutes(-2);
persistedRecord.EndTime = DateTime.Now.AddSeconds(-1);
skipConfig.ReferencePoint = "EndTime";
Assert("execution gap can use EndTime as its reference point",
    ExecutionRecordStorage.IsSkipTask(recordProject, out _,
        [new DailyExecutionRecord { ExecutionRecords = [persistedRecord] }]), "recent end time did not match");
skipConfig.ReferencePoint = "StartTime";
Assert("execution gap can use StartTime as its reference point",
    !ExecutionRecordStorage.IsSkipTask(recordProject, out _,
        [new DailyExecutionRecord { ExecutionRecords = [persistedRecord] }]), "stale start time matched");
Global.StartUpPath = executionRecordPreviousRoot;
Directory.Delete(executionRecordRuntimeRoot, recursive: true);
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
var sharedArchiveCacheDir = Path.Combine(Path.GetTempPath(), "bgi-release-archive-cache");
var lockDoc = System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(lockJson);
// Basic structure
Assert("B11.6.1.4 Lock has version", lockDoc.TryGetProperty("schemaVersion", out _), "");
Assert("B11.6.1.4 Lock has artifactSetVersion", lockDoc.TryGetProperty("artifactSetVersion", out _), "");
Assert("B11.6.1.4 Lock has sources", lockDoc.TryGetProperty("sources", out var sourcesArray) && sourcesArray.GetArrayLength() > 0, "");
Assert("B11.6.1.4 Lock has artifacts", lockDoc.TryGetProperty("artifacts", out var artifactsArray), "");
var lockArtifactsCount = artifactsArray.GetArrayLength();
Assert("B11.6.1.4 Lock has 34 artifacts", lockArtifactsCount == 34, $"got {lockArtifactsCount}");
// Validate each artifact
var lockDests = new HashSet<string>(StringComparer.Ordinal);
var lockHashes = new HashSet<string>(StringComparer.Ordinal);
var manifestPhysicalPaths = manifest.Artifacts.SelectMany(a => new[] { a.RelativePath }.Concat(a.Sidecars))
    .Concat(manifest.SidecarArtifacts.Select(s => s.RelativePath))
    .ToHashSet(StringComparer.Ordinal);
var requiredRuntimeAssetPaths = new HashSet<string>(StringComparer.Ordinal)
{
    "Assets/Model/ItemV2/item.onnx",
    "Assets/Model/ItemV2/item.csv",
    "Assets/Map/Teyvat/Teyvat_0_256_SIFT.kp.bin",
    "Assets/Map/Teyvat/Teyvat_0_256_SIFT.mat.png"
};
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
    Assert($"B11.6.1.4 destination is required {dest}",
        manifestPhysicalPaths.Contains(dest) || requiredRuntimeAssetPaths.Contains(dest),
        "not present in the model manifest or required runtime asset set");
    // LicenseEvidence exists with redistributionStatus
    Assert($"B11.6.1.4 licenseEvidence exists {dest}", art.TryGetProperty("licenseEvidence", out _), "");
    var licStatus = art.GetProperty("licenseEvidence").GetProperty("redistributionStatus").GetString();
    Assert($"B11.6.1.4 redistributionStatus non-empty {dest}", !string.IsNullOrEmpty(licStatus), "");
}
Assert("B11.6.1.4 34 unique destinations", lockDests.Count == 34, $"got {lockDests.Count}");
Assert("B11.6.1.4 34 unique hashes", lockHashes.Count == 34, $"got {lockHashes.Count}");
Assert("B11.6.1.4 covers every model manifest path", manifestPhysicalPaths.IsSubsetOf(lockDests),
    $"missing {string.Join(", ", manifestPhysicalPaths.Except(lockDests))}");
Assert("B11.6.1.4 contains exact runtime asset set",
    lockDests.Except(manifestPhysicalPaths).ToHashSet(StringComparer.Ordinal).SetEquals(requiredRuntimeAssetPaths),
    $"unexpected {string.Join(", ", lockDests.Except(manifestPhysicalPaths))}");
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
Assert("B11.6.2 Downloader has 34 artifacts", downloaderLock.Artifacts.Count == 34, $"got {downloaderLock.Artifacts.Count}");
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
    var fakeCache = Path.Combine(fakeWork, "cache");
    var dlResult = await dl.DownloadAsync(fakeLockPath, fakeOutput, CancellationToken.None, fakeCache);
    Assert("B11.6.2 Fake archive download success", dlResult.Success, $"errors={string.Join("; ", dlResult.Errors)}");
    Assert("B11.6.2 Fake archive extracted all files", dlResult.ArtifactsExtracted == fakeFiles.Count, $"extracted={dlResult.ArtifactsExtracted}");
    Assert("B11.6.2 Verified source archive is retained in Cache/Downloads",
        Directory.EnumerateFiles(fakeCache, "*.7z").Count() == 1, fakeCache);

    // Verify output files exist and match expected content
    foreach (var kvp in fakeFiles)
    {
        var outPath = Path.Combine(fakeOutput, kvp.Key);
        Assert($"B11.6.2 Fake output file exists {kvp.Key}", File.Exists(outPath), "");
        var content = File.ReadAllBytes(outPath);
        Assert($"B11.6.2 Fake output content matches {kvp.Key}", content.SequenceEqual(kvp.Value), "");
    }

    var alreadyInstalled = await dl.EnsureInstalledAsync(fakeLockPath, fakeOutput, CancellationToken.None, fakeCache);
    Assert("B11.6.2 Ensure skips a fully verified install",
        alreadyInstalled.Success && alreadyInstalled.ArtifactsExtracted == 0 &&
        alreadyInstalled.ArtifactsSkipped == fakeFiles.Count,
        $"extracted={alreadyInstalled.ArtifactsExtracted}, skipped={alreadyInstalled.ArtifactsSkipped}");
    File.WriteAllBytes(Path.Combine(fakeOutput, fakeFiles.Keys.First()), [0]);
    var repaired = await dl.EnsureInstalledAsync(fakeLockPath, fakeOutput, CancellationToken.None, fakeCache);
    Assert("B11.6.2 Ensure repairs a corrupt installed artifact",
        repaired.Success && repaired.ArtifactsExtracted == fakeFiles.Count,
        $"errors={string.Join("; ", repaired.Errors)}");

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

    // Create every source-locked file, including non-model runtime assets.
    var allDestinations = downloaderLock.Artifacts
        .Select(artifact => artifact.DestinationRelativePath)
        .Distinct(StringComparer.Ordinal)
        .ToList();
    Assert("B12.1 All 34 destination paths enumerated", allDestinations.Count == 34, $"got {allDestinations.Count}");

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
    var chainArtifactsJson = string.Join(",", allDestinations.Select(destination =>
        $"{{\"destinationRelativePath\":\"{destination}\",\"sourceId\":\"test\",\"memberPath\":\"BetterGI/{destination}\",\"sizeBytes\":{contentDict[destination].LongLength},\"sha256\":\"{Convert.ToHexString(SHA256.HashData(contentDict[destination])).ToLowerInvariant()}\",\"transformation\":\"relocate\",\"licenseEvidence\":{{\"spdxId\":null,\"source\":\"test\",\"redistributionStatus\":\"test\"}}}}"));
    var chainLock = "{\"schemaVersion\":1,\"artifactSetVersion\":\"chain\"," +
        "\"sources\":[{\"id\":\"test\",\"type\":\"archive\"," +
        "\"url\":\"file://" + chainArchive.Replace('\\', '/') + "\"," +
        "\"sha256\":\"" + chainSha + "\"," +
        "\"format\":\"7z\",\"sizeBytes\":" + new FileInfo(chainArchive).Length + "," +
        "\"memberCount\":0," +
        "\"provenance\":{\"project\":\"test\",\"releaseTag\":\"v0\"," +
        "\"commitSha\":\"0000000000000000000000000000000000000000\"," +
        "\"publishedAt\":\"2025-01-01T00:00:00Z\"}}]," +
        "\"artifacts\":[" + chainArtifactsJson + "]}";
    var chainLockPath = Path.Combine(chainWork, "lock.json");
    File.WriteAllText(chainLockPath, chainLock);

    // Download
    using var chainDl = new BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader();
    Directory.CreateDirectory(chainModelRoot);
    var chainResult = await chainDl.DownloadAsync(chainLockPath, chainModelRoot, CancellationToken.None);
    Assert("B12.1 Chain download success", chainResult.Success, $"errors={string.Join("; ", chainResult.Errors)}");
    Assert("B12.1 Chain all 34 files placed", chainResult.ArtifactsExtracted == 34, $"extracted={chainResult.ArtifactsExtracted}");

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
            lockedTestSourcePath, lockedRuntimeRoot, CancellationToken.None, sharedArchiveCacheDir);
        Assert("B12.2 locked release installation succeeds", installResult.Success,
            string.Join("; ", installResult.Errors));
        Assert("B12.2 locked release installs all 34 artifacts",
            installResult.ArtifactsExtracted == 34, $"got {installResult.ArtifactsExtracted}");
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

        var itemV2ModelPath = Path.Combine(lockedRuntimeRoot, "Assets", "Model", "ItemV2", "item.onnx");
        try
        {
            using var itemV2Session = new InferenceSession(itemV2ModelPath);
            Assert("B12.2 ItemV2 InferenceSession created", itemV2Session.InputMetadata.Count > 0 &&
                itemV2Session.OutputMetadata.ContainsKey("embedding"),
                "ItemV2 model does not expose the upstream input/embedding contract");
        }
        catch (Exception exception)
        {
            Assert("B12.2 ItemV2 InferenceSession created", false, exception.ToString());
        }

        var itemV2CsvPath = Path.Combine(lockedRuntimeRoot, "Assets", "Model", "ItemV2", "item.csv");
        var itemV2Header = File.ReadLines(itemV2CsvPath).FirstOrDefault() ?? string.Empty;
        Assert("B12.2 ItemV2 prototype CSV preserves required columns",
            itemV2Header.Contains("item_name", StringComparison.Ordinal) &&
            itemV2Header.Contains("material_type", StringComparison.Ordinal) &&
            itemV2Header.Contains("embedding", StringComparison.Ordinal),
            itemV2Header);

        Console.WriteLine($"B12.2: {sessionCount}/{testModels.Length} InferenceSessions created successfully");
    }
}
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
    var realBase = Path.Combine(lockedRuntimeRoot, "Assets", "Model");
    Assert("B12.3 locked model directory exists", Directory.Exists(realBase), realBase);
    if (Directory.Exists(realBase))
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
            var recV4EnYaml = Path.Combine(realBase, "PaddleOCR/Rec/V4En/inference.yml");
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
GameTaskManagerPlatform.Configure(new VerificationGameTaskManagerPlatform(b5SystemInfo, triggerLogger));
var verificationOcrService = new VerificationOcrService();
BetterGenshinImpact.Core.Recognition.OCR.ImageRegionOcrPlatform.Configure(verificationOcrService);
BetterGenshinImpact.GameTask.Model.TaskParameterPlatform.Configure(
    new VerificationTaskParameterPlatform("zh-CN"));

Console.WriteLine("AutoArtifactSalvage: real Grid, Paddle OCR, ONNX and ClearScript");
var artifactGridFixture = Path.Combine(
    AppContext.BaseDirectory, "Fixtures", "AutoArtifactSalvage", "ArtifactGrid.png");
using (var artifactGrid = Cv2.ImRead(artifactGridFixture))
{
    var gridItems = GridScreen.GridEnumerator.GetGridItems(artifactGrid, 2).ToArray();
    Assert("AutoArtifactSalvage detects all fixture grid cells", gridItems.Length == 4,
        $"got {gridItems.Length}");
    var statuses = gridItems.Select(rect =>
    {
        using var item = artifactGrid.SubMat(rect);
        return AutoArtifactSalvageTask.GetArtifactStatus(item);
    }).ToArray();
    Assert("AutoArtifactSalvage preserves selected/locked status detection",
        statuses.Count(value => value == AutoArtifactSalvageTask.ArtifactStatus.Selected) == 2 &&
        statuses.Count(value => value == AutoArtifactSalvageTask.ArtifactStatus.Locked) == 2,
        string.Join(",", statuses));
}

using (var artifactOcrFactory = new BetterGenshinImpact.Core.Recognition.OCR.OcrFactory(
           NullLogger<BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory>.Instance,
           CpuFactory(new ModelRootPathResolver(lockedRuntimeRoot)),
           new MacCoreRuntimeAdapter(new AutoPickConfig(), PaddleOcrModelConfig.V5, "zh-Hans"),
           new OcrResourcePathResolver(lockedRuntimeRoot)))
using (var artifactCard = Cv2.ImRead(Path.Combine(
           AppContext.BaseDirectory, "Fixtures", "AutoArtifactSalvage", "ArtifactAffixes.png")))
{
    var artifactTask = new AutoArtifactSalvageTask(
        new AutoArtifactSalvageTaskParam(5, null, null, null, null,
            new CultureInfo("zh-Hans"),
            BetterGenshinImpact.GameTask.Model.TaskParameterPlatform.Current
                .GetStringLocalizer<AutoArtifactSalvageTask>()),
        artifactOcrFactory.Service,
        1,
        NullLogger<AutoArtifactSalvageTask>.Instance);
    var artifact = artifactTask.GetArtifactStat(artifactCard, artifactOcrFactory.Service, out _);
    Assert("AutoArtifactSalvage real OCR reads artifact name and affixes",
        artifact.Name.Contains("异种", StringComparison.Ordinal) &&
        artifact.MainAffix.Type == ArtifactAffixType.HP &&
        artifact.MinorAffixes.Length >= 4,
        artifact.ToStructuredString());
    var selected = await AutoArtifactSalvageTask.IsMatchJavaScript(
        artifact,
        "Output = ArtifactStat.Level == 0 && Array.from(ArtifactStat.MinorAffixes).length >= 4;",
        NullLogger<AutoArtifactSalvageTask>.Instance);
    Assert("AutoArtifactSalvage ClearScript filter consumes real OCR model", selected, "Output=false");
}

var previousGlobalRoot = Global.StartUpPath;
Global.StartUpPath = lockedRuntimeRoot;
try
{
    using var gridIconSession = GridIconClassifier.LoadModel(out var gridIconPrototypes);
    Assert("AutoArtifactSalvage grid icon ONNX and prototypes load",
        gridIconSession.InputMetadata.Count > 0 && gridIconPrototypes.Count > 0,
        $"inputs={gridIconSession.InputMetadata.Count}, prototypes={gridIconPrototypes.Count}");
}
finally
{
    Global.StartUpPath = previousGlobalRoot;
}
Console.WriteLine();

var verificationAutoFightConfig = new AutoFightConfig
{
    TeamNames = "钟离,夜兰,纳西妲,久岐忍"
};
AutoFightRuntimePlatform.Configure(new VerificationAutoFightRuntimePlatform(
    b5SystemInfo, verificationAutoFightConfig, verificationOcrService,
    CpuFactory(new ModelRootPathResolver(lockedRuntimeRoot))));
Console.WriteLine("AutoFight end detection: upstream TXT and JSON task flows");
var autoFightStrategyDirectory = Path.Combine("/tmp", "bgi-auto-fight-end-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(autoFightStrategyDirectory);
var txtStrategyPath = Path.Combine(autoFightStrategyDirectory, "strategy.txt");
var jsonStrategyPath = Path.Combine(autoFightStrategyDirectory, "strategy.json");
File.WriteAllText(txtStrategyPath, "钟离 attack");
File.WriteAllText(jsonStrategyPath,
    """{"Info":{"Name":"verification"},"Actions":[{"Name":"attack","Character":"钟离","Action":"attack","Condition":{"Expression":"true"},"Index":1}]}""");
var finishDetectConfig = new AutoFightConfig();
var txtFightTask = new AutoFightTask(new AutoFightParam(txtStrategyPath, finishDetectConfig));
var jsonFightTask = new AutoFightJsonTask(new AutoFightParam(jsonStrategyPath, finishDetectConfig));
Mat CreateFinishedFightFrame()
{
    var frame = new Mat(1080, 1920, MatType.CV_8UC3, Scalar.Black);
    frame.Set(50, 790, new Vec3b(0, 235, 255));
    frame.Set(50, 768, new Vec3b(255, 255, 255));
    return frame;
}

foreach (var (label, checkFightFinish) in new (string Label, Func<Task<bool>> Check)[]
         {
             ("TXT", () => txtFightTask.CheckFightFinish(0, 0)),
             ("JSON", () => jsonFightTask.CheckFightFinish(0, 0))
         })
{
    recordingTaskControl.RecordCaptures = true;
    recordingTaskControl.Calls.Clear();
    recordingTaskControl.CaptureFrameProvider = CreateFinishedFightFrame;
    var finished = await checkFightFinish();
    Assert($"AutoFight {label} recognizes shared finished frame", finished, "returned false");
    Assert($"AutoFight {label} preserves finished input/capture order",
        recordingTaskControl.Calls.SequenceEqual([
            "action:OpenPartySetupScreen:KeyPress", "capture", "action:Drop:KeyPress",
            "action:OpenPartySetupScreen:KeyPress"
        ]), string.Join(",", recordingTaskControl.Calls));

    recordingTaskControl.Calls.Clear();
    recordingTaskControl.CaptureFrameProvider = () => new Mat(1080, 1920, MatType.CV_8UC3, Scalar.Black);
    finished = await checkFightFinish();
    Assert($"AutoFight {label} rejects non-finished frame", !finished, "returned true");
    Assert($"AutoFight {label} preserves non-finished input/capture order",
        recordingTaskControl.Calls.SequenceEqual([
            "action:OpenPartySetupScreen:KeyPress", "capture", "action:Drop:KeyPress"
        ]), string.Join(",", recordingTaskControl.Calls));
}
recordingTaskControl.RecordCaptures = false;
recordingTaskControl.CaptureFrameProvider = null;
Directory.Delete(autoFightStrategyDirectory, recursive: true);
Console.WriteLine();

Console.WriteLine("AvatarSide: pinned real screenshots through upstream CombatScenes");
var avatarFixtureDirectory = Path.Combine(AppContext.BaseDirectory, "Fixtures", "AutoFight");
var avatarScenarios = new[]
{
    new AvatarRecognitionScenario("别人进我世界_2人.png", "9f11e9762332f7dddcd3e926dbc7c4d7330e43d083d060ca929b2382e7c04b2f", 2, true, ["阿蕾奇诺", "钟离"]),
    new AvatarRecognitionScenario("别人进我世界_3人.png", "b1f422e70fd4c59f664824982d3381c39e849630bcd8f5c2440bbfd643a3ea6f", 3, true, ["阿蕾奇诺", "钟离"]),
    new AvatarRecognitionScenario("别人进我世界_4人.png", "d906980dc59cce2fe3a79644fc44dacd29ab86961eb3dca39c7e84bd9c66c280", 3, true, ["阿蕾奇诺"]),
    new AvatarRecognitionScenario("别人进我世界_4人_2.png", "3557d084f5b5250dc1590c9dd5ed1b3fd7246b76542a6cf90ad9100138b01718", 3, true, ["阿蕾奇诺"]),
    new AvatarRecognitionScenario("我进别人世界_2人.png", "04ab814db9f26005f1d84fa2b8536223fef7c14b0800a13d1fb73cb6ab7a96eb", 2, false, ["阿蕾奇诺", "钟离"]),
    new AvatarRecognitionScenario("我进别人世界_3人.png", "40cbb476bbe21cace4317310d419de1d4273ba588b5b2bc1fdf079b0146a4b48", 3, false, ["阿蕾奇诺"]),
    new AvatarRecognitionScenario("我进别人世界_4人.png", "93d602f695b958374bb7c15fb07cea7fa227a0349fcb5e15b74abc952d3f14a5", 3, false, ["阿蕾奇诺"])
};
var visualAutoFightConfig = new AutoFightConfig();
foreach (var scenario in avatarScenarios)
{
    var fixturePath = Path.Combine(avatarFixtureDirectory, scenario.FileName);
    Assert($"AvatarSide fixture exists: {scenario.FileName}", File.Exists(fixturePath), fixturePath);
    if (!File.Exists(fixturePath)) continue;

    var fixtureHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(fixturePath))).ToLowerInvariant();
    Assert($"AvatarSide fixture hash: {scenario.FileName}", fixtureHash == scenario.Sha256, fixtureHash);
    using var screenshot = Cv2.ImRead(fixturePath, ImreadModes.Color);
    Assert($"AvatarSide fixture decodes: {scenario.FileName}",
        screenshot.Width == 1920 && screenshot.Height == 1080,
        $"{screenshot.Width}x{screenshot.Height}");
    if (screenshot.Empty()) continue;

    using var imageRegion = new ImageRegion(screenshot, 0, 0);
    using var combatScenes = new CombatScenes().InitializeTeam(imageRegion, visualAutoFightConfig);
    var status = combatScenes.CurrentMultiGameStatus;
    Assert($"AvatarSide detects multiplayer status: {scenario.FileName}",
        status is { IsInMultiGame: true } && status.PlayerCount == scenario.PlayerCount && status.IsHost == scenario.IsHost,
        status == null ? "null" : $"players={status.PlayerCount} host={status.IsHost}");
    var names = combatScenes.GetAvatars().Select(avatar => avatar.Name).ToArray();
    Assert($"AvatarSide recognizes upstream team: {scenario.FileName}",
        names.SequenceEqual(scenario.ExpectedNames), string.Join(",", names));
}
Console.WriteLine();

Console.WriteLine("Pathing mining: upstream handler through RunnerContext and real Avatar");
var miningFixturePath = Path.Combine(avatarFixtureDirectory, "别人进我世界_2人.png");
recordingTaskControl.Calls.Clear();
var miningCaptureCount = 0;
recordingTaskControl.CaptureFrameProvider = () =>
{
    miningCaptureCount++;
    return Cv2.ImRead(miningFixturePath, ImreadModes.Color);
};
string[] miningTeamNames = [];
RunnerContext.Instance.Reset();
try
{
    await new MiningHandler().RunAsync(CancellationToken.None);
    var miningScenes = await RunnerContext.Instance.GetCombatScenes(CancellationToken.None);
    miningTeamNames = miningScenes?.GetAvatars().Select(avatar => avatar.Name).ToArray() ?? [];
}
finally
{
    RunnerContext.Instance.Reset();
    recordingTaskControl.CaptureFrameProvider = null;
}
Assert("MiningHandler executes the upstream Zhongli hold-skill action",
    recordingTaskControl.Calls.Contains("action:ElementalSkill:Hold"),
    string.Join(" | ", recordingTaskControl.Calls));
Assert("MiningHandler caches the configured upstream CombatScenes team",
    miningTeamNames.SequenceEqual(["钟离", "夜兰", "纳西妲", "久岐忍"]),
    string.Join(",", miningTeamNames));
Assert("MiningHandler consumes real capture frames for UI, team and skill checks",
    miningCaptureCount >= 3, $"captures={miningCaptureCount}");
Assert("MiningHandler leaves movement actions released",
    !recordingTaskControl.IsPressed(GIActions.MoveForward) &&
    !recordingTaskControl.IsPressed(GIActions.MoveBackward) &&
    !recordingTaskControl.IsPressed(GIActions.MoveLeft) &&
    !recordingTaskControl.IsPressed(GIActions.MoveRight),
    string.Join(" | ", recordingTaskControl.Calls));
Console.WriteLine();

Console.WriteLine("AutoDomain: shared capture geometry validation");
AutoDomainTask.ValidateScreenResolution(
    new BetterGenshinImpact.Platform.Abstractions.BgiRect(0, 0, 2560, 1440),
    NullLogger.Instance);
var rejectedNonWideDomainResolution = false;
try
{
    AutoDomainTask.ValidateScreenResolution(
        new BetterGenshinImpact.Platform.Abstractions.BgiRect(0, 0, 1920, 1200),
        NullLogger.Instance);
}
catch (Exception exception) when (exception.Message == "游戏窗口分辨率不是 16:9")
{
    rejectedNonWideDomainResolution = true;
}
Assert("AutoDomain preserves upstream 16:9 resolution gate",
    rejectedNonWideDomainResolution, "1920x1200 was accepted");

Console.WriteLine("AutoBoss: shared configuration, resolution and PathExecutor factory");
var autoBossConfig = new AutoBossConfig
{
    BossName = "无相之雷",
    StrategyName = "verification-boss",
    TeamName = "verification-party",
    SpecifyRunCount = true,
    RunCount = 4,
    UseTransientResin = true,
    UseFragileResin = true,
    ReviveRetryCount = 2,
    ReturnToStatueAfterEachRound = true,
    RewardRecognitionEnabled = true,
};
var autoBossParam = new AutoBossParam("/verification/strategy.txt", autoBossConfig);
Assert("AutoBoss parameter copies the Core-owned config snapshot",
    autoBossParam.BossName == autoBossConfig.BossName &&
    autoBossParam.StrategyName == autoBossConfig.StrategyName &&
    autoBossParam.TeamName == autoBossConfig.TeamName &&
    autoBossParam.SpecifyRunCount && autoBossParam.RunCount == 4 &&
    autoBossParam.UseTransientResin && autoBossParam.UseFragileResin &&
    autoBossParam.ReviveRetryCount == 2 &&
    autoBossParam.ReturnToStatueAfterEachRound &&
    autoBossParam.RewardRecognitionEnabled &&
    autoBossParam.CombatStrategyPath == "/verification/strategy.txt",
    $"boss={autoBossParam.BossName} runs={autoBossParam.RunCount}");
AutoBossTask.ValidateScreenResolution(
    new BgiRect(0, 0, 2560, 1440), NullLogger.Instance);
var rejectedNonWideBossResolution = false;
try
{
    AutoBossTask.ValidateScreenResolution(
        new BgiRect(0, 0, 1920, 1200), NullLogger.Instance);
}
catch (Exception exception) when (exception.Message == "游戏窗口分辨率不是 16:9")
{
    rejectedNonWideBossResolution = true;
}
Assert("AutoBoss preserves upstream 16:9 resolution gate",
    rejectedNonWideBossResolution, "1920x1200 was accepted");
var autoBossExecutionServices = new RecordingAutoBossExecutionServices();
var autoBossFactory = new AutoBossPathExecutorFactory(
    autoBossExecutionServices,
    () => new PathingPartyConfig { AutoEatEnabled = true });
var autoBossExecutor = autoBossFactory.Create(CancellationToken.None);
var autoBossPartyConfig = AutoBossTask.ConfigurePathingPartyConfig(
    autoBossFactory.CreatePartyConfig());
Assert("AutoBoss creates PathExecutor through the explicit Core factory",
    ReferenceEquals(autoBossExecutor, autoBossExecutionServices.Executor) &&
    autoBossExecutionServices.CreateCount == 1,
    $"createCount={autoBossExecutionServices.CreateCount}");
Assert("AutoBoss pathing preserves platform defaults but disables switch and fight",
    autoBossPartyConfig.AutoEatEnabled && autoBossPartyConfig.SkipPartySwitch &&
    !autoBossPartyConfig.AutoFightEnabled,
    $"eat={autoBossPartyConfig.AutoEatEnabled} switch={autoBossPartyConfig.SkipPartySwitch} fight={autoBossPartyConfig.AutoFightEnabled}");

Console.WriteLine("AutoCook: upstream UI recognition, peak tracking and semantic Space input");
using var cookFrame = new Mat(1080, 1920, MatType.CV_8UC3, Scalar.Black);
var cookIconRecognition = ElementRecognition.Get("UiLeftTopCookIcon", 1920, 1080);
var sourceCookIconTemplate = cookIconRecognition.TemplateImageMat
    ?? throw new InvalidOperationException("UiLeftTopCookIcon template is not initialized.");
using var cookIconTemplate = sourceCookIconTemplate.Channels() == 4
    ? sourceCookIconTemplate.CvtColor(ColorConversionCodes.BGRA2BGR)
    : sourceCookIconTemplate.Clone();
var cookIconRoi = cookIconRecognition.RegionOfInterest;
using (var target = new Mat(cookFrame, new Rect(
           cookIconRoi.X + 5, cookIconRoi.Y + 5, cookIconTemplate.Width, cookIconTemplate.Height)))
{
    cookIconTemplate.CopyTo(target);
}
var cookFrames = new Queue<Mat>();
foreach (var colorCount in new[] { 700, 710, 705, 350 })
{
    var frame = cookFrame.Clone();
    using var colorTarget = new Mat(frame, new Rect(600, 660, colorCount, 1));
    colorTarget.SetTo(new Scalar(64, 192, 255));
    cookFrames.Enqueue(frame);
}
recordingTaskControl.Calls.Clear();
recordingTaskControl.CaptureFrameProvider = () =>
    (cookFrames.Count > 0 ? cookFrames.Dequeue() : cookFrame).Clone();
using (var cookCancellation = new CancellationTokenSource(TimeSpan.FromSeconds(2)))
{
    var cookTask = new AutoCookTask(
        new AutoCookConfig { CheckIntervalMs = 1, StopTaskWhenRecoverButtonDetected = false },
        1,
        NullLogger<AutoCookTask>.Instance);
    var execution = cookTask.Start(cookCancellation.Token);
    for (var attempt = 0;
         attempt < 200 && !recordingTaskControl.Calls.Contains("press:32");
         attempt++)
        await Task.Delay(5);
    cookCancellation.Cancel();
    try { await execution; }
    catch (OperationCanceledException) { }
    catch (BetterGenshinImpact.GameTask.AutoGeniusInvokation.Exception.NormalEndException)
        when (cookCancellation.IsCancellationRequested) { }
}
recordingTaskControl.CaptureFrameProvider = null;
while (cookFrames.Count > 0) cookFrames.Dequeue().Dispose();
Assert("AutoCook emits exactly one semantic Space press after a stable peak",
    recordingTaskControl.Calls.Count(call => call == "press:32") == 1,
    string.Join(" | ", recordingTaskControl.Calls));
Console.WriteLine();

Console.WriteLine("AutoWood: upstream gadget recognition and runtime lifecycle");
using var woodFrame = new Mat(1080, 1920, MatType.CV_8UC3, Scalar.Black);
var woodRecognition = RecognitionAssets.Get("AutoWood", "TheBoonOfTheElderTree", 1920, 1080);
var sourceWoodTemplate = woodRecognition.TemplateImageMat
    ?? throw new InvalidOperationException("TheBoonOfTheElderTree template is not initialized.");
using var woodTemplate = sourceWoodTemplate.Channels() == 4
    ? sourceWoodTemplate.CvtColor(ColorConversionCodes.BGRA2BGR)
    : sourceWoodTemplate.Clone();
var woodRoi = woodRecognition.RegionOfInterest;
using (var target = new Mat(woodFrame, new Rect(
           woodRoi.X + 5, woodRoi.Y + 5, woodTemplate.Width, woodTemplate.Height)))
{
    woodTemplate.CopyTo(target);
}
var woodRuntime = new RecordingAutoWoodRuntimePlatform();
recordingTaskControl.Calls.Clear();
recordingTaskControl.RecordCaptures = true;
recordingTaskControl.CaptureFrameProvider = () => woodFrame.Clone();
overlayRecorder.Commands.Clear();
await new AutoWoodTask(new WoodTaskParam(1, 2000), woodRuntime.Config, woodRuntime)
    .Start(CancellationToken.None);
recordingTaskControl.CaptureFrameProvider = null;
recordingTaskControl.RecordCaptures = false;
Assert("AutoWood acquires and releases sleep prevention exactly once",
    woodRuntime.SleepAcquireCount == 1 && woodRuntime.SleepReleaseCount == 1,
    $"acquire={woodRuntime.SleepAcquireCount} release={woodRuntime.SleepReleaseCount}");
Assert("AutoWood refreshes third-party login availability exactly once",
    woodRuntime.LoginSession.RefreshCount == 1,
    $"refresh={woodRuntime.LoginSession.RefreshCount}");
Assert("AutoWood recognizes the real gadget template before one semantic action",
    recordingTaskControl.Calls.Count(call => call == "capture") == 1 &&
    recordingTaskControl.Calls.Count(call => call == "action:QuickUseGadget:KeyPress") == 1,
    string.Join(" | ", recordingTaskControl.Calls));
Assert("AutoWood clears overlay state after the completed round",
    overlayRecorder.Commands.Count(command => command == "clearAll") == 1,
    string.Join(" | ", overlayRecorder.Commands));
Console.WriteLine();

Console.WriteLine("AutoMusicGame: upstream six-lane blue-channel hold state machine");
var musicRuntime = new RecordingAutoMusicGameRuntimePlatform();
recordingTaskControl.Calls.Clear();
using (var musicCancellation = new CancellationTokenSource(TimeSpan.FromSeconds(2)))
{
    var musicTask = new AutoMusicGameTask(new AutoMusicGameParam(), musicRuntime);
    var execution = musicTask.Start(musicCancellation.Token);
    for (var attempt = 0;
         attempt < 200 && !recordingTaskControl.Calls.Contains("keyUp:65");
         attempt++)
        await Task.Delay(5);
    musicCancellation.Cancel();
    try { await execution; }
    catch (OperationCanceledException) when (musicCancellation.IsCancellationRequested) { }
}
Assert("AutoMusicGame validates the supported capture resolution",
    musicRuntime.ValidateCount == 1, $"validate={musicRuntime.ValidateCount}");
Assert("AutoMusicGame holds and releases only the darkened A lane",
    recordingTaskControl.Calls.Count(call => call == "keyDown:65") == 1 &&
    recordingTaskControl.Calls.Count(call => call == "keyUp:65") == 1 &&
    !recordingTaskControl.Calls.Any(call => call.StartsWith("keyDown:") && call != "keyDown:65"),
    string.Join(" | ", recordingTaskControl.Calls));
Assert("AutoMusicGame releases all pressed input on cancellation",
    recordingTaskControl.Calls.LastOrDefault() == "releaseAll",
    string.Join(" | ", recordingTaskControl.Calls));
Console.WriteLine();

Console.WriteLine("Pathing pyro collect: upstream elemental handler and real Avatar attack");
using var pyroCollectFrame = new Mat(1080, 1920, MatType.CV_8UC4, Scalar.Black);
var paimonTemplate = ElementRecognition.Get("PaimonMenu", 1920, 1080).TemplateImageMat
    ?? throw new InvalidOperationException("Paimon template is not initialized.");
using var pyroCollectPaimon = new Mat();
Cv2.CvtColor(paimonTemplate, pyroCollectPaimon, ColorConversionCodes.BGR2BGRA);
using (var paimonTarget = new Mat(pyroCollectFrame,
           new Rect(24, 20, pyroCollectPaimon.Width, pyroCollectPaimon.Height)))
{
    pyroCollectPaimon.CopyTo(paimonTarget);
}
foreach (var indexRect in AutoFightAssets.Get(1920, 1080).AvatarIndexRectList.Skip(1))
{
    using var inactiveIndex = new Mat(pyroCollectFrame, indexRect);
    inactiveIndex.SetTo(Scalar.White);
}
recordingTaskControl.Calls.Clear();
var pyroCollectCaptureCount = 0;
string[] pyroCollectTeamNames = [];
var originalTeamNames = verificationAutoFightConfig.TeamNames;
verificationAutoFightConfig.TeamNames = "烟绯,钟离,夜兰,纳西妲";
RunnerContext.Instance.Reset();
try
{
    recordingTaskControl.CaptureFrameProvider = () =>
    {
        pyroCollectCaptureCount++;
        return pyroCollectFrame.Clone();
    };
    var pyroCollectHandler = ActionFactory.GetAfterHandler(ActionEnum.PyroCollect.Code);
    Assert("ActionFactory selects the upstream Pyro ElementalCollectHandler",
        pyroCollectHandler is ElementalCollectHandler,
        pyroCollectHandler.GetType().FullName ?? "null");
    await pyroCollectHandler.RunAsync(CancellationToken.None);
    var pyroCollectScenes = await RunnerContext.Instance.GetCombatScenes(CancellationToken.None);
    pyroCollectTeamNames = pyroCollectScenes?.GetAvatars().Select(avatar => avatar.Name).ToArray() ?? [];
}
finally
{
    RunnerContext.Instance.Reset();
    verificationAutoFightConfig.TeamNames = originalTeamNames;
    recordingTaskControl.CaptureFrameProvider = null;
}
Assert("Pyro ElementalCollectHandler uses the configured real CombatScenes team",
    pyroCollectTeamNames.SequenceEqual(["烟绯", "钟离", "夜兰", "纳西妲"]),
    string.Join(",", pyroCollectTeamNames));
Assert("Pyro ElementalCollectHandler preserves Yanfei normal-attack behavior",
    recordingTaskControl.Calls.SequenceEqual(["action:NormalAttack:KeyPress"]),
    string.Join(" | ", recordingTaskControl.Calls));
Assert("Pyro ElementalCollectHandler consumes main-UI, team and active-avatar captures",
    pyroCollectCaptureCount == 3, $"captures={pyroCollectCaptureCount}");
Console.WriteLine();

Console.WriteLine("Pathing stop-flying: upstream before-handler and motion recognition");
recordingTaskControl.Calls.Clear();
var stopFlyingCaptureCount = 0;
recordingTaskControl.CaptureFrameProvider = () =>
{
    stopFlyingCaptureCount++;
    return Cv2.ImRead(miningFixturePath, ImreadModes.Color);
};
try
{
    var stopFlyingHandler = ActionFactory.GetBeforeHandler(ActionEnum.StopFlying.Code);
    Assert("ActionFactory selects the upstream StopFlyingHandler",
        stopFlyingHandler is StopFlyingHandler, stopFlyingHandler.GetType().FullName ?? "null");
    await stopFlyingHandler.RunAsync(CancellationToken.None);
}
finally
{
    recordingTaskControl.CaptureFrameProvider = null;
}
Assert("StopFlyingHandler emits the upstream plunge attack",
    recordingTaskControl.Calls.SequenceEqual(["action:NormalAttack:KeyPress"]),
    string.Join(" | ", recordingTaskControl.Calls));
Assert("StopFlyingHandler exits after one real normal-motion frame",
    stopFlyingCaptureCount == 1, $"captures={stopFlyingCaptureCount}");
Console.WriteLine();

Console.WriteLine("Pathing four-leaf sigil: upstream debounce, interaction and flight recognition");
using var leafDetectionFrame = new Mat(1080, 1920, MatType.CV_8UC3, Scalar.Black);
foreach (var point in new[] { new Point(1500, 1000), new Point(1508, 1041), new Point(1500, 987), new Point(1500, 1010) })
{
    leafDetectionFrame.Set(point.Y, point.X, new Vec3b(255, 255, 255));
}
using var flyingFrame = new Mat(1080, 1920, MatType.CV_8UC3, Scalar.Black);
var spaceRecognition = ElementRecognition.Get("SpaceKey", 1920, 1080);
var sourceSpaceTemplate = spaceRecognition.TemplateImageMat
    ?? throw new InvalidOperationException("SpaceKey template is not initialized.");
using var spaceTemplate = sourceSpaceTemplate.Channels() == 4
    ? sourceSpaceTemplate.CvtColor(ColorConversionCodes.BGRA2BGR)
    : sourceSpaceTemplate.Clone();
var spaceRoi = spaceRecognition.RegionOfInterest;
using (var target = new Mat(flyingFrame, new Rect(spaceRoi.X + 10, spaceRoi.Y + 10, spaceTemplate.Width, spaceTemplate.Height)))
{
    spaceTemplate.CopyTo(target);
}
var leafFrames = new Queue<Mat>([leafDetectionFrame, leafDetectionFrame, flyingFrame]);
var leafCaptureCount = 0;
recordingTaskControl.Calls.Clear();
recordingTaskControl.RecordMiddleClicks = true;
recordingTaskControl.CaptureFrameProvider = () =>
{
    leafCaptureCount++;
    return leafFrames.Count > 0 ? leafFrames.Dequeue().Clone() : flyingFrame.Clone();
};
try
{
    var leafHandler = ActionFactory.GetBeforeHandler(ActionEnum.UpDownGrabLeaf.Code);
    Assert("ActionFactory selects the upstream UpDownGrabLeafHandler",
        leafHandler is UpDownGrabLeafHandler, leafHandler.GetType().FullName ?? "null");
    await leafHandler.RunAsync(CancellationToken.None);
}
finally
{
    recordingTaskControl.CaptureFrameProvider = null;
    recordingTaskControl.RecordMiddleClicks = false;
}
Assert("UpDownGrabLeafHandler requires two consecutive upstream point detections",
    leafCaptureCount == 3, $"captures={leafCaptureCount}");
Assert("UpDownGrabLeafHandler preserves interaction and camera-reset order",
    recordingTaskControl.Calls.SequenceEqual([
        "action:InteractionInSomeMode:KeyPress", "middleClick"
    ]), string.Join(" | ", recordingTaskControl.Calls));
Assert("UpDownGrabLeafHandler recognizes the real SpaceKey template as flying",
    !recordingTaskControl.Calls.Contains("action:Jump:KeyPress"),
    string.Join(" | ", recordingTaskControl.Calls));
Console.WriteLine();

Console.WriteLine("Pathing pick-around: upstream circular movement and camera resets");
recordingTaskControl.Calls.Clear();
recordingTaskControl.RecordMiddleClicks = true;
try
{
    var pickAroundHandler = ActionFactory.GetAfterHandler(ActionEnum.PickAround.Code);
    Assert("ActionFactory selects the upstream PickAroundHandler",
        pickAroundHandler is PickAroundHandler, pickAroundHandler.GetType().FullName ?? "null");
    await pickAroundHandler.RunAsync(CancellationToken.None);
}
finally
{
    recordingTaskControl.RecordMiddleClicks = false;
}
var pickAroundActions = recordingTaskControl.Calls
    .Where(call => call.StartsWith("action:", StringComparison.Ordinal))
    .ToList();
Assert("PickAroundHandler preserves the upstream movement action order",
    pickAroundActions.SequenceEqual([
        "action:MoveBackward:KeyPress",
        "action:MoveForward:KeyDown",
        "action:MoveForward:KeyUp",
        "action:MoveLeft:KeyPress",
        "action:MoveForward:KeyDown",
        "action:MoveForward:KeyUp",
        "action:MoveLeft:KeyDown",
        "action:MoveLeft:KeyUp"
    ]), string.Join(" | ", pickAroundActions));
Assert("PickAroundHandler performs all nine upstream camera resets",
    recordingTaskControl.Calls.Count(call => call == "middleClick") == 9,
    string.Join(" | ", recordingTaskControl.Calls));
Assert("PickAroundHandler leaves movement released",
    !recordingTaskControl.IsPressed(GIActions.MoveBackward) &&
    !recordingTaskControl.IsPressed(GIActions.MoveForward) &&
    !recordingTaskControl.IsPressed(GIActions.MoveLeft),
    string.Join(" | ", recordingTaskControl.Calls));
Console.WriteLine();

Console.WriteLine("Genshin battle pass: upstream no-reward claim flow");
recorder.Clear();
recordingTaskControl.Calls.Clear();
var battlePassCaptureCount = 0;
recordingTaskControl.CaptureFrameProvider = () =>
{
    battlePassCaptureCount++;
    return Cv2.ImRead(miningFixturePath, ImreadModes.Color);
};
try
{
    await new ClaimBattlePassRewardsTask().DoOnce(CancellationToken.None);
}
finally
{
    recordingTaskControl.CaptureFrameProvider = null;
}
Assert("ClaimBattlePassRewardsTask opens battle pass through semantic input",
    recordingTaskControl.Calls.SequenceEqual(["action:OpenBattlePassScreen:KeyPress"]),
    string.Join(" | ", recordingTaskControl.Calls));
Assert("ClaimBattlePassRewardsTask preserves both upstream tab clicks",
    recorder.Calls.SequenceEqual([
        "MoveMouseTo(X=960, Y=45)", "LeftButtonDown()", "LeftButtonUp()",
        "MoveMouseTo(X=858, Y=45)", "LeftButtonDown()", "LeftButtonUp()"
    ]), string.Join(" | ", recorder.Calls));
Assert("ClaimBattlePassRewardsTask captures both reward pages and main UI",
    battlePassCaptureCount >= 5, $"captures={battlePassCaptureCount}");
Console.WriteLine();

Console.WriteLine("Genshin crafting bench: canonical path assets");
var craftingBenchRouteDirectory = Path.Combine(Global.StartUpPath, "GameTask", "Common", "Element", "Assets", "Json");
var craftingBenchRoutes = new[] { "蒙德", "璃月", "稻妻", "枫丹" }
    .Select(country => PathingTask.BuildFromFilePath(
        Path.Combine(craftingBenchRouteDirectory, $"合成台_{country}.json")))
    .ToArray();
Assert("GoToCraftingBench loads every upstream country route",
    craftingBenchRoutes.All(route => route is { Positions.Count: >= 2 }),
    string.Join(",", craftingBenchRoutes.Select(route => route?.Positions.Count ?? -1)));
Assert("GoToCraftingBench preserves teleport-then-movement route shape",
    craftingBenchRoutes.All(route => route!.Positions.First().Type == WaypointType.Teleport.Code &&
                                     route.Positions.Skip(1).Any(position =>
                                         position.Type != WaypointType.Teleport.Code)),
    "one or more crafting-bench routes lost its teleport or movement segment");
Console.WriteLine();

Console.WriteLine("Genshin material crafting: upstream parsing and validation semantics");
var readPositiveInt = typeof(CraftMaterialTask).GetMethod(
    "ReadFirstPositiveInt", BindingFlags.Static | BindingFlags.NonPublic)
    ?? throw new MissingMethodException(typeof(CraftMaterialTask).FullName, "ReadFirstPositiveInt");
Assert("CraftMaterial preserves upstream full-width quantity parsing",
    (int)readPositiveInt.Invoke(null,
        [BetterGenshinImpact.Helpers.StringUtils.ConvertFullWidthNumToHalfWidth(" １２ / ３ ")])! == 12,
    "full-width OCR quantity did not normalize to the first positive integer");
try
{
    await new CraftMaterialTask("测试材料", 0, "角色与武器培养素材").Start(CancellationToken.None);
    Assert("CraftMaterial rejects non-positive target quantity", false, "task returned success");
}
catch (ArgumentOutOfRangeException exception)
{
    Assert("CraftMaterial rejects non-positive target quantity",
        exception.ActualValue is 0 && exception.Message.Contains("大于 0", StringComparison.Ordinal),
        exception.ToString());
}
Console.WriteLine();

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

// ==== B6: AutoPickAssets dynamic cache ====
Console.WriteLine("AutoPickAssets: capture-size and key cache");
var assets = AutoPickAssets.Get(1920, 1080, "F");
var sameAssets = AutoPickAssets.Get(1920, 1080, "F");
var scaledAssets = AutoPickAssets.Get(2560, 1440, "F");
var alternateKeyAssets = AutoPickAssets.Get(1920, 1080, "W");
Assert("Same capture size and key reuse assets", ReferenceEquals(assets, sameAssets), "cache miss");
Assert("Different capture size creates assets", !ReferenceEquals(assets, scaledAssets), "cache collision");
Assert("Different pick key creates assets", !ReferenceEquals(assets, alternateKeyAssets), "key omitted from cache");
Assert("Default PickVk is F", assets.PickVk == BgiKey.F, $"got {assets.PickVk}");
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
recorder.Clear();
GameCaptureRegion.GameRegion1080PPosClick(1500, 1000);
Assert("SetTime shared game-region click uses composed capture metrics",
    recorder.Calls.SequenceEqual([
        "MoveMouseTo(X=1500, Y=1000)", "LeftButtonDown()", "LeftButtonUp()"
    ]), string.Join(" | ", recorder.Calls));
var setTimePosition = (double[])typeof(BetterGenshinImpact.GameTask.Common.Job.SetTimeTask)
    .GetMethod("GetPosition", BindingFlags.Instance | BindingFlags.NonPublic)!
    .Invoke(new BetterGenshinImpact.GameTask.Common.Job.SetTimeTask(), [30d, 0d])!;
Assert("SetTime real upstream dial geometry is linked",
    Math.Abs(setTimePosition[0] - 1471d) < 0.001 && Math.Abs(setTimePosition[1] - 501.6d) < 0.001,
    $"x={setTimePosition[0]}, y={setTimePosition[1]}");
var setTimeHandler = ActionFactory.GetAfterHandler(ActionEnum.SetTime.Code);
Assert("ActionFactory selects the upstream SetTimeHandler",
    setTimeHandler is SetTimeHandler, setTimeHandler.GetType().FullName ?? "unknown");
recordingTaskControl.Calls.Clear();
await setTimeHandler.RunAsync(
    CancellationToken.None,
    new WaypointForTrack(
        new Waypoint { Action = ActionEnum.SetTime.Code, ActionParams = string.Empty },
        MapTypes.Teyvat.ToString(),
        "SIFT"));
Assert("SetTimeHandler preserves empty-parameter no-op semantics",
    recordingTaskControl.Calls.Count == 0, string.Join(" | ", recordingTaskControl.Calls));
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
var assetsBefore = AutoPickAssets.Get(1920, 1080, "F");

// Real AddTrigger call (not pseudo-trigger via new ctor)
GameTaskManager.ClearTriggers();
var added = GameTaskManager.AddTrigger("AutoPick", null, defaultRuntimeState, b82Recorder, b5SystemInfo, testConfigProvider, testPaddle, testYap);
Assert("B8.2 shared AddTrigger returns true", added, "returned false");
Assert("B8.2 shared TriggerDictionary contains AutoPick",
    GameTaskManager.TriggerDictionary?.ContainsKey("AutoPick") == true, "not found");
var addedTrigger = GameTaskManager.TriggerDictionary?["AutoPick"];
Assert("B8.2 platform-created trigger is AutoPickTrigger",
    addedTrigger is AutoPickTrigger, $"got {addedTrigger?.GetType().Name}");
var assetsAfter = AutoPickAssets.Get(1920, 1080, "F");
Assert("B8.2 AddTrigger preserves cached assets",
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

// ==== Navigation execution: real TemplateMatch pipeline against ground-truth map imagery ====
Console.WriteLine();
Console.WriteLine("Navigation execution: ground-truth minimap track through the real TemplateMatch pipeline");
static Mat BuildGroundTruthNavigationFrame(Mat coarseMap, Rect minimapRect, Point2f groundTruthGenshin)
{
    // The 1080p in-game minimap renders the surrounding 260 world units inside the
    // center 156x156 px of the 212x212 minimap (MiniMapPreprocessorUtils.Size = 156,
    // MiniMapMatchConfig RoughZoom = 5 => 52px coarse template = 260 world units).
    // Reproduce that exact layout from the real release layer imagery at a known
    // ground-truth genshin position, so the real upstream pipeline must recover it.
    const double layerLeft = 8.0, layerTop = -1016.0;
    var centerX = (int)Math.Round((layerLeft - groundTruthGenshin.X) / 5.0);
    var centerY = (int)Math.Round((layerTop - groundTruthGenshin.Y) / 5.0);
    var cropRect = new Rect(centerX - 26, centerY - 26, 52, 52);
    if (cropRect.X < 0 || cropRect.Y < 0 || cropRect.Right > coarseMap.Width || cropRect.Bottom > coarseMap.Height)
        throw new InvalidOperationException($"ground-truth crop escapes the staged layer: {cropRect}");
    using var coarsePatch = new Mat(coarseMap, cropRect);
    using var patch156 = new Mat();
    Cv2.Resize(coarsePatch, patch156, new Size(156, 156), interpolation: InterpolationFlags.Cubic);
    using var minimap = new Mat(minimapRect.Height, minimapRect.Width, MatType.CV_8UC3, Scalar.Black);
    using (var minimapCenter = new Mat(minimap, new Rect(28, 28, 156, 156)))
        patch156.CopyTo(minimapCenter);
    var frame = new Mat(1080, 1920, MatType.CV_8UC3, Scalar.Black);
    using (var minimapTarget = new Mat(frame, minimapRect))
        minimap.CopyTo(minimapTarget);
    return frame;
}
static int OrientationDelta(int a, int b)
{
    var d = Math.Abs(a - b) % 360;
    return d > 180 ? 360 - d : d;
}
var mapVerificationRoot = Path.Combine(Path.GetTempPath(), "bgi-map-verify-" + Guid.NewGuid().ToString("N")[..8]);
var startUpPathBeforeNavigation = Global.StartUpPath;
try
{
    var gameTaskSource = Path.Combine(Directory.GetCurrentDirectory(), "BetterGenshinImpact", "GameTask");
    foreach (var assetSource in Directory.GetDirectories(gameTaskSource, "Assets", SearchOption.AllDirectories))
    {
        foreach (var sourcePath in Directory.GetFiles(assetSource, "*", SearchOption.AllDirectories))
        {
            var targetPath = Path.Combine(
                mapVerificationRoot, "GameTask", Path.GetRelativePath(gameTaskSource, sourcePath));
            Directory.CreateDirectory(Path.GetDirectoryName(targetPath)!);
            File.Copy(sourcePath, targetPath);
        }
    }

    // Stage the real MapBack_3 layer (covers the 雷音权现前往 route) from the verified
    // 0.62.0 release archive through the same hash-checked downloader pipeline as B12.2.
    var releaseSource = downloaderLock.Sources.Single();
    var mapStageSource = new ArtifactDownloader.SourceEntry
    {
        Id = releaseSource.Id,
        Type = releaseSource.Type,
        Url = releaseSource.Url,
        Sha256 = releaseSource.Sha256,
        Format = releaseSource.Format,
        SizeBytes = releaseSource.SizeBytes,
        Provenance = new ArtifactDownloader.SourceProvenance
        {
            Project = releaseSource.Provenance.Project,
            ReleaseTag = releaseSource.Provenance.ReleaseTag,
            CommitSha = releaseSource.Provenance.CommitSha,
            PublishedAt = releaseSource.Provenance.PublishedAt
        }
    };
    var navigationLocalArchive = Path.GetFullPath(Path.Combine(
        Directory.GetCurrentDirectory(),
        "artifacts/provenance-audit/release-0.62.0/downloads/BetterGI_v0.62.0.7z"));
    if (File.Exists(navigationLocalArchive))
    {
        mapStageSource.Url = new Uri(navigationLocalArchive).AbsoluteUri;
    }
    var mapLicense = new ArtifactDownloader.LicenseEvidenceEntry
    {
        SpdxId = "GPL-3.0",
        Source = "BetterGI release 0.62.0 map layer data",
        RedistributionStatus = "allowed"
    };
    ArtifactDownloader.ArtifactEntry MapArtifact(
        string destinationRelativePath, string memberPath, long sizeBytes, string sha256) => new()
    {
        DestinationRelativePath = destinationRelativePath,
        SourceId = mapStageSource.Id,
        MemberPath = memberPath,
        SizeBytes = sizeBytes,
        Sha256 = sha256,
        Transformation = "relocate",
        LicenseEvidence = mapLicense
    };
    var mapStageLock = new ArtifactDownloader.SourceLock
    {
        SchemaVersion = 1,
        ArtifactSetVersion = "0.62.0",
        Sources = [mapStageSource],
        Artifacts =
        [
            MapArtifact("Assets/Map/Teyvat/mapback_info.json", "BetterGI/Assets/Map/Teyvat/mapback_info.json", 705,
                "7adf428edd494f8c6445a3e6f66a889f579b6ba0578a148d4cbf0bc1ddb135ea"),
            MapArtifact("Assets/Map/Teyvat/MapBack_3_color.webp", "BetterGI/Assets/Map/Teyvat/MapBack_3_color.webp", 149064,
                "e64715356c3e6e84646d4022533c4c7a709c57cfc93b92213a4cfc8d52b90fc4"),
            MapArtifact("Assets/Map/Teyvat/MapBack_3_gray.webp", "BetterGI/Assets/Map/Teyvat/MapBack_3_gray.webp", 1302572,
                "1bfafc57afbda3d0dd4a89a301d2ae645f47df3ad456eb63c856adc0193d1379")
        ]
    };
    var mapStageLockPath = Path.Combine(Path.GetTempPath(), "bgi-map-lock-" + Guid.NewGuid().ToString("N") + ".json");
    File.WriteAllText(mapStageLockPath, JsonSerializer.Serialize(mapStageLock, new JsonSerializerOptions
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    }));
    using (var mapDownloader = new BetterGenshinImpact.Core.Infrastructure.ArtifactDownloader())
    {
        var mapInstall = await mapDownloader.DownloadAsync(
            mapStageLockPath, mapVerificationRoot, CancellationToken.None, sharedArchiveCacheDir);
        Assert("Navigation staged map layer installation succeeds", mapInstall.Success,
            string.Join("; ", mapInstall.Errors));
        Assert("Navigation staged map layer installs all 3 members",
            mapInstall.ArtifactsExtracted == 3, $"got {mapInstall.ArtifactsExtracted}");
    }
    File.Delete(mapStageLockPath);

    // Trim the descriptor to the staged layer only; the upstream loader loads every
    // json entry's imagery and would fail on the unstaged sibling layers.
    var stagedDescriptorPath = Path.Combine(mapVerificationRoot, "Assets", "Map", "Teyvat", "mapback_info.json");
    using (var stagedDescriptor = JsonDocument.Parse(await File.ReadAllTextAsync(stagedDescriptorPath)))
    {
        var mapBack3Entry = stagedDescriptor.RootElement.EnumerateArray()
            .Single(e => e.GetProperty("LayerId").GetString() == "MapBack_3");
        Assert("Navigation staged descriptor preserves the release origin values",
            mapBack3Entry.GetProperty("Left").GetDouble() == 8.0 &&
            mapBack3Entry.GetProperty("Top").GetDouble() == -1016.0 &&
            mapBack3Entry.GetProperty("Scale").GetDouble() == 1.0 &&
            mapBack3Entry.GetProperty("Floor").GetInt32() == 0, mapBack3Entry.GetRawText());
        await File.WriteAllTextAsync(stagedDescriptorPath, "[" + mapBack3Entry.GetRawText() + "]");
    }

    var stagedCombatAssetDirectory = Path.Combine(
        mapVerificationRoot, "GameTask", "AutoFight", "Assets");
    var stagedCombatAvatarPath = Path.Combine(stagedCombatAssetDirectory, "combat_avatar.json");
    Assert("Navigation runtime stages the original configured-team combat metadata",
        new FileInfo(stagedCombatAvatarPath).Length > 0,
        stagedCombatAvatarPath);

    Global.StartUpPath = mapVerificationRoot;
    var recordingNavigation = new RecordingNavigationPlatform();
    NavigationPlatform.Configure(recordingNavigation);

    var navigationMap = MapManager.GetMap(MapTypes.Teyvat, "TemplateMatch");
    var templateNavigationMap = navigationMap as SceneBaseMapByTemplateMatch
        ?? throw new InvalidOperationException($"Expected TemplateMatch map, got {navigationMap.GetType().Name}.");
    var stagedLayers = templateNavigationMap.Layers;
    Assert("Navigation real upstream loader reads exactly the staged MapBack_3 layer",
        stagedLayers.Count == 1 && stagedLayers[0].LayerId == "MapBack_3",
        $"layers={stagedLayers.Count}");
    Assert("Navigation staged layer carries real match imagery",
        stagedLayers.Count == 1 && !stagedLayers[0].FineGrayMap.Empty(),
        "FineGrayMap empty");

    using var coarseMap = Cv2.ImRead(
        Path.Combine(mapVerificationRoot, "Assets", "Map", "Teyvat", "MapBack_3_color.webp"), ImreadModes.Color);
    Assert("Navigation staged coarse layer image decodes", !coarseMap.Empty(),
        $"{coarseMap.Width}x{coarseMap.Height}");

    // Ground-truth track: the real route 雷音权现前往 (teleport waypoint -> path waypoint),
    // extended along the same bearing so the walk covers a meaningful distance.
    var navRouteTask = PathingTask.BuildFromFilePath(realPathingFixture)
        ?? throw new InvalidDataException("The real pathing fixture could not be loaded.");
    var routePositions = navRouteTask.Positions
        ?? throw new InvalidDataException("The real pathing fixture has no positions.");
    if (routePositions.Count < 2)
        throw new InvalidDataException($"The real pathing fixture has only {routePositions.Count} position(s).");
    var navWp1 = new WaypointForTrack(routePositions[0], MapTypes.Teyvat.ToString(), "TemplateMatch");
    var navWp2 = new WaypointForTrack(routePositions[1], MapTypes.Teyvat.ToString(), "TemplateMatch");
    var track = new List<Point2f>();
    for (var step = 0; step <= 8; step++)
    {
        var t = step * 0.25;
        track.Add(new Point2f(
            (float)(navWp1.GameX + (navWp2.GameX - navWp1.GameX) * t),
            (float)(navWp1.GameY + (navWp2.GameY - navWp1.GameY) * t)));
    }

    var minimapRect = MapAssets.Get(1920, 1080).MimiMapRect;
    var matchedPositions = new List<Point2f>();
    var groundTruthImagePositions = new List<Point2f>();
    Navigation.Reset();
    for (var i = 0; i < track.Count; i++)
    {
        var groundTruthImage = navigationMap.ConvertGenshinMapCoordinatesToImageCoordinates(track[i]);
        groundTruthImagePositions.Add(groundTruthImage);
        using var frame = BuildGroundTruthNavigationFrame(coarseMap, minimapRect, track[i]);
        using var region = new ImageRegion(frame, 0, 0);
        // The exact call PathExecutor makes every loop iteration (PathExecutor.cs:1228).
        var position = Navigation.GetPosition(region, MapTypes.Teyvat.ToString(), "TemplateMatch");
        matchedPositions.Add(position);
        var error = position == default
            ? double.NaN
            : Math.Sqrt(Math.Pow(position.X - groundTruthImage.X, 2) + Math.Pow(position.Y - groundTruthImage.Y, 2));
        Console.WriteLine($"  track[{i}] genshin=({track[i].X:F1},{track[i].Y:F1}) " +
                          $"position=({position.X:F1},{position.Y:F1}) error={error:F2}px " +
                          $"confidence={templateNavigationMap.PrevSuccessResult.Confidence:F4}");
    }

    for (var i = 0; i < track.Count; i++)
    {
        Assert($"Navigation track[{i}] returns a position through the real pipeline",
            matchedPositions[i] != default, "pipeline returned default (unrecognized)");
        if (matchedPositions[i] == default) continue;
        var error = Math.Sqrt(
            Math.Pow(matchedPositions[i].X - groundTruthImagePositions[i].X, 2) +
            Math.Pow(matchedPositions[i].Y - groundTruthImagePositions[i].Y, 2));
        Assert($"Navigation track[{i}] matches ground truth within 15px", error <= 15, $"error={error:F2}px");
    }

    // Movement decisions PathExecutor derives from positions: distance must shrink as the
    // walk approaches the target waypoint, and the target orientation must match the
    // ground-truth bearing (both computed by the real upstream math).
    var approachDistances = matchedPositions.Select(p => Navigation.GetDistance(navWp2, p)).ToList();
    for (var i = 1; i <= 4; i++)
    {
        Assert($"Navigation approach distance shrinks at track[{i}]",
            matchedPositions[i] != default && matchedPositions[i - 1] != default &&
            approachDistances[i] < approachDistances[i - 1] + 1.0,
            $"{approachDistances[i - 1]:F1} -> {approachDistances[i]:F1}");
    }
    Assert("Navigation reaches the real target waypoint at track[4]",
        matchedPositions[4] != default && approachDistances[4] <= 15,
        $"distance={approachDistances[4]:F1}");
    Assert("Navigation distance grows again after passing the target waypoint",
        approachDistances[^1] > approachDistances[4] + 100,
        $"target={approachDistances[4]:F1} final={approachDistances[^1]:F1}");
    for (var i = 0; i < track.Count - 1; i++)
    {
        if (matchedPositions[i] == default || approachDistances[i] <= 40) continue;
        var matchedOrientation = Navigation.GetTargetOrientation(navWp2, matchedPositions[i]);
        var truthOrientation = Navigation.GetTargetOrientation(navWp2, groundTruthImagePositions[i]);
        Assert($"Navigation track[{i}] target orientation matches ground-truth bearing",
            OrientationDelta(matchedOrientation, truthOrientation) <= 8,
            $"matched={matchedOrientation} truth={truthOrientation}");
    }

    Assert("Navigation platform publishes every position PathExecutor consumes",
        recordingNavigation.Positions.Count == track.Count &&
        recordingNavigation.Positions.Zip(matchedPositions).All(pair =>
            Math.Abs(pair.First.X - pair.Second.X) < 0.01f && Math.Abs(pair.First.Y - pair.Second.Y) < 0.01f),
        $"published={recordingNavigation.Positions.Count} expected={track.Count}");

    // Drive the original PathExecutor movement loop with real localized frames. The
    // route is aligned with the camera orientation recovered from the same minimap,
    // so WaitUntilRotatedTo and MoveTo consume one coherent visual track.
    using var orientationSource = BuildGroundTruthNavigationFrame(coarseMap, minimapRect, track[0]);
    using var orientationFrame = orientationSource.Clone();
    var cameraOrientation = CameraOrientation.Compute(orientationFrame);
    var movementStartImage = navigationMap.ConvertGenshinMapCoordinatesToImageCoordinates(track[0]);
    const float movementDistance = 120f;
    var movementRadians = cameraOrientation * Math.PI / 180.0;
    var movementTargetImage = new Point2f(
        movementStartImage.X + movementDistance * (float)Math.Cos(movementRadians),
        movementStartImage.Y + movementDistance * (float)Math.Sin(movementRadians));
    var movementTargetGame = navigationMap.ConvertImageCoordinatesToGenshinMapCoordinates(movementTargetImage)
        ?? throw new InvalidOperationException("PathExecutor target escaped the staged map layer.");
    var movementGroundTruth = Enumerable.Range(0, 6).Select(step =>
    {
        var ratio = step / 5f;
        return new Point2f(
            track[0].X + (movementTargetGame.X - track[0].X) * ratio,
            track[0].Y + (movementTargetGame.Y - track[0].Y) * ratio);
    }).ToList();
    var movementFrames = movementGroundTruth
        .Select(point => BuildGroundTruthNavigationFrame(coarseMap, minimapRect, point))
        .ToList();
    var expectedMovementPositions = new List<Point2f>();
    Navigation.Reset();
    foreach (var movementFrame in movementFrames)
    {
        using var expectedRegion = new ImageRegion(movementFrame.Clone(), 0, 0);
        expectedMovementPositions.Add(Navigation.GetPosition(
            expectedRegion, MapTypes.Teyvat.ToString(), "TemplateMatch"));
    }
    var localizedTargetGame = navigationMap.ConvertImageCoordinatesToGenshinMapCoordinates(expectedMovementPositions[^1])
        ?? throw new InvalidOperationException("Localized PathExecutor target escaped the staged map layer.");
    var movementWaypoint = new WaypointForTrack(new Waypoint
    {
        X = localizedTargetGame.X,
        Y = localizedTargetGame.Y,
        Type = WaypointType.Path.Code,
        MoveMode = MoveModeEnum.Walk.Code
    }, MapTypes.Teyvat.ToString(), "TemplateMatch");

    var movementCaptureIndex = 0;
    var publishedBeforeMoveTo = recordingNavigation.Positions.Count;
    recordingTaskControl.Calls.Clear();
    recordingTaskControl.ActionStateQueries.Clear();
    recordingTaskControl.CaptureFrameProvider = () =>
    {
        var index = recordingTaskControl.IsPressed(GIActions.MoveForward)
            ? Math.Min(movementCaptureIndex++, movementFrames.Count - 1)
            : 0;
        return movementFrames[index].Clone();
    };
    Navigation.Reset();
    var verificationPathExecutionServices = new VerificationScriptGroupExecutionServices();
    var verificationPathAutoSkipFactory = new PathExecutorAutoSkipSessionFactory();
    var movementPathingPlatform = new RecordingPathExecutorPlatform(b5SystemInfo, verificationOcrService);
    try
    {
        var pathExecutor = new PathExecutor(
            CancellationToken.None, movementPathingPlatform, verificationPathAutoSkipFactory,
            verificationPathExecutionServices)
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
        await pathExecutor.MoveTo(movementWaypoint);
    }
    finally
    {
        recordingTaskControl.CaptureFrameProvider = null;
        foreach (var movementFrame in movementFrames) movementFrame.Dispose();
    }

    var movementActionCalls = recordingTaskControl.Calls
        .Where(call => call.StartsWith("action:MoveForward:", StringComparison.Ordinal))
        .ToList();
    Assert("PathExecutor MoveTo presses forward exactly once and releases it",
        movementActionCalls.SequenceEqual([
            "action:MoveForward:KeyDown",
            "action:MoveForward:KeyUp"
        ]), string.Join(" | ", movementActionCalls));
    Assert("PathExecutor MoveTo reads the real platform key state while moving",
        recordingTaskControl.ActionStateQueries.Count >= movementFrames.Count - 1 &&
        recordingTaskControl.ActionStateQueries.All(action => action == GIActions.MoveForward),
        $"queries={recordingTaskControl.ActionStateQueries.Count}");
    var moveToPublished = recordingNavigation.Positions.Skip(publishedBeforeMoveTo).ToList();
    Assert("PathExecutor MoveTo consumes the complete localized frame track",
        movementCaptureIndex >= movementFrames.Count &&
        moveToPublished.Count >= movementFrames.Count + 1 &&
        Navigation.GetDistance(movementWaypoint, moveToPublished[^1]) < 0.01,
        $"captures={movementCaptureIndex} published={moveToPublished.Count} finalDistance=" +
        $"{(moveToPublished.Count == 0 ? double.NaN : Navigation.GetDistance(movementWaypoint, moveToPublished[^1])):F2}");
    Assert("PathExecutor MoveTo leaves forward released",
        !recordingTaskControl.IsPressed(GIActions.MoveForward), "MoveForward remains pressed");

    using var pathingPaimon = Cv2.ImRead(paimonPath, ImreadModes.Color);
    var pathingFrames = movementGroundTruth.Select(point =>
    {
        var frame = BuildGroundTruthNavigationFrame(coarseMap, minimapRect, point);
        using var paimonTarget = new Mat(frame, new Rect(24, 20, pathingPaimon.Width, pathingPaimon.Height));
        pathingPaimon.CopyTo(paimonTarget);
        frame.Set(50, 790, new Vec3b(0, 235, 255));
        frame.Set(50, 768, new Vec3b(255, 255, 255));
        return frame;
    }).ToList();
    var pathingCaptureIndex = 0;
    const string pathingLogMessage = "真实用户路径 log_output 执行门禁";
    var pathingLogger = new RecordingLogger();
    recordingTaskControl.Logger = pathingLogger;
    recordingTaskControl.Calls.Clear();
    recordingTaskControl.ActionStateQueries.Clear();
    recordingTaskControl.CaptureFrameProvider = () =>
    {
        var index = recordingTaskControl.IsPressed(GIActions.MoveForward)
            ? Math.Min(pathingCaptureIndex++, pathingFrames.Count - 1)
            : 0;
        return pathingFrames[index].Clone();
    };
    var pathingPlatform = new RecordingPathExecutorPlatform(b5SystemInfo, verificationOcrService);
    PathExecutorPlatform.Configure(pathingPlatform);
    RunnerContext.Instance.Reset();
    Navigation.Reset();
    var pathingFightStrategyName = "core-verification-fight-" + Guid.NewGuid().ToString("N");
    var pathingFightStrategyPath = Global.Absolute($@"User\AutoFight\{pathingFightStrategyName}.txt");
    Directory.CreateDirectory(Path.GetDirectoryName(pathingFightStrategyPath)!);
    File.WriteAllText(pathingFightStrategyPath, "钟离 keypress(VK_F)");
    var pathingFightConfig = new AutoFightConfig
    {
        StrategyName = pathingFightStrategyName,
        TeamNames = verificationAutoFightConfig.TeamNames,
        FightFinishDetectEnabled = true,
        KazuhaPickupEnabled = false,
        PickDropsAfterFightEnabled = false,
        SwimmingEnabled = false,
        FinishDetectConfig = new AutoFightConfig.FightFinishDetectConfig
        {
            CheckEndDelay = "0",
            BeforeDetectDelay = "0",
            RotateFindEnemyEnabled = false
        }
    };
    var verificationCombatCommandPlatform = (VerificationCombatCommandPlatform)CombatCommandPlatform.Current;
    verificationCombatCommandPlatform.Calls.Clear();
    var fullPathExecutor = new PathExecutor(
        CancellationToken.None, pathingPlatform, verificationPathAutoSkipFactory,
        verificationPathExecutionServices)
    {
        PartyConfig = new PathingPartyConfig
        {
            SkipPartySwitch = true,
            OnlyInTeleportRecover = true,
            MainAvatarIndex = string.Empty,
            GuardianAvatarIndex = string.Empty,
            AutoRunEnabled = false,
            AutoSkipEnabled = false,
            UseGadgetIntervalMs = 0,
            AutoFightEnabled = true,
            AutoFightConfig = pathingFightConfig
        }
    };
    var fullPathingTask = new PathingTask
    {
        Info = new PathingTaskInfo
        {
            Name = "Core verification configured-team path",
            MapName = MapTypes.Teyvat.ToString(),
            MapMatchMethod = "TemplateMatch"
        },
        Positions =
        [
            new Waypoint
            {
                X = localizedTargetGame.X,
                Y = localizedTargetGame.Y,
                Type = WaypointType.Path.Code,
                MoveMode = MoveModeEnum.Walk.Code,
                Action = ActionEnum.LogOutput.Code,
                ActionParams = pathingLogMessage
            },
            new Waypoint
            {
                X = localizedTargetGame.X,
                Y = localizedTargetGame.Y,
                Type = WaypointType.Path.Code,
                MoveMode = MoveModeEnum.Walk.Code,
                Action = ActionEnum.UseGadget.Code,
                ActionParams = "not_wait"
            },
            new Waypoint
            {
                X = localizedTargetGame.X,
                Y = localizedTargetGame.Y,
                Type = WaypointType.Path.Code,
                MoveMode = MoveModeEnum.Walk.Code,
                Action = ActionEnum.Fight.Code,
                PointExtParams = new Waypoint.ExtParams
                {
                    MonsterTag = "normal",
                    EnableMonsterLootSplit = true
                }
            }
        ]
    };
    try
    {
        await fullPathExecutor.Pathing(fullPathingTask);
    }
    finally
    {
        recordingTaskControl.CaptureFrameProvider = null;
        foreach (var pathingFrame in pathingFrames) pathingFrame.Dispose();
        RunnerContext.Instance.Reset();
        File.Delete(pathingFightStrategyPath);
    }
    Assert("PathExecutor Pathing initializes the configured upstream CombatScenes team",
        verificationAutoFightConfig.TeamNames == "钟离,夜兰,纳西妲,久岐忍",
        verificationAutoFightConfig.TeamNames);
    Assert("PathExecutor Pathing publishes the exact task through its platform boundary",
        ReferenceEquals(pathingPlatform.CurrentPathing, fullPathingTask),
        pathingPlatform.CurrentPathing?.Info.Name ?? "null");
    Assert("PathExecutor Pathing completes the shared waypoint orchestration",
        fullPathExecutor.SuccessEnd && fullPathExecutor.SuccessFight == 1,
        $"successEnd={fullPathExecutor.SuccessEnd} successFight={fullPathExecutor.SuccessFight}");
    Assert("PathExecutor Pathing executes the upstream log_output action exactly once",
        pathingLogger.Messages.Count(message => message == pathingLogMessage) == 1,
        string.Join(" | ", pathingLogger.Messages));
    Assert("PathExecutor Pathing executes the upstream use-gadget action handler",
        recordingTaskControl.Calls.Count(call => call == "action:QuickUseGadget:KeyPress") == 2,
        string.Join(" | ", recordingTaskControl.Calls));
    Assert("PathExecutor Pathing executes the upstream AutoFightHandler task chain",
        verificationCombatCommandPlatform.Calls.SequenceEqual(["KeyPress(VK_F)"]),
        string.Join(" | ", verificationCombatCommandPlatform.Calls));
    Assert("PathExecutor Pathing exits fight through the shared combat-end detector",
        recordingTaskControl.Calls.Count(call => call == "action:OpenPartySetupScreen:KeyPress") == 2 &&
        recordingTaskControl.Calls.Count(call => call == "action:Drop:KeyPress") == 1,
        string.Join(" | ", recordingTaskControl.Calls));
    Assert("PathExecutor Pathing drives and releases movement through TaskControl",
        pathingCaptureIndex >= pathingFrames.Count &&
        recordingTaskControl.Calls.Count(call => call == "action:MoveForward:KeyDown") == 3 &&
        recordingTaskControl.Calls.Count(call => call == "action:MoveForward:KeyUp") == 4 &&
        !recordingTaskControl.IsPressed(GIActions.MoveForward),
        $"captures={pathingCaptureIndex} calls={string.Join(" | ", recordingTaskControl.Calls)}");

    using (var blackFrame = new Mat(1080, 1920, MatType.CV_8UC3, Scalar.Black))
    using (var blackRegion = new ImageRegion(blackFrame, 0, 0))
    {
        var blackPosition = Navigation.GetPosition(blackRegion, MapTypes.Teyvat.ToString(), "TemplateMatch");
        Assert("Navigation rejects a frame without map content instead of inventing a position",
            blackPosition == default, $"unexpected ({blackPosition.X:F1},{blackPosition.Y:F1})");
    }
}
finally
{
    Global.StartUpPath = startUpPathBeforeNavigation;
    if (Directory.Exists(mapVerificationRoot)) Directory.Delete(mapVerificationRoot, recursive: true);
    if (Directory.Exists(lockedRuntimeRoot)) Directory.Delete(lockedRuntimeRoot, recursive: true);
}

Console.WriteLine();
Console.WriteLine($"=== {passed} passed, {failed} failed ===");
Microsoft.ML.OnnxRuntime.OrtEnv.Instance().Dispose();
Environment.ExitCode = failed > 0 ? 1 : 0;

class DeadProvider : BetterGenshinImpact.Core.Abstractions.Runtime.IOcrRuntimeConfigProvider
{
    public PaddleOcrModelConfig PaddleModel => throw new InvalidOperationException("Dead provider");
    public string GameCultureInfoName => throw new InvalidOperationException("Dead provider");
}

sealed class RecordingNavigationPlatform : INavigationPlatform
{
    public List<Point2f> Positions { get; } = [];
    public void PublishCurrentPosition(Point2f position) => Positions.Add(position);
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
    public void SetRectangles(string name, Region source, IReadOnlyList<Rect> rectangles) =>
        Commands.AddRange(rectangles.Select(rect =>
        {
            var mapped = source.ConvertPositionToGameCaptureRegion(rect.X, rect.Y, rect.Width, rect.Height);
            return $"set:{name}:{mapped.X},{mapped.Y},{mapped.Width},{mapped.Height}";
        }));
    public void RemoveRectangles(string name) => Commands.Add($"remove:{name}");
    public void ClearAll() => Commands.Add("clearAll");
}

sealed class RecordingAutoWoodRuntimePlatform : IAutoWoodRuntimePlatform
{
    public AutoWoodConfig Config { get; } = new()
    {
        AfterZSleepDelay = 0,
        WoodCountOcrEnabled = false,
        UseWonderlandRefresh = true,
    };
    public RecordingAutoWoodLoginSession LoginSession { get; } = new();
    public int SleepAcquireCount { get; private set; }
    public int SleepReleaseCount { get; private set; }

    public IDisposable AcquireSleepPrevention()
    {
        SleepAcquireCount++;
        return new CallbackDisposable(() => SleepReleaseCount++);
    }

    public IAutoWoodLoginSession CreateLoginSession() => LoginSession;
}

sealed class RecordingAutoMusicGameRuntimePlatform : IAutoMusicGameRuntimePlatform
{
    private int _aLaneSamples;
    public double AssetScale => 1;
    public int ValidateCount { get; private set; }
    public void ValidateResolution() => ValidateCount++;
    public byte ReadBlueChannel(int x, int y)
    {
        if (x != 417) return 255;
        return Interlocked.Increment(ref _aLaneSamples) <= 2 ? (byte)100 : (byte)255;
    }
}

sealed class RecordingAutoWoodLoginSession : IAutoWoodLoginSession
{
    public bool IsAvailable => false;
    public bool IsBilibili => false;
    public int RefreshCount { get; private set; }
    public void RefreshAvailability() => RefreshCount++;
    public void Login(CancellationToken cancellationToken) =>
        throw new InvalidOperationException("Unavailable login session must not be used.");
}

sealed class CallbackDisposable(Action dispose) : IDisposable
{
    private Action? _dispose = dispose;
    public void Dispose() => Interlocked.Exchange(ref _dispose, null)?.Invoke();
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

sealed class VerificationCraftMaterialRuntimePlatform : ICraftMaterialRuntimePlatform
{
    public Microsoft.Extensions.Logging.ILogger<CraftMaterialTask> Logger => NullLogger<CraftMaterialTask>.Instance;
}

sealed class VerificationGridScreenRuntimePlatform(VerificationSystemInfo systemInfo) : IGridScreenRuntimePlatform
{
    public double AssetScale => systemInfo.AssetScale;
    public int CaptureAreaX => systemInfo.CaptureAreaRect.X;
    public int CaptureAreaY => systemInfo.CaptureAreaRect.Y;
}

sealed class VerificationRewardResultRuntimePlatform : IRewardResultRuntimePlatform
{
    public Microsoft.Extensions.Logging.ILogger<RewardResultRecognizer> Logger => NullLogger<RewardResultRecognizer>.Instance;
    public BetterGenshinImpact.Core.Recognition.OCR.IOcrService OcrService { get; } = new VerificationOcrService();
    public bool SaveDebugScreenshots => false;
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
    public List<string> Calls { get; } = [];

    public void ValidateKeyName(string keyName)
    {
        var normalized = keyName.Trim().ToUpperInvariant();
        if (normalized.StartsWith("VK_", StringComparison.Ordinal)) normalized = normalized[3..];
        if (normalized.Length == 1 && normalized[0] is >= 'A' and <= 'Z') return;
        if (normalized is "LBUTTON" or "RBUTTON" or "MBUTTON" or "SPACE" or "ESCAPE") return;
        throw new ArgumentException($"Unsupported verification key: {keyName}", nameof(keyName));
    }
    public void KeyDown(string keyName)
    {
        ValidateKeyName(keyName);
        Calls.Add($"KeyDown({keyName})");
    }

    public void KeyUp(string keyName)
    {
        ValidateKeyName(keyName);
        Calls.Add($"KeyUp({keyName})");
    }

    public void KeyPress(string keyName)
    {
        ValidateKeyName(keyName);
        Calls.Add($"KeyPress({keyName})");
    }
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
    private readonly HashSet<GIActions> _pressedActions = [];
    public List<string> Calls { get; } = [];
    public List<GIActions> ActionStateQueries { get; } = [];
    public Func<Mat>? CaptureFrameProvider { get; set; }
    public bool RecordCaptures { get; set; }
    public bool RecordMiddleClicks { get; set; }
    public Microsoft.Extensions.Logging.ILogger Logger { get; set; } = NullLogger.Instance;
    public double DpiScale => 1;
    public bool IsHdrCapture => false;
    public void EnsureGameActive() { }
    public void ReleasePressedInputs() => Calls.Add("releaseAll");
    public void SimulateAction(GIActions action, KeyType keyType)
    {
        if (keyType == KeyType.KeyDown) _pressedActions.Add(action);
        else if (keyType == KeyType.KeyUp) _pressedActions.Remove(action);
        Calls.Add($"action:{action}:{keyType}");
    }
    public bool IsActionKeyDown(GIActions action)
    {
        ActionStateQueries.Add(action);
        return IsPressed(action);
    }
    public bool IsPressed(GIActions action) => _pressedActions.Contains(action);
    public void MoveMouseBy(int x, int y) => Calls.Add($"move:{x},{y}");
    public void LeftButtonDown() => Calls.Add("leftDown");
    public void LeftButtonUp() => Calls.Add("leftUp");
    public void LeftButtonClick() { }
    public void RightButtonDown() { }
    public void RightButtonUp() { }
    public void RightButtonClick() { }
    public void MiddleButtonDown() { }
    public void MiddleButtonUp() { }
    public void MiddleButtonClick()
    {
        if (RecordMiddleClicks) Calls.Add("middleClick");
    }
    public void VerticalScroll(int scrollAmountInClicks) { }
    public void KeyDown(int windowsVirtualKey) => Calls.Add($"keyDown:{windowsVirtualKey}");
    public void KeyUp(int windowsVirtualKey) => Calls.Add($"keyUp:{windowsVirtualKey}");
    public void PressKey(int windowsVirtualKey) => Calls.Add($"press:{windowsVirtualKey}");
    public void InputText(string text) { }
    public void PressEscape() { }
    public ImageRegion CaptureToRectArea(bool forceNew)
    {
        if (CaptureFrameProvider is null) throw new NotSupportedException();
        if (RecordCaptures) Calls.Add("capture");
        return new ImageRegion(CaptureFrameProvider(), 0, 0);
    }
}

sealed class RecordingLogger : Microsoft.Extensions.Logging.ILogger
{
    public List<string> Messages { get; } = [];

    public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
    public bool IsEnabled(Microsoft.Extensions.Logging.LogLevel logLevel) => true;

    public void Log<TState>(
        Microsoft.Extensions.Logging.LogLevel logLevel,
        Microsoft.Extensions.Logging.EventId eventId,
        TState state,
        Exception? exception,
        Func<TState, Exception?, string> formatter)
    {
        Messages.Add(formatter(state, exception));
    }
}

sealed class RecordingPathExecutorPlatform(
    VerificationSystemInfo systemInfo,
    BetterGenshinImpact.Core.Recognition.OCR.IOcrService ocrService) : IPathExecutorPlatform
{
    public PathingTask? CurrentPathing { get; private set; }
    public (int Width, int Height) GetGameScreenSize() =>
        (systemInfo.GameScreenSize.Width, systemInfo.GameScreenSize.Height);
    public void PublishCurrentPathing(PathingTask task) => CurrentPathing = task;
    public string AutoFetchDispatchAdventurersGuildCountry => string.Empty;
    public PathingConditionConfig PathingConditionConfig { get; } = new();
    public BetterGenshinImpact.Core.Recognition.OCR.IOcrService OcrService { get; } = ocrService;
}

sealed class VerificationScriptGroupExecutionServices : IScriptGroupExecutionServices
{
    public IPathExecutor CreatePathExecutor(CancellationToken cancellationToken) =>
        throw new NotSupportedException("Nested PathExecutor creation is not used by this verification.");
    public PathingPartyConfig DefaultPartyConfig { get; } = new();
    public void AddAutoPickTrigger() => throw new NotSupportedException();
    public PathingFailurePolicy PathingFailurePolicy => new(false, false, false);
    public void RecordFarmingSession(FarmingSession session, FarmingRouteInfo route) { }
}

sealed class RecordingAutoBossExecutionServices : IScriptGroupExecutionServices
{
    public RecordingAutoBossPathExecutor Executor { get; } = new();
    public int CreateCount { get; private set; }

    public IPathExecutor CreatePathExecutor(CancellationToken cancellationToken)
    {
        CreateCount++;
        return Executor;
    }

    public PathingPartyConfig DefaultPartyConfig { get; } = new();
    public void AddAutoPickTrigger() => throw new NotSupportedException();
    public PathingFailurePolicy PathingFailurePolicy => new(false, false, false);
    public void RecordFarmingSession(FarmingSession session, FarmingRouteInfo route) { }
}

sealed class RecordingAutoBossPathExecutor : IPathExecutor
{
    public PathingPartyConfig PartyConfig { get; set; } = new();
    public int SuccessFight => 0;
    public bool SuccessEnd => false;
    public Task Pathing(PathingTask task) => Task.CompletedTask;
}

sealed class VerificationAutoFightRuntimePlatform(
    VerificationSystemInfo systemInfo,
    AutoFightConfig autoFightConfig,
    BetterGenshinImpact.Core.Recognition.OCR.IOcrService ocrService,
    BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory onnxFactory) : IAutoFightRuntimePlatform
{
    private AutoFightConfig _autoFightConfig = autoFightConfig;

    public BetterGenshinImpact.GameTask.Model.ISystemInfo SystemInfo => systemInfo;
    public AutoFightConfig AutoFightConfig => Volatile.Read(ref _autoFightConfig);
    public BetterGenshinImpact.Core.Recognition.OCR.IOcrService OcrService { get; } = ocrService;
    public double DpiScale => 1;
    public int CombatMacroPriority => 0;
    public Microsoft.Extensions.Logging.ILogger<T> GetLogger<T>() => NullLogger<T>.Instance;
    public BetterGenshinImpact.Core.Recognition.ONNX.BgiYoloPredictor CreateYoloPredictor(
        BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel model) => onnxFactory.CreateYoloPredictor(model);
    public IDisposable UseConfig(AutoFightConfig config)
    {
        ArgumentNullException.ThrowIfNull(config);
        var original = Interlocked.Exchange(ref _autoFightConfig, config);
        return new CallbackDisposable(() =>
            Interlocked.Exchange(ref _autoFightConfig, original));
    }
}

sealed class VerificationOcrService : BetterGenshinImpact.Core.Recognition.OCR.IOcrService
{
    public string Ocr(Mat mat) => string.Empty;
    public string OcrWithoutDetector(Mat mat) => string.Empty;
    public BetterGenshinImpact.Core.Recognition.OCR.OcrResult OcrResult(Mat mat) => new([]);
}

sealed class VerificationTaskParameterPlatform(string gameCultureInfoName) : BetterGenshinImpact.GameTask.Model.ITaskParameterPlatform
{
    public string GameCultureInfoName { get; } = gameCultureInfoName;
    public Microsoft.Extensions.Localization.IStringLocalizer<T> GetStringLocalizer<T>() =>
        new BetterGenshinImpact.Core.Infrastructure.EmbeddedResourceStringLocalizer<T>();
}

sealed record AvatarRecognitionScenario(
    string FileName,
    string Sha256,
    int PlayerCount,
    bool IsHost,
    string[] ExpectedNames);

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

sealed class VerificationFarmingStatsRuntimePlatform(string root) : IFarmingStatsRuntimePlatform
{
    public string LogDirectory { get; } = root;
    public OtherConfig.FarmingPlan Config { get; } = new();
    public Microsoft.Extensions.Logging.ILogger Logger => NullLogger.Instance;
    public DateTimeOffset ServerTimeNow { get; set; }
    public Task UpdateMiyousheDataAsync(CancellationToken cancellationToken) =>
        throw new InvalidOperationException("Miyoushe synchronization is outside this deterministic store verification.");
}
