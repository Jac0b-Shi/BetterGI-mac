using BetterGenshinImpact.GameTask.AutoMusicGame;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.Helpers;
using OpenCvSharp;
using Vanara.PInvoke;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoMusicGameRuntimePlatform : IAutoMusicGameRuntimePlatform
{
    public double AssetScale => TaskContext.Instance().SystemInfo.AssetScale;

    public void ValidateResolution() => AssertUtils.CheckGameResolution("自动音游");

    public void ReadBlueChannels(ReadOnlySpan<Point> points, Span<byte> blueChannels)
    {
        if (blueChannels.Length < points.Length)
            throw new ArgumentException(
                "The blue-channel destination is smaller than the requested point set.",
                nameof(blueChannels));

        var gameHandle = TaskContext.Instance().GameHandle;
        var deviceContext = User32.GetDC(gameHandle);
        try
        {
            for (var index = 0; index < points.Length; index++)
                blueChannels[index] =
                    Gdi32.GetPixel(deviceContext, points[index].X, points[index].Y).B;
        }
        finally
        {
            User32.ReleaseDC(gameHandle, deviceContext);
        }
    }
}
