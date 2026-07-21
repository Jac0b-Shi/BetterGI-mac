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

    public byte ReadBlueChannel(int x, int y)
    {
        lock (_frameLock)
        {
            var now = Environment.TickCount64;
            if (_cachedFrame is null || now - _cachedAt >= 16)
            {
                _cachedFrame?.Dispose();
                _cachedFrame = TaskControl.CaptureToRectArea();
                _cachedAt = now;
            }
            if (x < 0 || y < 0 || x >= _cachedFrame.Width || y >= _cachedFrame.Height)
                throw new ArgumentOutOfRangeException(nameof(x), $"Music sample point ({x},{y}) is outside the capture frame.");
            return _cachedFrame.SrcMat.At<Vec4b>(y, x).Item0;
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
