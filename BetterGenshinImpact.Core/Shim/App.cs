namespace BetterGenshinImpact;

/// <summary>
/// Core compatibility shim. Only ServiceProvider remains for WPF backward-compatible code paths
/// inside `#if !BGI_PLATFORM_MAC` branches. The logging gateway (GetLogger<T>) has been removed —
/// all consumers migrated to explicit constructor injection.
/// </summary>
public static class App
{
    public static IServiceProvider ServiceProvider =>
        throw new NotSupportedException("App.ServiceProvider not available in Core.");
}
