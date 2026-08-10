using BetterGenshinImpact.GameTask.Music.Model;
using BetterGenshinImpact.GameTask.Music.Service;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacMusicKeyInputTransport(
    ForegroundInputCoordinator input,
    CancellationToken hostCancellationToken) : KeyInputTransportBase
{
    public override MusicInputMode Mode => MusicInputMode.ForegroundSendInput;

    protected override void SendKeyDown(char key)
    {
        Dispatch("keyDown", key);
    }

    protected override void SendKeyUp(char key)
    {
        Dispatch("keyUp", key);
    }

    protected override void ReleasePressedKeys(IReadOnlyList<char> pressedKeys)
    {
        if (!hostCancellationToken.IsCancellationRequested)
        {
            input.ReleaseAllWhenFocused(
                hostCancellationToken,
                includeOperationCancellation: false);
        }
    }

    private void Dispatch(string action, char key)
    {
        input.DispatchOnce(
            JObject.FromObject(new
            {
                action,
                windowsVirtualKey = (int)key,
            }),
            hostCancellationToken);
    }
}

public sealed class MacMusicPlaybackGate(
    ForegroundInputCoordinator input,
    CancellationToken hostCancellationToken) : IMusicPlaybackGate
{
    public bool IsAvailable(CancellationToken cancellationToken)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            hostCancellationToken, cancellationToken);
        return input.IsInputAvailable(linked.Token);
    }

    public Task WaitUntilAvailableAsync(CancellationToken cancellationToken)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            hostCancellationToken, cancellationToken);
        input.WaitForGameFocus(linked.Token);
        return Task.CompletedTask;
    }
}
