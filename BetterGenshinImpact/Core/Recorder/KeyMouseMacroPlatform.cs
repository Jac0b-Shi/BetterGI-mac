using Microsoft.Extensions.Logging;
using System;
using System.Drawing;
using System.Threading;

namespace BetterGenshinImpact.Core.Recorder;

public interface IKeyMouseMacroPlatform
{
    ILogger Logger { get; }
    bool IsInitialized { get; }
    Rectangle CaptureArea { get; }
    Size WorkingArea { get; }
    double DpiScale { get; }
    void ActivateGameWindow();
    double GetCameraOrientation();
    void KeyDown(int windowsVirtualKey);
    void KeyUp(int windowsVirtualKey);
    void MoveMouseTo(double normalizedX, double normalizedY);
    void MoveMouseBy(int x, int y);
    void MouseDown(string button);
    void MouseUp(string button);
    void VerticalScroll(int clicks);
}

public static class KeyMouseMacroPlatform
{
    private static IKeyMouseMacroPlatform? _current;

    public static IKeyMouseMacroPlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("Key/mouse macro platform has not been composed.");

    public static void Configure(IKeyMouseMacroPlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("Key/mouse macro platform has already been configured.");
    }
}
