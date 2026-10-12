using System.Collections.Generic;
using System.Linq;
using BetterGenshinImpact.Core.Mask;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask.Model.Area;
using OpenCvSharp;
using Point = System.Windows.Point;

namespace BetterGenshinImpact.Core.Runtime.Windows;
public sealed class WindowsOverlayDrawPlatform : IOverlayDrawPlatform
{
    public void SetRectangles(string name, Region source, IReadOnlyList<Rect> rectangles) =>
        source.DrawingBoard.Set(name, rectangles.Select(rect => source.ToMaskWindowDrawingRect(rect)).ToArray());
    public void RemoveRectangles(string name) => MaskWindowDrawingPlatform.Current.Clear(name);
    public void ClearAll() => MaskWindowDrawingPlatform.Current.ClearAll();
    public void SetLabels(string name, Region source, IReadOnlyList<OverlayLabel> labels)
    {
        var shapes = new List<MaskWindowDrawingShape>();
        foreach (var label in labels)
        {
            var rect = source.ToMaskWindowDrawingRect(label.Rectangle) with {
                Stroke = MaskWindowDrawingStroke.FromColor(label.Recognized ? System.Drawing.Color.Lime : System.Drawing.Color.Red)
            };
            shapes.Add(rect);
            shapes.Add(new MaskWindowDrawingText(label.Text, new Point(rect.Bounds.X + rect.Bounds.Width / 3, rect.Bounds.Y)));
        }
        source.DrawingBoard.Set(name, shapes);
    }
    public void RemoveLabels(string name) => MaskWindowDrawingPlatform.Current.Clear(name);
}
