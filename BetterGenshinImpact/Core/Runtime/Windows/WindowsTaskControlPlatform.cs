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
        foreach (User32.VK key in Enum.GetValues(typeof(User32.VK)))
        {
            if ((User32.GetAsyncKeyState((int)key) & 0x8000) == 0) continue;
            Logger.LogWarning("解除{Key}的按下状态.", key);
            Simulation.SendInput.Keyboard.KeyUp(key);
        }
    }

    public void SimulateAction(GIActions action, KeyType keyType) =>
        Simulation.SendInput.SimulateAction(action, keyType);
    public bool IsActionKeyDown(GIActions action) =>
        Simulation.IsKeyDown(action.ToActionKey().ToVK());
    public void MoveMouseBy(int x, int y) => Simulation.SendInput.Mouse.MoveMouseBy(x, y);
    public void LeftButtonDown() => Simulation.SendInput.Mouse.LeftButtonDown();
    public void LeftButtonUp() => Simulation.SendInput.Mouse.LeftButtonUp();
    public void LeftButtonClick() => Simulation.SendInput.Mouse.LeftButtonClick();
    public void RightButtonDown() => Simulation.SendInput.Mouse.RightButtonDown();
    public void RightButtonUp() => Simulation.SendInput.Mouse.RightButtonUp();
    public void RightButtonClick() => Simulation.SendInput.Mouse.RightButtonClick();
    public void MiddleButtonDown() => Simulation.SendInput.Mouse.MiddleButtonDown();
    public void MiddleButtonUp() => Simulation.SendInput.Mouse.MiddleButtonUp();
    public void MiddleButtonClick() => Simulation.SendInput.Mouse.MiddleButtonClick();
    public void VerticalScroll(int scrollAmountInClicks) =>
        Simulation.SendInput.Mouse.VerticalScroll(scrollAmountInClicks);
    public void KeyDown(int windowsVirtualKey) =>
        Simulation.SendInput.Keyboard.KeyDown((User32.VK)windowsVirtualKey);
    public void KeyUp(int windowsVirtualKey) =>
        Simulation.SendInput.Keyboard.KeyUp((User32.VK)windowsVirtualKey);
    public void PressKey(int windowsVirtualKey) =>
        Simulation.SendInput.Keyboard.KeyPress((User32.VK)windowsVirtualKey);
    public void InputText(string text) => Simulation.SendInput.Keyboard.TextEntry(text);
    public void PressEscape() => Simulation.SendInput.Keyboard.KeyPress(User32.VK.VK_ESCAPE);

    public ImageRegion CaptureToRectArea(bool forceNew)
    {
        var image = TaskControl.CaptureGameImage(TaskTriggerDispatcher.GlobalGameCapture);
        var content = new CaptureContent(image, 0, 0);
        return content.CaptureRectArea;
    }
}
