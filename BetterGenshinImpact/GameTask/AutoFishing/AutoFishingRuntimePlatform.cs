using BetterGenshinImpact.GameTask.Model.Area;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.AutoFishing;

public interface IAutoFishingRuntimePlatform
{
    void SaveBehaviourScreenshot(ImageRegion imageRegion, string fileName);
}

public static class AutoFishingRuntimePlatform
{
    private static IAutoFishingRuntimePlatform? _current;

    public static IAutoFishingRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("AutoFishing runtime platform has not been composed.");

    public static void Configure(IAutoFishingRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("AutoFishing runtime platform has already been configured.");
    }
}
