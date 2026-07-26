using System.Collections.Generic;
using BetterGenshinImpact.GameTask.Common.Reward;

namespace BetterGenshinImpact.GameTask.Common.Job;

/// <summary>合成指定材料的执行结果。</summary>
public class CraftMaterialResult
{
    public bool Success { get; set; }
    public string MaterialName { get; set; } = string.Empty;
    public int TargetQuantity { get; set; }
    public int ActualQuantity { get; set; }
    public string MaterialType { get; set; } = string.Empty;
    public List<RewardItem> Rewards { get; set; } = [];

    public static CraftMaterialResult CreateSuccess(string materialName, int targetQuantity,
        int actualQuantity, string materialType, List<RewardItem> rewards) => new()
        {
            Success = true,
            MaterialName = materialName,
            TargetQuantity = targetQuantity,
            ActualQuantity = actualQuantity,
            MaterialType = materialType,
            Rewards = rewards
        };
}
