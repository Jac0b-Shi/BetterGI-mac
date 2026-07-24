using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Macro;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.QuickBuy;
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
    ILogger logger,
    ForegroundInputCoordinator inputCoordinator,
    GameActionKeyResolver keyResolver) : ITaskControlPlatform
{
    private readonly AsyncLocal<CancellationToken?> _operationCancellation = new();

    public ILogger Logger { get; } = logger;
    public bool IsHdrCapture => false;
    public double DpiScale => Invoke("window.metrics", null).Value<double?>("dpiScale")
        ?? throw new InvalidDataException("window.metrics did not return dpiScale.");

    public void EnsureGameActive() => inputCoordinator.WaitForGameFocus(cancellationToken);
    public void ReleasePressedInputs() => inputCoordinator.ReleaseAllWhenFocused(cancellationToken);
    public void SimulateAction(GIActions action, KeyType keyType)
    {
        var resolvedKey = keyResolver.Resolve(action);
        if (resolvedKey.WindowsVirtualKey is null && resolvedKey.MouseButton is null)
            return;
        var parameters = new JObject
        {
            ["action"] = "gameAction",
            ["gameAction"] = LowerCamel(action.ToString()),
            ["keyType"] = LowerCamel(keyType.ToString())
        };
        AddResolvedKey(parameters, resolvedKey);
        Dispatch(parameters);
    }

    public bool IsActionKeyDown(GIActions action) => Invoke(
        "input.query", CreateActionQuery(action)).Value<bool?>("isDown")
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
        return captureRing.Read(response).DeriveTo1080P();
    }

    public ImageRegion CaptureToRectArea(
        bool forceNew,
        CancellationToken operationCancellation) =>
        WithCancellation(
            operationCancellation,
            () => CaptureToRectArea(forceNew));

    public Action<CancellationToken> CreateDialogButtonAction(
        DialogButtonType buttonType) =>
        cancellationToken => WithCancellation(
            cancellationToken,
            () => DialogButtonClickMacro.Done(
                buttonType, cancellationToken));

    public Action<CancellationToken> CreateQuickBuyAction() =>
        cancellationToken => WithCancellation(
            cancellationToken,
            () =>
            {
                QuickBuyTask.Done(cancellationToken);
                return true;
            });

    private T WithCancellation<T>(
        CancellationToken operationCancellation,
        Func<T> operation)
    {
        var previous = _operationCancellation.Value;
        _operationCancellation.Value = operationCancellation;
        try
        {
            return operation();
        }
        finally
        {
            _operationCancellation.Value = previous;
        }
    }

    private JObject CreateActionQuery(GIActions action)
    {
        var parameters = new JObject
        {
            ["action"] = "isGameActionDown",
            ["gameAction"] = LowerCamel(action.ToString())
        };
        AddResolvedKey(parameters, keyResolver.Resolve(action));
        return parameters;
    }

    private static void AddResolvedKey(
        JObject parameters,
        ResolvedGameActionKey resolvedKey)
    {
        if (resolvedKey.MouseButton is null)
            parameters["windowsVirtualKey"] = resolvedKey.WindowsVirtualKey
                ?? throw new InvalidOperationException("Game action does not have a physical key binding.");
        else
            parameters["mouseButton"] = resolvedKey.MouseButton;
    }

    private void Dispatch(object value) =>
        inputCoordinator.Dispatch(JObject.FromObject(value), EffectiveCancellation);

    private void RequireAcknowledgement(string method, JObject? parameters)
    {
        if (Invoke(method, parameters).Value<bool?>("acknowledged") != true)
            throw new InvalidDataException($"{method} did not return acknowledged=true.");
    }

    private JToken Invoke(string method, JObject? parameters) =>
        callbacks.InvokeAsync(
                method, parameters, sessionToken, EffectiveCancellation)
            .GetAwaiter().GetResult()
        ?? throw new InvalidDataException($"{method} returned an empty response.");

    private CancellationToken EffectiveCancellation =>
        _operationCancellation.Value ?? cancellationToken;

    private static string LowerCamel(string value) =>
        value.Length == 0 ? value : char.ToLowerInvariant(value[0]) + value[1..];
}
