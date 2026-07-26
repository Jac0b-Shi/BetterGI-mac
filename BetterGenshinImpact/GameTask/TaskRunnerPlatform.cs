using Microsoft.Extensions.Logging;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask;

public interface ITaskRunnerPlatform
{
    ILogger Logger { get; }
    ILogger RunnerLogger { get; }
    SemaphoreSlim TaskSemaphore { get; }
    bool RethrowUnexpectedExceptions => false;
    bool ThrowOnLockFailure => false;
    void InitializeTask();
    void EndTask();
    void NotifyCancellation(string message);
    void NotifyError(string message, Exception exception);
}

public static class TaskRunnerPlatform
{
    private static ITaskRunnerPlatform? _current;
    public static ITaskRunnerPlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("TaskRunner platform has not been composed.");

    public static void Configure(ITaskRunnerPlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("TaskRunner platform has already been configured.");
    }
}
