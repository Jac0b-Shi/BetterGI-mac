using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.QuickSereniteaPot;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using System.Runtime.Versioning;

namespace BetterGenshinImpact.Core.Host.Runtime;

[SupportedOSPlatform("macos")]
public sealed class MacQuickSereniteaPotRuntimePlatform(
    Func<ISystemInfo> systemInfo,
    MacTaskControlPlatform taskControl,
    ForegroundInputCoordinator inputCoordinator,
    CancellationToken hostCancellationToken,
    ILogger<MacQuickSereniteaPotRuntimePlatform> logger)
    : IQuickSereniteaPotRuntimePlatform
{
    public bool IsInitialized
    {
        get
        {
            var size = systemInfo().GameScreenSize;
            return size.Width > 0 && size.Height > 0;
        }
    }

    public bool IsGameProcessActive =>
        inputCoordinator.IsGameFocused(hostCancellationToken);

    public void NotifyNotStarted() =>
        logger.LogWarning(
            "Quick Serenitea Pot requires the BetterGI runtime.");

    public ImageRegion Capture(
        bool forceNew,
        CancellationToken cancellationToken) =>
        taskControl.CaptureToRectArea(forceNew, cancellationToken);

    public void SimulateAction(
        GIActions action,
        CancellationToken cancellationToken) =>
        taskControl.WithOperationCancellation(
            cancellationToken,
            () =>
            {
                taskControl.SimulateAction(action, KeyType.KeyPress);
                return true;
            });

    public void ClickGame1080P(
        double x,
        double y,
        CancellationToken cancellationToken)
    {
        var info = systemInfo();
        var capture = info.CaptureAreaRect;
        var scale = info.ScaleTo1080PRatio;
        inputCoordinator.Dispatch(
            JObject.FromObject(new
            {
                action = "mouseClick",
                button = "left",
                x = capture.X + (int)Math.Round(x * scale),
                y = capture.Y + (int)Math.Round(y * scale),
            }),
            cancellationToken);
    }

    public void Wait(int milliseconds, CancellationToken cancellationToken)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            hostCancellationToken,
            cancellationToken);
        Task.Delay(milliseconds, linked.Token).GetAwaiter().GetResult();
    }

    public void ClearOverlay() => OverlayDrawPlatform.Current.ClearAll();

    public void LogInformation(string message) =>
        logger.LogInformation("{Message}", message);

    public void LogWarning(Exception exception) =>
        logger.LogWarning(
            exception,
            "Quick Serenitea Pot input sequence failed.");
}
