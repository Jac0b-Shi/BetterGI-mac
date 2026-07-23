using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class AuxiliaryControlCoordinator(
    MacroSettingsCatalog settings,
    Action<int, CancellationToken> pressKey,
    CancellationToken hostCancellationToken,
    ILogger<AuxiliaryControlCoordinator> logger) : IDisposable
{
    public const string PickUpOrInteractControl = "pickUpOrInteract";
    public const string JumpControl = "jump";

    private readonly object _lock = new();
    private readonly Dictionary<string, ActiveControl> _activeControls =
        new(StringComparer.Ordinal);
    private bool _acceptingInput;
    private int _disposed;

    public void Start()
    {
        ThrowIfDisposed();
        lock (_lock)
            _acceptingInput = true;
    }

    public object HandleKeyEdge(string control, bool isDown)
    {
        ThrowIfDisposed();
        var specification = ResolveSpecification(control, settings.Snapshot());
        if (!isDown)
        {
            Cancel(control);
            return new { control, state = "released" };
        }
        if (!specification.Enabled)
            return new { control, state = "disabled" };

        lock (_lock)
        {
            if (!_acceptingInput)
                return new { control, state = "stopped" };
            if (_activeControls.ContainsKey(control))
                return new { control, state = "held" };

            var cancellation = CancellationTokenSource.CreateLinkedTokenSource(
                hostCancellationToken);
            var active = new ActiveControl(cancellation);
            _activeControls.Add(control, active);
            active.Task = Task.Run(
                () => RunAsync(control, specification, active));
        }
        return new { control, state = "armed" };
    }

    public async Task StopAsync()
    {
        ActiveControl[] activeControls;
        lock (_lock)
        {
            _acceptingInput = false;
            activeControls = _activeControls.Values.ToArray();
            _activeControls.Clear();
        }
        foreach (var active in activeControls)
            active.Cancellation.Cancel();
        await Task.WhenAll(activeControls.Select(active => active.Task));
    }

    public void ApplySettings(MacroSettingsSnapshot snapshot)
    {
        if (!snapshot.FPressHoldToContinuationEnabled)
            Cancel(PickUpOrInteractControl);
        if (!snapshot.SpacePressHoldToContinuationEnabled)
            Cancel(JumpControl);
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0)
            return;
        StopAsync().GetAwaiter().GetResult();
        GC.SuppressFinalize(this);
    }

    private async Task RunAsync(
        string control,
        ControlSpecification specification,
        ActiveControl active)
    {
        try
        {
            await Task.Delay(specification.HoldThreshold, active.Cancellation.Token);
            while (true)
            {
                await Task.Delay(
                    TimeSpan.FromMilliseconds(specification.IntervalMilliseconds),
                    active.Cancellation.Token);
                pressKey(
                    specification.WindowsVirtualKey,
                    active.Cancellation.Token);
            }
        }
        catch (OperationCanceledException)
            when (active.Cancellation.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            logger.LogWarning(
                exception,
                "Auxiliary control {Control} stopped after input dispatch failed.",
                control);
        }
        finally
        {
            lock (_lock)
            {
                if (_activeControls.TryGetValue(control, out var current) &&
                    ReferenceEquals(current, active))
                {
                    _activeControls.Remove(control);
                }
            }
            active.Cancellation.Dispose();
        }
    }

    private void Cancel(string control)
    {
        ActiveControl? active;
        lock (_lock)
        {
            if (!_activeControls.Remove(control, out active))
                return;
        }
        active.Cancellation.Cancel();
    }

    private static ControlSpecification ResolveSpecification(
        string control,
        MacroSettingsSnapshot snapshot) => control switch
    {
        PickUpOrInteractControl => new ControlSpecification(
            snapshot.FPressHoldToContinuationEnabled,
            snapshot.FFireInterval,
            snapshot.PickUpOrInteractKeyCode,
            TimeSpan.FromMilliseconds(200)),
        JumpControl => new ControlSpecification(
            snapshot.SpacePressHoldToContinuationEnabled,
            snapshot.SpaceFireInterval,
            snapshot.JumpKeyCode,
            TimeSpan.FromMilliseconds(300)),
        _ => throw new ArgumentException(
            $"Unknown auxiliary control: {control}",
            nameof(control)),
    };

    private void ThrowIfDisposed()
    {
        if (Volatile.Read(ref _disposed) != 0)
            throw new ObjectDisposedException(nameof(AuxiliaryControlCoordinator));
    }

    private sealed class ActiveControl(CancellationTokenSource cancellation)
    {
        public CancellationTokenSource Cancellation { get; } = cancellation;
        public Task Task { get; set; } = Task.CompletedTask;
    }

    private sealed record ControlSpecification(
        bool Enabled,
        int IntervalMilliseconds,
        int WindowsVirtualKey,
        TimeSpan HoldThreshold);
}
