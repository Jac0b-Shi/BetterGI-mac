using BetterGenshinImpact.Core.Input;
using BetterGenshinImpact.GameTask.AutoFight.Script;
using BetterGenshinImpact.Helpers;
using BetterGenshinImpact.Core.Simulator;
using BetterGenshinImpact.ViewModel.Pages;
using Vanara.PInvoke;
using System;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsCombatCommandPlatform : ICombatCommandPlatform
{
    public void ValidateKeyName(string keyName) => User32Helper.ToVk(keyName);

    public void KeyDown(string keyName) => Dispatch(keyName,
        vk => InputHub.Foreground.Keyboard.KeyDown(vk),
        () => InputHub.Foreground.Mouse.LeftButtonDown(),
        () => InputHub.Foreground.Mouse.RightButtonDown(),
        () => InputHub.Foreground.Mouse.MiddleButtonDown(),
        button => InputHub.Foreground.Mouse.XButtonDown(button));

    public void KeyUp(string keyName) => Dispatch(keyName,
        vk => InputHub.Foreground.Keyboard.KeyUp(vk),
        () => InputHub.Foreground.Mouse.LeftButtonUp(),
        () => InputHub.Foreground.Mouse.RightButtonUp(),
        () => InputHub.Foreground.Mouse.MiddleButtonUp(),
        button => InputHub.Foreground.Mouse.XButtonUp(button));

    public void KeyPress(string keyName) => Dispatch(keyName,
        vk => InputHub.Foreground.Keyboard.KeyPress(vk),
        () => InputHub.Foreground.Mouse.LeftButtonClick(),
        () => InputHub.Foreground.Mouse.RightButtonClick(),
        () => InputHub.Foreground.Mouse.MiddleButtonClick(),
        button => InputHub.Foreground.Mouse.XButtonClick(button));

    private static void Dispatch(string keyName, Action<User32.VK> keyboard, Action left, Action right,
        Action middle, Action<int> xButton)
    {
        var vk = KeyBindingsSettingsPageViewModel.MappingKey(User32Helper.ToVk(keyName));
        switch (keyName)
        {
            case "VK_LBUTTON": left(); break;
            case "VK_RBUTTON": right(); break;
            case "VK_MBUTTON": middle(); break;
            case "VK_XBUTTON1": xButton(0x0001); break;
            case "VK_XBUTTON2": xButton(0x0001); break;
            default: keyboard(vk); break;
        }
    }
}
