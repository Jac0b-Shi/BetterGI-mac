using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoTrackPath;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.QuickTeleport;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsTpTaskRuntimePlatform : ITpTaskRuntimePlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public TpConfig TpConfig => TaskContext.Instance().Config.TpConfig;
    public QuickTeleportConfig QuickTeleportConfig => TaskContext.Instance().Config.QuickTeleportConfig;
    public string MapMatchingMethod => TaskContext.Instance().Config.PathingConditionConfig.MapMatchingMethod;
    public double DpiScale => TaskContext.Instance().DpiScale;
}
