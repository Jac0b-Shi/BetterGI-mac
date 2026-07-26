using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition.OCR;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.AutoPathing;

public interface IPathExecutorPlatform
{
    (int Width, int Height) GetGameScreenSize();
    void PublishCurrentPathing(PathingTask task);
    string AutoFetchDispatchAdventurersGuildCountry { get; }
    PathingConditionConfig PathingConditionConfig { get; }
    IOcrService OcrService { get; }
}

public static class PathExecutorPlatform
{
    private static IPathExecutorPlatform? _current;

    public static IPathExecutorPlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("PathExecutor platform has not been composed.");

    public static void Configure(IPathExecutorPlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("PathExecutor platform has already been configured.");
    }
}
