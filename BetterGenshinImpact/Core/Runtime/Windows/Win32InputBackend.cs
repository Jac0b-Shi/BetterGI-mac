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
public sealed class WindowsSemanticInputBackend : IInputBackend
{


    // --- Keyboard ---

    public void KeyDown(BgiKey key)
    {
        var vk = (User32.VK)Win32InputHelpers.MapBgiKeyToVk(key);
        BetterGenshinImpact.Core.Input.InputHub.Foreground.Keyboard.KeyDown(vk);
    }

    public void KeyUp(BgiKey key)
    {
        var vk = (User32.VK)Win32InputHelpers.MapBgiKeyToVk(key);
        BetterGenshinImpact.Core.Input.InputHub.Foreground.Keyboard.KeyUp(vk);
    }

    public void KeyPress(BgiKey key)
    {
        var vk = (User32.VK)Win32InputHelpers.MapBgiKeyToVk(key);
        BetterGenshinImpact.Core.Input.InputHub.Foreground.Keyboard.KeyPress(vk);
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
        BetterGenshinImpact.Core.Input.InputHub.Foreground.Mouse.MoveMouseTo(nx, ny);
    }

    public void MoveMouseBy(int deltaX, int deltaY)
    {
        BetterGenshinImpact.Core.Input.InputHub.Foreground.Mouse.MoveMouseBy(deltaX, deltaY);
    }

    public void LeftButtonDown()
    {
        BetterGenshinImpact.Core.Input.InputHub.Foreground.Mouse.LeftButtonDown();
    }

    public void LeftButtonUp()
    {
        BetterGenshinImpact.Core.Input.InputHub.Foreground.Mouse.LeftButtonUp();
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
        BetterGenshinImpact.Core.Input.InputHub.Foreground.Mouse.VerticalScroll(delta);
    }
}
