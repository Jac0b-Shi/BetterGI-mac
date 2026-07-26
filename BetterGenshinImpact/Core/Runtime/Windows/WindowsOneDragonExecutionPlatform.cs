using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.Core.Script.OneDragon;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.Helpers;
using BetterGenshinImpact.Model;
using BetterGenshinImpact.Service;
using BetterGenshinImpact.Service.Interface;
using BetterGenshinImpact.Service.Notification;
using BetterGenshinImpact.Service.Notification.Model.Enum;
using BetterGenshinImpact.ViewModel.Pages;
using BetterGenshinImpact.ViewModel.Pages.View;
using Microsoft.Extensions.Logging;
using Wpf.Ui.Violeta.Controls;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsOneDragonExecutionPlatform(
    ILogger logger,
    Action saveConfiguration,
    Action resumeMarkerConsumed) : IOneDragonExecutionPlatform
{
    public ILogger Logger { get; } = logger;

    public Task StartGameTask() => ScriptService.StartGameTask();

    public async Task ExecuteBuiltInTask(
        OneDragonBuiltInTaskRequest request,
        CancellationToken cancellationToken)
    {
        var item = new OneDragonTaskItem(GetTaskName(request.Task), request.Id);
        item.InitAction(request.Config);
        if (item.Action is null)
        {
            throw new InvalidOperationException(
                $"一条龙内置任务未构造执行动作: {request.Task}");
        }
        await item.Action();
    }

    private static string GetTaskName(OneDragonBuiltInTask task) =>
        task switch
        {
            OneDragonBuiltInTask.ClaimMail => "领取邮件",
            OneDragonBuiltInTask.CraftCondensedResin => "合成树脂",
            OneDragonBuiltInTask.AutoDomain => "自动秘境",
            OneDragonBuiltInTask.AutoBoss => "自动首领讨伐",
            OneDragonBuiltInTask.AutoStygianOnslaught => "自动幽境危战",
            OneDragonBuiltInTask.AutoLeyLineOutcrop => "自动地脉花",
            OneDragonBuiltInTask.ClaimDailyRewards => "领取每日奖励",
            OneDragonBuiltInTask.ClaimSereniteaPotRewards => "领取尘歌壶奖励",
            _ => throw new ArgumentOutOfRangeException(nameof(task), task, null),
        };

    public async Task ExecuteScriptGroup(
        OneDragonScriptGroupRequest request,
        CancellationToken cancellationToken)
    {
        var path = Path.Combine(
            Global.Absolute(@"User\ScriptGroup"),
            $"{request.Name}.json");
        var group = ScriptGroup.FromJson(await File.ReadAllTextAsync(path, cancellationToken));
        var scriptService = App.GetService<IScriptService>()
            ?? throw new InvalidOperationException("ScriptService is unavailable.");
        await scriptService.RunMulti(
            ScriptControlViewModel.GetNextProjects(group),
            group.Name,
            preserveCancellationContext: true);
    }

    public Task CheckRewards(CancellationToken cancellationToken) =>
        new CheckRewardsTask().Start(cancellationToken);

    public void SaveConfiguration(OneDragonFlowConfig config) => saveConfiguration();

    public void ResumeMarkerConsumed(OneDragonFlowConfig config)
    {
        saveConfiguration();
        resumeMarkerConsumed();
    }

    public void NotifyDragonStart(string message) =>
        Notify.Event(NotificationEvent.DragonStart).Success(message);

    public void NotifyDragonEnd(string message) =>
        Notify.Event(NotificationEvent.DragonEnd).Success(message);

    public void ReportScriptGroupFailure(
        OneDragonScriptGroupRequest request,
        Exception exception)
    {
        Logger.LogDebug(exception, "执行配置组任务时失败: {Name}", request.Name);
        Toast.Error("执行配置组任务时失败");
    }

    public void ExecuteCompletionAction(OneDragonCompletionAction action)
    {
        switch (action)
        {
            case OneDragonCompletionAction.None:
                return;
            case OneDragonCompletionAction.CloseGame:
                SystemControl.CloseGame();
                return;
            case OneDragonCompletionAction.CloseApplication:
                Application.Current.Dispatcher.Invoke(Application.Current.Shutdown);
                return;
            case OneDragonCompletionAction.CloseGameAndApplication:
                SystemControl.CloseGame();
                Application.Current.Dispatcher.Invoke(Application.Current.Shutdown);
                return;
            case OneDragonCompletionAction.Shutdown:
                SystemControl.CloseGame();
                SystemControl.Shutdown();
                return;
            default:
                throw new ArgumentOutOfRangeException(nameof(action), action, null);
        }
    }
}
