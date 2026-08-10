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
        input.Dispatch(
            JObject.FromObject(new
            {
                action,
                windowsVirtualKey = (int)key,
            }),
            hostCancellationToken);
    }
}
