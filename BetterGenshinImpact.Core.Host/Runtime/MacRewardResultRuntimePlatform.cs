using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.Common.Reward;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacRewardResultRuntimePlatform(
    IOcrService ocrService,
    ILogger<RewardResultRecognizer> logger) : IRewardResultRuntimePlatform
{
    public ILogger<RewardResultRecognizer> Logger { get; } = logger ?? throw new ArgumentNullException(nameof(logger));
    public IOcrService OcrService { get; } = ocrService ?? throw new ArgumentNullException(nameof(ocrService));
    public bool SaveDebugScreenshots => false;
}
