using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Recognition.ONNX;
using Microsoft.ML.OnnxRuntime;

namespace BetterGenshinImpact.Core.Recognition.ONNX;

/// <summary>
/// Core/macOS ONNX model factory: CPU-only InferenceSession creation.
/// Requires <see cref="IOnnxModelPathResolver"/> for explicit model root resolution.
/// See WPF authoritative for GPU/CUDA/TensorRT-enabled version.
/// </summary>
public class BgiOnnxFactory
{
    private readonly IOnnxModelPathResolver _pathResolver;

    public BgiOnnxFactory(IOnnxModelPathResolver pathResolver)
    {
        _pathResolver = pathResolver ?? throw new ArgumentNullException(nameof(pathResolver));
    }

    public InferenceSession CreateInferenceSession(BgiOnnxModel model, bool ocr = false)
    {
        var modelPath = _pathResolver.ResolveModelPath(model);
        return new InferenceSession(modelPath);
    }
}
