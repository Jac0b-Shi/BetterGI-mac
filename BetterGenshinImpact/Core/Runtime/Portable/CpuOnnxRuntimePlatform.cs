using System;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Recognition.ONNX;
using Microsoft.ML.OnnxRuntime;

namespace BetterGenshinImpact.Core.Runtime.Portable;

/// <summary>Portable CPU ONNX Runtime adapter used by the macOS Core Host.</summary>
public sealed class CpuOnnxRuntimePlatform(IOnnxModelPathResolver pathResolver) : IOnnxRuntimePlatform
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
        return new BgiYoloPredictor(model, _pathResolver.ResolveModelPath(model), new SessionOptions());
    }

    public InferenceSession CreateInferenceSession(BgiOnnxModel model, bool ocr = false)
    {
        ArgumentNullException.ThrowIfNull(model);
        return new InferenceSession(_pathResolver.ResolveModelPath(model));
    }
}
