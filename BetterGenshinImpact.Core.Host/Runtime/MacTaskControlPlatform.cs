using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model.Area;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using System.Runtime.Versioning;

namespace BetterGenshinImpact.Core.Host.Runtime;

[SupportedOSPlatform("macos")]
public sealed class MacTaskControlPlatform(
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken cancellationToken,
    SharedCaptureRingReader captureRing,
    ILogger logger) : ITaskControlPlatform
{
    public ILogger Logger { get; } = logger;
    public bool IsHdrCapture => false;
    public double DpiScale => Invoke("window.metrics", null).Value<double?>("dpiScale")
        ?? throw new InvalidDataException("window.metrics did not return dpiScale.");

    public void EnsureGameActive() => RequireAcknowledgement("window.activate", null);
    public void ReleasePressedInputs() => Dispatch(new { action = "releaseAll" });
    public void SimulateAction(GIActions action, KeyType keyType) => Dispatch(new
    {
        action = "gameAction",
        gameAction = LowerCamel(action.ToString()),
        keyType = LowerCamel(keyType.ToString())
    });
    public bool IsActionKeyDown(GIActions action) => Invoke(
        "input.query", JObject.FromObject(new
        {
            action = "isGameActionDown",
            gameAction = LowerCamel(action.ToString())
        })).Value<bool?>("isDown")
        ?? throw new InvalidDataException("input.query did not return isDown.");
    public void MoveMouseBy(int x, int y) => Dispatch(new { action = "moveMouseBy", x, y });
    public void LeftButtonDown() => Dispatch(new { action = "mouseDown", button = "left" });
    public void LeftButtonUp() => Dispatch(new { action = "mouseUp", button = "left" });
    public void LeftButtonClick() => Dispatch(new { action = "mouseClick", button = "left" });
    public void RightButtonDown() => Dispatch(new { action = "mouseDown", button = "right" });
    public void RightButtonUp() => Dispatch(new { action = "mouseUp", button = "right" });
    public void RightButtonClick() => Dispatch(new { action = "mouseClick", button = "right" });
    public void MiddleButtonDown() => Dispatch(new { action = "mouseDown", button = "middle" });
    public void MiddleButtonUp() => Dispatch(new { action = "mouseUp", button = "middle" });
    public void MiddleButtonClick() => Dispatch(new { action = "mouseClick", button = "middle" });
    public void VerticalScroll(int scrollAmountInClicks) =>
        Dispatch(new { action = "verticalScroll", clicks = scrollAmountInClicks });
    public void KeyDown(int windowsVirtualKey) =>
        Dispatch(new { action = "keyDown", windowsVirtualKey });
    public void KeyUp(int windowsVirtualKey) =>
        Dispatch(new { action = "keyUp", windowsVirtualKey });
    public void PressKey(int windowsVirtualKey) =>
        Dispatch(new { action = "keyPress", windowsVirtualKey });
    public void InputText(string text) => Dispatch(new { action = "inputText", text });
    public void PressEscape() => PressKey(0x1B);

    public ImageRegion CaptureToRectArea(bool forceNew)
    {
        var response = Invoke("capture.request", JObject.FromObject(new { forceNew }));
        return captureRing.Read(response);
    }

    private void Dispatch(object value) => RequireAcknowledgement(
        "input.dispatch", JObject.FromObject(value));

    private void RequireAcknowledgement(string method, JObject? parameters)
    {
        if (Invoke(method, parameters).Value<bool?>("acknowledged") != true)
            throw new InvalidDataException($"{method} did not return acknowledged=true.");
    }

    private JToken Invoke(string method, JObject? parameters) =>
        callbacks.InvokeAsync(method, parameters, sessionToken, cancellationToken)
            .GetAwaiter().GetResult()
        ?? throw new InvalidDataException($"{method} returned an empty response.");

    private static string LowerCamel(string value) =>
        value.Length == 0 ? value : char.ToLowerInvariant(value[0]) + value[1..];
}
