using Microsoft.Extensions.Logging;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.Common.Job;

public interface ICraftMaterialRuntimePlatform
{
    ILogger<CraftMaterialTask> Logger { get; }
}

public static class CraftMaterialRuntimePlatform
{
    private static ICraftMaterialRuntimePlatform? _current;

    public static ICraftMaterialRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("CraftMaterial runtime platform has not been composed.");

    public static void Configure(ICraftMaterialRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("CraftMaterial runtime platform has already been configured.");
    }
}
