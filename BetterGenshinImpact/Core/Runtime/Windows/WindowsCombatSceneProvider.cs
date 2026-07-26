using BetterGenshinImpact.GameTask.AutoFight.Script;
using BetterGenshinImpact.GameTask;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsCombatSceneProvider : ICombatSceneProvider
{
    public async Task<ICombatScriptScene?> GetCombatScene(CancellationToken cancellationToken) =>
        await RunnerContext.Instance.GetCombatScenes(cancellationToken);
}
