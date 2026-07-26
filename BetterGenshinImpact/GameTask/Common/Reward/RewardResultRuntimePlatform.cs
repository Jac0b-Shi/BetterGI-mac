using BetterGenshinImpact.Core.Recognition.OCR;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.Common.Reward;

public interface IRewardResultRuntimePlatform
{
    ILogger<RewardResultRecognizer> Logger { get; }
    IOcrService OcrService { get; }
    bool SaveDebugScreenshots { get; }
}

public static class RewardResultRuntimePlatform
{
    private static IRewardResultRuntimePlatform? _current;

    public static IRewardResultRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("RewardResult runtime platform has not been composed.");

    public static void Configure(IRewardResultRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("RewardResult runtime platform has already been configured.");
    }
}
