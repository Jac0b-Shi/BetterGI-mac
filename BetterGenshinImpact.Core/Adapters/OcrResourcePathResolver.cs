using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Recognition.ONNX;

namespace BetterGenshinImpact.Core.Adapters;

/// <summary>
/// Resolves PaddleOCR resource paths relative to an explicit model root directory.
/// Normalizes backslashes and forward slashes to the platform's directory separator.
/// </summary>
public sealed class OcrResourcePathResolver : IOcrResourcePathResolver
{
    private readonly string _modelRoot;

    public OcrResourcePathResolver(string modelRoot)
    {
        if (string.IsNullOrWhiteSpace(modelRoot))
            throw new ArgumentException("Model root must be non-empty.", nameof(modelRoot));
        _modelRoot = Path.GetFullPath(modelRoot);
    }

    public string ResolveModelPath(BgiOnnxModel model)
    {
        var normalized = NormalizePath(ModelArtifactPathCatalog.RelativePath(model));
        return Path.GetFullPath(Path.Combine(_modelRoot, normalized));
    }

    public string ResolveModelDirectory(BgiOnnxModel model)
    {
        var modelPath = ResolveModelPath(model);
        var dir = Path.GetDirectoryName(modelPath);
        return dir ?? throw new InvalidOperationException($"Cannot determine directory for model path: {modelPath}");
    }

    public string ResolveSidecarPath(string relativePath)
    {
        var normalized = NormalizePath(relativePath);
        return Path.GetFullPath(Path.Combine(_modelRoot, normalized));
    }

    private static string NormalizePath(string path)
    {
        return path.Replace('\\', Path.DirectorySeparatorChar)
                   .Replace('/', Path.DirectorySeparatorChar);
    }
}
