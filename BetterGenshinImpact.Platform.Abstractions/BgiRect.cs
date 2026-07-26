namespace BetterGenshinImpact.Platform.Abstractions;

/// <summary>
/// Platform-independent rectangle. Replaces both Vanara.RECT (Windows) and OpenCvSharp.Rect
/// in system-level interfaces, so the system info layer does not depend on a visual library.
/// Provides implicit conversion to/from OpenCvSharp.Rect for transitional compatibility.
/// </summary>
public readonly record struct BgiRect(int X, int Y, int Width, int Height)
{
    public int Right => X + Width;
    public int Bottom => Y + Height;
    public bool IsEmpty => Width == 0 || Height == 0;

    public static implicit operator OpenCvSharp.Rect(BgiRect r) => new(r.X, r.Y, r.Width, r.Height);
    public static implicit operator BgiRect(OpenCvSharp.Rect r) => new(r.X, r.Y, r.Width, r.Height);
}
