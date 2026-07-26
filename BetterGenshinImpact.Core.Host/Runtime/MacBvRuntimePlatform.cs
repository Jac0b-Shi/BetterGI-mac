using BetterGenshinImpact.Core.BgiVision;
using BetterGenshinImpact.GameTask.Model;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacBvRuntimePlatform(Func<ISystemInfo> systemInfoProvider) : IBvRuntimePlatform
{
    private readonly Func<ISystemInfo> _systemInfoProvider = systemInfoProvider
        ?? throw new ArgumentNullException(nameof(systemInfoProvider));

    public ISystemInfo SystemInfo => _systemInfoProvider();
}
