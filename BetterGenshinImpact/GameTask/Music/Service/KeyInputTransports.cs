using BetterGenshinImpact.Core.Simulator;
using BetterGenshinImpact.GameTask.Music.Model;
using Fischless.WindowsInput;
using System;
using Vanara.PInvoke;

namespace BetterGenshinImpact.GameTask.Music.Service;

public sealed class PostMessageKeyInputTransport : KeyInputTransportBase
{
    public override MusicInputMode Mode => MusicInputMode.BackgroundPostMessage;

    protected override void SendKeyDown(char key)
    {
        TaskContext.Instance().PostMessageSimulator.KeyDownBackground(ToVirtualKey(key));
    }

    protected override void SendKeyUp(char key)
    {
        TaskContext.Instance().PostMessageSimulator.KeyUpBackground(ToVirtualKey(key));
    }

    private static User32.VK ToVirtualKey(char key) => (User32.VK)key;
}

public sealed class SendInputKeyInputTransport : KeyInputTransportBase
{
    public override MusicInputMode Mode => MusicInputMode.ForegroundSendInput;

    protected override void SendKeyDown(char key)
    {
        var virtualKey = (User32.VK)key;
        if (InputBuilder.IsExtendedKey(virtualKey))
        {
            Simulation.SendInput.Keyboard.KeyDown(false, virtualKey);
        }
        else
        {
            Simulation.SendInput.Keyboard.KeyDown(virtualKey);
        }
    }

    protected override void SendKeyUp(char key)
    {
        var virtualKey = (User32.VK)key;
        if (InputBuilder.IsExtendedKey(virtualKey))
        {
            Simulation.SendInput.Keyboard.KeyUp(false, virtualKey);
        }
        else
        {
            Simulation.SendInput.Keyboard.KeyUp(virtualKey);
        }
    }
}
