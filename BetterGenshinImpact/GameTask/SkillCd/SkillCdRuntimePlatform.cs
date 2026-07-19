using System;
using System.Collections.Generic;
using BetterGenshinImpact.GameTask.AutoFight.Model;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Platform.Abstractions;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.GameTask.SkillCd;

public readonly record struct SkillCdTextCommand(string Text, double X, double Y);

public interface ISkillCdRuntimePlatform
{
    SkillCdConfig Config { get; }
    int TriggerInterval { get; }
    ISystemInfo SystemInfo { get; }
    ILogger Logger { get; }
    bool IsElementalSkillDown();
    bool IsPartySlotDown(int zeroBasedSlot);
    CombatScenes? TrySyncCombatScenesSilent();
    void Publish(IReadOnlyList<SkillCdTextCommand>? commands);
}

public static class SkillCdRuntimePlatform
{
    public static ISkillCdRuntimePlatform Current { get; private set; } = null!;
    public static void Configure(ISkillCdRuntimePlatform platform) =>
        Current = platform ?? throw new ArgumentNullException(nameof(platform));
}
