using BetterGenshinImpact.GameTask.AutoFight.Model;
using BetterGenshinImpact.GameTask.Common.Job;
using Microsoft.Extensions.Logging;
using System.Threading;
using System.Threading.Tasks;
using static BetterGenshinImpact.GameTask.Common.TaskControl;

namespace BetterGenshinImpact.GameTask;

public partial class RunnerContext
{
    public async Task<CombatScenes?> GetCombatScenes(CancellationToken ct)
    {
        if (CombatScenesState is CombatScenes existingCombatScenes)
            return existingCombatScenes;

        var returnMainUiTask = new ReturnMainUiTask();
        await returnMainUiTask.Start(ct);
        await Delay(200, ct);
        CombatScenes? combatScenes = new CombatScenes().InitializeTeam(CaptureToRectArea());
        if (!combatScenes.CheckTeamInitialized())
        {
            Logger.LogError("队伍角色识别失败");
            combatScenes = null;
        }
        CombatScenesState = combatScenes;
        return combatScenes;
    }

    public CombatScenes? TrySyncCombatScenesSilent()
    {
        try
        {
            using var region = CaptureToRectArea();
            var scenes = new CombatScenes(logger: Microsoft.Extensions.Logging.Abstractions.NullLogger.Instance).InitializeTeamSilent(region);
            if (scenes.CheckTeamInitialized()) return scenes;
            scenes.Dispose();
        }
        catch
        {
            // Upstream silent recognition intentionally suppresses all failures.
        }
        return null;
    }
}
