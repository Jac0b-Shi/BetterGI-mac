using BetterGenshinImpact.Core.Infrastructure;
using BetterGenshinImpact.Verification.Framework;
using System.Net;
using System.Net.Http.Headers;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class ArtifactDownloaderSuite : IVerificationSuite
{
    public string Name => "artifact-downloader";

    public async Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var root = Path.Combine(Path.GetTempPath(), $"bgi-multi-source-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            var first = CreateArchive(root, "first", "archive-a/model.bin", [1, 2, 3]);
            var second = CreateArchive(root, "second", "archive-b/data.csv", [4, 5, 6, 7]);
            var lockDocument = new ArtifactDownloader.SourceLock
            {
                SchemaVersion = 1,
                ArtifactSetVersion = "multi-source-test",
                Sources = [first.Source, second.Source],
                Artifacts =
                [
                    CreateArtifact(first.Source.Id, "archive-a/model.bin", "Assets/A/model.bin", [1, 2, 3]),
                    CreateArtifact(second.Source.Id, "archive-b/data.csv", "Assets/B/data.csv", [4, 5, 6, 7]),
                ],
            };
            var lockPath = Path.Combine(root, "lock.json");
            await File.WriteAllTextAsync(lockPath, JsonSerializer.Serialize(
                lockDocument,
                new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }),
                cancellationToken);

            var output = Path.Combine(root, "output");
            var cache = Path.Combine(root, "cache");
            using var downloader = new ArtifactDownloader();
            var result = await downloader.DownloadAsync(
                lockPath, output, cancellationToken, cache);

            context.Require(result.Success, string.Join("; ", result.Errors));
            context.Require(result.ArtifactsExtracted == 2,
                $"Expected two extracted artifacts, got {result.ArtifactsExtracted}.");
            context.Require(File.ReadAllBytes(Path.Combine(output, "Assets/A/model.bin"))
                .SequenceEqual(new byte[] { 1, 2, 3 }), "First source artifact did not match.");
            context.Require(File.ReadAllBytes(Path.Combine(output, "Assets/B/data.csv"))
                .SequenceEqual(new byte[] { 4, 5, 6, 7 }), "Second source artifact did not match.");
            context.Require(Directory.EnumerateFiles(cache, "*.zip").Count() == 2,
                "Each locked source must retain its own verified cache archive.");

            var firstCache = Path.Combine(cache, $"bettergi-{first.Source.Sha256}.zip");
            var secondCache = Path.Combine(cache, $"bettergi-{second.Source.Sha256}.zip");
            context.Require(File.Exists(firstCache) && File.Exists(secondCache),
                "Archive caches must be content-addressed by their locked SHA-256.");

            File.Delete(Path.Combine(output, "Assets/B/data.csv"));
            File.Delete(secondCache);
            File.Delete(first.Path);
            lockDocument.ArtifactSetVersion = "map-only-update";
            await File.WriteAllTextAsync(lockPath, JsonSerializer.Serialize(
                lockDocument,
                new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }),
                cancellationToken);
            var selectiveResult = await downloader.EnsureInstalledAsync(
                lockPath, output, cancellationToken, cache);
            context.Require(selectiveResult.Success, string.Join("; ", selectiveResult.Errors));
            context.Require(selectiveResult.ArtifactsExtracted == 1,
                "A source-lock update must install only the source containing invalid artifacts.");
            context.Require(File.Exists(Path.Combine(output, "Assets/B/data.csv")),
                "Selective source installation did not restore the invalid artifact.");

            var legacyRoot = Path.Combine(root, "legacy-reuse");
            var legacyCache = Path.Combine(legacyRoot, "cache");
            Directory.CreateDirectory(legacyCache);
            File.Copy(firstCache, Path.Combine(legacyCache, "bettergi-legacy-name.zip"));
            var legacyLock = new ArtifactDownloader.SourceLock
            {
                SchemaVersion = 1,
                ArtifactSetVersion = "different-version",
                Sources = [first.Source],
                Artifacts = [lockDocument.Artifacts[0]],
            };
            var legacyLockPath = Path.Combine(legacyRoot, "lock.json");
            await File.WriteAllTextAsync(legacyLockPath, JsonSerializer.Serialize(
                legacyLock,
                new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }),
                cancellationToken);
            var legacyResult = await downloader.EnsureInstalledAsync(
                legacyLockPath,
                Path.Combine(legacyRoot, "output"),
                cancellationToken,
                legacyCache);
            context.Require(legacyResult.Success, string.Join("; ", legacyResult.Errors));
            context.Require(File.Exists(Path.Combine(legacyCache, $"bettergi-{first.Source.Sha256}.zip")),
                "A verified legacy cache was not migrated to its content-addressed name.");

            var resumeRoot = Path.Combine(root, "resume");
            Directory.CreateDirectory(resumeRoot);
            var archiveBytes = await File.ReadAllBytesAsync(second.Path, cancellationToken);
            var resumeSource = new ArtifactDownloader.SourceEntry
            {
                Id = second.Source.Id,
                Type = second.Source.Type,
                Url = "https://verification.invalid/archive.zip",
                Sha256 = second.Source.Sha256,
                Format = second.Source.Format,
                SizeBytes = second.Source.SizeBytes,
                Provenance = second.Source.Provenance,
            };
            var resumeLock = new ArtifactDownloader.SourceLock
            {
                SchemaVersion = 1,
                ArtifactSetVersion = "resume-test",
                Sources = [resumeSource],
                Artifacts = [lockDocument.Artifacts[1]],
            };
            var resumeLockPath = Path.Combine(resumeRoot, "lock.json");
            await File.WriteAllTextAsync(resumeLockPath, JsonSerializer.Serialize(
                resumeLock,
                new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }),
                cancellationToken);
            var resumeHandler = new InterruptedDownloadHandler(archiveBytes);
            using var resumeDownloader = new ArtifactDownloader(new HttpClient(resumeHandler));
            var resumeResult = await resumeDownloader.EnsureInstalledAsync(
                resumeLockPath,
                Path.Combine(resumeRoot, "output"),
                cancellationToken,
                Path.Combine(resumeRoot, "cache"));
            context.Require(resumeResult.Success, string.Join("; ", resumeResult.Errors));
            context.Require(resumeHandler.RequestCount == 2 && resumeHandler.ResumeOffset > 0,
                "An interrupted HTTP download did not resume with a Range request.");
            context.Require(!Directory.EnumerateFiles(
                    Path.Combine(resumeRoot, "cache"), "*.part").Any(),
                "A completed resumed download left a partial cache behind.");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    private static (string Path, ArtifactDownloader.SourceEntry Source) CreateArchive(
        string root,
        string id,
        string memberPath,
        byte[] content)
    {
        var sourceDirectory = Path.Combine(root, id);
        var file = Path.Combine(sourceDirectory, memberPath);
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        File.WriteAllBytes(file, content);
        var archivePath = Path.Combine(root, $"{id}.zip");
        ZipFile.CreateFromDirectory(sourceDirectory, archivePath);
        return (archivePath, new ArtifactDownloader.SourceEntry
        {
            Id = id,
            Type = "archive",
            Url = new Uri(archivePath).AbsoluteUri,
            Sha256 = Hash(File.ReadAllBytes(archivePath)),
            Format = "zip",
            SizeBytes = new FileInfo(archivePath).Length,
            Provenance = new ArtifactDownloader.SourceProvenance
            {
                Project = "verification",
                ReleaseTag = id,
                CommitSha = new string('0', 40),
                PublishedAt = "2026-01-01T00:00:00Z",
            },
        });
    }

    private static ArtifactDownloader.ArtifactEntry CreateArtifact(
        string sourceId,
        string memberPath,
        string destination,
        byte[] content) => new()
        {
            SourceId = sourceId,
            MemberPath = memberPath,
            DestinationRelativePath = destination,
            SizeBytes = content.LongLength,
            Sha256 = Hash(content),
            Transformation = "relocate",
            LicenseEvidence = new ArtifactDownloader.LicenseEvidenceEntry
            {
                Source = "verification fixture",
                RedistributionStatus = "test-only",
            },
        };

    private static string Hash(byte[] bytes) =>
        Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();

    private sealed class InterruptedDownloadHandler(byte[] content) : HttpMessageHandler
    {
        public int RequestCount { get; private set; }
        public long ResumeOffset { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestCount++;
            var requestedOffset = request.Headers.Range?.Ranges.Single().From;
            if (RequestCount == 1)
            {
                var firstLength = Math.Max(1, content.Length / 2);
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new ByteArrayContent(content[..firstLength]),
                });
            }

            ResumeOffset = requestedOffset ?? 0;
            var offset = checked((int)ResumeOffset);
            var response = new HttpResponseMessage(HttpStatusCode.PartialContent)
            {
                Content = new ByteArrayContent(content[offset..]),
            };
            response.Content.Headers.ContentRange = new ContentRangeHeaderValue(
                offset,
                content.Length - 1,
                content.Length);
            return Task.FromResult(response);
        }
    }
}
