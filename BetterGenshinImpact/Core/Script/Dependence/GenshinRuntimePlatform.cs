using System;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Common.Job;

namespace BetterGenshinImpact.Core.Script.Dependence;

public interface IGenshinRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
    double DpiScale { get; }
    string MapMatchingMethod { get; }
    AutoFishingTaskParam BuildAutoFishingTaskParam();
    Task<CraftMaterialResult> CraftMaterial(string materialName, int quantity, string? materialType,
        CancellationToken cancellationToken);
    Task ClaimBattlePassRewards(CancellationToken cancellationToken);
    Task GoToCraftingBench(string country, CancellationToken cancellationToken);
    Task ChooseTalkOption(string option, int skipTimes, bool isOrange,
        CancellationToken cancellationToken);
    Task SetTime(int hour, int minute, bool skip, CancellationToken cancellationToken);
    Task<bool> SwitchCharacter(string slot1, string slot2, string slot3, string slot4,
        CancellationToken cancellationToken);
}

public static class GenshinRuntimePlatform
{
    public static IGenshinRuntimePlatform Current { get; private set; } = null!;
    public static void Configure(IGenshinRuntimePlatform platform) =>
        Current = platform ?? throw new ArgumentNullException(nameof(platform));
}
