using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.GameTask;
using Microsoft.Extensions.Logging;
using System;
using BetterGenshinImpact.Service.Notification;
using BetterGenshinImpact.Service.Notification.Model.Enum;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsScriptHostServices(ILoggerFactory loggerFactory) : IScriptHostServices
{
    public ILogger CreateLogger(string categoryName) => loggerFactory.CreateLogger(categoryName);
    public ScriptGroupProject? CurrentProject => TaskContext.Instance().CurrentScriptProject;
    public TimeSpan ServerTimeZoneOffset => TaskContext.Instance().Config.OtherConfig.ServerTimeZoneOffset;
    public bool JsNotificationEnabled => TaskContext.Instance().Config.NotificationConfig.JsNotificationEnabled;

    public void EmitNotification(ScriptNotificationKind kind, string message)
    {
        if (kind == ScriptNotificationKind.Error)
            Notify.Event(NotificationEvent.JsError).Error(message);
        else
            Notify.Event(NotificationEvent.JsCustom).Send(message);
    }
}
