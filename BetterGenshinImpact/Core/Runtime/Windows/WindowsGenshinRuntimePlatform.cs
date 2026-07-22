using System;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.ViewModel.Pages;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Recognition.ONNX;
using Microsoft.Extensions.DependencyInjection;
using BetterGenshinImpact.GameTask.AutoSkip;

namespace BetterGenshinImpact.Core.Script.Dependence;

public sealed class WindowsGenshinRuntimePlatform : IGenshinRuntimePlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public double DpiScale => TaskContext.Instance().DpiScale;
    public string MapMatchingMethod => TaskContext.Instance().Config.PathingConditionConfig.MapMatchingMethod;
    public AutoFishingTaskParam BuildAutoFishingTaskParam()
    {
        var viewModel = App.GetService<TaskSettingsPageViewModel>()
            ?? throw new InvalidOperationException("TaskSettingsPageViewModel is unavailable.");
        return AutoFishingTaskParam.BuildFromConfig(
            TaskContext.Instance().Config.AutoFishingConfig, viewModel.SaveScreenshotOnKeyTick);
    }
    public Task<CraftMaterialResult> CraftMaterial(string materialName, int quantity,
        string? materialType, CancellationToken cancellationToken) =>
        new CraftMaterialTask(materialName, quantity, materialType).Start(cancellationToken);
    public Task ClaimBattlePassRewards(CancellationToken cancellationToken) =>
        new ClaimBattlePassRewardsTask().Start(cancellationToken);
    public Task GoToCraftingBench(string country, CancellationToken cancellationToken) =>
        new GoToCraftingBenchTask().Start(country, cancellationToken);
    public Task ChooseTalkOption(string option, int skipTimes, bool isOrange,
        CancellationToken cancellationToken) =>
        new ChooseTalkOptionTask(
                App.GetLogger<ChooseTalkOptionTask>(),
                SystemInfo,
                AutoSkipRuntimePlatform.Current)
            .SingleSelectText(option, cancellationToken, skipTimes, isOrange);
    public Task SetTime(int hour, int minute, bool skip, CancellationToken cancellationToken) =>
        new SetTimeTask().Start(hour, minute, cancellationToken, skip);
    public Task<bool> SwitchCharacter(string slot1, string slot2, string slot3, string slot4,
        CancellationToken cancellationToken) =>
        new SwitchCharacterStateMachineTask(
            App.GetLogger<SwitchCharacterStateMachineTask>(),
            SystemInfo,
            App.ServiceProvider.GetRequiredService<BgiOnnxFactory>(),
            App.ServiceProvider.GetRequiredService<OcrFactory>().Service)
            .Start(slot1, slot2, slot3, slot4, cancellationToken);
}
