using BetterGenshinImpact.Core.Recognition.ONNX;

namespace BetterGenshinImpact.Core.Abstractions.Runtime;

/// <summary>
/// Resolves OCR model and sidecar resource paths relative to an explicitly
/// configured model root. Sidecars include PaddleOCR inference.yml, preheat
/// images, and the Yap index dictionary.
/// Sidecar resources are not ONNX models —
/// this interface is kept separate from <see cref="IOnnxModelPathResolver"/>.
/// </summary>
public interface IOcrResourcePathResolver
{
    string ResolveModelPath(BgiOnnxModel model);
    string ResolveModelDirectory(BgiOnnxModel model);
    string ResolveSidecarPath(string relativePath);
}
