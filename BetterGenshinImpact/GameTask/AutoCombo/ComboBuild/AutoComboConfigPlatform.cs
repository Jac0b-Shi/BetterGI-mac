using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.AutoCombo.ComboBuild;

/// <summary>配置由宿主读取；建树与战斗业务不依赖 Windows 的 TaskContext。</summary>
public static class AutoComboConfigPlatform
{
    private static Func<AutoComboBuildConfig>? _provider;

    public static void Configure(Func<AutoComboBuildConfig> provider)
    {
        ArgumentNullException.ThrowIfNull(provider);
        if (Interlocked.CompareExchange(ref _provider, provider, null) is not null)
            throw new InvalidOperationException("AutoCombo config platform has already been composed.");
    }

    public static AutoComboBuildConfig GetConfig()
    {
#if BGI_PLATFORM_MAC
        return (Volatile.Read(ref _provider) ?? throw new InvalidOperationException(
            "AutoCombo config platform has not been composed."))();
#else
        return TaskContext.Instance().Config.AutoComboBuildConfig;
#endif
    }
}
