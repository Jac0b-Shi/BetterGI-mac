using System;
using BetterGenshinImpact.Service.Notifier.Interface;
using Microsoft.Extensions.Logging;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using BetterGenshinImpact.Service.Notification.Model;

namespace BetterGenshinImpact.Service.Notifier;

public class NotifierManager
{
    private readonly List<INotifier> _notifiers = [];
    private readonly ILogger _logger;

    public NotifierManager(ILogger<NotifierManager> logger)
        : this((ILogger)logger)
    {
    }

    public NotifierManager(ILogger logger)
    {
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    public void RegisterNotifier(INotifier notifier)
    {
        _notifiers.Add(notifier);
    }

    public void RemoveNotifier<T>() where T : INotifier
    {
        var matches = _notifiers.Where(notifier => notifier is T).ToArray();
        foreach (var notifier in matches)
        {
            _notifiers.Remove(notifier);
            if (notifier is IDisposable disposable)
                disposable.Dispose();
        }
    }

    public void RemoveAllNotifiers()
    {
        foreach (var notifier in _notifiers)
        {
            if (notifier is IDisposable disposable)
                disposable.Dispose();
        }
        _notifiers.Clear();
    }

    public INotifier? GetNotifier<T>() where T : INotifier
    {
        return _notifiers.FirstOrDefault(o => o is T);
    }

    public async Task SendNotificationAsync(INotifier notifier, BaseNotificationData content)
    {
        try
        {
            await notifier.SendAsync(content);
        }
        catch (System.Exception ex)
        {
            _logger.LogWarning(
                "{name} 通知发送失败: {ex}",
                notifier.Name,
                ex.Message);
        }
    }

    public async Task SendNotificationAsync<T>(BaseNotificationData content) where T : INotifier
    {
        var notifier = _notifiers.FirstOrDefault(o => o is T);

        if (notifier != null)
        {
            await SendNotificationAsync(notifier, content);
        }
    }

    public async Task SendNotificationToAllAsync(BaseNotificationData content)
    {
        await Task.WhenAll(_notifiers.Select(notifier => SendNotificationAsync(notifier, content)));
    }
}
