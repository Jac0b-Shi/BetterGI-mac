using BetterGenshinImpact.GameTask.AutoMusicGame;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.Helpers;
using Vanara.PInvoke;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoMusicGameRuntimePlatform : IAutoMusicGameRuntimePlatform
{
    public double AssetScale => TaskContext.Instance().SystemInfo.AssetScale;

    public void ValidateResolution() => AssertUtils.CheckGameResolution("自动音游");

    public byte ReadBlueChannel(int x, int y)
    {
        var gameHandle = TaskContext.Instance().GameHandle;
        var deviceContext = User32.GetDC(gameHandle);
        try
        {
            return Gdi32.GetPixel(deviceContext, x, y).B;
        }
        finally
        {
            User32.ReleaseDC(gameHandle, deviceContext);
        }
    }
}
