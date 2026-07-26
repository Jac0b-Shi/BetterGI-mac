using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using static BetterGenshinImpact.GameTask.Common.TaskControl;

namespace BetterGenshinImpact.GameTask.AutoFight.Script;

public partial class CombatScriptBag
{
    public List<CombatCommand> FindCombatScript<TAvatar>(IReadOnlyCollection<TAvatar> avatars)
        where TAvatar : ICombatCommandAvatar
    {
        foreach (var combatScript in CombatScripts)
        {
            var matchCount = 0;
            foreach (var avatar in avatars)
            {
                if (combatScript.AvatarNames.Contains(avatar.Name))
                {
                    matchCount++;
                }

                if (matchCount != avatars.Count) continue;
                Logger.LogInformation("匹配到战斗脚本：{Name}", combatScript.Name);
                return combatScript.CombatCommands;
            }

            combatScript.MatchCount = matchCount;
        }

        CombatScripts.Sort((a, b) => b.MatchCount.CompareTo(a.MatchCount));
        if (CombatScripts[0].MatchCount == 0)
        {
            throw new Exception("未匹配到任何战斗脚本");
        }

        Logger.LogWarning("未完整匹配到四人队伍，使用匹配度最高的队伍：{Name}", CombatScripts[0].Name);
        return CombatScripts[0].CombatCommands;
    }
}
