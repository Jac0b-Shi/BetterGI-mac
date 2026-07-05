namespace BetterGenshinImpact.Core.Abstractions.Runtime;

/// <summary>
/// Runtime state for AutoPick coordination.
/// Exposes only the read-only <c>StopCount</c> that AutoPickTrigger consumes.
/// Coordination methods (<c>StopAutoPick</c>, <c>ResumeAutoPick</c>) are not
/// included — the current Core only reads the counter.
/// </summary>
public interface IAutoPickRuntimeState
{
    /// <summary>Stop count &gt; 0 means picking is paused.</summary>
    int StopCount { get; }
}
