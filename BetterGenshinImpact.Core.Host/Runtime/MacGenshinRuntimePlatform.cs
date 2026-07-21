using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.Model;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacGenshinRuntimePlatform(
    Func<ISystemInfo> systemInfo,
    IAutoFishingRuntimePlatform autoFishing,
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
    private static CapabilityUnavailableException Unavailable(string member) => new(
        $"genshin.{member} is not composed on macOS because its shared task still depends on Win32 input.");
}
