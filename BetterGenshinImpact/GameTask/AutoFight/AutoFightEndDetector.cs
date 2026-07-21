using OpenCvSharp;

namespace BetterGenshinImpact.GameTask.AutoFight;

internal static class AutoFightEndDetector
{
    public static bool IsFightFinished(Mat frame)
    {
        var progressBar = frame.At<Vec3b>(50, 790);
        var whiteTile = frame.At<Vec3b>(50, 768);

        return IsWhite(whiteTile.Item2, whiteTile.Item1, whiteTile.Item0) &&
               IsYellow(progressBar.Item2, progressBar.Item1, progressBar.Item0);
    }

    private static bool IsYellow(int red, int green, int blue) =>
        red is >= 200 and <= 255 &&
        green is >= 200 and <= 255 &&
        blue is >= 0 and <= 100;

    private static bool IsWhite(int red, int green, int blue) =>
        red is >= 240 and <= 255 &&
        green is >= 240 and <= 255 &&
        blue is >= 240 and <= 255;
}
