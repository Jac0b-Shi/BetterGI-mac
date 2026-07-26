using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Platform.Abstractions;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>macOS semantic input adapter. Every operation requires an ACK from Swift's InputSafetyGate.</summary>
public sealed class MacSemanticInputBackend(
    ForegroundInputCoordinator inputCoordinator,
    CancellationToken cancellationToken) : IInputBackend
{
    public void KeyDown(BgiKey key) => Dispatch(new { action = "keyDown", key = KeyName(key) });
    public void KeyUp(BgiKey key) => Dispatch(new { action = "keyUp", key = KeyName(key) });
    public void KeyPress(BgiKey key) => Dispatch(new { action = "keyPress", key = KeyName(key) });
    public void MoveMouseTo(int screenX, int screenY) => Dispatch(new
        { action = "moveMouseToScreen", x = screenX, y = screenY });
    public void MoveMouseBy(int deltaX, int deltaY) => Dispatch(new
        { action = "moveMouseBy", x = deltaX, y = deltaY });
    public void LeftButtonDown() => Dispatch(new { action = "mouseDown", button = "left" });
    public void LeftButtonUp() => Dispatch(new { action = "mouseUp", button = "left" });
    public void LeftClick(int screenX, int screenY) => Dispatch(new
        { action = "mouseClick", button = "left", x = screenX, y = screenY });
    public void Scroll(int delta) => Dispatch(new { action = "verticalScroll", clicks = delta });

    private void Dispatch(object parameters)
    {
        inputCoordinator.Dispatch(JObject.FromObject(parameters), cancellationToken);
    }

    private static string KeyName(BgiKey key) => key switch
    {
        BgiKey.None => throw new ArgumentOutOfRangeException(nameof(key)),
        _ => key.ToString(),
    };
}
