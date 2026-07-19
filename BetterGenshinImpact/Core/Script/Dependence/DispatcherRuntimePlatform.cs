using System;
using System.Threading;

namespace BetterGenshinImpact.Core.Script.Dependence;

public interface IDispatcherRuntimePlatform
{
    CancellationToken GlobalCancellationToken { get; }
    void ClearTriggers();
    bool AddTrigger(string name, object? config);
}

public static class DispatcherRuntimePlatform
{
    public static IDispatcherRuntimePlatform Current { get; private set; } = null!;

    public static void Configure(IDispatcherRuntimePlatform platform) =>
        Current = platform ?? throw new ArgumentNullException(nameof(platform));
}
