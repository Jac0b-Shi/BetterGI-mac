using BetterGenshinImpact.Platform.Abstractions;
using Fischless.WindowsInput;
using Vanara.PInvoke;
using System.Threading;

namespace BetterGenshinImpact.Core.Runtime.Windows;

/// <summary>
/// Windows IInputBackend implementation using Fischless.WindowsInput (Win32 SendInput).
/// All mouse coordinates are screen-pixel coordinates; this backend converts them
/// to normalized 0–65535 absolute coordinates using the virtual desktop.
/// </summary>
public sealed class Win32InputBackend : IInputBackend
{
    private readonly InputSimulator _sim = new();

    // --- Keyboard ---

    public void KeyDown(BgiKey key)
    {
        var vk = (User32.VK)Win32InputHelpers.MapBgiKeyToVk(key);
        _sim.Keyboard.KeyDown(vk);
    }

    public void KeyUp(BgiKey key)
    {
        var vk = (User32.VK)Win32InputHelpers.MapBgiKeyToVk(key);
        _sim.Keyboard.KeyUp(vk);
    }

    public void KeyPress(BgiKey key)
    {
        var vk = (User32.VK)Win32InputHelpers.MapBgiKeyToVk(key);
        _sim.Keyboard.KeyPress(vk);
    }

    // --- Mouse ---

    public void MoveMouseTo(int screenX, int screenY)
    {
        var (nx, ny) = Win32InputHelpers.ScreenToNormalized(
            screenX, screenY,
            User32.GetSystemMetrics(User32.SystemMetric.SM_XVIRTUALSCREEN),
            User32.GetSystemMetrics(User32.SystemMetric.SM_YVIRTUALSCREEN),
            User32.GetSystemMetrics(User32.SystemMetric.SM_CXVIRTUALSCREEN),
            User32.GetSystemMetrics(User32.SystemMetric.SM_CYVIRTUALSCREEN));

        // Fischless MoveMouseToPositionOnVirtualDesktop uses
        // MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK | MOUSEEVENTF_MOVE
        _sim.Mouse.MoveMouseToPositionOnVirtualDesktop(nx, ny);
    }

    public void MoveMouseBy(int deltaX, int deltaY)
    {
        _sim.Mouse.MoveMouseBy(deltaX, deltaY);
    }

    public void LeftButtonDown()
    {
        _sim.Mouse.LeftButtonDown();
    }

    public void LeftButtonUp()
    {
        _sim.Mouse.LeftButtonUp();
    }

    public void LeftClick(int screenX, int screenY)
    {
        MoveMouseTo(screenX, screenY);
        LeftButtonDown();
        Thread.Sleep(50);
        LeftButtonUp();
        Thread.Sleep(50);
    }

    public void Scroll(int delta)
    {
        // Scroll(delta) means delta logical scroll clicks, equivalent to
        // VerticalScroll(delta) on Windows. Positive → wheel up.
        _sim.Mouse.VerticalScroll(delta);
    }
}
