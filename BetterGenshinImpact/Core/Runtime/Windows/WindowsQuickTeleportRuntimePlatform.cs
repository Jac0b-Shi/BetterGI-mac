using System;
using System.Windows.Forms;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.QuickTeleport;
using BetterGenshinImpact.Model;
using Fischless.GameCapture;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsQuickTeleportRuntimePlatform : IQuickTeleportRuntimePlatform
{
    public QuickTeleportConfig Config => TaskContext.Instance().Config.QuickTeleportConfig;
    public string TickHotkey => TaskContext.Instance().Config.HotKeyConfig.QuickTeleportTickHotkey;
    public bool IsHdrCapture =>
        TaskContext.Instance().Config.CaptureMode == nameof(CaptureModes.WindowsGraphicsCaptureHdr);

    public bool IsTickHotkeyPressed()
    {
        if (HotKey.IsMouseButton(TickHotkey))
        {
            return MouseHook.AllMouseHooks.TryGetValue(
                       (MouseButtons)Enum.Parse(typeof(MouseButtons), TickHotkey), out var mouseHook) &&
                   mouseHook.IsPressed;
        }

        return KeyboardHook.AllKeyboardHooks.TryGetValue(
                   (Keys)Enum.Parse(typeof(Keys), TickHotkey), out var keyboardHook) &&
               keyboardHook.IsPressed;
    }
}
