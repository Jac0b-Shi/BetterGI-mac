namespace BetterGenshinImpact.Platform.Abstractions;

/// <summary>
/// Platform-independent semantic key identifiers.
/// Windows backend maps these to Win32 VK codes; macOS backend maps to CGKeyCode.
/// Numeric values carry no platform meaning.
/// </summary>
public enum BgiKey
{
    None,
    F,
    Escape,
    Space,
    Enter,
    Tab,
    W,
    A,
    S,
    D,
    LeftShift,
    LeftControl,
    LeftAlt,
}

public interface IInputBackend
{
    void KeyDown(BgiKey key);
    void KeyUp(BgiKey key);
    void KeyPress(BgiKey key);

    /// <summary>Move mouse to absolute screen-pixel coordinates.</summary>
    void MoveMouseTo(int screenX, int screenY);

    /// <summary>Move mouse by relative delta in screen pixels.</summary>
    void MoveMouseBy(int deltaX, int deltaY);

    void LeftButtonDown();
    void LeftButtonUp();
    void LeftClick(int screenX, int screenY);
    void Scroll(int delta);
}
