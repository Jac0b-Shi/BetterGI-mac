using BetterGenshinImpact.GameTask.AutoMusicGame;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model.Area;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoMusicGameRuntimePlatform(Func<double> assetScale) : IAutoMusicGameRuntimePlatform, IDisposable
{
    private readonly object _frameLock = new();
    private ImageRegion? _cachedFrame;
    private long _cachedAt;

    public double AssetScale => assetScale();

    public void ValidateResolution()
    {
        using var frame = TaskControl.CaptureToRectArea();
        if (frame.Width * 9 != frame.Height * 16)
            throw new InvalidOperationException(
                $"自动音游要求 16:9 游戏画面，实际截图为 {frame.Width}x{frame.Height}。");
    }

    public void ReadBlueChannels(ReadOnlySpan<Point> points, Span<byte> blueChannels)
    {
        if (blueChannels.Length < points.Length)
            throw new ArgumentException(
                "The blue-channel destination is smaller than the requested point set.",
                nameof(blueChannels));

        lock (_frameLock)
        {
            var now = Environment.TickCount64;
            if (_cachedFrame is null || now - _cachedAt >= 16)
            {
                _cachedFrame?.Dispose();
                _cachedFrame = TaskControl.CaptureToRectArea();
                _cachedAt = now;
            }
            for (var index = 0; index < points.Length; index++)
            {
                var point = points[index];
                if (point.X < 0 || point.Y < 0 ||
                    point.X >= _cachedFrame.Width || point.Y >= _cachedFrame.Height)
                {
                    throw new ArgumentOutOfRangeException(
                        nameof(points),
                        $"Music sample point ({point.X},{point.Y}) is outside the capture frame.");
                }
                blueChannels[index] = _cachedFrame.SrcMat.At<Vec4b>(point.Y, point.X).Item0;
            }
        }
    }

    public void Dispose()
    {
        lock (_frameLock)
        {
            _cachedFrame?.Dispose();
            _cachedFrame = null;
        }
    }
}
