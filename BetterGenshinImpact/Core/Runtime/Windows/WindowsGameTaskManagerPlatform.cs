using System.Collections.Generic;
using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Script.Dependence.Model.TimerConfig;
using BetterGenshinImpact.GameTask.AutoBoss.Assets;
using BetterGenshinImpact.GameTask.AutoDomain.Assets;
using BetterGenshinImpact.GameTask.AutoFight.Assets;
using BetterGenshinImpact.GameTask.AutoFishing.Assets;
using BetterGenshinImpact.GameTask.AutoGeniusInvokation.Assets;
using BetterGenshinImpact.GameTask.AutoPick.Assets;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.AutoSkip.Assets;
using BetterGenshinImpact.GameTask.AutoWood.Assets;
using BetterGenshinImpact.GameTask.AutoEat.Assets;
using BetterGenshinImpact.GameTask.Common.Element.Assets;
using BetterGenshinImpact.GameTask.GameLoading;
using BetterGenshinImpact.GameTask.GameLoading.Assets;
using BetterGenshinImpact.GameTask.MapMask;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Placeholder;
using BetterGenshinImpact.GameTask.QuickSereniteaPot.Assets;
using BetterGenshinImpact.GameTask.QuickTeleport.Assets;
using BetterGenshinImpact.GameTask.SkillCd;
using BetterGenshinImpact.Platform.Abstractions;
using BetterGenshinImpact.View.Drawable;

namespace BetterGenshinImpact.GameTask;

public sealed class WindowsGameTaskManagerPlatform : IGameTaskManagerPlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;

    public IReadOnlyList<KeyValuePair<string, ITaskTrigger>> CreateInitialTriggers(
        IInputBackend inputBackend, ISystemInfo systemInfo, IAutoPickRuntimeState runtimeState,
        IAutoPickConfigProvider autoPickConfigProvider,
        IPaddleAutoPickTextRecognizer paddleRecognizer, IYapAutoPickTextRecognizer yapRecognizer)
    {
        AutoPickAssets.Initialize(systemInfo, autoPickConfigProvider, App.GetLogger<AutoPickAssets>());
        return
        [
            new("RecognitionTest", new TestTrigger()), new("GameLoading", new GameLoadingTrigger()),
            new("AutoPick", new AutoPick.AutoPickTrigger(null, runtimeState, autoPickConfigProvider,
                inputBackend, systemInfo, App.GetLogger<AutoPick.AutoPickTrigger>(), paddleRecognizer, yapRecognizer)),
            new("QuickTeleport", new QuickTeleport.QuickTeleportTrigger()),
            new("AutoSkip", new AutoSkip.AutoSkipTrigger(TaskContext.Instance().Config.AutoSkipConfig)), new("AutoFish", new AutoFishing.AutoFishingTrigger()),
            new("AutoEat", new AutoEat.AutoEatTrigger()), new("MapMask", new MapMaskTrigger()),
            new("SkillCd", new SkillCdTrigger()),
        ];
    }

    public KeyValuePair<string, ITaskTrigger>? CreateTrigger(
        string name, object? externalConfig, IAutoPickRuntimeState runtimeState,
        IInputBackend inputBackend, ISystemInfo systemInfo, IAutoPickConfigProvider autoPickConfigProvider,
        IPaddleAutoPickTextRecognizer paddleRecognizer, IYapAutoPickTextRecognizer yapRecognizer) => name switch
    {
        "AutoPick" => new("AutoPick", new AutoPick.AutoPickTrigger(externalConfig as AutoPickExternalConfig,
            runtimeState, autoPickConfigProvider, inputBackend, systemInfo,
            App.GetLogger<AutoPick.AutoPickTrigger>(), paddleRecognizer, yapRecognizer)),
        "AutoSkip" => new("AutoSkip", new AutoSkip.AutoSkipTrigger(
            externalConfig as AutoSkipConfig ?? TaskContext.Instance().Config.AutoSkipConfig)),
        "AutoEat" => new("AutoEat", new AutoEat.AutoEatTrigger()),
        _ => null,
    };

    public void ClearOverlay() => VisionContext.Instance().DrawContent.ClearAll();
    public void ReloadAssets()
    {
        AutoPickAssets.DestroyInstance(); AutoSkipAssets.DestroyInstance(); AutoFishingAssets.DestroyInstance();
        QuickTeleportAssets.DestroyInstance(); AutoWoodAssets.DestroyInstance(); AutoGeniusInvokationAssets.DestroyInstance();
        AutoFightAssets.DestroyInstance(); ElementAssets.DestroyInstance(); QuickSereniteaPotAssets.DestroyInstance();
        GameLoadingAssets.DestroyInstance(); MapLazyAssets.DestroyInstance(); AutoEatAssets.DestroyInstance();
        AutoDomainAssets.DestroyInstance(); AutoBossAssets.DestroyInstance();
    }
}
