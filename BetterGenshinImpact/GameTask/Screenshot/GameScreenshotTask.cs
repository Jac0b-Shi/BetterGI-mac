using BetterGenshinImpact.Core.Config;
using Microsoft.Extensions.Logging;
using OpenCvSharp;
using System;
using System.IO;

namespace BetterGenshinImpact.GameTask.Screenshot;

public interface IGameScreenshotRuntimePlatform
{
    Mat Capture();

    string ScreenshotDirectory { get; }

    bool ScreenshotUidCoverEnabled { get; }

    double ScaleTo1080PRatio { get; }
}

public sealed class GameScreenshotTask(
    IGameScreenshotRuntimePlatform platform,
    ILogger logger,
    TimeProvider? timeProvider = null)
{
    private readonly TimeProvider _timeProvider = timeProvider ?? TimeProvider.System;

    public string TakeScreenshot()
    {
        Directory.CreateDirectory(platform.ScreenshotDirectory);
        using var captured = platform.Capture();
        using var image = NormalizeForPng(captured);
        if (platform.ScreenshotUidCoverEnabled)
            ScreenshotPrivacy.ApplyUidCover(image, platform.ScaleTo1080PRatio);

        var name = $"{_timeProvider.GetLocalNow():yyyyMMddHHmmssffff}.png";
        var path = Path.Combine(platform.ScreenshotDirectory, name);
        if (!Cv2.ImWrite(path, image))
            throw new IOException($"OpenCV failed to save screenshot '{name}'.");

        logger.LogInformation("截图已保存: {Name}", name);
        return path;
    }

    private static Mat NormalizeForPng(Mat captured)
    {
        var image = new Mat();
        switch (captured.Channels())
        {
            case 3:
                captured.CopyTo(image);
                break;
            case 4:
                Cv2.CvtColor(captured, image, ColorConversionCodes.BGRA2BGR);
                break;
            default:
                image.Dispose();
                throw new InvalidDataException(
                    $"Screenshot capture must be BGR or BGRA, got {captured.Channels()} channels.");
        }
        return image;
    }
}
