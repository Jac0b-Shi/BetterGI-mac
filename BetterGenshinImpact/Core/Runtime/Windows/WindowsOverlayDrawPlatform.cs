using System.Collections.Generic;
using System.Linq;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.View.Drawable;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsOverlayDrawPlatform : IOverlayDrawPlatform
{
    public void SetRectangles(string name, ImageRegion source, IReadOnlyList<Rect> rectangles) =>
        VisionContext.Instance().DrawContent.PutOrRemoveRectList(
            name, rectangles.Select(rect => source.ToRectDrawable(rect, name)).ToList());
    public void RemoveRectangles(string name) => VisionContext.Instance().DrawContent.RemoveRect(name);
    public void ClearAll() => VisionContext.Instance().DrawContent.ClearAll();
}
