using System;
using System.Collections.Generic;
using System.Linq;
using BetterGenshinImpact.GameTask.Model.Area;
using OpenCvSharp;
using System.Threading;

namespace BetterGenshinImpact.Core.Recognition;

public interface IOverlayDrawPlatform
{
    void SetRectangles(string name, Region source, IReadOnlyList<Rect> rectangles);
    void RemoveRectangles(string name);
    void ClearAll();
    void SetLabels(string name, Region source, IReadOnlyList<OverlayLabel> labels) =>
        SetRectangles(name, source, labels.Select(label => label.Rectangle).ToArray());
    void RemoveLabels(string name) => RemoveRectangles(name);
}

public readonly record struct OverlayLabel(Rect Rectangle, string Text, bool Recognized);

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
