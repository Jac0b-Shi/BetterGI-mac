using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.AutoArtifactSalvage;
using BetterGenshinImpact.GameTask.AutoStygianOnslaught;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Service.Notification.Model.Enum;
using Microsoft.Extensions.Logging;
using NotifyService = BetterGenshinImpact.Service.Notification.Notify;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoStygianOnslaughtRuntimePlatform(
    Func<ISystemInfo> systemInfo,
    IOcrService ocrService,
    IAutoPickConfigProvider autoPickConfigProvider,
    ILoggerFactory loggerFactory) : IAutoStygianOnslaughtRuntimePlatform
{
    public ISystemInfo SystemInfo => systemInfo();
    public IOcrService OcrService { get; } = ocrService;
    public string PickKey => autoPickConfigProvider.AutoPickConfig.PickKey;
    public ILogger<AutoStygianOnslaughtTask> Logger { get; } =
        loggerFactory.CreateLogger<AutoStygianOnslaughtTask>();

    public void Notify(AutoStygianOnslaughtNotification notification, string message)
    {
        var eventName = notification switch
        {
            AutoStygianOnslaughtNotification.Start => NotificationEvent.DomainStart,
            AutoStygianOnslaughtNotification.Reward => NotificationEvent.DomainReward,
            AutoStygianOnslaughtNotification.End => NotificationEvent.DomainEnd,
            _ => throw new ArgumentOutOfRangeException(
                nameof(notification), notification, null),
        };
        NotifyService.Event(eventName).Success(message);
    }

    public Task RunArtifactSalvage(
        AutoArtifactSalvageTaskParam parameter, CancellationToken taskCancellationToken) =>
        new AutoArtifactSalvageTask(
                parameter,
                OcrService,
                SystemInfo.AssetScale,
                loggerFactory.CreateLogger<AutoArtifactSalvageTask>())
            .Start(taskCancellationToken);
}
