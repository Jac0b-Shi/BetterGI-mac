using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Recorder;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using System.Drawing;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.Map;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacKeyMouseMacroPlatform(
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken cancellationToken,
    ILogger logger,
    ForegroundInputCoordinator inputCoordinator) : IKeyMouseMacroPlatform
{
    public ILogger Logger { get; } = logger;
    public bool IsInitialized => Metrics().Value<int?>("captureWidth") > 0;
    public double DpiScale => Metrics().Value<double?>("dpiScale")
        ?? throw InvalidMetrics("dpiScale");

    public Rectangle CaptureArea
    {
        get
        {
            var metrics = Metrics();
            return new Rectangle(
                RequiredInt(metrics, "captureX"), RequiredInt(metrics, "captureY"),
                RequiredInt(metrics, "captureWidth"), RequiredInt(metrics, "captureHeight"));
        }
    }

    public Size WorkingArea
    {
        get
        {
            var metrics = Metrics();
            return new Size(RequiredInt(metrics, "workingAreaWidth"), RequiredInt(metrics, "workingAreaHeight"));
        }
    }

    public void ActivateGameWindow() => inputCoordinator.WaitForGameFocus(cancellationToken);
    public double GetCameraOrientation()
    {
        using var region = TaskControl.CaptureToRectArea();
        return CameraOrientation.Compute(region.SrcMat);
    }
    public void KeyDown(int windowsVirtualKey) => Input(new { action = "keyDown", windowsVirtualKey });
    public void KeyUp(int windowsVirtualKey) => Input(new { action = "keyUp", windowsVirtualKey });
    public void MoveMouseTo(double normalizedX, double normalizedY) =>
        Input(new { action = "moveMouseToVirtualDesktop", normalizedX, normalizedY });
    public void MoveMouseBy(int x, int y) => Input(new { action = "moveMouseBy", x, y });
    public void MouseDown(string button) => Input(new { action = "mouseDown", button });
    public void MouseUp(string button) => Input(new { action = "mouseUp", button });
    public void VerticalScroll(int clicks) => Input(new { action = "verticalScroll", clicks });

    private JObject Metrics() => Invoke("window.metrics", null) as JObject
        ?? throw new InvalidDataException("window.metrics did not return an object.");
    private void Input(object value) =>
        inputCoordinator.Dispatch(JObject.FromObject(value), cancellationToken);

    private void Acknowledged(string method, JObject? parameters)
    {
        var response = Invoke(method, parameters);
        if (response.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException($"{method} did not return acknowledged=true.");
    }

    private JToken Invoke(string method, JObject? parameters) =>
        callbacks.InvokeAsync(method, parameters, sessionToken, cancellationToken).GetAwaiter().GetResult()
        ?? throw new InvalidDataException($"{method} returned an empty response.");
    private static int RequiredInt(JObject value, string name) =>
        value.Value<int?>(name) ?? throw InvalidMetrics(name);
    private static InvalidDataException InvalidMetrics(string name) =>
        new($"window.metrics did not return {name}.");
}
