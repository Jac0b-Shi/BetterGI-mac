using System;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.GameTask.AutoFight.Script;

public interface ICombatSceneProvider
{
    Task<ICombatScriptScene?> GetCombatScene(CancellationToken cancellationToken);
}

public static class CombatSceneProvider
{
    private static ICombatSceneProvider? _current;

    public static ICombatSceneProvider Current => _current
        ?? throw new InvalidOperationException("CombatSceneProvider has not been configured.");

    public static void Configure(ICombatSceneProvider provider)
    {
        ArgumentNullException.ThrowIfNull(provider);
        if (Interlocked.CompareExchange(ref _current, provider, null) is not null)
            throw new InvalidOperationException("CombatSceneProvider is already configured.");
    }
}
