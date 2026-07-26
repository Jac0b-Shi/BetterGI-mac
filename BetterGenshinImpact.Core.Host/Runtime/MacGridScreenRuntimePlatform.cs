using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Model.GameUI;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacGridScreenRuntimePlatform(Func<ISystemInfo> systemInfo) : IGridScreenRuntimePlatform
{
    private readonly Func<ISystemInfo> _systemInfo = systemInfo ?? throw new ArgumentNullException(nameof(systemInfo));
    public double AssetScale => _systemInfo().AssetScale;
    public int CaptureAreaX => _systemInfo().CaptureAreaRect.X;
    public int CaptureAreaY => _systemInfo().CaptureAreaRect.Y;
}
