using System.Diagnostics;
using Compunet.YoloSharp;
using System.Text.Json;
using BetterGenshinImpact.Core.Adapters;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition.OCR.Paddle;
using BetterGenshinImpact.Core.Recognition.ONNX;
using BetterGenshinImpact.Core.Runtime.Portable;
using BetterGenshinImpact.GameTask.Model.Area;
using Newtonsoft.Json.Linq;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed record MacInferenceSettings
{
    public int CpuThreads { get; init; }
    public PaddleOcrCpuOptions PaddleOcrCpu { get; init; } = new();
    public bool IsValid => CpuThreads >= 0 && CpuThreads <= Environment.ProcessorCount
        && PaddleOcrCpu is { IsValid: true };
}

/// <summary>macOS ships a native CPU runtime. Windows DLL installers never alter its library path.</summary>
public sealed class MacInferenceSettingsCatalog
{
    private readonly RuntimeLayout _layout;
    private readonly object _gate = new();
    private readonly SemaphoreSlim _benchmarkGate = new(1, 1);
    public MacInferenceSettings Active { get; }
    public string StartupMessage { get; } = "";
    private string SettingsPath => Path.Combine(_layout.UserPath, "mac-inference.json");

    public MacInferenceSettingsCatalog(RuntimeLayout layout)
    {
        _layout = layout;
        try { Active = Read(); }
        catch (Exception e) when (e is JsonException or ArgumentException)
        {
            Active = new();
            StartupMessage = "推理设置无效，本次使用 CPU 默认设置。";
        }
    }

    private MacInferenceSettings Read()
    {
        var value = File.Exists(SettingsPath)
            ? JsonSerializer.Deserialize<MacInferenceSettings>(File.ReadAllText(SettingsPath), ConfigJson.Options)
              ?? throw new ArgumentException("推理设置不能为空。") : new();
        if (!value.IsValid) throw new ArgumentException("CPU/OCR 线程设置不符合当前处理器范围。");
        return value;
    }

    public object Get()
    {
        lock (_gate)
        {
            MacInferenceSettings saved;
            try { saved = Read(); }
            catch (Exception e) when (e is JsonException or ArgumentException) { saved = Active; }
            return new { engine = "CPU", maxThreads = Environment.ProcessorCount,
                saved = JObject.Parse(JsonSerializer.Serialize(saved, ConfigJson.Options)),
                pendingRestart = saved != Active, startupMessage = StartupMessage,
                runtimeVersion = typeof(Microsoft.ML.OnnxRuntime.InferenceSession).Assembly.GetName().Version?.ToString() };
        }
    }

    public object Save(JObject settings)
    {
        var value = settings.ToObject<MacInferenceSettings>() ?? throw new ArgumentException("settings is required.");
        if (!value.IsValid) throw new ArgumentException("CPU/OCR 线程设置不符合当前处理器范围。");
        lock (_gate)
        {
            Directory.CreateDirectory(_layout.UserPath);
            var temporary = SettingsPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                File.WriteAllText(temporary, JsonSerializer.Serialize(value, ConfigJson.Options));
                File.Move(temporary, SettingsPath, true);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
            return Get();
        }
    }

    /// <summary>Uses independent sessions; never unloads the OCR service used by running tasks.</summary>
    public async Task<object> BenchmarkAsync(string scene, CancellationToken token)
    {
        if (scene is not ("ocr" or "tree")) throw new ArgumentException("scene must be ocr or tree.");
        if (!await _benchmarkGate.WaitAsync(0, token)) throw new InvalidOperationException("推理验证正在运行。");
        try
        {
            MacInferenceSettings settings;
            lock (_gate) settings = Read();
            return await Task.Run<object>(() =>
            {
                token.ThrowIfCancellationRequested();
                var factory = new BgiOnnxFactory(new CpuOnnxRuntimePlatform(
                    new ModelRootPathResolver(_layout.RootPath), settings.CpuThreads, settings.PaddleOcrCpu));
                var timer = Stopwatch.StartNew();
                if (scene == "ocr")
                {
                    using var ocr = new PaddleOcrService(factory, PaddleOcrService.PaddleOcrModelType.V5,
                        new OcrResourcePathResolver(_layout.RootPath));
                }
                else
                {
                    using var predictor = factory.CreateYoloPredictor(BgiOnnxModel.BgiTree);
                    using var region = new ImageRegion(Cv2.ImRead(Path.Combine(_layout.RootPath, "Assets/Model/Domain/test_petrified_trees.jpg")), 0, 0, drawingBoard: BetterGenshinImpact.Core.Mask.NullMaskWindowDrawingBoard.Instance);
                    if (region.SrcMat.Empty()) throw new FileNotFoundException("缺少已锁定的古树验证图像。");
                    _ = predictor.Predictor.Detect(region.CacheImage);
                }
                token.ThrowIfCancellationRequested();
                return new { scene, engine = "CPU", elapsedMs = timer.Elapsed.TotalMilliseconds, validated = true };
            }, token);
        }
        finally { _benchmarkGate.Release(); }
    }
}
