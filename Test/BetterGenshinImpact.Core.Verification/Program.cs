using BetterGenshinImpact;
using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Adapters;
using BetterGenshinImpact.Core.Composition;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Runtime.Windows;
using OpenCvSharp;
using System.Text.Json;
using BetterGenshinImpact.Core.Script.Dependence.Model.TimerConfig;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.AutoPick.Assets;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.Platform.Abstractions;
using System.Collections.Concurrent;
using System.Reflection;
using System.Threading;

using Microsoft.Extensions.Logging.Abstractions;

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
var onnxResolver = new BetterGenshinImpact.Core.Adapters.ModelRootPathResolver(
    System.IO.Path.GetTempPath());
var ocrResourceResolver = new BetterGenshinImpact.Core.Adapters.OcrResourcePathResolver(
    System.IO.Path.GetTempPath());
using var ocrFactory = new BetterGenshinImpact.Core.Recognition.OCR.OcrFactory(
    Microsoft.Extensions.Logging.Abstractions.NullLogger<BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory>.Instance,
    new BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory(onnxResolver),
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
    new BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory(onnxResolver),
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
    new BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxFactory(onnxResolver),
    whiteProvider,
    ocrResourceResolver);
var whiteCulture = (string)(fallbackCultureField?.GetValue(whitespaceFactory) ?? throw new InvalidOperationException());
Assert("Whitespace culture falls back to default", whiteCulture == expectedCulture, $"got {whiteCulture}");
Console.WriteLine();

// ==== IOnnxModelPathResolver ====
Console.WriteLine("IOnnxModelPathResolver: path normalization");
var normRoot = System.IO.Path.GetTempPath();
var normResolver = new BetterGenshinImpact.Core.Adapters.ModelRootPathResolver(normRoot);
var normResult = normResolver.ResolveModelPath(new BetterGenshinImpact.Core.Recognition.ONNX.BgiOnnxModel
{
    Name = "Test",
    ModelRelativePath = @"Assets\Model\PaddleOCR\Det\V5\ppocr_det_v5.onnx"
});
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

// ==== B5: AutoPickTrigger IAutoPickRuntimeState injection ====
Console.WriteLine("AutoPickTrigger: IAutoPickRuntimeState injection");
var b5SystemInfo = new BetterGenshinImpact.GameTask.MacSystemInfo();
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
    .GetField("_externalConfig", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);

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

MacAutoPickComposition? comp7;
{
    comp7 = (MacAutoPickComposition)composeMethod.Invoke(null,
        [b7Provider, b7State, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, b7ExtConfig])!;
    Assert("B7.1 Compose succeeds", comp7.Trigger != null, "trigger is null");
}

// B7.2: Compose preserves external config reference
Assert("B7.2 _externalConfig preserved",
    ReferenceEquals(extField.GetValue(comp7.Trigger), b7ExtConfig), "different reference");

// B7.3: Compose preserves runtime state reference
Assert("B7.3 _runtimeState preserved",
    ReferenceEquals(b7RuntimeStateField.GetValue(comp7.Trigger), b7State), "different reference");

// B7.4: Init() reads IsEnabled from provider
Assert("B7.4 IsEnabled from provider (true)", comp7.Trigger.IsEnabled == true, $"got {comp7.Trigger.IsEnabled}");

// B7.5: _configProvider field preserved
Assert("B7.5 _configProvider preserved",
    ReferenceEquals(b7ConfigProvField.GetValue(comp7.Trigger), b7Provider), "different reference");

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
        composeMethod.Invoke(null, [concProv, concState, b7Recorder, b5SystemInfo, defaultLogger, triggerLogger, testPaddle, testYap, null]);
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

// ==== B8.2: Core shim AddTrigger preserves Assets singleton ====
Console.WriteLine("B8.2: Core shim AddTrigger after Initialize preserves Assets singleton");

// Tests the Core/macOS GameTaskManager shim's AddTrigger ("AutoPick") path.
// Verifies it does NOT re-initialize AutoPickAssets.
// NOT a test of the Windows production GameTaskManager.AddTrigger —
// that comes from source diff review. The shim and Windows implementation
// are separate compile units; this test prevents drift in the macOS path only.
var b82Recorder = new RecordingInputBackend();
var b82Prov = new BetterGenshinImpact.Core.Adapters.MacCoreRuntimeAdapter(
    new AutoPickConfig { PickKey = "F", Enabled = true },
    PaddleOcrModelConfig.V5, "zh-Hans");
var assetsBefore = AutoPickAssets.Instance;

// Real AddTrigger call (not pseudo-trigger via new ctor)
GameTaskManager.ClearTriggers();
var added = GameTaskManager.AddTrigger("AutoPick", null, defaultRuntimeState, b82Recorder, b5SystemInfo, testConfigProvider, triggerLogger, testPaddle, testYap);
Assert("B8.2 Core shim AddTrigger returns true", added, "returned false");
Assert("B8.2 Core shim TriggerDictionary contains AutoPick",
    GameTaskManager.TriggerDictionary?.ContainsKey("AutoPick") == true, "not found");
var addedTrigger = GameTaskManager.TriggerDictionary?["AutoPick"];
Assert("B8.2 Core shim added trigger is AutoPickTrigger",
    addedTrigger is AutoPickTrigger, $"got {addedTrigger?.GetType().Name}");
var assetsAfter = AutoPickAssets.Instance;
Assert("B8.2 Core shim Assets singleton preserved after AddTrigger",
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

// Unsupported placeholders throw
using (var mat = new Mat(1, 1, MatType.CV_8UC3))
{
    try { new UnsupportedPaddleAutoPickTextRecognizer().Recognize(mat); Assert("UnsupportedPaddle should throw", false, ""); }
    catch (NotSupportedException) { Assert("B9.2 UnsupportedPaddle → NotSupportedException", true, ""); }
    try { new UnsupportedYapAutoPickTextRecognizer().Recognize(mat); Assert("UnsupportedYap should throw", false, ""); }
    catch (NotSupportedException) { Assert("B9.2 UnsupportedYap → NotSupportedException", true, ""); }
}

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

sealed class FakePaddleAutoPickTextRecognizer : IPaddleAutoPickTextRecognizer
{
    public string Recognize(Mat textRegion) => "FakePaddleResult";
}

sealed class FakeYapAutoPickTextRecognizer : IYapAutoPickTextRecognizer
{
    public string Recognize(Mat textRegion) => "FakeYapResult";
}
