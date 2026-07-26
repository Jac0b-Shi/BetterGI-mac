using OpenCvSharp;
using System;

namespace BetterGenshinImpact.Core.Config;

public static class ScreenshotPrivacy
{
    public static readonly Rect UidCoverRightBottomRect =
        new(1920 - 1685, 1080 - 1053, 178, 22);

    public static void ApplyUidCover(Mat image, double scaleTo1080P)
    {
        ArgumentNullException.ThrowIfNull(image);
        var source = UidCoverRightBottomRect;
        var rect = new Rect(
            (int)(image.Width - source.X * scaleTo1080P),
            (int)(image.Height - source.Y * scaleTo1080P),
            (int)(source.Width * scaleTo1080P),
            (int)(source.Height * scaleTo1080P));
        image.Rectangle(rect, Scalar.White, -1);
    }
}
