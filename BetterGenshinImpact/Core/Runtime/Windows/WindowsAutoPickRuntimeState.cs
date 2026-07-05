using BetterGenshinImpact.Core.Abstractions.Runtime;

namespace BetterGenshinImpact.Core.Runtime.Windows;

/// <summary>
/// Windows implementation of <see cref="IAutoPickRuntimeState"/>.
/// Delegates to the real upstream <see cref="GameTask.RunnerContext"/> at each access.
/// Does NOT cache <c>StopCount</c> — ensures runtime state is always current.
/// </summary>
public sealed class WindowsAutoPickRuntimeState : IAutoPickRuntimeState
{
    public int StopCount => GameTask.RunnerContext.Instance.AutoPickTriggerStopCount;
}
