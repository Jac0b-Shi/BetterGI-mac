using OpenCvSharp;
using System;
using System.Drawing;
using System.Collections.Generic;

namespace BetterGenshinImpact.Core.Recognition.OpenCv;

/// <summary>WPF-independent OpenCV helpers shared by Windows and the extracted Core.</summary>
public static class CoreOpenCvExtensions
{
    public static Scalar ToScalar(this Color color) => new(color.R, color.G, color.B);

    public static Rect ClampTo(this Rect rect, int maxWidth, int maxHeight)
    {
        var x1 = Math.Clamp(rect.X, 0, maxWidth);
        var y1 = Math.Clamp(rect.Y, 0, maxHeight);
        var x2 = Math.Clamp(rect.X + rect.Width, 0, maxWidth);
        var y2 = Math.Clamp(rect.Y + rect.Height, 0, maxHeight);
        return new Rect(x1, y1, x2 - x1, y2 - y1);
    }

    public static Rect ClampTo(this Rect rect, Mat mat) => rect.ClampTo(mat.Cols, mat.Rows);

#if BGI_PLATFORM_MAC
    public static OpenCvSharp.Point GetCenterPoint(this Rect rectangle)
    {
        if (rectangle == default) throw new ArgumentException("rectangle is empty");
        return new OpenCvSharp.Point(rectangle.X + rectangle.Width / 2, rectangle.Y + rectangle.Height / 2);
    }

    public static Point2d ToPoint2d(this Point2f point) => new(point.X, point.Y);

    public static List<Point2d> ToPoint2d(this List<Point2f> points) => points.ConvertAll(ToPoint2d);
#endif
}
