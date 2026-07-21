using System;

namespace BetterGenshinImpact.GameTask.AutoMusicGame;

public interface IAutoMusicGameRuntimePlatform
{
    double AssetScale { get; }
    void ValidateResolution();
    byte ReadBlueChannel(int x, int y);
}
