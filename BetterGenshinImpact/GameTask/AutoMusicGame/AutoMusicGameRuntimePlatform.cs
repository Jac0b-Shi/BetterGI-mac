using System;
using OpenCvSharp;

namespace BetterGenshinImpact.GameTask.AutoMusicGame;

public interface IAutoMusicGameRuntimePlatform
{
    double AssetScale { get; }
    void ValidateResolution();
    void ReadBlueChannels(ReadOnlySpan<Point> points, Span<byte> blueChannels);
}
