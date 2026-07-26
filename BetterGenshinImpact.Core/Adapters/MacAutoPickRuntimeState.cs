using BetterGenshinImpact.Core.Abstractions.Runtime;

namespace BetterGenshinImpact.Core.Adapters;

/// <summary>
/// macOS adapter for the shared AutoPick pause counter.
/// The delegate is read on every trigger frame so RunnerContext changes are observed immediately.
/// </summary>
public sealed class MacAutoPickRuntimeState : IAutoPickRuntimeState
{
    private readonly Func<int> _getStopCount;

    public MacAutoPickRuntimeState(int stopCount = 0)
    {
        _getStopCount = () => stopCount;
    }

    public MacAutoPickRuntimeState(Func<int> getStopCount)
    {
        _getStopCount = getStopCount ?? throw new ArgumentNullException(nameof(getStopCount));
    }

    public int StopCount => _getStopCount();
}
