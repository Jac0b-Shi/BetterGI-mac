using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Script.Dependence.Model.TimerConfig;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Platform.Abstractions;
using OpenCvSharp;
using System.Collections.Concurrent;

namespace BetterGenshinImpact.GameTask;

/// <summary>
/// Core shim: minimal GameTaskManager for macOS/Core.
/// Supports LoadAssetImage with resolution-dependent directories and
/// a narrow subset of trigger management (AddTrigger, ConvertToTriggerList,
/// ClearTriggers) for AutoPick only.
///
/// LIMITATIONS (compared to Windows production GameTaskManager):
/// - ConvertToTriggerList does NOT call Init() or sort by Priority
/// - AddTrigger only handles "AutoPick" — not other trigger types
/// - TriggerDictionary is the only state — no assets tracking
/// This is NOT a general-purpose replacement. Do not expand it further;
/// extract shared logic instead when macOS runtime needs full dispatcher behavior.
///
/// <b>LoadAssetImage resize behavior (intentional difference from Windows):</b>
/// - Windows implementation: always scales by AssetScale when GameScreenSize.Width != 1920
/// - Core shim: only scales when FALLING BACK to 1920x1080 assets (usedFallback == true)
/// - Rationale: target-resolution directories (e.g. 1280x720) are expected to contain
///   correctly-sized assets. The resize is only needed when no matching resolution
///   directory exists and we fall back to the 1920x1080 baseline.
/// </summary>
public static class GameTaskManager
{
    public static ConcurrentDictionary<string, ITaskTrigger>? TriggerDictionary { get; set; }

    public static List<ITaskTrigger> ConvertToTriggerList(bool allEnabled = false)
    {
        if (TriggerDictionary is null)
            return [];
        return allEnabled
            ? [.. TriggerDictionary.Values]
            : [.. TriggerDictionary.Values.Where(t => t.IsEnabled)];
    }

    public static void ClearTriggers()
    {
        TriggerDictionary?.Clear();
    }

    public static bool AddTrigger(string name, object? externalConfig, IInputBackend inputBackend, ISystemInfo systemInfo, IAutoPickConfigProvider autoPickConfigProvider)
    {
        TriggerDictionary ??= new ConcurrentDictionary<string, ITaskTrigger>();

        ITaskTrigger? trigger = null;
        if (name == "AutoPick")
        {
            // Assets already initialized by LoadInitialTriggers; reuse.
            trigger = new AutoPick.AutoPickTrigger(
                externalConfig as AutoPickExternalConfig, null, autoPickConfigProvider, inputBackend, systemInfo);
        }

        if (trigger == null) return false;
        TriggerDictionary[name] = trigger;
        return true;
    }

    // ── Asset loading ──

    /// <summary>
    /// Load a PNG asset image from the Assets directory.
    /// Path is resolved relative to the task's Assets/1920x1080/ subfolder.
    /// </summary>
    public static Mat LoadAssetImage(string taskName, string fileName)
    {
        return LoadAssetImage(taskName, fileName, null);
    }

    /// <summary>
    /// Load a PNG asset image, scaled for the given ISystemInfo resolution.
    /// Falls back to 1920x1080 directory if target resolution directory does not exist.
    ///
    /// NOTE: Unlike the Windows implementation which unconditionally scales at
    /// AssetScale when GameScreenSize.Width != 1920, the Core shim only resizes
    /// when a fallback to 1920x1080 baseline assets occurred. Target-resolution
    /// directories are assumed to contain correctly-sized assets.
    /// </summary>
    public static Mat LoadAssetImage(string taskName, string fileName, ISystemInfo? systemInfo)
    {
        var resolutionDir = (systemInfo?.GameScreenSize.Width).HasValue
            ? $"{systemInfo!.GameScreenSize.Width}x{systemInfo.GameScreenSize.Height}"
            : "1920x1080";

        var baseDir = AppDomain.CurrentDomain.BaseDirectory;
        var dir = baseDir;
        while (dir != null && !Directory.Exists(Path.Combine(dir, "BetterGenshinImpact")))
        {
            dir = Path.GetDirectoryName(dir);
        }

        var assetDir = dir != null
            ? Path.Combine(dir, "BetterGenshinImpact", "GameTask", taskName, "Assets", resolutionDir)
            : Path.Combine(baseDir, "GameTask", taskName, "Assets", resolutionDir);

        var filePath = Path.Combine(assetDir, fileName);
        bool usedFallback = false;
        if (!File.Exists(filePath))
        {
            // Fallback to 1920x1080
            var fallbackDir = dir != null
                ? Path.Combine(dir, "BetterGenshinImpact", "GameTask", taskName, "Assets", "1920x1080")
                : Path.Combine(baseDir, "GameTask", taskName, "Assets", "1920x1080");
            filePath = Path.Combine(fallbackDir, fileName);
            if (!File.Exists(filePath))
            {
                throw new FileNotFoundException($"Asset not found: {filePath}");
            }
            usedFallback = true;
        }

        var mat = Cv2.ImRead(filePath, ImreadModes.Color);

        if (usedFallback && systemInfo != null && systemInfo.AssetScale < 1)
        {
            var newWidth = (int)(mat.Width * systemInfo.AssetScale);
            var newHeight = (int)(mat.Height * systemInfo.AssetScale);
            if (newWidth > 0 && newHeight > 0)
            {
                Cv2.Resize(mat, mat, new OpenCvSharp.Size(newWidth, newHeight));
            }
        }

        return mat;
    }
}
