using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
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
    public const string ProgressOutputPrefix = "@@bettergi-artifact-progress@@";

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

    public sealed record ArtifactProgress(
        string Phase,
        string SourceId,
        string DisplayName,
        long BytesCompleted,
        long BytesTotal,
        int SourceIndex,
        int SourceCount);

    public async Task<DownloadResult> EnsureInstalledAsync(
        string sourceLockPath,
        string modelRoot,
        CancellationToken ct = default,
        string? archiveCacheDirectory = null,
        Action<ArtifactProgress>? progress = null)
    {
        var lockDoc = LoadSourceLock(sourceLockPath);
        progress?.Invoke(new ArtifactProgress("verifying", "", "正在校验运行资源", 0, 0, 0, 0));
        var verificationErrors = new List<string>();
        var sourcesToInstall = new HashSet<string>(StringComparer.Ordinal);
        foreach (var artifact in lockDoc.Artifacts)
        {
            ct.ThrowIfCancellationRequested();
            var error = await VerifyArtifactAsync(artifact, modelRoot, ct);
            if (error is null) continue;
            verificationErrors.Add(error);
            sourcesToInstall.Add(artifact.SourceId);
        }
        if (verificationErrors.Count == 0)
        {
            progress?.Invoke(new ArtifactProgress("completed", "", "运行资源已就绪", 0, 0, 0, 0));
            return new DownloadResult
            {
                Success = true,
                ArtifactsSkipped = lockDoc.Artifacts.Count
            };
        }

        var downloaded = await DownloadSourcesAsync(
            lockDoc,
            modelRoot,
            ct,
            archiveCacheDirectory,
            progress,
            sourcesToInstall);
        if (!downloaded.Success) return downloaded;

        var postInstallErrors = await VerifyInstalledAsync(lockDoc, modelRoot, ct);
        if (postInstallErrors.Count == 0)
        {
            progress?.Invoke(new ArtifactProgress("completed", "", "运行资源已就绪", 0, 0, 0, 0));
            return downloaded;
        }
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
        foreach (var artifact in lockDoc.Artifacts)
        {
            ct.ThrowIfCancellationRequested();
            var error = await VerifyArtifactAsync(artifact, modelRoot, ct);
            if (error is not null) errors.Add(error);
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
        string? archiveCacheDirectory = null,
        Action<ArtifactProgress>? progress = null)
    {
        if (string.IsNullOrWhiteSpace(modelRoot))
        {
            return new DownloadResult { Errors = ["modelRoot is null or empty"] };
        }

        // 1. Load source-lock
        SourceLock lockDoc;
        try
        {
            lockDoc = LoadSourceLock(sourceLockPath);
        }
        catch (Exception ex)
        {
            return new DownloadResult { Errors = [$"Failed to load source-lock: {ex.Message}"] };
        }

        return await DownloadSourcesAsync(
            lockDoc,
            modelRoot,
            ct,
            archiveCacheDirectory,
            progress,
            sourceIdsToInstall: null);
    }

    private async Task<DownloadResult> DownloadSourcesAsync(
        SourceLock lockDoc,
        string modelRoot,
        CancellationToken ct,
        string? archiveCacheDirectory,
        Action<ArtifactProgress>? progress,
        IReadOnlySet<string>? sourceIdsToInstall)
    {
        var result = new DownloadResult();

        if (lockDoc.Sources.Count == 0)
        {
            result.Errors.Add("Source-lock contains no sources");
            return result;
        }

        var sourceIds = lockDoc.Sources.Select(source => source.Id).ToHashSet(StringComparer.Ordinal);
        var unknownSourceIds = lockDoc.Artifacts
            .Select(artifact => artifact.SourceId)
            .Where(sourceId => !sourceIds.Contains(sourceId))
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (unknownSourceIds.Length > 0)
        {
            result.Errors.Add($"Artifacts reference unknown sources: {string.Join(", ", unknownSourceIds)}");
            return result;
        }

        var tempDir = Path.Combine(Path.GetTempPath(), "bgi-artifacts-" + Guid.NewGuid().ToString("N")[..12]);
        Directory.CreateDirectory(tempDir);

        try
        {
            modelRoot = Path.GetFullPath(modelRoot);
            Directory.CreateDirectory(modelRoot);
            var selectedSources = lockDoc.Sources
                .Where(source => sourceIdsToInstall is null || sourceIdsToInstall.Contains(source.Id))
                .ToArray();
            var sourceOrdinal = 0;

            foreach (var source in selectedSources)
            {
                sourceOrdinal++;
                var sourceArtifacts = lockDoc.Artifacts
                    .Where(artifact => string.Equals(artifact.SourceId, source.Id, StringComparison.Ordinal))
                    .ToArray();
                if (sourceArtifacts.Length == 0) continue;

                var artifactsToInstall = new List<ArtifactEntry>();
                foreach (var artifact in sourceArtifacts)
                {
                    if (await VerifyArtifactAsync(artifact, modelRoot, ct) is null)
                        result.ArtifactsSkipped++;
                    else
                        artifactsToInstall.Add(artifact);
                }
                if (artifactsToInstall.Count == 0) continue;

                // 2. Download archive
                var expectedHash = source.Sha256.ToLowerInvariant();
                var archiveExtension = source.Format.All(char.IsLetterOrDigit) && source.Format.Length > 0
                    ? source.Format.ToLowerInvariant()
                    : "archive";
                var archiveFileName = $"bettergi-{expectedHash}.{archiveExtension}";
                var archivePath = Path.Combine(tempDir, archiveFileName);
                var displayName = SourceDisplayName(source);
                if (!string.IsNullOrWhiteSpace(archiveCacheDirectory))
                {
                    Directory.CreateDirectory(archiveCacheDirectory);
                    var cachedPath = Path.Combine(Path.GetFullPath(archiveCacheDirectory), archiveFileName);
                    var verifiedCache = await FindVerifiedCacheAsync(
                        archiveCacheDirectory,
                        cachedPath,
                        source.SizeBytes,
                        expectedHash,
                        ct);
                    if (verifiedCache is not null)
                    {
                        archivePath = verifiedCache;
                        Console.WriteLine($"Using verified cached archive {archivePath}");
                        progress?.Invoke(new ArtifactProgress(
                            "cached", source.Id, displayName, source.SizeBytes, source.SizeBytes,
                            sourceOrdinal, selectedSources.Length));
                    }
                    else
                    {
                        Console.WriteLine($"Downloading {source.Url}");
                        var partialPath = cachedPath + ".part";
                        await DownloadFileAsync(
                            source.Url,
                            partialPath,
                            source.SizeBytes,
                            ct,
                            downloaded => progress?.Invoke(new ArtifactProgress(
                                "downloading", source.Id, displayName, downloaded, source.SizeBytes,
                                sourceOrdinal, selectedSources.Length)));
                        Console.WriteLine($"Downloaded {new FileInfo(partialPath).Length:N0} bytes");
                        var downloadedHash = await ComputeSha256Async(partialPath);
                        if (downloadedHash != expectedHash)
                        {
                            File.Delete(partialPath);
                            result.Errors.Add(
                                $"Archive SHA-256 mismatch: expected {expectedHash}, got {downloadedHash}");
                            return result;
                        }
                        File.Move(partialPath, cachedPath, true);
                        archivePath = cachedPath;
                    }
                }
                else
                {
                    Console.WriteLine($"Downloading {source.Url}");
                    await DownloadFileAsync(
                        source.Url,
                        archivePath,
                        source.SizeBytes,
                        ct,
                        downloaded => progress?.Invoke(new ArtifactProgress(
                            "downloading", source.Id, displayName, downloaded, source.SizeBytes,
                            sourceOrdinal, selectedSources.Length)));
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
                progress?.Invoke(new ArtifactProgress(
                    "extracting", source.Id, displayName, source.SizeBytes, source.SizeBytes,
                    sourceOrdinal, selectedSources.Length));

                // 4. Open and validate the 7z in-process. Core distribution must not
                // depend on a Homebrew/system 7z executable.
                // 5. Validate destinations up front, then scan the solid 7z exactly
                // once. Opening every entry separately can decode the same solid
                // block repeatedly and is unusably slow for the official archive.
                var pendingArtifacts = new Dictionary<string, (ArtifactEntry Artifact, string Destination)>(StringComparer.Ordinal);
                foreach (var artifact in artifactsToInstall)
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

                result.ArchivePath ??= archivePath;
            }

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

    private async Task DownloadFileAsync(
        string url,
        string path,
        long expectedSize,
        CancellationToken ct,
        Action<long>? progress)
    {
        if (url.StartsWith("file://"))
        {
            var localPath = url["file://".Length..];
            File.Copy(localPath, path, overwrite: true);
            progress?.Invoke(new FileInfo(path).Length);
            return;
        }

        const int maxAttempts = 4;
        for (var attempt = 1; attempt <= maxAttempts; attempt++)
        {
            ct.ThrowIfCancellationRequested();
            var downloaded = File.Exists(path) ? new FileInfo(path).Length : 0;
            if (downloaded > expectedSize)
            {
                File.Delete(path);
                downloaded = 0;
            }
            if (downloaded == expectedSize)
            {
                progress?.Invoke(downloaded);
                return;
            }

            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, url);
                if (downloaded > 0) request.Headers.Range = new RangeHeaderValue(downloaded, null);
                using var response = await _http.SendAsync(
                    request, HttpCompletionOption.ResponseHeadersRead, ct);

                var append = downloaded > 0 && response.StatusCode == HttpStatusCode.PartialContent;
                if (append && response.Content.Headers.ContentRange?.From != downloaded)
                    throw new InvalidDataException("Server returned an invalid resume range.");
                if (!append)
                {
                    response.EnsureSuccessStatusCode();
                    downloaded = 0;
                }

                await using var stream = await response.Content.ReadAsStreamAsync(ct);
                await using var fs = new FileStream(
                    path,
                    append ? FileMode.Append : FileMode.Create,
                    FileAccess.Write,
                    FileShare.None);
                var buffer = new byte[1024 * 1024];
                var nextReport = downloaded;
                progress?.Invoke(downloaded);
                while (true)
                {
                    var count = await stream.ReadAsync(buffer, ct);
                    if (count == 0) break;
                    await fs.WriteAsync(buffer.AsMemory(0, count), ct);
                    downloaded += count;
                    if (downloaded > expectedSize)
                        throw new InvalidDataException("Downloaded archive exceeds its locked size.");
                    if (downloaded >= nextReport || downloaded == expectedSize)
                    {
                        progress?.Invoke(downloaded);
                        nextReport = downloaded + 4L * 1024 * 1024;
                    }
                }

                if (downloaded == expectedSize) return;
                throw new EndOfStreamException(
                    $"Download ended at {downloaded:N0} of {expectedSize:N0} bytes.");
            }
            catch (Exception ex) when (
                ex is HttpRequestException or IOException &&
                attempt < maxAttempts &&
                !ct.IsCancellationRequested)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(250 * attempt), ct);
            }
        }

        throw new EndOfStreamException("Download did not reach its locked size.");
    }

    private static async Task<string?> FindVerifiedCacheAsync(
        string cacheDirectory,
        string canonicalPath,
        long expectedSize,
        string expectedHash,
        CancellationToken ct)
    {
        if (File.Exists(canonicalPath) &&
            new FileInfo(canonicalPath).Length == expectedSize &&
            await ComputeSha256Async(canonicalPath) == expectedHash)
            return canonicalPath;

        if (File.Exists(canonicalPath)) File.Delete(canonicalPath);
        foreach (var candidate in Directory.EnumerateFiles(cacheDirectory))
        {
            ct.ThrowIfCancellationRequested();
            if (candidate.Equals(canonicalPath, StringComparison.Ordinal) ||
                candidate.EndsWith(".part", StringComparison.OrdinalIgnoreCase) ||
                new FileInfo(candidate).Length != expectedSize)
                continue;
            if (await ComputeSha256Async(candidate) != expectedHash) continue;
            File.Move(candidate, canonicalPath, true);
            return canonicalPath;
        }
        return null;
    }

    private static async Task<string?> VerifyArtifactAsync(
        ArtifactEntry artifact,
        string modelRoot,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(modelRoot)) return "modelRoot is null or empty";
        var root = Path.GetFullPath(modelRoot);
        var relativePath = NormalizeArchiveMember(artifact.DestinationRelativePath);
        if (!IsSafeArchiveMember(relativePath))
            return $"Unsafe artifact destination path: {artifact.DestinationRelativePath}";
        var path = Path.GetFullPath(Path.Combine(
            root, relativePath.Replace('/', Path.DirectorySeparatorChar)));
        if (!path.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.Ordinal))
            return $"Artifact destination escapes model root: {artifact.DestinationRelativePath}";
        if (!File.Exists(path)) return $"Artifact is missing: {artifact.DestinationRelativePath}";
        if (new FileInfo(path).Length != artifact.SizeBytes)
            return $"Artifact size mismatch: {artifact.DestinationRelativePath}";
        ct.ThrowIfCancellationRequested();
        var hash = await ComputeSha256Async(path);
        return hash.Equals(artifact.Sha256, StringComparison.OrdinalIgnoreCase)
            ? null
            : $"Artifact SHA-256 mismatch: {artifact.DestinationRelativePath}";
    }

    private static string SourceDisplayName(SourceEntry source)
    {
        var release = string.IsNullOrWhiteSpace(source.Provenance.ReleaseTag)
            ? source.Id
            : source.Provenance.ReleaseTag;
        release = release.Split('/', StringSplitOptions.RemoveEmptyEntries).LastOrDefault() ?? release;
        if (source.Id.Contains("assets-map", StringComparison.OrdinalIgnoreCase))
            return $"地图资源 {release}";
        if (source.Id.Contains("assets-model", StringComparison.OrdinalIgnoreCase))
            return $"模型资源 {release}";
        return $"BetterGI {release}";
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
