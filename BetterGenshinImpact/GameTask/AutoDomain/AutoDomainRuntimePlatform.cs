using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Recognition.ONNX;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Model.Area;
using Microsoft.Extensions.Localization;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.GameTask.AutoDomain;

public enum AutoDomainNotification
{
    Start,
    Retry,
    Reward,
    End,
}

public interface IAutoDomainRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
    IOcrService OcrService { get; }
    IStringLocalizer<AutoDomainTask> StringLocalizer { get; }
    ILogger<AutoDomainTask> Logger { get; }
    BgiYoloPredictor CreateTreePredictor();
    void DrawCameraDirection(ImageRegion region, double angle);
    void AddAutoEatTrigger();
    void Notify(AutoDomainNotification notification, string message);
}
