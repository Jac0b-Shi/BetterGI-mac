using BetterGenshinImpact.Platform.Abstractions;
using Fischless.WindowsInput;
using Vanara.PInvoke;
using System;

namespace BetterGenshinImpact.Core.Simulator.Extensions;

/// <summary>
/// Windows 平台键码桥接。共享业务层只保存语义键，Windows 输入后端在这里转换为 VK。
/// 未知键必须抛错，禁止静默映射到任意按键。
/// </summary>
public static class WindowsInputSimulatorExtensions
{
    public static IKeyboardSimulator KeyPress(this IKeyboardSimulator keyboard, BgiKey key) =>
        keyboard.KeyPress(key.ToWindowsVirtualKey());

    public static IKeyboardSimulator KeyDown(this IKeyboardSimulator keyboard, BgiKey key) =>
        keyboard.KeyDown(key.ToWindowsVirtualKey());

    public static IKeyboardSimulator KeyUp(this IKeyboardSimulator keyboard, BgiKey key) =>
        keyboard.KeyUp(key.ToWindowsVirtualKey());

    public static User32.VK ToWindowsVirtualKey(this BgiKey key) => key switch
    {
        BgiKey.F => User32.VK.VK_F,
        BgiKey.Escape => User32.VK.VK_ESCAPE,
        BgiKey.Space => User32.VK.VK_SPACE,
        BgiKey.Enter => User32.VK.VK_RETURN,
        BgiKey.Tab => User32.VK.VK_TAB,
        BgiKey.W => User32.VK.VK_W,
        BgiKey.A => User32.VK.VK_A,
        BgiKey.S => User32.VK.VK_S,
        BgiKey.D => User32.VK.VK_D,
        BgiKey.LeftShift => User32.VK.VK_LSHIFT,
        BgiKey.LeftControl => User32.VK.VK_LCONTROL,
        BgiKey.LeftAlt => User32.VK.VK_LMENU,
        _ => throw new ArgumentOutOfRangeException(nameof(key), key, "Unsupported Windows virtual key")
    };
}
