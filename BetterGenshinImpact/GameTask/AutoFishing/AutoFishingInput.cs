using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask.Common;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.AutoFishing;

public interface IAutoFishingInput
{
    void MoveMouseBy(int x, int y);
    void LeftButtonDown();
    void LeftButtonUp();
    void LeftButtonClick();
    void RightButtonClick();
    bool IsLeftButtonDown();
    void PressEscape();
    void PressInteraction();
    void SetMoveForward(bool isDown);
    void SetMoveBackward(bool isDown);
    void ReleaseAll();
}

public sealed class TaskControlAutoFishingInput : IAutoFishingInput
{
    public void MoveMouseBy(int x, int y) => TaskControlPlatform.Current.MoveMouseBy(x, y);
    public void LeftButtonDown() => TaskControlPlatform.Current.LeftButtonDown();
    public void LeftButtonUp() => TaskControlPlatform.Current.LeftButtonUp();
    public void LeftButtonClick() => TaskControlPlatform.Current.LeftButtonClick();
    public void RightButtonClick() => TaskControlPlatform.Current.RightButtonClick();
    public bool IsLeftButtonDown() =>
        TaskControlPlatform.Current.IsActionKeyDown(GIActions.NormalAttack);
    public void PressEscape() => TaskControlPlatform.Current.PressEscape();
    public void PressInteraction() => TaskControlPlatform.Current.SimulateAction(
        GIActions.PickUpOrInteract, KeyType.KeyPress);
    public void SetMoveForward(bool isDown) => TaskControlPlatform.Current.SimulateAction(
        GIActions.MoveForward, isDown ? KeyType.KeyDown : KeyType.KeyUp);
    public void SetMoveBackward(bool isDown) => TaskControlPlatform.Current.SimulateAction(
        GIActions.MoveBackward, isDown ? KeyType.KeyDown : KeyType.KeyUp);
    public void ReleaseAll() => TaskControlPlatform.Current.ReleasePressedInputs();
}

internal sealed class SessionBoundAutoFishingInput(IAutoFishingInput inner) : IAutoFishingInput
{
    private readonly AsyncLocal<CancellationToken?> _sessionCancellation = new();

    public IDisposable UseSession(CancellationToken cancellationToken)
    {
        var previous = _sessionCancellation.Value;
        _sessionCancellation.Value = cancellationToken;
        return new SessionScope(this, previous);
    }

    public void MoveMouseBy(int x, int y) => Dispatch(() => inner.MoveMouseBy(x, y));
    public void LeftButtonDown() => Dispatch(inner.LeftButtonDown);
    public void LeftButtonUp() => Dispatch(inner.LeftButtonUp);
    public void LeftButtonClick() => Dispatch(inner.LeftButtonClick);
    public void RightButtonClick() => Dispatch(inner.RightButtonClick);
    public bool IsLeftButtonDown() => Dispatch(inner.IsLeftButtonDown);
    public void PressEscape() => Dispatch(inner.PressEscape);
    public void PressInteraction() => Dispatch(inner.PressInteraction);
    public void SetMoveForward(bool isDown) => Dispatch(() => inner.SetMoveForward(isDown));
    public void SetMoveBackward(bool isDown) => Dispatch(() => inner.SetMoveBackward(isDown));
    public void ReleaseAll() => inner.ReleaseAll();

    private void Dispatch(Action action)
    {
        var cancellationToken = CurrentCancellationToken();
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            action();
        }
        finally
        {
            ReleaseIfCancelled(cancellationToken);
        }
    }

    private T Dispatch<T>(Func<T> action)
    {
        var cancellationToken = CurrentCancellationToken();
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            return action();
        }
        finally
        {
            ReleaseIfCancelled(cancellationToken);
        }
    }

    private CancellationToken CurrentCancellationToken() =>
        _sessionCancellation.Value
        ?? throw new InvalidOperationException("Auto-fishing input was used outside an active session.");

    private void ReleaseIfCancelled(CancellationToken cancellationToken)
    {
        if (!cancellationToken.IsCancellationRequested)
        {
            return;
        }

        try
        {
            inner.ReleaseAll();
        }
        finally
        {
            cancellationToken.ThrowIfCancellationRequested();
        }
    }

    private sealed class SessionScope(
        SessionBoundAutoFishingInput owner,
        CancellationToken? previous) : IDisposable
    {
        private int _disposed;

        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) == 0)
            {
                owner._sessionCancellation.Value = previous;
            }
        }
    }
}
