using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.GameTask.Model.Area;
using Newtonsoft.Json.Linq;
using System.Runtime.Versioning;
using BetterGenshinImpact.GameTask.AutoFight.Script;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>
/// macOS implementation of BetterGI's JavaScript global input surface. Every operation is
/// acknowledged by Swift after its foreground-window and InputSafetyGate checks.
/// </summary>
[SupportedOSPlatform("macos")]
public sealed class MacGlobalMethodRuntime(
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken cancellationToken,
    SharedCaptureRingReader captureRing,
    ForegroundInputCoordinator inputCoordinator) : IGlobalMethodRuntime
{
    public CancellationToken CancellationToken => cancellationToken;

    public double DpiScale => Invoke("window.metrics", null).Value<double?>("dpiScale")
        ?? throw new InvalidDataException("window.metrics did not return dpiScale.");

    public void KeyDown(string key) => Dispatch(new { action = "keyDown", key });
    public void KeyUp(string key) => Dispatch(new { action = "keyUp", key });
    public void KeyPress(string key) => Dispatch(new { action = "keyPress", key });
    public void MoveMouseBy(int x, int y) => Dispatch(new { action = "moveMouseBy", x, y });
    public void MoveMouseToGameCoordinate(int x, int y, int gameWidth, int gameHeight) =>
        Dispatch(new { action = "moveMouseToGame", x, y, gameWidth, gameHeight });
    public void LeftButtonClick() => Dispatch(new { action = "mouseClick", button = "left" });
    public void LeftButtonDown() => Dispatch(new { action = "mouseDown", button = "left" });
    public void LeftButtonUp() => Dispatch(new { action = "mouseUp", button = "left" });
    public void RightButtonClick() => Dispatch(new { action = "mouseClick", button = "right" });
    public void RightButtonDown() => Dispatch(new { action = "mouseDown", button = "right" });
    public void RightButtonUp() => Dispatch(new { action = "mouseUp", button = "right" });
    public void MiddleButtonClick() => Dispatch(new { action = "mouseClick", button = "middle" });
    public void MiddleButtonDown() => Dispatch(new { action = "mouseDown", button = "middle" });
    public void MiddleButtonUp() => Dispatch(new { action = "mouseUp", button = "middle" });
    public void VerticalScroll(int scrollAmountInClicks) =>
        Dispatch(new { action = "verticalScroll", clicks = scrollAmountInClicks });
    public void InputText(string text) => Dispatch(new { action = "inputText", text });

    public ImageRegion CaptureGameRegion() => captureRing.Read(Invoke("capture.request", null));

    public string[] GetAvatars()
    {
        var scene = CombatSceneProvider.Current.GetCombatScene(cancellationToken)
            .GetAwaiter().GetResult()
            ?? throw new InvalidOperationException("队伍角色识别失败");
        return scene.GetAvatars().Select(avatar => avatar.Name).ToArray();
    }

    private void Dispatch(object operation)
    {
        inputCoordinator.Dispatch(JObject.FromObject(operation), cancellationToken);
    }

    private JToken Invoke(string method, JObject? parameters) =>
        callbacks.InvokeAsync(method, parameters, sessionToken, cancellationToken)
            .GetAwaiter().GetResult()
        ?? throw new InvalidDataException($"{method} returned an empty response.");
}
