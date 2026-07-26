using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Recognition.ONNX;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Localization;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.GameTask.AutoFishing;

public interface IAutoFishingRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
    AutoFishingConfig Config { get; }
    string GameCultureInfoName { get; }
    IOcrService OcrService { get; }
    ILogger<T> GetLogger<T>();
    IStringLocalizer<T> GetStringLocalizer<T>();
    BgiYoloPredictor CreateYoloPredictor(BgiOnnxModel model);
    bool IsGameActive(out string activeProcessName);
    ImageRegion? CaptureFrame();
    void DisableRealtimeFishing();
    Task SetTimeAsync(int hour, int minute, CancellationToken cancellationToken);
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
