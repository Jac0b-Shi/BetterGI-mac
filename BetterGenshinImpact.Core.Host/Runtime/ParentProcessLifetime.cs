using System.Diagnostics;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class ParentProcessLifetime(int parentProcessId, TimeSpan? pollInterval = null)
{
    private readonly TimeSpan _pollInterval = pollInterval ?? TimeSpan.FromMilliseconds(500);

    public async Task MonitorAsync(Action onParentExit, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(onParentExit);
        using var timer = new PeriodicTimer(_pollInterval);
        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            if (IsProcessAlive(parentProcessId))
                continue;
            onParentExit();
            return;
        }
    }

    public static bool IsProcessAlive(int processId)
    {
        if (processId <= 0)
            return false;
        try
        {
            using var process = Process.GetProcessById(processId);
            return !process.HasExited;
        }
        catch (Exception exception) when (exception is ArgumentException or InvalidOperationException)
        {
            return false;
        }
    }
}
