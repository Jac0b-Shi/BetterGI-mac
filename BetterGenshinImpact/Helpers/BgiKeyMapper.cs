using BetterGenshinImpact.Platform.Abstractions;
using System;

namespace BetterGenshinImpact.Helpers;

/// <summary>
/// Cross-platform key mapper. Replaces User32Helper.ToVk() (Vanara/Win32).
/// Unknown key names throw ArgumentException — never silently default to F.
/// </summary>
public static class BgiKeyMapper
{
    public static BgiKey ToKey(string key)
    {
        key = key.Trim().ToUpperInvariant();

        if (key.StartsWith("VK_"))
            key = key[3..];

        return key switch
        {
            "F" => BgiKey.F,
            "ESC" or "ESCAPE" => BgiKey.Escape,
            "SPACE" => BgiKey.Space,
            "ENTER" or "RETURN" => BgiKey.Enter,
            "TAB" => BgiKey.Tab,
            "W" => BgiKey.W,
            "A" => BgiKey.A,
            "S" => BgiKey.S,
            "D" => BgiKey.D,
            "LSHIFT" or "LEFTSHIFT" => BgiKey.LeftShift,
            "LCTRL" or "LEFTCONTROL" => BgiKey.LeftControl,
            "LALT" or "LEFTALT" => BgiKey.LeftAlt,
            _ => throw new ArgumentException(
                $"Unknown key name: '{key}'. Add it to BgiKeyMapper or use a supported key.")
        };
    }
}
