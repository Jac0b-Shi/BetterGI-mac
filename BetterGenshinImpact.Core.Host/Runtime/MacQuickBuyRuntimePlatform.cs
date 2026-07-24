using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.QuickBuy;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using System.Runtime.Versioning;

namespace BetterGenshinImpact.Core.Host.Runtime;

[SupportedOSPlatform("macos")]
public sealed class MacQuickBuyRuntimePlatform(
    Func<ISystemInfo> systemInfo,
    MacTaskControlPlatform taskControl,
    ForegroundInputCoordinator inputCoordinator,
    CancellationToken hostCancellationToken,
    ILogger<MacQuickBuyRuntimePlatform> logger)
    : IQuickBuyRuntimePlatform
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
        logger.LogWarning("Quick buy requires the BetterGI runtime.");

    public ImageRegion Capture() => taskControl.CaptureToRectArea(forceNew: false);

    public void MoveGame1080P(
        double x,
        double y,
        CancellationToken cancellationToken)
    {
        var point = ResolveScreenPoint(x, y);
        Dispatch(
            new
            {
                action = "moveMouseToScreen",
                x = point.X,
                y = point.Y,
            },
            cancellationToken);
    }

    public void ClickGame1080P(
        double x,
        double y,
        CancellationToken cancellationToken)
    {
        var point = ResolveScreenPoint(x, y);
        Dispatch(
            new
            {
                action = "mouseClick",
                button = "left",
                x = point.X,
                y = point.Y,
            },
            cancellationToken);
    }

    public void ClickFromBottomRight1080P(
        double x,
        double y,
        CancellationToken cancellationToken)
    {
        var info = systemInfo();
        var capture = info.CaptureAreaRect;
        var scale = info.ScaleTo1080PRatio;
        Dispatch(
            new
            {
                action = "mouseClick",
                button = "left",
                x = capture.X + (int)Math.Round(capture.Width - x * scale),
                y = capture.Y + (int)Math.Round(capture.Height - y * scale),
            },
            cancellationToken);
    }

    public void MoveMouseBy(
        int x,
        int y,
        CancellationToken cancellationToken) =>
        Dispatch(new { action = "moveMouseBy", x, y }, cancellationToken);

    public void LeftButtonDown(CancellationToken cancellationToken) =>
        Dispatch(
            new { action = "mouseDown", button = "left" },
            cancellationToken);

    public void LeftButtonUp(CancellationToken cancellationToken) =>
        Dispatch(
            new { action = "mouseUp", button = "left" },
            cancellationToken);

    public void Wait(int milliseconds, CancellationToken cancellationToken)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            hostCancellationToken, cancellationToken);
        Task.Delay(milliseconds, linked.Token).GetAwaiter().GetResult();
    }

    public void ClearOverlay() => OverlayDrawPlatform.Current.ClearAll();

    public void LogWarning(Exception exception) =>
        logger.LogWarning(exception, "Quick buy input sequence failed.");

    private (int X, int Y) ResolveScreenPoint(double x, double y)
    {
        var info = systemInfo();
        var capture = info.CaptureAreaRect;
        var scale = info.ScaleTo1080PRatio;
        return (
            capture.X + (int)Math.Round(x * scale),
            capture.Y + (int)Math.Round(y * scale));
    }

    private void Dispatch(object value, CancellationToken cancellationToken) =>
        inputCoordinator.Dispatch(
            JObject.FromObject(value),
            cancellationToken);
}
