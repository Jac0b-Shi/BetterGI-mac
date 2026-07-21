using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using SharpCompress.Archives;
using SharpCompress.Common;

namespace BetterGenshinImpact.Core.Infrastructure;

/// <summary>
/// Downloader that reads model-artifacts.source-lock.json, downloads the
/// referenced archive, verifies hashes, and places artifacts at canonical destinations.
/// Does NOT couple to Core runtime resolvers, UI, or network fallback logic.
/// </summary>
public sealed class ArtifactDownloader : IDisposable
{
    private readonly HttpClient _http;
    private readonly bool _ownsHttp;

    public ArtifactDownloader(HttpClient? httpClient = null)
    {
        _http = httpClient ?? new HttpClient();
        _ownsHttp = httpClient is null;
    }

    public void Dispose()
    {
        if (_ownsHttp) _http.Dispose();
    }

    // ──────────────────────────────────────────────
    //  Source-lock model (read-only, matches JSON)
    // ──────────────────────────────────────────────

    public sealed class SourceLock
    {
        public int SchemaVersion { get; set; }
        public string ArtifactSetVersion { get; set; } = "";
        public List<SourceEntry> Sources { get; set; } = [];
        public List<ArtifactEntry> Artifacts { get; set; } = [];
    }

    public sealed class SourceEntry
    {
        public string Id { get; set; } = "";
        public string Type { get; set; } = "";
        public string Url { get; set; } = "";
        public string Sha256 { get; set; } = "";
        public string Format { get; set; } = "";
        public long SizeBytes { get; set; }
        public SourceProvenance Provenance { get; set; } = new();
    }

    public sealed class SourceProvenance
    {
        public string Project { get; set; } = "";
        public string ReleaseTag { get; set; } = "";
        public string CommitSha { get; set; } = "";
        public string PublishedAt { get; set; } = "";
    }

    public sealed class ArtifactEntry
    {
        public string DestinationRelativePath { get; set; } = "";
        public string SourceId { get; set; } = "";
        public string MemberPath { get; set; } = "";
        public long SizeBytes { get; set; }
        public string Sha256 { get; set; } = "";
        public string Transformation { get; set; } = "";
        public LicenseEvidenceEntry? LicenseEvidence { get; set; }
    }

    public sealed class LicenseEvidenceEntry
    {
        public string? SpdxId { get; set; }
        public string Source { get; set; } = "";
        public string RedistributionStatus { get; set; } = "";
    }

    // ──────────────────────────────────────────────
    //  Load source-lock
    // ──────────────────────────────────────────────

    public static SourceLock LoadSourceLock(string path)
    {
        var json = File.ReadAllText(path);
        return JsonSerializer.Deserialize<SourceLock>(json, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        }) ?? throw new InvalidDataException($"Failed to deserialize source-lock: {path}");
    }

    // ──────────────────────────────────────────────
    //  Download result
    // ──────────────────────────────────────────────

    public sealed class DownloadResult
    {
        public bool Success { get; set; }
        public string? ArchivePath { get; set; }
        public int ArtifactsExtracted { get; set; }
        public int ArtifactsSkipped { get; set; }
        public List<string> Errors { get; set; } = [];
    }

    public async Task<DownloadResult> EnsureInstalledAsync(
        string sourceLockPath,
        string modelRoot,
        CancellationToken ct = default,
        string? archiveCacheDirectory = null)
    {
        var lockDoc = LoadSourceLock(sourceLockPath);
        var verificationErrors = await VerifyInstalledAsync(lockDoc, modelRoot, ct);
        if (verificationErrors.Count == 0)
        {
            return new DownloadResult
            {
                Success = true,
                ArtifactsSkipped = lockDoc.Artifacts.Count
            };
        }

        var downloaded = await DownloadAsync(sourceLockPath, modelRoot, ct, archiveCacheDirectory);
        if (!downloaded.Success) return downloaded;

        var postInstallErrors = await VerifyInstalledAsync(lockDoc, modelRoot, ct);
        if (postInstallErrors.Count == 0) return downloaded;
        downloaded.Success = false;
        downloaded.Errors.AddRange(postInstallErrors);
        return downloaded;
    }

    public async Task<IReadOnlyList<string>> VerifyInstalledAsync(
        SourceLock lockDoc,
        string modelRoot,
        CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(lockDoc);
        if (string.IsNullOrWhiteSpace(modelRoot))
            return ["modelRoot is null or empty"];

        var errors = new List<string>();
        var root = Path.GetFullPath(modelRoot);
        foreach (var artifact in lockDoc.Artifacts)
        {
            ct.ThrowIfCancellationRequested();
            var relativePath = NormalizeArchiveMember(artifact.DestinationRelativePath);
            if (!IsSafeArchiveMember(relativePath))
            {
                errors.Add($"Unsafe artifact destination path: {artifact.DestinationRelativePath}");
                continue;
            }

            var path = Path.GetFullPath(Path.Combine(root,
                relativePath.Replace('/', Path.DirectorySeparatorChar)));
            if (!path.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.Ordinal))
            {
                errors.Add($"Artifact destination escapes model root: {artifact.DestinationRelativePath}");
                continue;
            }
            if (!File.Exists(path))
            {
                errors.Add($"Artifact is missing: {artifact.DestinationRelativePath}");
                continue;
            }
            var info = new FileInfo(path);
            if (info.Length != artifact.SizeBytes)
            {
                errors.Add($"Artifact size mismatch: {artifact.DestinationRelativePath}");
                continue;
            }
            var hash = await ComputeSha256Async(path);
            if (!hash.Equals(artifact.Sha256, StringComparison.OrdinalIgnoreCase))
                errors.Add($"Artifact SHA-256 mismatch: {artifact.DestinationRelativePath}");
        }
        return errors;
    }

    // ──────────────────────────────────────────────
    //  Main download pipeline
    // ──────────────────────────────────────────────

    /// <summary>
    /// Downloads the archive from source-lock, verifies archive hash, extracts
    /// every locked artifact, verifies each artifact hash, and copies to canonical
    /// destination under modelRoot.
    /// </summary>
    /// <param name="sourceLockPath">Path to model-artifacts.source-lock.json</param>
    /// <param name="modelRoot">
    /// Target root directory. Artifacts will be placed at
    /// <c>modelRoot + "/" + artifact.DestinationRelativePath</c>.
    /// Must not be null, empty, or whitespace.
    /// </param>
    /// <param name="ct">Cancellation token.</param>
    public async Task<DownloadResult> DownloadAsync(
        string sourceLockPath,
        string modelRoot,
        CancellationToken ct = default,
        string? archiveCacheDirectory = null)
    {
        var result = new DownloadResult();

        if (string.IsNullOrWhiteSpace(modelRoot))
        {
            result.Errors.Add("modelRoot is null or empty");
            return result;
        }

        // 1. Load source-lock
        SourceLock lockDoc;
        try
        {
            lockDoc = LoadSourceLock(sourceLockPath);
        }
        catch (Exception ex)
        {
            result.Errors.Add($"Failed to load source-lock: {ex.Message}");
            return result;
        }

        if (lockDoc.Sources.Count == 0)
        {
            result.Errors.Add("Source-lock contains no sources");
            return result;
        }

        var source = lockDoc.Sources[0];
        var tempDir = Path.Combine(Path.GetTempPath(), "bgi-artifacts-" + Guid.NewGuid().ToString("N")[..12]);
        Directory.CreateDirectory(tempDir);

        try
        {
            // 2. Download archive
            var archiveFileName = $"bettergi-{lockDoc.ArtifactSetVersion}.7z";
            var expectedHash = source.Sha256.ToLowerInvariant();
            var archivePath = Path.Combine(tempDir, archiveFileName);
            if (!string.IsNullOrWhiteSpace(archiveCacheDirectory))
            {
                Directory.CreateDirectory(archiveCacheDirectory);
                var cachedPath = Path.Combine(Path.GetFullPath(archiveCacheDirectory), archiveFileName);
                if (File.Exists(cachedPath) &&
                    await ComputeSha256Async(cachedPath) == expectedHash)
                {
                    archivePath = cachedPath;
                    Console.WriteLine($"Using verified cached archive {cachedPath}");
                }
                else
                {
                    if (File.Exists(cachedPath)) File.Delete(cachedPath);
                    Console.WriteLine($"Downloading {source.Url}");
                    await DownloadFileAsync(source.Url, archivePath, source.SizeBytes, ct);
                    Console.WriteLine($"Downloaded {new FileInfo(archivePath).Length:N0} bytes");
                    var downloadedHash = await ComputeSha256Async(archivePath);
                    if (downloadedHash != expectedHash)
                    {
                        result.Errors.Add(
                            $"Archive SHA-256 mismatch: expected {expectedHash}, got {downloadedHash}");
                        return result;
                    }
                    File.Move(archivePath, cachedPath, true);
                    archivePath = cachedPath;
                }
            }
            else
            {
                Console.WriteLine($"Downloading {source.Url}");
                await DownloadFileAsync(source.Url, archivePath, source.SizeBytes, ct);
                Console.WriteLine($"Downloaded {new FileInfo(archivePath).Length:N0} bytes");
            }

            // 3. Verify archive SHA-256
            var archiveHash = await ComputeSha256Async(archivePath);
            if (archiveHash != expectedHash)
            {
                result.Errors.Add(
                    $"Archive SHA-256 mismatch: expected {expectedHash}, got {archiveHash}");
                return result;
            }
            Console.WriteLine($"Archive SHA-256 verified: {archiveHash[..16]}...");

            // 4. Open and validate the 7z in-process. Core distribution must not
            // depend on a Homebrew/system 7z executable.
            // 5. Validate destinations up front, then scan the solid 7z exactly
            // once. Opening every entry separately can decode the same solid
            // block repeatedly and is unusably slow for the official archive.
            modelRoot = Path.GetFullPath(modelRoot);
            Directory.CreateDirectory(modelRoot);
            var pendingArtifacts = new Dictionary<string, (ArtifactEntry Artifact, string Destination)>(StringComparer.Ordinal);
            foreach (var artifact in lockDoc.Artifacts)
            {
                var destinationRelativePath = NormalizeArchiveMember(artifact.DestinationRelativePath);
                if (!IsSafeArchiveMember(destinationRelativePath))
                {
                    result.Errors.Add($"Unsafe artifact destination path: {artifact.DestinationRelativePath}");
                    result.ArtifactsSkipped++;
                    continue;
                }

                var destPath = Path.GetFullPath(Path.Combine(modelRoot,
                    destinationRelativePath.Replace('/', Path.DirectorySeparatorChar)));
                if (!destPath.StartsWith(modelRoot + Path.DirectorySeparatorChar, StringComparison.Ordinal))
                {
                    result.Errors.Add($"Artifact destination escapes model root: {artifact.DestinationRelativePath}");
                    result.ArtifactsSkipped++;
                    continue;
                }
                var memberPath = NormalizeArchiveMember(artifact.MemberPath);
                if (!IsSafeArchiveMember(memberPath))
                {
                    result.Errors.Add($"Unsafe locked archive member path: {artifact.MemberPath}");
                    result.ArtifactsSkipped++;
                    continue;
                }
                pendingArtifacts.Add(memberPath, (artifact, destPath));
            }

            async Task ProcessEntryAsync(string? rawKey, bool isDirectory, Func<Stream> openEntryStream)
            {
                ct.ThrowIfCancellationRequested();
                if (rawKey is null || isDirectory) return;
                var memberPath = NormalizeArchiveMember(rawKey);
                if (!IsSafeArchiveMember(memberPath))
                {
                    throw new InvalidDataException($"Unsafe archive member path: {memberPath}");
                }
                if (!pendingArtifacts.Remove(memberPath, out var lockedArtifact)) return;

                Directory.CreateDirectory(Path.GetDirectoryName(lockedArtifact.Destination)!);
                await using (var input = openEntryStream())
                await using (var output = new FileStream(
                    lockedArtifact.Destination, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    await input.CopyToAsync(output, ct);
                }

                var actualSize = new FileInfo(lockedArtifact.Destination).Length;
                var fileHash = await ComputeSha256Async(lockedArtifact.Destination);
                var artifact = lockedArtifact.Artifact;
                if (actualSize != artifact.SizeBytes || fileHash != artifact.Sha256.ToLowerInvariant())
                {
                    result.Errors.Add(
                        $"Artifact integrity mismatch for {artifact.DestinationRelativePath}: " +
                        $"expected size/hash {artifact.SizeBytes}/{artifact.Sha256[..16]}..., " +
                        $"got {actualSize}/{fileHash[..16]}...");
                    File.Delete(lockedArtifact.Destination);
                    result.ArtifactsSkipped++;
                    return;
                }

                result.ArtifactsExtracted++;
            }

            using var archive = ArchiveFactory.OpenArchive(archivePath);
            if (archive.Type == ArchiveType.SevenZip)
            {
                using var reader = archive.ExtractAllEntries();
                while (reader.MoveToNextEntry())
                {
                    await ProcessEntryAsync(reader.Entry.Key, reader.Entry.IsDirectory, reader.OpenEntryStream);
                }
            }
            else
            {
                foreach (var entry in archive.Entries)
                {
                    await ProcessEntryAsync(entry.Key, entry.IsDirectory, entry.OpenEntryStream);
                }
            }

            foreach (var missing in pendingArtifacts.Values)
            {
                result.Errors.Add($"Archive member not found: {missing.Artifact.MemberPath}");
                result.ArtifactsSkipped++;
            }

            result.ArchivePath = archivePath;
            result.Success = result.Errors.Count == 0;
            return result;
        }
        catch (OperationCanceledException)
        {
            result.Errors.Add("Download cancelled");
            return result;
        }
        catch (Exception ex)
        {
            result.Errors.Add($"Download failed: {ex.Message}");
            return result;
        }
        finally
        {
            // Cleanup temp directory
            try { Directory.Delete(tempDir, recursive: true); }
            catch { /* best effort cleanup */ }
        }
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    private async Task DownloadFileAsync(string url, string path, long expectedSize, CancellationToken ct)
    {
        if (url.StartsWith("file://"))
        {
            var localPath = url["file://".Length..];
            File.Copy(localPath, path, overwrite: true);
            return;
        }

        using var response = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct);
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(ct);
        await using var fs = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None);
        var buffer = new byte[1024 * 1024];
        long downloaded = 0;
        long nextReport = 16L * 1024 * 1024;
        while (true)
        {
            var count = await stream.ReadAsync(buffer, ct);
            if (count == 0) break;
            await fs.WriteAsync(buffer.AsMemory(0, count), ct);
            downloaded += count;
            if (downloaded >= nextReport || downloaded == expectedSize)
            {
                Console.WriteLine($"Runtime archive download: {downloaded:N0} / {expectedSize:N0} bytes");
                nextReport = downloaded + 16L * 1024 * 1024;
            }
        }
    }

    private static async Task<string> ComputeSha256Async(string path)
    {
        await using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        var hash = await SHA256.HashDataAsync(fs);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    private static string NormalizeArchiveMember(string path)
    {
        return path.Replace('\\', '/');
    }

    private static bool IsSafeArchiveMember(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || Path.IsPathRooted(path)) return false;
        return path.Split('/', StringSplitOptions.RemoveEmptyEntries)
            .All(segment => segment is not "." and not "..");
    }
}
