using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.Macro;

public interface ITurnAroundRuntimePlatform
{
    int RunaroundInterval { get; }
    int RunaroundMouseXInterval { get; set; }
    void MoveMouseBy(int x, int y, CancellationToken cancellationToken);
    void Wait(int milliseconds, CancellationToken cancellationToken);
}

public static class TurnAroundRuntimePlatform
{
    private static ITurnAroundRuntimePlatform? _current;

    public static ITurnAroundRuntimePlatform Current =>
        Volatile.Read(ref _current)
        ?? throw new InvalidOperationException(
            "Turn-around runtime platform has not been composed.");

    public static void Configure(ITurnAroundRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
        {
            throw new InvalidOperationException(
                "Turn-around runtime platform has already been configured.");
        }
    }
}
