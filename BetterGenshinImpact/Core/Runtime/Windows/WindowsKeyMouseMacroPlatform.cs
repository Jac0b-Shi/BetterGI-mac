using BetterGenshinImpact.Core.Recorder;
using BetterGenshinImpact.Core.Simulator;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.Map;
using Fischless.WindowsInput;
using Microsoft.Extensions.Logging;
using System;
using System.Drawing;
using System.Windows.Forms;
using Vanara.PInvoke;

namespace BetterGenshinImpact.GameTask;

public sealed class WindowsKeyMouseMacroPlatform : IKeyMouseMacroPlatform
{
    public ILogger Logger => TaskControl.Logger;
    public bool IsInitialized => TaskContext.Instance().IsInitialized;
    public Rectangle CaptureArea
    {
        get
        {
            var rect = TaskContext.Instance().SystemInfo.CaptureAreaRect;
            return new Rectangle(rect.X, rect.Y, rect.Width, rect.Height);
        }
    }
    public Size WorkingArea => Screen.PrimaryScreen?.WorkingArea.Size
        ?? throw new InvalidOperationException("Primary screen is unavailable.");
    public double DpiScale => TaskContext.Instance().DpiScale;

    public void ActivateGameWindow() => SystemControl.ActivateWindow();
    public double GetCameraOrientation() => CameraOrientation.Compute(TaskControl.CaptureToRectArea().SrcMat);

    public void KeyDown(int windowsVirtualKey)
    {
        var key = (User32.VK)windowsVirtualKey;
        if (InputBuilder.IsExtendedKey(key)) Simulation.SendInput.Keyboard.KeyDown(false, key);
        else Simulation.SendInput.Keyboard.KeyDown(key);
    }

    public void KeyUp(int windowsVirtualKey)
    {
        var key = (User32.VK)windowsVirtualKey;
        if (InputBuilder.IsExtendedKey(key)) Simulation.SendInput.Keyboard.KeyUp(false, key);
        else Simulation.SendInput.Keyboard.KeyUp(key);
    }

    public void MoveMouseTo(double normalizedX, double normalizedY) =>
        Simulation.SendInput.Mouse.MoveMouseTo(normalizedX, normalizedY);
    public void MoveMouseBy(int x, int y) => Simulation.SendInput.Mouse.MoveMouseBy(x, y);

    public void MouseDown(string button)
    {
        switch (button)
        {
            case "left": Simulation.SendInput.Mouse.LeftButtonDown(); break;
            case "right": Simulation.SendInput.Mouse.RightButtonDown(); break;
            case "middle": Simulation.SendInput.Mouse.MiddleButtonDown(); break;
            default: throw new ArgumentOutOfRangeException(nameof(button));
        }
    }

    public void MouseUp(string button)
    {
        switch (button)
        {
            case "left": Simulation.SendInput.Mouse.LeftButtonUp(); break;
            case "right": Simulation.SendInput.Mouse.RightButtonUp(); break;
            case "middle": Simulation.SendInput.Mouse.MiddleButtonUp(); break;
            default: throw new ArgumentOutOfRangeException(nameof(button));
        }
    }

    public void VerticalScroll(int clicks) => Simulation.SendInput.Mouse.VerticalScroll(clicks);
}
