using BetterGenshinImpact.GameTask.Macro;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class HoldHotKeyCoordinator(
    CancellationToken hostCancellationToken,
    ILogger<HoldHotKeyCoordinator> logger) : IDisposable
{
    public const string TurnAroundHotKey = "TurnAroundHotkey";

    private readonly object _lock = new();
    private CancellationTokenSource? _activeCancellation;
    private Task _activeTask = Task.CompletedTask;
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
        if (!string.Equals(id, TurnAroundHotKey, StringComparison.Ordinal))
            throw new ArgumentException($"Unknown hold hotkey: {id}", nameof(id));
        if (!isDown)
        {
            Cancel();
            return new { id, state = "released" };
        }

        lock (_lock)
        {
            if (!_acceptingInput)
                return new { id, state = "stopped" };
            if (_activeCancellation is not null)
                return new { id, state = "held" };

            var cancellation = CancellationTokenSource.CreateLinkedTokenSource(
                hostCancellationToken);
            _activeCancellation = cancellation;
            _activeTask = Task.Run(() => RunAsync(cancellation));
        }
        return new { id, state = "armed" };
    }

    public async Task StopAsync()
    {
        Task activeTask;
        lock (_lock)
        {
            _acceptingInput = false;
            _activeCancellation?.Cancel();
            activeTask = _activeTask;
        }
        await activeTask;
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0)
            return;
        StopAsync().GetAwaiter().GetResult();
        GC.SuppressFinalize(this);
    }

    private Task RunAsync(CancellationTokenSource cancellation)
    {
        try
        {
            while (true)
                TurnAroundMacro.Done(cancellation.Token);
        }
        catch (OperationCanceledException)
            when (cancellation.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            logger.LogWarning(
                exception,
                "Hold hotkey {HotKey} stopped after input dispatch failed.",
                TurnAroundHotKey);
        }
        finally
        {
            lock (_lock)
            {
                if (ReferenceEquals(_activeCancellation, cancellation))
                {
                    _activeCancellation = null;
                    _activeTask = Task.CompletedTask;
                }
            }
            cancellation.Dispose();
        }
        return Task.CompletedTask;
    }

    private void Cancel()
    {
        lock (_lock)
            _activeCancellation?.Cancel();
    }

    private void ThrowIfDisposed()
    {
        if (Volatile.Read(ref _disposed) != 0)
            throw new ObjectDisposedException(nameof(HoldHotKeyCoordinator));
    }
}
