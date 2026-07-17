using System;
using System.Collections.Generic;
using BetterGenshinImpact.GameTask.Model.Area;
using OpenCvSharp;
using System.Threading;

namespace BetterGenshinImpact.Core.Recognition;

public interface IOverlayDrawPlatform
{
    void SetRectangles(string name, ImageRegion source, IReadOnlyList<Rect> rectangles);
    void RemoveRectangles(string name);
    void ClearAll();
}

public static class OverlayDrawPlatform
{
    private static IOverlayDrawPlatform? _current;
    public static IOverlayDrawPlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("Overlay draw platform has not been composed.");
    public static void Configure(IOverlayDrawPlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("Overlay draw platform has already been configured.");
    }
}
