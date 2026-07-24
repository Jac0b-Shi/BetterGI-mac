using BetterGenshinImpact.GameTask.Macro;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class HoldHotKeyCoordinator(
    CancellationToken hostCancellationToken,
    ILogger<HoldHotKeyCoordinator> logger,
    IReadOnlyDictionary<string, Action<CancellationToken>> actions)
    : IDisposable
{
    public const string TurnAroundHotKey = "TurnAroundHotkey";
    public const string ConfirmButtonHotKey = "ClickGenshinConfirmButtonHotkey";
    public const string CancelButtonHotKey = "ClickGenshinCancelButtonHotkey";
    public const string QuickEnhanceHotKey = "EnhanceArtifactHotkey";
    public const string QuickBuyHotKey = "QuickBuyHotkey";
    public const string OneKeyClaimRewardHotKey = "OneKeyClaimRewardHotkey";
    public const string OneKeyFightHotKey = "OneKeyFightHotkey";

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

    public object HandleKeyEdge(string id, bool isDown)
    {
        ThrowIfDisposed();
        if (!_actions.TryGetValue(id, out var action))
            throw new ArgumentException($"Unknown hold hotkey: {id}", nameof(id));
        if (!isDown)
        {
            Cancel(id);
            return new { id, state = "released" };
        }

        lock (_lock)
        {
            if (!_acceptingInput)
                return new { id, state = "stopped" };
            if (_active.ContainsKey(id))
                return new { id, state = "held" };

            var cancellation = CancellationTokenSource.CreateLinkedTokenSource(
                hostCancellationToken);
            var operation = new ActiveOperation(cancellation);
            _active[id] = operation;
            operation.Task = Task.Run(
                () => RunAsync(id, action, operation));
        }
        return new { id, state = "armed" };
    }

    public async Task StopAsync()
    {
        Task[] activeTasks;
        lock (_lock)
        {
            _acceptingInput = false;
            foreach (var operation in _active.Values)
                operation.Cancellation.Cancel();
            activeTasks = _active.Values.Select(operation => operation.Task).ToArray();
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

    private Task RunAsync(
        string id,
        Action<CancellationToken> action,
        ActiveOperation operation)
    {
        try
        {
            while (true)
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
                "Hold hotkey {HotKey} stopped after input dispatch failed.",
                id);
        }
        finally
        {
            lock (_lock)
            {
                if (_active.TryGetValue(id, out var active) &&
                    ReferenceEquals(active, operation))
                    _active.Remove(id);
            }
            operation.Cancellation.Dispose();
        }
        return Task.CompletedTask;
    }

    private void Cancel(string id)
    {
        lock (_lock)
        {
            if (_active.TryGetValue(id, out var operation))
                operation.Cancellation.Cancel();
        }
    }

    private void ThrowIfDisposed()
    {
        if (Volatile.Read(ref _disposed) != 0)
            throw new ObjectDisposedException(nameof(HoldHotKeyCoordinator));
    }

    private sealed class ActiveOperation(
        CancellationTokenSource cancellation)
    {
        public CancellationTokenSource Cancellation { get; } = cancellation;
        public Task Task { get; set; } = Task.CompletedTask;
    }
}
