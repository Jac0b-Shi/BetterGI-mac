using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common.Reward;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsRewardResultRuntimePlatform : IRewardResultRuntimePlatform
{
    public ILogger<RewardResultRecognizer> Logger => App.GetLogger<RewardResultRecognizer>();
    public IOcrService OcrService => OcrFactory.Paddle;
    public bool SaveDebugScreenshots =>
        TaskContext.Instance().Config.CommonConfig.ScreenshotEnabled &&
        TaskContext.Instance().Config.CommonConfig.RewardRecognitionScreenshotEnabled;
}
