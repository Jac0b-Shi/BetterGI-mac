using BetterGenshinImpact.Core.Simulator.Extensions;
using System;
using System.Threading;
using System.Collections.Generic;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Platform.Abstractions;
using BetterGenshinImpact.GameTask.Model.Area;

namespace BetterGenshinImpact.GameTask.AutoSkip;

public interface IAutoSkipAudioWaiter
{
    bool IsWaiting { get; }
    void Cancel();
    void ReleaseDetector();
    bool Start(int maxWaitMilliseconds, int fallbackDelayMilliseconds, Microsoft.Extensions.Logging.ILogger logger);
    bool Update(Microsoft.Extensions.Logging.ILogger logger);
}

public interface IAutoSkipAudioSampleCapture : IDisposable
{
    void ReadAvailableSamples(List<float> destination);
    void DiscardAvailableSamples();
}

public interface IAutoSkipRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
    string PickKey { get; }
    ILogger<T> GetLogger<T>();
    IOcrService OcrService { get; }
    bool IsGameActive();
    void ActivateGameWindow();
    IAutoSkipAudioWaiter CreateAudioWaiter();
    void SimulateBackgroundAction(GIActions action);
    void PressBackgroundKey(BgiKey key);
    void BackgroundLeftButtonClick();
    void BackgroundClick(Region region);
    void ReportError(string message);
}

public static class AutoSkipRuntimePlatform
{
    private static IAutoSkipRuntimePlatform? _current;

    public static IAutoSkipRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("AutoSkip runtime platform has not been composed.");

    public static void Configure(IAutoSkipRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("AutoSkip runtime platform has already been configured.");
    }
}
