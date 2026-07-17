using BetterGenshinImpact.GameTask.AutoFight.Script;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacCombatSceneProvider : ICombatSceneProvider
{
    public Task<ICombatScriptScene?> GetCombatScene(CancellationToken cancellationToken) =>
        throw new CapabilityUnavailableException(
            "Combat scene recognition is unavailable until the full upstream CombatScenes dependency closure is composed.");
}
