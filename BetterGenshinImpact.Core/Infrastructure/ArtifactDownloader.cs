using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.Core.Infrastructure;

/// <summary>
/// Minimal downloader that reads model-artifacts.source-lock.json, downloads the
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

    // ──────────────────────────────────────────────
    //  Main download pipeline
    // ──────────────────────────────────────────────

    /// <summary>
    /// Downloads the archive from source-lock, verifies archive hash, extracts
    /// all 21 artifacts, verifies each artifact hash, and copies to canonical
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
        CancellationToken ct = default)
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
            var archivePath = Path.Combine(tempDir, archiveFileName);

            var expectedHash = source.Sha256.ToLowerInvariant();
            Console.WriteLine($"Downloading {source.Url}");
            await DownloadFileAsync(source.Url, archivePath, ct);
            Console.WriteLine($"Downloaded {new FileInfo(archivePath).Length:N0} bytes");

            // 3. Verify archive SHA-256
            var archiveHash = await ComputeSha256Async(archivePath);
            if (archiveHash != expectedHash)
            {
                result.Errors.Add(
                    $"Archive SHA-256 mismatch: expected {expectedHash}, got {archiveHash}");
                return result;
            }
            Console.WriteLine($"Archive SHA-256 verified: {archiveHash[..16]}...");

            // 4. Extract archive to temp
            var extractDir = Path.Combine(tempDir, "extracted");
            Directory.CreateDirectory(extractDir);
            await Extract7zAsync(archivePath, extractDir);
            Console.WriteLine($"Extracted to {extractDir}");

            // 5. Verify and place each artifact
            modelRoot = Path.GetFullPath(modelRoot);
            Directory.CreateDirectory(modelRoot);

            foreach (var artifact in lockDoc.Artifacts)
            {
                ct.ThrowIfCancellationRequested();
                var destPath = Path.Combine(modelRoot, artifact.DestinationRelativePath);
                var destDir = Path.GetDirectoryName(destPath)!;

                // Resolve the actual file in extracted archive
                // memberPath is like "BetterGI/Assets/Model/..."
                // After extraction, files land under extractDir/BetterGI/Assets/Model/...
                var sourcePath = Path.Combine(extractDir, artifact.MemberPath.Replace('/', Path.DirectorySeparatorChar));

                if (!File.Exists(sourcePath))
                {
                    result.Errors.Add($"Extracted file not found: {artifact.MemberPath}");
                    result.ArtifactsSkipped++;
                    continue;
                }

                // Verify artifact SHA-256
                var fileHash = await ComputeSha256Async(sourcePath);
                if (fileHash != artifact.Sha256.ToLowerInvariant())
                {
                    result.Errors.Add(
                        $"Artifact SHA-256 mismatch for {artifact.DestinationRelativePath}: " +
                        $"expected {artifact.Sha256[..16]}..., got {fileHash[..16]}...");
                    result.ArtifactsSkipped++;
                    continue;
                }

                // Copy to canonical destination
                Directory.CreateDirectory(destDir);
                File.Copy(sourcePath, destPath, overwrite: true);
                result.ArtifactsExtracted++;
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

    private async Task DownloadFileAsync(string url, string path, CancellationToken ct)
    {
        using var response = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct);
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(ct);
        await using var fs = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None);
        await stream.CopyToAsync(fs, ct);
    }

    private static async Task<string> ComputeSha256Async(string path)
    {
        await using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        var hash = await SHA256.HashDataAsync(fs);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    private static async Task Extract7zAsync(string archivePath, string extractDir)
    {
        // Use system7z if available; otherwise fallback to SharpCompress
        if (await HasCommandAsync("7z"))
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "7z",
                Arguments = $"x \"{archivePath}\" -o\"{extractDir}\" -y",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var process = System.Diagnostics.Process.Start(psi)!;
            await process.WaitForExitAsync();
            if (process.ExitCode != 0)
            {
                var stderr = await process.StandardError.ReadToEndAsync();
                throw new InvalidOperationException($"7z extraction failed (exit {process.ExitCode}): {stderr}");
            }
        }
        else
        {
            throw new InvalidOperationException(
                "7z command not found. Install p7zip: `brew install p7zip`");
        }
    }

    private static async Task<bool> HasCommandAsync(string command)
    {
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "which",
                Arguments = command,
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var process = System.Diagnostics.Process.Start(psi)!;
            await process.WaitForExitAsync();
            return process.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }
}
