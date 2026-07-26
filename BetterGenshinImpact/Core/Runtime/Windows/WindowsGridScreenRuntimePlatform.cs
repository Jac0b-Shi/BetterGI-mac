using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Model.GameUI;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsGridScreenRuntimePlatform : IGridScreenRuntimePlatform
{
    public double AssetScale => TaskContext.Instance().SystemInfo.AssetScale;
    public int CaptureAreaX => TaskContext.Instance().SystemInfo.CaptureAreaRect.X;
    public int CaptureAreaY => TaskContext.Instance().SystemInfo.CaptureAreaRect.Y;
}
