using BetterGenshinImpact.Core.Infrastructure;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class RuntimeArtifactProvisioner(RuntimeLayout layout, ILogger logger)
{
    private readonly object _gate = new();
    private RuntimeArtifactStatus? _completed;

    public RuntimeArtifactStatus EnsureInstalled(CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            if (_completed is not null) return _completed;
            var sourceLockPath = Path.Combine(
                AppContext.BaseDirectory, "Manifest", "model-artifacts.source-lock.json");
            if (!File.Exists(sourceLockPath))
                throw new FileNotFoundException("The published Core artifact source-lock is missing.", sourceLockPath);

            using var downloader = new ArtifactDownloader();
            logger.LogInformation("Verifying locked BetterGI runtime artifacts under {Root}", layout.RootPath);
            var result = downloader.EnsureInstalledAsync(
                    sourceLockPath, layout.RootPath, cancellationToken, layout.DownloadCachePath)
                .GetAwaiter().GetResult();
            if (!result.Success)
                throw new InvalidDataException(
                    "Unable to install locked BetterGI runtime artifacts: " + string.Join("; ", result.Errors));

            _completed = new RuntimeArtifactStatus(
                result.ArtifactsExtracted,
                result.ArtifactsSkipped,
                sourceLockPath);
            logger.LogInformation(
                "Locked BetterGI runtime artifacts ready: extracted={Extracted}, verified={Verified}",
                _completed.Extracted, _completed.VerifiedExisting);
            return _completed;
        }
    }
}

public sealed record RuntimeArtifactStatus(int Extracted, int VerifiedExisting, string SourceLockPath);
