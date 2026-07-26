using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class OneShotHotKeyCoordinator(
    CancellationToken hostCancellationToken,
    ILogger<OneShotHotKeyCoordinator> logger,
    IReadOnlyDictionary<string, Action<CancellationToken>> actions)
    : IDisposable
{
    public const string QuickSereniteaPotHotKey =
        "QuickSereniteaPotHotkey";
    public const string BigMapPositionHotKey =
        "RecBigMapPosHotkey";

    private readonly object _lock = new();
    private readonly IReadOnlyDictionary<string, Action<CancellationToken>> _actions =
        actions ?? throw new ArgumentNullException(nameof(actions));
    private readonly Dictionary<string, ActiveOperation> _active =
        new(StringComparer.Ordinal);
    private bool _acceptingInput;
    private int _disposed;

    public void Start()
    {
        ThrowIfDisposed();
        lock (_lock)
            _acceptingInput = true;
    }

    public object Invoke(string id)
    {
        ThrowIfDisposed();
        if (!_actions.TryGetValue(id, out var action))
            throw new ArgumentException(
                $"Unknown one-shot hotkey: {id}",
                nameof(id));

        lock (_lock)
        {
            if (!_acceptingInput)
                return new { id, state = "stopped" };
            if (_active.ContainsKey(id))
                return new { id, state = "running" };

            var cancellation = CancellationTokenSource.CreateLinkedTokenSource(
                hostCancellationToken);
            var operation = new ActiveOperation(cancellation);
            _active[id] = operation;
            operation.Task = Task.Run(
                () => Run(id, action, operation));
        }
        return new { id, state = "started" };
    }

    public async Task StopAsync()
    {
        Task[] activeTasks;
        lock (_lock)
        {
            _acceptingInput = false;
            foreach (var operation in _active.Values)
                operation.Cancellation.Cancel();
            activeTasks = _active.Values
                .Select(operation => operation.Task)
                .ToArray();
        }
        await Task.WhenAll(activeTasks);
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0)
            return;
        StopAsync().GetAwaiter().GetResult();
        GC.SuppressFinalize(this);
    }

    private void Run(
        string id,
        Action<CancellationToken> action,
        ActiveOperation operation)
    {
        try
        {
            action(operation.Cancellation.Token);
        }
        catch (OperationCanceledException)
            when (operation.Cancellation.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            logger.LogWarning(
                exception,
                "One-shot hotkey {HotKey} failed.",
                id);
        }
        finally
        {
            lock (_lock)
            {
                if (_active.TryGetValue(id, out var active) &&
                    ReferenceEquals(active, operation))
                {
                    _active.Remove(id);
                }
            }
            operation.Cancellation.Dispose();
        }
    }

    private void ThrowIfDisposed()
    {
        if (Volatile.Read(ref _disposed) != 0)
            throw new ObjectDisposedException(nameof(OneShotHotKeyCoordinator));
    }

    private sealed class ActiveOperation(
        CancellationTokenSource cancellation)
    {
        public CancellationTokenSource Cancellation { get; } = cancellation;
        public Task Task { get; set; } = Task.CompletedTask;
    }
}
