using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.QuickBuy;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;
using Wpf.Ui.Violeta.Controls;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsQuickBuyRuntimePlatform : IQuickBuyRuntimePlatform
{
    public bool IsInitialized => TaskContext.Instance().IsInitialized;
    public bool IsGameProcessActive =>
        SystemControl.IsGenshinImpactActiveByProcess();

    public void NotifyNotStarted() => Toast.Warning("请先启动");
    public ImageRegion Capture() => TaskControl.CaptureToRectArea();

    public void MoveGame1080P(
        double x,
        double y,
        CancellationToken cancellationToken) =>
        GameCaptureRegion.GameRegion1080PPosMove(x, y);

    public void ClickGame1080P(
        double x,
        double y,
        CancellationToken cancellationToken) =>
        GameCaptureRegion.GameRegion1080PPosClick(x, y);

    public void ClickFromBottomRight1080P(
        double x,
        double y,
        CancellationToken cancellationToken) =>
        GameCaptureRegion.GameRegionClick(
            (size, scale) => (
                size.Width - x * scale,
                size.Height - y * scale));

    public void MoveMouseBy(
        int x,
        int y,
        CancellationToken cancellationToken) =>
        TaskControl.MoveMouseBy(x, y);

    public void LeftButtonDown(CancellationToken cancellationToken) =>
        TaskControl.LeftButtonDown();

    public void LeftButtonUp(CancellationToken cancellationToken) =>
        TaskControl.LeftButtonUp();

    public void Wait(int milliseconds, CancellationToken cancellationToken) =>
        TaskControl.Sleep(milliseconds, cancellationToken);

    public void ClearOverlay() => OverlayDrawPlatform.Current.ClearAll();

    public void LogWarning(Exception exception) =>
        TaskControl.Logger.LogWarning(exception, "{Message}", exception.Message);
}
