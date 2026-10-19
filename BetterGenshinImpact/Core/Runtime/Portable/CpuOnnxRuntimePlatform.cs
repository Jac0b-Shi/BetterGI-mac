using System;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Recognition.ONNX;
using Microsoft.ML.OnnxRuntime;

namespace BetterGenshinImpact.Core.Runtime.Portable;

/// <summary>Portable CPU ONNX Runtime adapter used by the macOS Core Host.</summary>
public sealed class CpuOnnxRuntimePlatform(IOnnxModelPathResolver pathResolver,
    int cpuThreads = 0, PaddleOcrCpuOptions? paddleOcrCpu = null) : IOnnxRuntimePlatform
{
    private readonly IOnnxModelPathResolver _pathResolver = pathResolver
        ?? throw new ArgumentNullException(nameof(pathResolver));
    public ProviderType[] ProviderTypes => [ProviderType.Cpu];
    public int DmlDeviceId => -1;
    public int CudaDeviceId => -1;
    public bool OptimizedModel => false;
    public bool TrtUseEmbedMode => false;
    public string OpenVinoDevice => string.Empty;
    public bool EnableCache => false;
    public bool CpuOcr => true;
    public bool OpenVinoCache => false;

    public BgiYoloPredictor CreateYoloPredictor(BgiOnnxModel model)
    {
        ArgumentNullException.ThrowIfNull(model);
        var options = CreateOptions(model);
        try { return new BgiYoloPredictor(model, _pathResolver.ResolveModelPath(model), options); }
        catch { options.Dispose(); throw; }
    }

    public InferenceSession CreateInferenceSession(BgiOnnxModel model, bool ocr = false)
    {
        ArgumentNullException.ThrowIfNull(model);
        using var options = CreateOptions(model);
        return new InferenceSession(_pathResolver.ResolveModelPath(model), options);
    }
    internal SessionOptions CreateOptions(BgiOnnxModel model)
    {
        var options = new SessionOptions();
        try
        {
            var ocr = paddleOcrCpu ?? new();
            var detection = model.Name.StartsWith("PpOcrDet", StringComparison.Ordinal);
            var isOcr = detection || model.Name.StartsWith("PpOcrRec", StringComparison.Ordinal);
            if (!isOcr || ocr.Mode != PaddleOcrCpuMode.RuntimeAuto)
                options.IntraOpNumThreads = cpuThreads;
            if (isOcr && ocr.Resolve(detection) is { } threads)
            {
                options.IntraOpNumThreads = threads.IntraOpThreads;
                options.InterOpNumThreads = threads.InterOpThreads;
                options.ExecutionMode = threads.ParallelExecution ? ExecutionMode.ORT_PARALLEL : ExecutionMode.ORT_SEQUENTIAL;
                options.AddSessionConfigEntry("session.intra_op.allow_spinning", threads.AllowSpinning ? "1" : "0");
                options.AddSessionConfigEntry("session.inter_op.allow_spinning", threads.AllowSpinning ? "1" : "0");
            }
            options.AppendExecutionProvider_CPU();
            return options;
        }
        catch { options.Dispose(); throw; }
    }
}
