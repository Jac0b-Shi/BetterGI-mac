using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoLeyLineOutcrop;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;
using NotifyService = BetterGenshinImpact.Service.Notification.Notify;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoLeyLineOutcropRuntimePlatform(
    Func<ISystemInfo> systemInfo,
    IOcrService ocrService,
    IAutoFightRuntimePlatform autoFightRuntimePlatform,
    IAutoPickConfigProvider autoPickConfigProvider,
    double mapScaleFactor,
    ILoggerFactory loggerFactory) : IAutoLeyLineOutcropRuntimePlatform
{
    public ISystemInfo SystemInfo => systemInfo();
    public IOcrService OcrService { get; } = ocrService;
    public AutoFightConfig AutoFightConfig => autoFightRuntimePlatform.AutoFightConfig;
    public string PickKey => autoPickConfigProvider.AutoPickConfig.PickKey;
    public double MapScaleFactor { get; } = mapScaleFactor;
    public ILogger<AutoLeyLineOutcropTask> Logger { get; } =
        loggerFactory.CreateLogger<AutoLeyLineOutcropTask>();

    public void Notify(AutoLeyLineOutcropNotification notification, string message)
    {
        var notificationData = NotifyService.Event("AutoLeyLineOutcrop");
        if (notification == AutoLeyLineOutcropNotification.Error)
            notificationData.Error(message);
        else
            notificationData.Send(message);
    }

    public void EnsureOverlayVisible() { }
    public void RefreshOverlay() { }
    public void RestoreOverlayVisible() { }
}
