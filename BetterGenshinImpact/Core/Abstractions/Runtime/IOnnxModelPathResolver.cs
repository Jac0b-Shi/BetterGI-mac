using BetterGenshinImpact.Core.Recognition.ONNX;

namespace BetterGenshinImpact.Core.Abstractions.Runtime;

/// <summary>
/// Resolves ONNX model file paths from a BgiOnnxModel registry entry.
/// Implementations must normalize cross-platform path separators.
/// Model root is provided explicitly by the composition root — no static fallback.
/// </summary>
public interface IOnnxModelPathResolver
{
    string ResolveModelPath(BgiOnnxModel model);
    string ResolveCachePath(BgiOnnxModel model);
}
