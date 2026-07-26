using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoArtifactSalvage;
using BetterGenshinImpact.GameTask.AutoStygianOnslaught;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Service.Notification;
using BetterGenshinImpact.Service.Notification.Model.Enum;
using Microsoft.Extensions.Logging;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoStygianOnslaughtRuntimePlatform :
    IAutoStygianOnslaughtRuntimePlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public IOcrService OcrService => OcrFactory.Paddle;
    public string PickKey => TaskContext.Instance().Config.AutoPickConfig.PickKey;
    public ILogger<AutoStygianOnslaughtTask> Logger =>
        App.GetLogger<AutoStygianOnslaughtTask>();

    public void Notify(AutoStygianOnslaughtNotification notification, string message)
    {
        var eventName = notification switch
        {
            AutoStygianOnslaughtNotification.Start => NotificationEvent.DomainStart,
            AutoStygianOnslaughtNotification.Reward => NotificationEvent.DomainReward,
            _ => NotificationEvent.DomainEnd,
        };
        BetterGenshinImpact.Service.Notification.Notify.Event(eventName).Success(message);
    }

    public Task RunArtifactSalvage(
        AutoArtifactSalvageTaskParam parameter, CancellationToken cancellationToken) =>
        new AutoArtifactSalvageTask(parameter).Start(cancellationToken);
}
