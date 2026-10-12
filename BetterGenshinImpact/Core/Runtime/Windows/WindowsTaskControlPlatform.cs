using BetterGenshinImpact.Core.Input;
using BetterGenshinImpact.Core.Simulator;
using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoGeniusInvokation.Exception;
using BetterGenshinImpact.GameTask.Model.Area;
using Microsoft.Extensions.Logging;
using Vanara.PInvoke;
using System;
using System.Threading;
using Fischless.GameCapture;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsTaskControlPlatform : ITaskControlPlatform
{
    public ILogger Logger => App.GetLogger<TaskControl>();
    public double DpiScale => TaskContext.Instance().DpiScale;
    public bool IsHdrCapture =>
        TaskContext.Instance().Config.CaptureMode == nameof(CaptureModes.WindowsGraphicsCaptureHdr);

    public void EnsureGameActive()
    {
        var window = TaskContext.Instance().Runtime?.Window;
        if (window is { RequiresForeground: false })
        {
            if (window.IsMinimized) window.Activate();
            return;
        }
        if (!TaskContext.Instance().Config.OtherConfig.RestoreFocusOnLostEnabled &&
            !SystemControl.IsGenshinImpactActiveByProcess())
        {
            var name = SystemControl.GetActiveByProcess();
            Logger.LogWarning("当前获取焦点的窗口为: {Name}，不是原神，暂停", name);
            throw new RetryException("当前获取焦点的窗口不是原神");
        }

        var count = 0;
        while (!SystemControl.IsGenshinImpactActiveByProcess())
        {
            if (count >= 10 && count % 10 == 0)
            {
                Logger.LogInformation("多次尝试未恢复，尝试最小化后激活窗口！");
                SystemControl.MinimizeAndActivateWindow(TaskContext.Instance().GameHandle);
            }
            else
            {
                var name = SystemControl.GetActiveByProcess();
                Logger.LogInformation("当前获取焦点的窗口为: {Name}，不是原神，尝试恢复窗口", name);
                SystemControl.FocusWindow(TaskContext.Instance().GameHandle);
            }
            count++;
            Thread.Sleep(1000);
        }
    }

    public void ReleasePressedInputs()
    {
        InputHub.ReleaseAll();
    }

    public void SimulateAction(GIActions action, KeyType keyType) =>
        InputHub.Foreground.SimulateAction(action, keyType);
    public bool IsActionKeyDown(GIActions action) =>
        InputHub.Foreground.IsKeyDown(action.ToActionKey().ToVK());
    public void MoveMouseBy(int x, int y) => InputHub.Foreground.Mouse.MoveMouseBy(x, y);
    public void LeftButtonDown() => InputHub.Foreground.Mouse.LeftButtonDown();
    public void LeftButtonUp() => InputHub.Foreground.Mouse.LeftButtonUp();
    public void LeftButtonClick() => InputHub.Foreground.Mouse.LeftButtonClick();
    public void RightButtonDown() => InputHub.Foreground.Mouse.RightButtonDown();
    public void RightButtonUp() => InputHub.Foreground.Mouse.RightButtonUp();
    public void RightButtonClick() => InputHub.Foreground.Mouse.RightButtonClick();
    public void MiddleButtonDown() => InputHub.Foreground.Mouse.MiddleButtonDown();
    public void MiddleButtonUp() => InputHub.Foreground.Mouse.MiddleButtonUp();
    public void MiddleButtonClick() => InputHub.Foreground.Mouse.MiddleButtonClick();
    public void VerticalScroll(int scrollAmountInClicks) =>
        InputHub.Foreground.Mouse.VerticalScroll(scrollAmountInClicks);
    public void KeyDown(int windowsVirtualKey) =>
        InputHub.Foreground.Keyboard.KeyDown((User32.VK)windowsVirtualKey);
    public void KeyUp(int windowsVirtualKey) =>
        InputHub.Foreground.Keyboard.KeyUp((User32.VK)windowsVirtualKey);
    public void PressKey(int windowsVirtualKey) =>
        InputHub.Foreground.Keyboard.KeyPress((User32.VK)windowsVirtualKey);
    public void InputText(string text)
    {
        BetterGenshinImpact.Helpers.UIDispatcherHelper.Invoke(() => System.Windows.Clipboard.SetDataObject(text));
        InputHub.Foreground.Keyboard.KeyDown(User32.VK.VK_CONTROL);
        try { Thread.Sleep(50); InputHub.Foreground.Keyboard.KeyPress(User32.VK.VK_V); Thread.Sleep(50); }
        finally { InputHub.Foreground.Keyboard.KeyUp(User32.VK.VK_CONTROL); }
    }
    public void PressEscape() => InputHub.Foreground.Keyboard.KeyPress(User32.VK.VK_ESCAPE);

    public ImageRegion CaptureToRectArea(bool forceNew)
    {
        var image = TaskControl.CaptureGameImage(TaskContext.Instance().Runtime?.Capture);
        var content = new CaptureContent(image, 0, 0);
        return content.CaptureRectArea;
    }
}
