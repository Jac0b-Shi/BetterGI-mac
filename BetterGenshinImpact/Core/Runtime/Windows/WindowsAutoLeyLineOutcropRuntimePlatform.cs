using System;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoLeyLineOutcrop;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Service.Notification;
using BetterGenshinImpact.View;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoLeyLineOutcropRuntimePlatform : IAutoLeyLineOutcropRuntimePlatform
{
    private bool _overlayDisplayTemporarilyEnabled;
    private bool _overlayDisplayOriginalValue;
    private DateTime _lastMaskBringTopTime = DateTime.MinValue;

    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public IOcrService OcrService => OcrFactory.Paddle;
    public AutoFightConfig AutoFightConfig => TaskContext.Instance().Config.AutoFightConfig;
    public string PickKey => TaskContext.Instance().Config.AutoPickConfig.PickKey;
    public double MapScaleFactor => TaskContext.Instance().Config.TpConfig.MapScaleFactor;
    public ILogger<AutoLeyLineOutcropTask> Logger => App.GetLogger<AutoLeyLineOutcropTask>();

    public void Notify(AutoLeyLineOutcropNotification notification, string message)
    {
        var sender = BetterGenshinImpact.Service.Notification.Notify.Event("AutoLeyLineOutcrop");
        if (notification == AutoLeyLineOutcropNotification.Error) sender.Error(message);
        else sender.Send(message);
    }

    public void EnsureOverlayVisible()
    {
        var config = TaskContext.Instance().Config.MaskWindowConfig;
        _overlayDisplayOriginalValue = config.DisplayRecognitionResultsOnMask;
        if (!config.DisplayRecognitionResultsOnMask)
        {
            config.DisplayRecognitionResultsOnMask = true;
            _overlayDisplayTemporarilyEnabled = true;
        }
        RefreshOverlay();
    }

    public void RefreshOverlay()
    {
        var maskWindow = MaskWindow.InstanceNullable();
        if (maskWindow is null) return;
        var now = DateTime.UtcNow;
        var shouldBringTop = now - _lastMaskBringTopTime > TimeSpan.FromSeconds(1);
        if (shouldBringTop) _lastMaskBringTopTime = now;
        maskWindow.Invoke(() =>
        {
            maskWindow.Topmost = true;
            if (!maskWindow.IsVisible) maskWindow.Show();
            if (shouldBringTop) maskWindow.BringToTop();
            maskWindow.Refresh();
        });
    }

    public void RestoreOverlayVisible()
    {
        if (!_overlayDisplayTemporarilyEnabled) return;
        TaskContext.Instance().Config.MaskWindowConfig.DisplayRecognitionResultsOnMask =
            _overlayDisplayOriginalValue;
        _overlayDisplayTemporarilyEnabled = false;
    }
}
