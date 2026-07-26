using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Simulator;
using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.QuickSereniteaPot;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;
using Wpf.Ui.Violeta.Controls;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsQuickSereniteaPotRuntimePlatform
    : IQuickSereniteaPotRuntimePlatform
{
    public bool IsInitialized => TaskContext.Instance().IsInitialized;
    public bool IsGameProcessActive =>
        SystemControl.IsGenshinImpactActiveByProcess();

    public void NotifyNotStarted() => Toast.Warning("请先启动");

    public ImageRegion Capture(
        bool forceNew,
        CancellationToken cancellationToken) =>
        TaskControl.CaptureToRectArea(forceNew);

    public void SimulateAction(
        GIActions action,
        CancellationToken cancellationToken) =>
        Simulation.SendInput.SimulateAction(action);

    public void ClickGame1080P(
        double x,
        double y,
        CancellationToken cancellationToken) =>
        GameCaptureRegion.GameRegion1080PPosClick(x, y);

    public void Wait(int milliseconds, CancellationToken cancellationToken) =>
        TaskControl.Sleep(milliseconds, cancellationToken);

    public void ClearOverlay() => OverlayDrawPlatform.Current.ClearAll();

    public void LogInformation(string message) =>
        TaskControl.Logger.LogInformation("{Message}", message);

    public void LogWarning(Exception exception) =>
        TaskControl.Logger.LogWarning(
            exception,
            "{Message}",
            exception.Message);
}
