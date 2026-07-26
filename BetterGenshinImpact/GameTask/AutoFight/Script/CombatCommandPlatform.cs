using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.AutoFight.Script;

public interface ICombatCommandPlatform
{
    void ValidateKeyName(string keyName);
    void KeyDown(string keyName);
    void KeyUp(string keyName);
    void KeyPress(string keyName);
}

public static class CombatCommandPlatform
{
    private static ICombatCommandPlatform? _current;

    public static ICombatCommandPlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("Combat command platform has not been composed.");

    public static void Configure(ICombatCommandPlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("Combat command platform has already been configured.");
    }
}
