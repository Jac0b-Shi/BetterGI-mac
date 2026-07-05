using BetterGenshinImpact;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Script.Dependence.Model.TimerConfig;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.AutoPick.Assets;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.Platform.Abstractions;

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

// Old instance after Destroy keeps its own configured state
AutoPickAssets.DestroyInstance();
var oldInstance = AutoPickAssets.Instance;
oldInstance.Configure(new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "W" }, PaddleOcrModelConfig.V5, "zh-Hans"));
var oldKey = oldInstance.PickVk; // should not throw — old instance keeps its state
AutoPickAssets.DestroyInstance();
var newInstance = AutoPickAssets.Instance; // new singleton, not configured
Assert("Old instance keeps PickVk after Destroy", oldKey == BgiKey.F, $"got {oldKey}");

// New singleton not configured, throws independently
try { _ = newInstance.PickRo; Assert("new PickRo should throw", false, ""); }
catch (InvalidOperationException) { Assert("New singleton unconfigured throws", true, ""); }
Console.WriteLine();

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
