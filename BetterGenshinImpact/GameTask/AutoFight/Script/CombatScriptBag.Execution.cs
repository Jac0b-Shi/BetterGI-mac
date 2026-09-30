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
        var (best, count) = SelectCombatScript(System.Linq.Enumerable.ToArray(
            System.Linq.Enumerable.Select(avatars, a => a.Name)));
        Logger.LogInformation("匹配到战斗脚本：{Name}，匹配 {Count}/{Total}", best.Name, count, avatars.Count);
        return best.CombatCommands;
    }
}
