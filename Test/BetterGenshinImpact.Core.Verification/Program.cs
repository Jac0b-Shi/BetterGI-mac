using BetterGenshinImpact;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Composition;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Script.Dependence.Model.TimerConfig;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.AutoPick.Assets;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.Platform.Abstractions;
using System.Collections.Concurrent;
using System.Reflection;
using System.Threading;

var recorder = new RecordingInputBackend();
PlatformServices.Input = recorder;
DesktopRegion.DisplayWidth = 1920;
DesktopRegion.DisplayHeight = 1080;

int passed = 0, failed = 0;
void Assert(string label, bool condition, string detail)
{
    if (condition) { Console.WriteLine($"  PASS: {label}"); passed++; }
    else { Console.WriteLine($"  FAIL: {label} — {detail}"); failed++; }
}

// ==== Native Smoke Test ====
Console.WriteLine("Smoke: OpenCV native runtime");
try
{
    using var mat = new OpenCvSharp.Mat(16, 16, OpenCvSharp.MatType.CV_8UC4);
    Assert("Mat created OK", mat.Width == 16 && mat.Height == 16, $"{mat.Width}x{mat.Height}");
    var ver = OpenCvSharp.Cv2.GetVersionString();
    Assert("Cv2.GetVersionString works", !string.IsNullOrEmpty(ver), ver);
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
var c1 = recorder.Calls.FirstOrDefault();
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
var c2 = recorder.Calls.FirstOrDefault();
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
using var ocrFactory = new BetterGenshinImpact.Core.Recognition.OCR.OcrFactory(
    Microsoft.Extensions.Logging.Abstractions.NullLogger<BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory>.Instance,
    adapter);

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
    deadProvider);
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
    whiteProvider);
var whiteCulture = (string)(fallbackCultureField?.GetValue(whitespaceFactory) ?? throw new InvalidOperationException());
Assert("Whitespace culture falls back to default", whiteCulture == expectedCulture, $"got {whiteCulture}");
Console.WriteLine();

// ==== B5: AutoPickTrigger IAutoPickRuntimeState injection ====
Console.WriteLine("AutoPickTrigger: IAutoPickRuntimeState injection");
BetterGenshinImpact.GameTask.TaskContext.Instance().SystemInfo =
    new BetterGenshinImpact.GameTask.MacSystemInfo();
var stopCountProp = typeof(BetterGenshinImpact.GameTask.AutoPick.AutoPickTrigger)
    .GetProperty("StopCount", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
var extField = typeof(BetterGenshinImpact.GameTask.AutoPick.AutoPickTrigger)
    .GetField("_externalConfig", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
var stateField = typeof(BetterGenshinImpact.GameTask.AutoPick.AutoPickTrigger)
    .GetField("_runtimeState", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);

// Test 1: injection with StopCount=0 (via two-param ctor, null config)
var state0B5 = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(0);
var t0 = new AutoPickTrigger(null, state0B5);
var actualStop0 = (int)(stopCountProp?.GetValue(t0) ?? throw new InvalidOperationException());
Assert("StopCount=0 from state", actualStop0 == 0, $"got {actualStop0}");

// Test 2: injection with StopCount=2
var stateForB5 = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(2);
var t2 = new AutoPickTrigger(null, stateForB5);
var actualStop2 = (int)(stopCountProp?.GetValue(t2) ?? throw new InvalidOperationException());
Assert("StopCount=2 from state", actualStop2 == 2, $"got {actualStop2}");

// Test 3: new AutoPickTrigger(null) compiles unambiguously (config-only with null)
var tNull = new AutoPickTrigger(null);
var extNull = extField?.GetValue(tNull);
var stateNull = stateField?.GetValue(tNull);
Assert("AutoPickTrigger(null) has null _externalConfig",
    extNull == null, "got non-null");
Assert("AutoPickTrigger(null) has null _runtimeState",
    stateNull == null, "got non-null");

// Test 3: externalConfig-only preserves _externalConfig, no runtime state
var external = new AutoPickExternalConfig { ForceInteraction = true };
var t3 = new AutoPickTrigger(external);
var ext3 = extField?.GetValue(t3);
Assert("externalConfig-only preserves _externalConfig",
    ReferenceEquals(ext3, external), "different reference");
Assert("externalConfig-only has null _runtimeState",
    stateField?.GetValue(t3) == null, "got non-null");

// Test 4: combined externalConfig + runtimeState
var t4 = new AutoPickTrigger(external, stateForB5);
var ext4 = extField?.GetValue(t4);
var state4 = stateField?.GetValue(t4);
Assert("Combined ctor preserves _externalConfig",
    ReferenceEquals(ext4, external), "different reference");
Assert("Combined ctor preserves _runtimeState",
    ReferenceEquals(state4, stateForB5), "different reference");

// Test 5: parameterless ctor has null _externalConfig and null _runtimeState
var t5 = new AutoPickTrigger();
Assert("parameterless has null _externalConfig",
    extField?.GetValue(t5) == null, "got non-null");
Assert("parameterless has null _runtimeState",
    stateField?.GetValue(t5) == null, "got non-null");

// ==== B6: AutoPickAssets split constructor + Configure() ====
Console.WriteLine("AutoPickAssets: split constructor + Configure()");
var pickConfigProvider = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "W" },
    PaddleOcrModelConfig.V5, "zh-Hans");
var assets = AutoPickAssets.Instance;

// 1. Field access before Configure should throw
try { _ = assets.PickRo; Assert("PickRo pre-Configure should throw", false, "no exception"); }
catch (InvalidOperationException) { Assert("PickRo pre-Configure throws", true, ""); }

try { _ = assets.PickVk; Assert("PickVk pre-Configure should throw", false, "no exception"); }
catch (InvalidOperationException) { Assert("PickVk pre-Configure throws", true, ""); }

try { _ = assets.ChatPickRo; Assert("ChatPickRo pre-Configure should throw", false, "no exception"); }
catch (InvalidOperationException) { Assert("ChatPickRo pre-Configure throws", true, ""); }

// 2. Configure (falls back to F since no test assets exist)
var configObj = pickConfigProvider.AutoPickConfig;
assets.Configure(pickConfigProvider);
Assert("After Configure PickVk = F", assets.PickVk == BgiKey.F, $"got {assets.PickVk}");
Assert("PickRo is FRo (fallback)", ReferenceEquals(assets.PickRo, assets.FRo), "not FRo");
Assert("ChatPickRo null (fallback)", assets.ChatPickRo == null, $"got {assets.ChatPickRo}");
Assert("PickKey written back to F", configObj.PickKey == "F", $"got {configObj.PickKey}");

// EnsureConfigured actually passes (not a no-op)
AutoPickAssets.EnsureConfigured();
Assert("EnsureConfigured post-Configure passes", true, "");

// 3. Duplicate Configure throws
try { assets.Configure(pickConfigProvider); Assert("duplicate should throw", false, ""); }
catch (InvalidOperationException) { Assert("Duplicate Configure throws", true, ""); }

// 4. Destroy + re-Configure
AutoPickAssets.DestroyInstance();
var freshAssets = AutoPickAssets.Instance;
var freshConfig = new AutoPickConfig { PickKey = "S" };
var freshProvider = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    freshConfig, PaddleOcrModelConfig.V5, "zh-Hans");
freshAssets.Configure(freshProvider);
Assert("Re-configured PickVk = F", freshAssets.PickVk == BgiKey.F, $"got {freshAssets.PickVk}");
Assert("Re-configured PickKey=F", freshConfig.PickKey == "F", $"got {freshConfig.PickKey}");

// 5. Destroy + access throws
AutoPickAssets.DestroyInstance();
_ = AutoPickAssets.Instance;
try { AutoPickAssets.EnsureConfigured(); Assert("post-Destroy should throw", false, ""); }
catch (InvalidOperationException) { Assert("Post-Destroy EnsureConfigured throws", true, ""); }

// 6. Empty-key behavior: Configure with empty key uses defaults, no write-back
AutoPickAssets.DestroyInstance();
var emptyCfg = new AutoPickConfig { PickKey = "" };
var emptyProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    emptyCfg, PaddleOcrModelConfig.V5, "zh-Hans");
var emptyAssets = AutoPickAssets.Instance;
emptyAssets.Configure(emptyProv);
Assert("Empty key: PickVk = F", emptyAssets.PickVk == BgiKey.F, $"got {emptyAssets.PickVk}");
Assert("Empty key: PickRo is FRo", ReferenceEquals(emptyAssets.PickRo, emptyAssets.FRo), "not FRo");
Assert("Empty key: PickKey unchanged (empty)", emptyCfg.PickKey == "", $"got '{emptyCfg.PickKey}'");

// Cleanup: return singleton to configured state for remaining tests
AutoPickAssets.DestroyInstance();
_ = AutoPickAssets.Instance;
var cleanupProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F" }, PaddleOcrModelConfig.V5, "zh-Hans");
AutoPickAssets.Instance.Configure(cleanupProv);
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

// Old instance after Destroy keeps its own configured state — read AFTER Destroy
AutoPickAssets.DestroyInstance();
var oldInstance = AutoPickAssets.Instance;
oldInstance.Configure(new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "W" }, PaddleOcrModelConfig.V5, "zh-Hans"));
AutoPickAssets.DestroyInstance();
var oldKeyAfterDestroy = oldInstance.PickVk; // old instance keeps its own state
Assert("Old instance PickVk after Destroy = F", oldKeyAfterDestroy == BgiKey.F, $"got {oldKeyAfterDestroy}");

// New singleton not configured, throws independently
var afterDestroyInstance = AutoPickAssets.Instance;
try { _ = afterDestroyInstance.PickRo; Assert("new PickRo should throw", false, ""); }
catch (InvalidOperationException) { Assert("New singleton unconfigured throws", true, ""); }

// Restore configured singleton for any subsequent tests
AutoPickAssets.DestroyInstance();
var finalProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F" }, PaddleOcrModelConfig.V5, "zh-Hans");
AutoPickAssets.Instance.Configure(finalProv);
Console.WriteLine();

// ==== B7: MacAutoPickComposition ====
Console.WriteLine("B7: MacAutoPickComposition");

var resetForVerification = typeof(MacAutoPickComposition)
    .GetMethod("ResetForVerification", BindingFlags.NonPublic | BindingFlags.Static)!;
var composeMethod = typeof(MacAutoPickComposition)
    .GetMethod("Compose", BindingFlags.Public | BindingFlags.Static)!;

// Reflection helpers for B7 trigger internals (extField/stateField already defined in B5)
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

MacAutoPickComposition? comp7;
{
    comp7 = (MacAutoPickComposition)composeMethod.Invoke(null, [b7Provider, b7State, b7ExtConfig])!;
    Assert("B7.1 Compose succeeds", comp7.Trigger != null, "trigger is null");
}

// B7.2: Compose preserves external config reference
Assert("B7.2 _externalConfig preserved",
    ReferenceEquals(extField.GetValue(comp7.Trigger), b7ExtConfig), "different reference");

// B7.3: Compose preserves runtime state reference
Assert("B7.3 _runtimeState preserved",
    ReferenceEquals(stateField.GetValue(comp7.Trigger), b7State), "different reference");

// B7.4: Init() reads IsEnabled from provider
Assert("B7.4 IsEnabled from provider (true)", comp7.Trigger.IsEnabled == true, $"got {comp7.Trigger.IsEnabled}");

// B7.5: _configProvider field preserved
Assert("B7.5 _configProvider preserved",
    ReferenceEquals(b7ConfigProvField.GetValue(comp7.Trigger), b7Provider), "different reference");

// B7.6: Double Compose throws (Composed state)
try
{
    composeMethod.Invoke(null, [b7Provider, b7State, null]);
    Assert("B7.6 Double Compose should throw", false, "no exception");
}
catch (TargetInvocationException ex) when (ex.InnerException is InvalidOperationException ioe)
{
    Assert("B7.6 Double Compose throws Composed error",
        ioe.Message.Contains("already been composed"), ioe.Message);
}

// B7.7: Compose uses provider config (not TaskContext fallback)
// Reset, then Compose with Enabled = false — verify IsEnabled from provider, not default TaskContext
resetForVerification.Invoke(null, null);
BetterGenshinImpact.GameTask.TaskContext.Instance().Config!.AutoPickConfig!.Enabled = true; // TaskContext says true
var disabledCfg = new AutoPickConfig { PickKey = "F", Enabled = false };
var disabledProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    disabledCfg, PaddleOcrModelConfig.V5, "zh-Hans");
var disabledState = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(0);
comp7 = (MacAutoPickComposition)composeMethod.Invoke(null, [disabledProv, disabledState, null])!;
Assert("B7.7 Init uses provider (not TaskContext): IsEnabled = false",
    comp7.Trigger.IsEnabled == false, $"got {comp7.Trigger.IsEnabled} (TaskContext.Enabled would be true)");

// B7.8: After ResetForVerification, Compose succeeds again
resetForVerification.Invoke(null, null);
var reProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true },
    PaddleOcrModelConfig.V5, "zh-Hans");
var reState = new BetterGenshinImpact.Core.Adapters.MacAutoPickRuntimeState(1);
comp7 = (MacAutoPickComposition)composeMethod.Invoke(null, [reProv, reState, null])!;
Assert("B7.8 After ResetForVerification, Compose succeeds",
    comp7.Trigger != null && comp7.Trigger.IsEnabled == true, $"trigger null or IsEnabled != true");

// B7.9: Compose with BlackListEnabled = false — _blackList is empty
resetForVerification.Invoke(null, null);
var blOffCfg = new AutoPickConfig { PickKey = "F", Enabled = true, BlackListEnabled = false };
var blOffProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    blOffCfg, PaddleOcrModelConfig.V5, "zh-Hans");
comp7 = (MacAutoPickComposition)composeMethod.Invoke(null, [blOffProv, reState, null])!;
var blList = (System.Collections.Generic.HashSet<string>)b7BlackListField.GetValue(comp7.Trigger)!;
Assert("B7.9 BlackListEnabled=false: _blackList empty", blList.Count == 0, $"got {blList.Count}");

// B7.10: Compose with WhiteListEnabled = false — _whiteList is empty
resetForVerification.Invoke(null, null);
var wlOffCfg = new AutoPickConfig { PickKey = "F", Enabled = true, WhiteListEnabled = false };
var wlOffProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    wlOffCfg, PaddleOcrModelConfig.V5, "zh-Hans");
comp7 = (MacAutoPickComposition)composeMethod.Invoke(null, [wlOffProv, reState, null])!;
var wlList = (System.Collections.Generic.HashSet<string>)b7WhiteListField.GetValue(comp7.Trigger)!;
Assert("B7.10 WhiteListEnabled=false: _whiteList empty", wlList.Count == 0, $"got {wlList.Count}");

// B7.11: Compose(null, validState) throws ArgumentNullException, state stays NotComposed
resetForVerification.Invoke(null, null);
try
{
    composeMethod.Invoke(null, [null!, b7State, null]);
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
comp7 = (MacAutoPickComposition)composeMethod.Invoke(null, [b711Prov, b7State, null])!;
Assert("B7.11 After null provider: valid Compose succeeds",
    comp7.Trigger != null, "trigger null — state was poisoned");

// B7.12: Compose(validProvider, null) throws ArgumentNullException
resetForVerification.Invoke(null, null);
try
{
    composeMethod.Invoke(null, [b7Provider, null!, null]);
    Assert("B7.12 null runtimeState should throw", false, "no exception");
}
catch (TargetInvocationException ex) when (ex.InnerException is ArgumentNullException)
{
    Assert("B7.12 null runtimeState → ArgumentNullException", true, "");
}
var b712Prov = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true },
    PaddleOcrModelConfig.V5, "zh-Hans");
comp7 = (MacAutoPickComposition)composeMethod.Invoke(null, [b712Prov, b7State, null])!;
Assert("B7.12 After null state: valid Compose succeeds",
    comp7.Trigger != null, "trigger null");

// B7.13: Concurrent Compose — only one succeeds
resetForVerification.Invoke(null, null);
int successCount = 0;
int failCount = 0;
var barrier = new Barrier(2);
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
        composeMethod.Invoke(null, [concProv, concState, null]);
        Interlocked.Increment(ref successCount);
    }
    catch (TargetInvocationException ex)
    {
        Interlocked.Increment(ref failCount);
        concurrentErrors.Enqueue(ex.InnerException);
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
    composeMethod.Invoke(null, [throwingProvider, validState, null]);
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
    composeMethod.Invoke(null, [concProv, concState, null]);
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
var b715Comp = (MacAutoPickComposition)composeMethod.Invoke(null, [b715Prov, concState, null])!;
Assert("B7.15 From Failed: after ResetForVerification, Compose succeeds",
    b715Comp.Trigger != null, "trigger null");
Console.WriteLine();

// Final cleanup: restore configured singleton
resetForVerification.Invoke(null, null);
var b7CleanupProv = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F" }, PaddleOcrModelConfig.V5, "zh-Hans");
AutoPickAssets.Instance.Configure(b7CleanupProv);

Console.WriteLine($"=== {passed} passed, {failed} failed ===");
Environment.Exit(failed > 0 ? 1 : 0);

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

sealed class ThrowingAutoPickConfigProvider : IAutoPickConfigProvider
{
    public AutoPickConfig AutoPickConfig =>
        throw new InvalidOperationException("Injected composition failure");
}
