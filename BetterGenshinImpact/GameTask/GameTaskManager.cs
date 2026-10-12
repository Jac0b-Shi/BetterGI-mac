using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Recognition.OpenCv;
using BetterGenshinImpact.Core.Script.Dependence.Model.TimerConfig;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Platform.Abstractions;
using OpenCvSharp;
#if !BGI_PLATFORM_MAC
using BetterGenshinImpact.GameTask.GameLoading;
using BetterGenshinImpact.GameTask.Placeholder;
using BetterGenshinImpact.GameTask.MapMask;
using BetterGenshinImpact.GameTask.SkillCd;
#endif
using System.Collections.Concurrent;
using System.Threading;

namespace BetterGenshinImpact.GameTask;

/// <summary>Shared trigger registry, lifecycle ordering and asset-loading behavior.</summary>
public static class GameTaskManager
{
#if !BGI_PLATFORM_MAC
    public static List<ITaskTrigger> CreateTriggers()
    {
        List<ITaskTrigger> triggers =
        [
            new TestTrigger(),
            new GameLoadingTrigger(),
            new AutoPick.AutoPickTrigger(),
            new QuickTeleport.QuickTeleportTrigger(),
            new AutoSkip.AutoSkipTrigger(),
            new AutoFishing.AutoFishingTrigger(),
            new AutoEat.AutoEatTrigger(),
            new MapMaskTrigger(),
            new SkillCdTrigger(),
        ];

        return [.. triggers.OrderByDescending(t => t.Priority)];
    }

#endif
    public sealed record TriggerRequest(object? Options, long Version);
    private static long _requestVersion;
    public static ConcurrentDictionary<string, TriggerRequest> RequestedTriggers { get; } = new();
    private static readonly ConcurrentDictionary<string, long> RefreshVersions = new();
    private static readonly object RequestLock = new();
    private static readonly Dictionary<string, List<TriggerRequest>> RequestOwners = new();
    public static void RequestTrigger(string name, object? options)
    {
        lock (RequestLock)
        {
            var request = new TriggerRequest(options, Interlocked.Increment(ref _requestVersion));
            RequestOwners[name] = [request];
            RequestedTriggers[name] = request;
        }
    }
    public static IDisposable RequestTriggerLease(string name, object? options)
    {
        lock (RequestLock)
        {
            var request = new TriggerRequest(options, Interlocked.Increment(ref _requestVersion));
            if (!RequestOwners.TryGetValue(name, out var owners)) RequestOwners[name] = owners = [];
            owners.Add(request);
            RequestedTriggers[name] = request;
            return new TriggerLease(name, request);
        }
    }
    public static void ClearTriggerRequests()
    {
        lock (RequestLock)
        {
            RequestOwners.Clear();
            RequestedTriggers.Clear();
        }
    }
    private sealed class TriggerLease(string name, TriggerRequest request) : IDisposable
    {
        public void Dispose()
        {
            lock (RequestLock)
            {
                if (!RequestOwners.TryGetValue(name, out var owners) || !owners.Remove(request)) return;
                if (owners.Count == 0)
                {
                    RequestOwners.Remove(name);
                    RequestedTriggers.TryRemove(name, out _);
                }
                else RequestedTriggers[name] = owners[^1];
            }
        }
    }
    public static void RequestRefresh(string name) => RefreshVersions[name] = Interlocked.Increment(ref _requestVersion);
    public static long RefreshVersion(string name) => RefreshVersions.GetValueOrDefault(name);
    private static ConcurrentDictionary<string, ITaskTrigger>? _triggerDictionary;
    public static ConcurrentQueue<ITaskTrigger> RetiredTriggers { get; } = new();
    public static ConcurrentDictionary<string, ITaskTrigger>? TriggerDictionary
    {
        get => Volatile.Read(ref _triggerDictionary);
        set
        {
            var previous = Interlocked.Exchange(ref _triggerDictionary, value);
            if (previous is not null && !ReferenceEquals(previous, value))
                foreach (var trigger in previous.Values) RetiredTriggers.Enqueue(trigger);
        }
    }

    public static List<ITaskTrigger> LoadInitialTriggers(
        IInputBackend inputBackend, ISystemInfo systemInfo, IAutoPickRuntimeState runtimeState,
        IAutoPickConfigProvider autoPickConfigProvider,
        IPaddleAutoPickTextRecognizer paddleRecognizer, IYapAutoPickTextRecognizer yapRecognizer)
    {
        ArgumentNullException.ThrowIfNull(runtimeState);
        GameTaskManagerPlatform.Current.ReloadAssets();
        TriggerDictionary = new ConcurrentDictionary<string, ITaskTrigger>(
            GameTaskManagerPlatform.Current.CreateInitialTriggers(
                inputBackend, systemInfo, runtimeState, autoPickConfigProvider,
                paddleRecognizer, yapRecognizer));
        return ConvertToTriggerList();
    }

    public static List<ITaskTrigger> ConvertToTriggerList(bool allEnabled = false)
    {
        if (TriggerDictionary is null) return [];
        var loadedTriggers = TriggerDictionary.Values.ToList();
        if (allEnabled) foreach (var pair in TriggerDictionary) RequestTrigger(pair.Key, null);
        return [.. loadedTriggers.OrderByDescending(trigger => trigger.Priority)];
    }

    public static void ClearTriggers()
    {
        if (TriggerDictionary is not { } triggers)
        {
            return;
        }

        ClearTriggerRequests();
        foreach (var trigger in triggers.Values) RetiredTriggers.Enqueue(trigger);
        triggers.Clear();
        // Dispatcher observes removed instances and invokes OnDisabled before disposing them.
    }

    public static bool AddTrigger(
        string name, object? externalConfig, IAutoPickRuntimeState runtimeState,
        IInputBackend inputBackend, ISystemInfo systemInfo,
        IAutoPickConfigProvider autoPickConfigProvider,
        IPaddleAutoPickTextRecognizer paddleRecognizer, IYapAutoPickTextRecognizer yapRecognizer)
    {
        ArgumentNullException.ThrowIfNull(runtimeState);
        TriggerDictionary ??= new ConcurrentDictionary<string, ITaskTrigger>();
        var created = GameTaskManagerPlatform.Current.CreateTrigger(
            name, externalConfig, runtimeState, inputBackend, systemInfo,
            autoPickConfigProvider, paddleRecognizer, yapRecognizer);
        if (created is not { } pair) return false;
        if (!TriggerDictionary.TryAdd(pair.Key, pair.Value))
            (pair.Value as IDisposable)?.Dispose();
        RequestTrigger(pair.Key, externalConfig);
        return true;
    }

    public static void RefreshTriggerConfigs()
    {
        if (TriggerDictionary is { Count: > 0 })
        {
            foreach (var name in new[] { "AutoPick", "AutoSkip", "AutoFish", "QuickTeleport", "AutoEat", "MapMask", "SkillCd" })
                RequestRefresh(name);
            GameTaskManagerPlatform.Current.ClearOverlay();
        }
        GameTaskManagerPlatform.Current.ReloadAssets();
    }

    public static void RefreshTriggerConfig(string name)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        RequestRefresh(name);
        GameTaskManagerPlatform.Current.ReloadAssets();
    }

    public static void ReloadAssets() => GameTaskManagerPlatform.Current.ReloadAssets();

    public static Mat LoadAssetImage(string featureName, string assetName, ImreadModes flags = ImreadModes.Color) =>
        LoadAssetImage(featureName, assetName, GameTaskManagerPlatform.Current.SystemInfo, flags);

    public static Mat LoadAssetImage(
        string featureName, string assetName, ISystemInfo systemInfo,
        ImreadModes flags = ImreadModes.Color)
    {
        var assetsFolder = Global.Absolute($@"GameTask\{featureName}\Assets\{systemInfo.GameScreenSize.Width}x{systemInfo.GameScreenSize.Height}");
        if (!Directory.Exists(assetsFolder))
            assetsFolder = Global.Absolute($@"GameTask\{featureName}\Assets\1920x1080");
        if (!Directory.Exists(assetsFolder))
            throw new FileNotFoundException($"未找到{featureName}的素材文件夹");
        var filePath = Path.Combine(assetsFolder, assetName);
        if (!File.Exists(filePath))
            throw new FileNotFoundException($"未找到{featureName}中的{assetName}文件");
        using var stream = File.OpenRead(filePath);
        var mat = Mat.FromStream(stream, flags);
        return systemInfo.GameScreenSize.Width == 1920
            ? mat
            : ResizeHelper.Resize(mat, systemInfo.AssetScale);
    }

    /// <summary>
    /// 根据捕获区域宽高加载素材图片并缩放
    /// </summary>
    /// <returns></returns>
    /// <exception cref="FileNotFoundException"></exception>
    public static Mat LoadAssetImage(string featName, string assertName, int captureWidth, int captureHeight, ImreadModes flags = ImreadModes.Color)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(captureWidth);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(captureHeight);

        var assetsFolder = Global.Absolute($@"GameTask\{featName}\Assets\{captureWidth}x{captureHeight}");
        if (!Directory.Exists(assetsFolder))
        {
            assetsFolder = Global.Absolute($@"GameTask\{featName}\Assets\1920x1080");
        }

        if (!Directory.Exists(assetsFolder))
        {
            throw new FileNotFoundException($"未找到{featName}的素材文件夹");
        }

        var filePath = Path.Combine(assetsFolder, assertName);
        if (!File.Exists(filePath))
        {
            throw new FileNotFoundException($"未找到{featName}中的{assertName}文件");
        }

        using var stream = File.OpenRead(filePath);
        var mat = Mat.FromStream(stream, flags);
        if (captureWidth < 1920)
        {
            using (mat)
            {
                return ResizeHelper.Resize(mat, captureWidth / 1920d);
            }
        }

        return mat;
    }
}
