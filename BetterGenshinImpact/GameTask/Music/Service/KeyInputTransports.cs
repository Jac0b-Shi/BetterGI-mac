using BetterGenshinImpact.Core.Input;
using BetterGenshinImpact.GameTask.Music.Model;
using System;
using Vanara.PInvoke;

namespace BetterGenshinImpact.GameTask.Music.Service;

public sealed class PostMessageKeyInputTransport : KeyInputTransportBase
{
    public override MusicInputMode Mode => MusicInputMode.BackgroundPostMessage;

    protected override void SendKeyDown(char key)
    {
        InputHub.Background.Keyboard.KeyDown((User32.VK)key);
    }

    protected override void SendKeyUp(char key)
    {
        InputHub.Background.Keyboard.KeyUp((User32.VK)key);
    }

    private static User32.VK ToVirtualKey(char key) => (User32.VK)key;
}

/// <summary>
/// 前台模式：走 InputHub.Foreground，每次调用时取通道
/// </summary>
public sealed class SendInputKeyInputTransport : KeyInputTransportBase
{
    public override MusicInputMode Mode => MusicInputMode.ForegroundSendInput;

    protected override void SendKeyDown(char key)
    {
        InputHub.Foreground.Keyboard.KeyDown((User32.VK)key);
    }

    protected override void SendKeyUp(char key)
    {
        InputHub.Foreground.Keyboard.KeyUp((User32.VK)key);
    }
}
