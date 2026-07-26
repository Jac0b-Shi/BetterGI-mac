using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.AutoSkip;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacGenshinRuntimePlatform(
    Func<ISystemInfo> systemInfo,
    IAutoFishingRuntimePlatform autoFishing,
    MacImageRegionOcrService ocrService,
    ILoggerFactory loggerFactory,
    IAutoSkipRuntimePlatform autoSkipRuntimePlatform,
    string mapMatchingMethod) : IGenshinRuntimePlatform
{
    public ISystemInfo SystemInfo => systemInfo();
    public double DpiScale => BetterGenshinImpact.GameTask.Common.TaskControlPlatform.Current.DpiScale;
    public string MapMatchingMethod { get; } = mapMatchingMethod;
    public AutoFishingTaskParam BuildAutoFishingTaskParam() =>
        AutoFishingTaskParam.BuildFromConfig(autoFishing.Config, false);
    public Task<CraftMaterialResult> CraftMaterial(string materialName, int quantity,
        string? materialType, CancellationToken cancellationToken) =>
        new CraftMaterialTask(materialName, quantity, materialType).Start(cancellationToken);
    public Task ClaimBattlePassRewards(CancellationToken cancellationToken) =>
        new ClaimBattlePassRewardsTask().Start(cancellationToken);
    public Task GoToCraftingBench(string country, CancellationToken cancellationToken) =>
        new GoToCraftingBenchTask().GoToCraftingBench(country, cancellationToken);
    public Task ChooseTalkOption(string option, int skipTimes, bool isOrange,
        CancellationToken cancellationToken) =>
        new ChooseTalkOptionTask(
                loggerFactory.CreateLogger<ChooseTalkOptionTask>(),
                SystemInfo,
                autoSkipRuntimePlatform)
            .SingleSelectText(option, cancellationToken, skipTimes, isOrange);
    public Task SetTime(int hour, int minute, bool skip, CancellationToken cancellationToken) =>
        new SetTimeTask().Start(hour, minute, cancellationToken, skip);
    public Task<bool> SwitchCharacter(string slot1, string slot2, string slot3, string slot4,
        CancellationToken cancellationToken) =>
        new SwitchCharacterStateMachineTask(
            loggerFactory.CreateLogger<SwitchCharacterStateMachineTask>(),
            SystemInfo,
            ocrService.OnnxFactory,
            ocrService).Start(slot1, slot2, slot3, slot4, cancellationToken);
    private static CapabilityUnavailableException Unavailable(string member) => new(
        $"genshin.{member} is not composed on macOS because its shared task still depends on Win32 input.");
}
