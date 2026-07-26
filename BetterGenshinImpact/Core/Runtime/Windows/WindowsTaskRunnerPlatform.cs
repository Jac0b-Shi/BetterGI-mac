using BetterGenshinImpact.Core.Simulator;
using BetterGenshinImpact.GameTask.AutoGeniusInvokation.Exception;
using BetterGenshinImpact.Helpers;
using BetterGenshinImpact.Service.Notification;
using BetterGenshinImpact.Service.Notification.Model.Enum;
using BetterGenshinImpact.View;
using BetterGenshinImpact.View.Drawable;
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
        TaskTriggerDispatcher.Instance().ClearTriggers();
        UIDispatcherHelper.Invoke(() =>
        {
            if (MaskWindow.InstanceNullable() != null && MaskWindow.Instance().DataContext is MaskWindowViewModel vm)
                vm.IsInBigMapUi = false;
        });
        VisionContext.Instance().DrawContent.ClearAll();
        var maskWindow = MaskWindow.Instance();
        SystemControl.ActivateWindow();
        maskWindow.Invoke(maskWindow.Show);
    }

    public void EndTask()
    {
        if (!TaskContext.Instance().IsInitialized) return;
        Simulation.ReleaseAllKey();
        TaskTriggerDispatcher.Instance().ClearTriggers();
        TaskTriggerDispatcher.Instance().ReloadInitialTriggers();
        VisionContext.Instance().DrawContent.ClearAll();
        HtmlMaskWindow.CloseAll();
    }
}
