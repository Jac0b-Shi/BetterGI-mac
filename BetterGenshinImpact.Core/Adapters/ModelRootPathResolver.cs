using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Recognition.ONNX;

namespace BetterGenshinImpact.Core.Adapters;

/// <summary>
/// Resolves ONNX model paths relative to an explicit model root directory.
/// Normalizes backslashes and forward slashes to the platform's directory separator.
/// </summary>
public sealed class ModelRootPathResolver : IOnnxModelPathResolver
{
    private readonly string _modelRoot;

    public ModelRootPathResolver(string modelRoot)
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

    public string ResolveCachePath(BgiOnnxModel model)
    {
        var normalized = NormalizePath(model.CacheRelativePath);
        return Path.GetFullPath(Path.Combine(_modelRoot, normalized));
    }

    private static string NormalizePath(string path)
    {
        return path.Replace('\\', Path.DirectorySeparatorChar)
                   .Replace('/', Path.DirectorySeparatorChar);
    }
}
