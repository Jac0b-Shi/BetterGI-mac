using BetterGenshinImpact.Service.Notification.Model;
using System;
using System.Threading;

namespace BetterGenshinImpact.Service.Notification;

public interface INotificationRuntimePlatform
{
    void Send(BaseNotificationData notificationData);
}

public static class NotificationRuntimePlatform
{
    private static INotificationRuntimePlatform? _current;

    public static void Configure(INotificationRuntimePlatform platform) =>
        Interlocked.Exchange(
            ref _current,
            platform ?? throw new ArgumentNullException(nameof(platform)));

    public static void Send(BaseNotificationData notificationData) =>
        (_current ?? throw new InvalidOperationException(
            "Notification runtime platform has not been configured."))
        .Send(notificationData);
}
