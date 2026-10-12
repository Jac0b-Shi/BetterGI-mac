using BetterGenshinImpact.Core.Mask;
using BetterGenshinImpact.Core.Simulator;
using BetterGenshinImpact.GameTask.AutoGeniusInvokation.Exception;
using BetterGenshinImpact.Helpers;
using BetterGenshinImpact.Service.Notification;
using BetterGenshinImpact.Service.Notification.Model.Enum;
using BetterGenshinImpact.View;

using BetterGenshinImpact.ViewModel;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;
using Wpf.Ui.Violeta.Controls;

namespace BetterGenshinImpact.GameTask;

public sealed class WindowsTaskRunnerPlatform : ITaskRunnerPlatform
{
    public ILogger Logger => App.GetLogger<TaskRunner>();
    public ILogger RunnerLogger => Common.TaskControl.Logger;
    public SemaphoreSlim TaskSemaphore => Common.TaskControl.TaskSemaphore;

    public void NotifyCancellation(string message) =>
        Notify.Event(NotificationEvent.TaskCancel).Success(message);

    public void NotifyError(string message, Exception exception) =>
        Notify.Event(NotificationEvent.TaskError).Error(message, exception);

    public void InitializeTask()
    {
        if (!TaskContext.Instance().IsInitialized)
        {
            UIDispatcherHelper.Invoke(() => Toast.Warning("请先在启动页，启动截图器再使用本功能"));
            throw new NormalEndException("请先在启动页，启动截图器再使用本功能");
        }
        TaskTriggerDispatcher.Instance().BeginTask();
        TaskContext.Instance().Runtime?.MaskWindowMapState.Reset();
        MaskWindowDrawingPlatform.Current.ClearAll();
        TaskContext.Instance().Runtime?.Window.Activate();
    }

    public void EndTask()
    {
        if (!TaskContext.Instance().IsInitialized) return;
        BetterGenshinImpact.Core.Input.InputHub.ReleaseAll();
        TaskTriggerDispatcher.Instance().EndTask();
        MaskWindowDrawingPlatform.Current.ClearAll();
        HtmlMaskWindow.CloseAll();
    }
}
