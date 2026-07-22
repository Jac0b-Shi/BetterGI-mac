using System;
using System.Threading;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Recognition.ONNX;
using BetterGenshinImpact.GameTask.AutoFight.Config;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.GameTask.AutoFight;

public interface IAutoFightRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
    AutoFightConfig AutoFightConfig { get; }
    IOcrService OcrService { get; }
    double DpiScale { get; }
    int CombatMacroPriority { get; }
    ILogger<T> GetLogger<T>();
    BgiYoloPredictor CreateYoloPredictor(BgiOnnxModel model);
    IDisposable UseConfig(AutoFightConfig config);
}

public static class AutoFightRuntimePlatform
{
    private static IAutoFightRuntimePlatform? _current;
    public static IAutoFightRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("AutoFight runtime platform has not been composed.");

    public static void Configure(IAutoFightRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("AutoFight runtime platform has already been configured.");
    }
}
