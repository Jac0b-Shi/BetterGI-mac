namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed record SchedulerStatusSnapshot(
    string? TaskId,
    string State,
    string? GroupName,
    string? Error);

public sealed class SchedulerStatusTracker
{
    private static readonly HashSet<string> ValidStates =
    [
        "running", "paused", "stopping", "completed", "cancelled", "failed"
    ];
    private readonly object _sync = new();
    private SchedulerStatusSnapshot _snapshot = new(null, "idle", null, null);

    public SchedulerStatusSnapshot Start(string taskId, string groupName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(taskId);
        ArgumentException.ThrowIfNullOrWhiteSpace(groupName);
        lock (_sync)
        {
            _snapshot = new SchedulerStatusSnapshot(taskId, "running", groupName, null);
            return _snapshot;
        }
    }

    public SchedulerStatusSnapshot Transition(string taskId, string state, string? error = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(taskId);
        ArgumentException.ThrowIfNullOrWhiteSpace(state);
        if (!ValidStates.Contains(state))
            throw new ArgumentException($"Unsupported scheduler state '{state}'.", nameof(state));
        lock (_sync)
        {
            if (!string.Equals(taskId, _snapshot.TaskId, StringComparison.Ordinal))
                throw new InvalidOperationException($"Scheduler task '{taskId}' is not current.");
            _snapshot = _snapshot with { State = state, Error = error };
            return _snapshot;
        }
    }

    public SchedulerStatusSnapshot Snapshot()
    {
        lock (_sync)
        {
            return _snapshot;
        }
    }

    public static bool IsTerminal(string state) =>
        state is "completed" or "cancelled" or "failed";
}
