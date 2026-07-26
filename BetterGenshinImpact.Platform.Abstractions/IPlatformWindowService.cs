using OpenCvSharp;

namespace BetterGenshinImpact.Platform.Abstractions;

public record GameWindowMetrics(
    int Width, int Height,
    int CaptureX, int CaptureY,
    int CaptureWidth, int CaptureHeight,
    double AssetScale, double ScaleTo1080PRatio,
    int ProcessId);

public interface IPlatformWindowService
{
    bool IsGameActive { get; }
    bool IsGameMinimized { get; }
    GameWindowMetrics Metrics { get; }
}
