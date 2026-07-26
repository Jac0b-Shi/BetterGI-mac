using System;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.GameTask.Shell;

public interface IShellTaskPlatform
{
    Task<ShellExecutionRecord> ExecuteAsync(ShellTaskParam param, bool waitForExit, CancellationToken cancellationToken);
    void ActivateGameWindow();
}

public static class ShellTaskPlatform
{
    private static IShellTaskPlatform? _current;
    public static IShellTaskPlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("Shell task platform has not been composed.");

    public static void Configure(IShellTaskPlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("Shell task platform has already been configured.");
    }
}

public sealed record ShellExecutionRecord(bool End, string Shell, string Output)
{
    public bool HasOutput => !string.IsNullOrEmpty(Output) || !string.IsNullOrEmpty(Shell);
}
