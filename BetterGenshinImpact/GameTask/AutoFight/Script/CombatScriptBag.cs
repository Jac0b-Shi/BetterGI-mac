using System.Collections.Generic;

namespace BetterGenshinImpact.GameTask.AutoFight.Script;

public partial class CombatScriptBag(List<CombatScript> combatScripts)
{
    private List<CombatScript> CombatScripts { get; set; } = combatScripts;

    public CombatScriptBag(CombatScript combatScript) : this([combatScript])
    {
    }
}
