using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Recognition.ONNX;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.CharacterDevelopment;

public interface ICharacterDevelopmentRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
    IOcrService OcrService { get; }
    BgiOnnxFactory OnnxFactory { get; }
    ILogger<T> GetLogger<T>();
}

public static class CharacterDevelopmentRuntimePlatform
{
    private static ICharacterDevelopmentRuntimePlatform? _current;

    public static ICharacterDevelopmentRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("Character development runtime platform has not been composed.");

    public static void Configure(ICharacterDevelopmentRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
        {
            throw new InvalidOperationException("Character development runtime platform has already been configured.");
        }
    }
}
