using Microsoft.ML.OnnxRuntime;

namespace BetterGenshinImpact.Core.Recognition.ONNX;

public interface IOnnxRuntimePlatform
{
    ProviderType[] ProviderTypes { get; }
    int DmlDeviceId { get; }
    int CudaDeviceId { get; }
    bool OptimizedModel { get; }
    bool TrtUseEmbedMode { get; }
    string OpenVinoDevice { get; }
    bool EnableCache { get; }
    bool CpuOcr { get; }
    bool OpenVinoCache { get; }
    BgiYoloPredictor CreateYoloPredictor(BgiOnnxModel model);
    InferenceSession CreateInferenceSession(BgiOnnxModel model, bool ocr = false);
}
