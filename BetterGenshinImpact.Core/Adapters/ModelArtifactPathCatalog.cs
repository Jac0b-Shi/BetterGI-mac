using BetterGenshinImpact.Core.Artifacts;
using BetterGenshinImpact.Core.Recognition.ONNX;
using System.Reflection;

namespace BetterGenshinImpact.Core.Adapters;

/// <summary>Maps the real upstream model registry fields to the locked macOS artifact layout.</summary>
internal static class ModelArtifactPathCatalog
{
    private static readonly Lazy<IReadOnlyDictionary<string, string>> Paths = new(LoadPaths);

    public static string RelativePath(BgiOnnxModel model)
    {
        ArgumentNullException.ThrowIfNull(model);
        var registryKey = typeof(BgiOnnxModel)
            .GetFields(BindingFlags.Public | BindingFlags.Static)
            .Where(field => field.FieldType == typeof(BgiOnnxModel))
            .FirstOrDefault(field => ReferenceEquals(field.GetValue(null), model))?.Name;
        return registryKey is not null && Paths.Value.TryGetValue(registryKey, out var path)
            ? path
            : model.ModelRelativePath;
    }

    private static IReadOnlyDictionary<string, string> LoadPaths()
    {
        using var stream = typeof(ModelArtifactPathCatalog).Assembly.GetManifestResourceStream(
            "BetterGenshinImpact.Core.ModelArtifacts.Manifest.json")
            ?? throw new FileNotFoundException("The embedded locked model artifact manifest is missing.");
        return ModelArtifactManifestLoader.Load(stream).Artifacts
            .ToDictionary(entry => entry.RegistryKey, entry => entry.RelativePath, StringComparer.Ordinal);
    }
}
