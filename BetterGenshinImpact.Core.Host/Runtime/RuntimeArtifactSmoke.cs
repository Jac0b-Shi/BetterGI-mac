using BetterGenshinImpact.Core.Artifacts;
using BetterGenshinImpact.Core.Infrastructure;
using BetterGenshinImpact.Core.Adapters;
using BetterGenshinImpact.Core.Recognition.ONNX;
using BetterGenshinImpact.Core.Runtime.Portable;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>Exercises installed production archives and native loaders without a game session.</summary>
public static class RuntimeArtifactSmoke
{
    public static async Task<object> RunAsync(string runtimeRoot, CancellationToken ct)
    {
        var layout = new RuntimeLayout(runtimeRoot);
        layout.EnsureCreated();
        var manifestRoot = Path.Combine(AppContext.BaseDirectory, "Manifest");
        var lockPath = Path.Combine(manifestRoot, "model-artifacts.source-lock.json");
        using var downloader = new ArtifactDownloader();
        var install = await downloader.EnsureInstalledAsync(lockPath, layout.RootPath, ct, layout.DownloadCachePath);
        if (!install.Success)
            throw new InvalidDataException(string.Join("; ", install.Errors));
        var sourceLock = ArtifactDownloader.LoadSourceLock(lockPath);
        var manifest = ModelArtifactManifestLoader.Parse(
            await File.ReadAllTextAsync(Path.Combine(manifestRoot, "model-artifacts.manifest.json"), ct));
        var factory = new BgiOnnxFactory(new CpuOnnxRuntimePlatform(new ModelRootPathResolver(layout.RootPath)));
        foreach (var model in manifest.Artifacts)
        {
            ct.ThrowIfCancellationRequested();
            var field = typeof(BgiOnnxModel).GetField(model.RegistryKey,
                System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
            var registryModel = field?.GetValue(null) as BgiOnnxModel
                ?? throw new InvalidDataException($"Model is not registered: {model.RegistryKey}");
            using var session = factory.CreateInferenceSession(registryModel);
            if (session.InputMetadata.Count == 0 || session.OutputMetadata.Count == 0)
                throw new InvalidDataException($"Model has no inputs or outputs: {model.RegistryKey}");
        }
        var mapImages = sourceLock.Artifacts.Where(a => a.DestinationRelativePath.StartsWith("Assets/Map/", StringComparison.Ordinal)
            && Path.GetExtension(a.DestinationRelativePath) is ".webp" or ".png").ToArray();
        foreach (var map in mapImages)
        {
            ct.ThrowIfCancellationRequested();
            using var image = Cv2.ImRead(Path.Combine(layout.RootPath, map.DestinationRelativePath), ImreadModes.Unchanged);
            if (image.Empty()) throw new InvalidDataException($"Map cannot be decoded: {map.DestinationRelativePath}");
        }
        return new { sourceLock.ArtifactSetVersion, installed = install.ArtifactsExtracted,
            verified = install.ArtifactsSkipped, modelsLoaded = manifest.Artifacts.Count, mapImagesLoaded = mapImages.Length };
    }
}
