using BetterGenshinImpact.GameTask.AutoFight.Script;
using BetterGenshinImpact.GameTask;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacCombatSceneProvider : ICombatSceneProvider
{
    public async Task<ICombatScriptScene?> GetCombatScene(CancellationToken cancellationToken) =>
        await RunnerContext.Instance.GetCombatScenes(cancellationToken);
}
