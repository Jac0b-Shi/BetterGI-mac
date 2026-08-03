using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Recognition.ONNX;
using BetterGenshinImpact.GameTask.CharacterDevelopment;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacCharacterDevelopmentRuntimePlatform(
    Func<ISystemInfo> systemInfoProvider,
    MacImageRegionOcrService recognition,
    ILoggerFactory loggerFactory) : ICharacterDevelopmentRuntimePlatform
{
    private readonly Func<ISystemInfo> _systemInfoProvider =
        systemInfoProvider ?? throw new ArgumentNullException(nameof(systemInfoProvider));
    private readonly MacImageRegionOcrService _recognition =
        recognition ?? throw new ArgumentNullException(nameof(recognition));
    private readonly ILoggerFactory _loggerFactory =
        loggerFactory ?? throw new ArgumentNullException(nameof(loggerFactory));

    public ISystemInfo SystemInfo => _systemInfoProvider();
    public IOcrService OcrService => _recognition;
    public BgiOnnxFactory OnnxFactory => _recognition.OnnxFactory;
    public ILogger<T> GetLogger<T>() => _loggerFactory.CreateLogger<T>();
}
