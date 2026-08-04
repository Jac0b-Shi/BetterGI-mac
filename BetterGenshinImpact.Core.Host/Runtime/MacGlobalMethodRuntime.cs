using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Script;
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
    SharedCaptureRingReader captureRing,
    ForegroundInputCoordinator inputCoordinator,
    ExternalKeyMappingResolver keyMappingResolver) : IGlobalMethodRuntime
{
    public CancellationToken CancellationToken => CancellationContext.Instance.Cts.Token;

    public double DpiScale => Invoke("window.metrics", null).Value<double?>("dpiScale")
        ?? throw new InvalidDataException("window.metrics did not return dpiScale.");

    public void KeyDown(string key) => DispatchKey("keyDown", key);
    public void KeyUp(string key) => DispatchKey("keyUp", key);
    public void KeyPress(string key) => DispatchKey("keyPress", key);
    public void MoveMouseBy(int x, int y) => Dispatch(new { action = "moveMouseBy", x, y });
    public void MoveMouseToGameCoordinate(int x, int y, int gameWidth, int gameHeight) =>
        Dispatch(new { action = "moveMouseToGame", x, y, gameWidth, gameHeight });
    public void ClickGameCoordinate(int x, int y, int gameWidth, int gameHeight) =>
        Dispatch(new { action = "mouseClickGame", button = "left", x, y, gameWidth, gameHeight });
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

    public ImageRegion CaptureGameRegion() =>
        captureRing.Read(Invoke(
            "capture.request", null, PlatformCallbackChannel.CaptureResponseTimeout))
            .DeriveTo1080P();

    public string[] GetAvatars()
    {
        var scene = CombatSceneProvider.Current.GetCombatScene(CancellationToken)
            .GetAwaiter().GetResult()
            ?? throw new InvalidOperationException("队伍角色识别失败");
        return scene.GetAvatars().Select(avatar => avatar.Name).ToArray();
    }

    private void Dispatch(object operation)
    {
        inputCoordinator.Dispatch(JObject.FromObject(operation), CancellationToken);
    }

    private void DispatchKey(string action, string key)
    {
        var mapped = keyMappingResolver.Resolve(key);
        if (mapped is null)
        {
            Dispatch(new JObject
            {
                ["action"] = action,
                ["key"] = key,
            });
            return;
        }
        if (mapped.WindowsVirtualKey is null &&
            mapped.MouseButton is null)
        {
            return;
        }
        if (mapped.MouseButton is not null)
        {
            Dispatch(new JObject
            {
                ["action"] = action switch
                {
                    "keyDown" => "mouseDown",
                    "keyUp" => "mouseUp",
                    "keyPress" => "mouseClick",
                    _ => throw new ArgumentOutOfRangeException(
                        nameof(action), action, null),
                },
                ["button"] = mapped.MouseButton,
            });
            return;
        }
        Dispatch(new JObject
        {
            ["action"] = action,
            ["windowsVirtualKey"] = mapped.WindowsVirtualKey,
        });
    }

    private JToken Invoke(
        string method,
        JObject? parameters,
        TimeSpan? responseTimeout = null) =>
        callbacks.InvokeAsync(
                method, parameters, sessionToken, CancellationToken, responseTimeout)
            .GetAwaiter().GetResult()
        ?? throw new InvalidDataException($"{method} returned an empty response.");
}
