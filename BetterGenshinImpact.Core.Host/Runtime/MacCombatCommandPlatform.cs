using BetterGenshinImpact.GameTask.AutoFight.Script;
using BetterGenshinImpact.Core.Script.Dependence;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacCombatCommandPlatform(IGlobalMethodRuntime input) : ICombatCommandPlatform
{
    private static readonly HashSet<string> NamedKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        "ESC", "ESCAPE", "RETURN", "ENTER", "SPACE", "TAB", "BACK", "BACKSPACE", "DELETE", "DEL",
        "LEFT", "RIGHT", "UP", "DOWN", "HOME", "END", "PRIOR", "PAGEUP", "NEXT", "PAGEDOWN",
        "SHIFT", "LSHIFT", "CONTROL", "LCONTROL", "CTRL", "LCTRL", "MENU", "LMENU", "ALT",
        "LBUTTON", "RBUTTON", "MBUTTON", "XBUTTON1", "XBUTTON2",
        "OEM_COMMA", "OEM_MINUS", "OEM_PLUS", "OEM_PERIOD", "OEM_2", "OEM_5", "OEM_1", "OEM_4", "OEM_6", "OEM_3"
    };

    public void ValidateKeyName(string keyName)
    {
        if (string.IsNullOrWhiteSpace(keyName))
            throw new ArgumentException("Key name must not be empty.", nameof(keyName));

        var normalized = keyName.Trim().ToUpperInvariant();
        if (normalized.StartsWith("VK_", StringComparison.Ordinal))
            normalized = normalized[3..];

        var isLetter = normalized.Length == 1 && normalized[0] is >= 'A' and <= 'Z';
        var isDigit = normalized.Length == 1 && normalized[0] is >= '0' and <= '9';
        var isFunctionKey = normalized.Length >= 2 && normalized[0] == 'F'
            && int.TryParse(normalized[1..], out var functionNumber) && functionNumber is >= 1 and <= 12;
        if (!isLetter && !isDigit && !isFunctionKey && !NamedKeys.Contains(normalized))
            throw new ArgumentException($"Unsupported macOS semantic key name: '{keyName}'.", nameof(keyName));
    }

    public void KeyDown(string keyName) { ValidateKeyName(keyName); input.KeyDown(keyName); }
    public void KeyUp(string keyName) { ValidateKeyName(keyName); input.KeyUp(keyName); }
    public void KeyPress(string keyName) { ValidateKeyName(keyName); input.KeyPress(keyName); }
}
