using OpenCvSharp;

namespace BetterGenshinImpact.Platform.Abstractions;

public record CaptureFrame(Mat Mat, int FrameIndex);

public interface IGameCaptureBackend
{
    CaptureFrame? Capture();
}
