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
using System.Collections.Concurrent;

namespace BetterGenshinImpact.GameTask;

/// <summary>Shared trigger registry, lifecycle ordering and asset-loading behavior.</summary>
public static class GameTaskManager
{
    public static ConcurrentDictionary<string, ITaskTrigger>? TriggerDictionary { get; set; }

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
        loadedTriggers.ForEach(trigger => trigger.Init());
        if (allEnabled) loadedTriggers.ForEach(trigger => trigger.IsEnabled = true);
        return [.. loadedTriggers.OrderByDescending(trigger => trigger.Priority)];
    }

    public static void ClearTriggers() => TriggerDictionary?.Clear();

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
        TriggerDictionary[pair.Key] = pair.Value;
        return true;
    }

    public static void RefreshTriggerConfigs()
    {
        if (TriggerDictionary is { Count: > 0 })
        {
            foreach (var name in new[] { "AutoPick", "AutoSkip", "AutoFish", "QuickTeleport", "AutoEat", "MapMask", "SkillCd" })
                TriggerDictionary.GetValueOrDefault(name)?.Init();
            GameTaskManagerPlatform.Current.ClearOverlay();
        }
        GameTaskManagerPlatform.Current.ReloadAssets();
    }

    public static void RefreshTriggerConfig(string name)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        TriggerDictionary?.GetValueOrDefault(name)?.Init();
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
