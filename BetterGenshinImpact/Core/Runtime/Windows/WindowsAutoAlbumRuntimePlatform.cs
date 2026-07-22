using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoMusicGame;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Service.Notification.Model.Enum;
using Microsoft.Extensions.Logging;
using NotifyService = BetterGenshinImpact.Service.Notification.Notify;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoAlbumRuntimePlatform : IAutoAlbumRuntimePlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public bool PropagateTaskExceptions => false;
    public ILogger<AutoAlbumTask> Logger => App.GetLogger<AutoAlbumTask>();

    public void Notify(
        AutoAlbumNotification notification, string message,
        System.Exception? exception = null)
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
                    .Error(message, exception ?? new System.Exception(message));
                break;
            default:
                throw new System.ArgumentOutOfRangeException(
                    nameof(notification), notification, null);
        }
    }
}
