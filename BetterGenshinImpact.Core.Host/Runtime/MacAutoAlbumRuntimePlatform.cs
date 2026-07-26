using BetterGenshinImpact.GameTask.AutoMusicGame;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Service.Notification.Model.Enum;
using Microsoft.Extensions.Logging;
using NotifyService = BetterGenshinImpact.Service.Notification.Notify;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoAlbumRuntimePlatform(
    Func<ISystemInfo> systemInfo,
    ILogger<AutoAlbumTask> logger) : IAutoAlbumRuntimePlatform
{
    public ISystemInfo SystemInfo => systemInfo();
    public bool PropagateTaskExceptions => true;
    public ILogger<AutoAlbumTask> Logger { get; } = logger;

    public void Notify(
        AutoAlbumNotification notification, string message, Exception? exception = null)
    {
        switch (notification)
        {
            case AutoAlbumNotification.Start:
                NotifyService.Event(NotificationEvent.AlbumStart).Success(message);
                break;
            case AutoAlbumNotification.End:
                NotifyService.Event(NotificationEvent.AlbumEnd).Success(message);
                break;
            case AutoAlbumNotification.Error:
                NotifyService.Event(NotificationEvent.AlbumError)
                    .Error(message, exception ?? new Exception(message));
                break;
            default:
                throw new ArgumentOutOfRangeException(
                    nameof(notification), notification, null);
        }
    }
}
