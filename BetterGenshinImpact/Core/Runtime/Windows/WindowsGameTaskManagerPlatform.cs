using System.Collections.Generic;
using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Script.Dependence.Model.TimerConfig;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.GameLoading;
using BetterGenshinImpact.GameTask.MapMask;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Placeholder;
using BetterGenshinImpact.GameTask.SkillCd;
using BetterGenshinImpact.Platform.Abstractions;
using BetterGenshinImpact.View.Drawable;
using BetterGenshinImpact.Core.Recognition;

namespace BetterGenshinImpact.GameTask;

public sealed class WindowsGameTaskManagerPlatform : IGameTaskManagerPlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;

    public IReadOnlyList<KeyValuePair<string, ITaskTrigger>> CreateInitialTriggers(
        IInputBackend inputBackend, ISystemInfo systemInfo, IAutoPickRuntimeState runtimeState,
        IAutoPickConfigProvider autoPickConfigProvider,
        IPaddleAutoPickTextRecognizer paddleRecognizer, IYapAutoPickTextRecognizer yapRecognizer)
    {
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
        RecognitionAssets.ClearAll();
    }
}
