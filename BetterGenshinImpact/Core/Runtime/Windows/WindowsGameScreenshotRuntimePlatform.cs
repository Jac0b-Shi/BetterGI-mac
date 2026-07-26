using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Screenshot;
using Fischless.GameCapture;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsGameScreenshotRuntimePlatform(IGameCapture gameCapture)
    : IGameScreenshotRuntimePlatform
{
    public string ScreenshotDirectory => Global.Absolute(@"log\screenshot");

    public bool ScreenshotUidCoverEnabled =>
        TaskContext.Instance().Config.CommonConfig.ScreenshotUidCoverEnabled;

    public double ScaleTo1080PRatio =>
        TaskContext.Instance().SystemInfo.ScaleTo1080PRatio;

    public Mat Capture() => TaskControl.CaptureGameImage(gameCapture);
}
