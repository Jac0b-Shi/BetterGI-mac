using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.Common.Job;

public interface IExitAndReloginPlatform
{
    void FocusGameWindow();
    bool TryLoginThirdParty(CancellationToken cancellationToken);
}

public static class ExitAndReloginPlatform
{
    private static IExitAndReloginPlatform? _current;

    public static IExitAndReloginPlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("Exit-and-relogin platform has not been composed.");

    public static void Configure(IExitAndReloginPlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("Exit-and-relogin platform has already been configured.");
    }
}
