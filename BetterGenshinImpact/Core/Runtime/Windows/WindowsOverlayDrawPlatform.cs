using System.Collections.Generic;
using System.Linq;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.View.Drawable;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsOverlayDrawPlatform : IOverlayDrawPlatform
{
    public void SetRectangles(string name, Region source, IReadOnlyList<Rect> rectangles) =>
        VisionContext.Instance().DrawContent.PutOrRemoveRectList(
            name, rectangles.Select(rect => source.ToRectDrawable(rect, name)).ToList());
    public void RemoveRectangles(string name) => VisionContext.Instance().DrawContent.RemoveRect(name);
    public void ClearAll() => VisionContext.Instance().DrawContent.ClearAll();
    public void SetLabels(string name, Region source, IReadOnlyList<OverlayLabel> labels)
    {
        VisionContext.Instance().DrawContent.PutOrRemoveRectList(name,
            labels.Select(label => source.ToRectDrawable(
                label.Rectangle, name,
                label.Recognized ? System.Drawing.Pens.Lime : System.Drawing.Pens.Red)).ToList());
        VisionContext.Instance().DrawContent.PutOrRemoveTextList(name,
            labels.Select(label =>
            {
                var rect = source.ConvertPositionToGameCaptureRegion(
                    label.Rectangle.X, label.Rectangle.Y,
                    label.Rectangle.Width, label.Rectangle.Height);
                return new TextDrawable(label.Text,
                    new System.Windows.Point(rect.X + rect.Width / 3d, rect.Y));
            }).ToList());
    }
    public void RemoveLabels(string name)
    {
        VisionContext.Instance().DrawContent.RemoveRect(name);
        VisionContext.Instance().DrawContent.PutOrRemoveTextList(name, null);
    }
}
