using BetterGenshinImpact.Core.Infrastructure;
using BetterGenshinImpact.Verification.Framework;
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
}
