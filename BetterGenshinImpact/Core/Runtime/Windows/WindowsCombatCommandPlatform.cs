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
        vk => Simulation.SendInput.Keyboard.KeyDown(vk),
        () => Simulation.SendInput.Mouse.LeftButtonDown(),
        () => Simulation.SendInput.Mouse.RightButtonDown(),
        () => Simulation.SendInput.Mouse.MiddleButtonDown(),
        button => Simulation.SendInput.Mouse.XButtonDown(button));

    public void KeyUp(string keyName) => Dispatch(keyName,
        vk => Simulation.SendInput.Keyboard.KeyUp(vk),
        () => Simulation.SendInput.Mouse.LeftButtonUp(),
        () => Simulation.SendInput.Mouse.RightButtonUp(),
        () => Simulation.SendInput.Mouse.MiddleButtonUp(),
        button => Simulation.SendInput.Mouse.XButtonUp(button));

    public void KeyPress(string keyName) => Dispatch(keyName,
        vk => Simulation.SendInput.Keyboard.KeyPress(vk),
        () => Simulation.SendInput.Mouse.LeftButtonClick(),
        () => Simulation.SendInput.Mouse.RightButtonClick(),
        () => Simulation.SendInput.Mouse.MiddleButtonClick(),
        button => Simulation.SendInput.Mouse.XButtonClick(button));

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
