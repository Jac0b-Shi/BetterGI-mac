using System.Threading;
using BetterGenshinImpact.GameTask;

namespace BetterGenshinImpact.Core.Script.Dependence;

public sealed class WindowsDispatcherRuntimePlatform : IDispatcherRuntimePlatform
{
    public CancellationToken GlobalCancellationToken => CancellationContext.Instance.Cts.Token;

    public void ClearTriggers() => TaskTriggerDispatcher.Instance().ClearTriggers();

    public bool AddTrigger(string name, object? config) =>
        TaskTriggerDispatcher.Instance().AddTrigger(name, config);
}
