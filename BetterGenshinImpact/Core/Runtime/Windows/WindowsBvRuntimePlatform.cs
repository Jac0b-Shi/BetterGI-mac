using BetterGenshinImpact.Core.BgiVision;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Model;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsBvRuntimePlatform : IBvRuntimePlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
}
