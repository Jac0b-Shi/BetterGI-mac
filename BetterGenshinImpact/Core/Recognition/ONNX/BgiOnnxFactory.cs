using System;
using Microsoft.ML.OnnxRuntime;

namespace BetterGenshinImpact.Core.Recognition.ONNX;

/// <summary>
/// Shared BetterGI ONNX facade. Provider selection and native session construction are supplied
/// by the host runtime; all consumers use this single business-facing type.
/// </summary>
public sealed class BgiOnnxFactory(IOnnxRuntimePlatform runtime)
{
    private readonly IOnnxRuntimePlatform _runtime = runtime ?? throw new ArgumentNullException(nameof(runtime));
    public ProviderType[] ProviderTypes => _runtime.ProviderTypes;
    public int DmlDeviceId => _runtime.DmlDeviceId;
    public int CudaDeviceId => _runtime.CudaDeviceId;
    public bool OptimizedModel => _runtime.OptimizedModel;
    public bool TrtUseEmbedMode => _runtime.TrtUseEmbedMode;
    public string OpenVinoDevice => _runtime.OpenVinoDevice;
    public bool EnableCache => _runtime.EnableCache;
    public bool CpuOcr => _runtime.CpuOcr;
    public bool OpenVinoCache => _runtime.OpenVinoCache;
    public BgiYoloPredictor CreateYoloPredictor(BgiOnnxModel model) => _runtime.CreateYoloPredictor(model);
    public InferenceSession CreateInferenceSession(BgiOnnxModel model, bool ocr = false) =>
        _runtime.CreateInferenceSession(model, ocr);
#if !BGI_PLATFORM_MAC
    public BgiOnnxFactory(Microsoft.Extensions.Logging.ILogger<BgiOnnxFactory> logger)
        : this(new WindowsOnnxRuntimePlatform(logger)) { }
#endif
}
