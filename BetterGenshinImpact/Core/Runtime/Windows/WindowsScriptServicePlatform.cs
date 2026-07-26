using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.FarmingPlan;
using BetterGenshinImpact.Service.Notification;
using BetterGenshinImpact.Service.Notification.Model.Enum;
using BetterGenshinImpact.ViewModel.Pages;
using Microsoft.Extensions.Logging;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.Service;

public sealed class WindowsScriptServicePlatform : IScriptServicePlatform
{
    private readonly BlessingOfTheWelkinMoonTask _blessingTask = new();

    public ILogger Logger => App.GetLogger<ScriptService>();
    public string AutoPathingRoot => MapPathingViewModel.PathJsonPath;
    public string MapMatchingMethod => TaskContext.Instance().Config.PathingConditionConfig.MapMatchingMethod;
    public IReadOnlyList<ScriptGroup> ScriptGroups => App.GetService<ScriptControlViewModel>().ScriptGroups;
    public bool FarmingPlanEnabled => TaskContext.Instance().Config.OtherConfig.FarmingPlanConfig.Enabled;
    public bool IsDailyFarmingLimitReached(FarmingSession farmingSession, out string message) =>
        FarmingStatsRecorder.IsDailyFarmingLimitReached(farmingSession, out message);
    public void ClearTriggers() => TaskTriggerDispatcher.Instance().ClearTriggers();
    public SchedulerRestartPolicy RestartPolicy
    {
        get
        {
            var restart = TaskContext.Instance().Config.OtherConfig.AutoRestartConfig;
            var start = TaskContext.Instance().Config.GenshinStartConfig;
            return new SchedulerRestartPolicy(
                restart.Enabled, restart.FailureCount, restart.RestartGameTogether,
                start.LinkedStartEnabled, start.AutoEnterGameEnabled);
        }
    }
    public void SetCurrentScriptProject(ScriptGroupProject project) =>
        TaskContext.Instance().CurrentScriptProject = project;

    public Task HandleBlessingOfTheWelkinMoon(CancellationToken cancellationToken) =>
        _blessingTask.Start(cancellationToken);

    public void NotifyGroupStart(string groupName) =>
        Notify.Event(NotificationEvent.GroupStart).Success($"配置组{groupName}启动");

    public void NotifyGroupEndSuccess(string groupName) =>
        Notify.Event(NotificationEvent.GroupEnd).Success($"配置组{groupName}结束");

    public void NotifyGroupEndError(string message) =>
        Notify.Event(NotificationEvent.GroupEnd).Error(message);

    public void CloseGame() => SystemControl.CloseGame();

    public void RestartApplication(string taskProgressName) =>
        SystemControl.RestartApplication(["--TaskProgress", taskProgressName]);

    public async Task StartGameTask(bool waitForMainUi)
    {
        var homePageViewModel = App.GetService<HomePageViewModel>();
        if (!homePageViewModel!.TaskDispatcherEnabled)
        {
            await homePageViewModel.OnStartTriggerAsync();
            if (waitForMainUi)
            {
                await Task.Run(async () =>
                {
                    await Task.Delay(200);
                    var first = true;
                    var sw = Stopwatch.StartNew();
                    var loseFocusCount = 0;
                    while (true)
                    {
                        if (CancellationContext.Instance.IsCancellationRequested)
                        {
                            TaskControl.Logger.LogInformation("检测到停止指令，退出启动等待");
                            return;
                        }
                        if (!homePageViewModel.TaskDispatcherEnabled || !TaskContext.Instance().IsInitialized)
                        {
                            await Task.Delay(500);
                            continue;
                        }
                        using var content = TaskControl.CaptureToRectArea();
                        if (Bv.IsInMainUi(content) || Bv.IsInAnyClosableUi(content) || Bv.IsInDomain(content)) return;
                        if (first)
                        {
                            first = false;
                            TaskControl.Logger.LogInformation("当前不在游戏主界面，等待进入主界面后执行任务...");
                            TaskControl.Logger.LogInformation("如果你已经在游戏内的其他界面，请自行退出当前界面（ESC），或是30秒后将程序将自动尝试到入主界面，使当前任务能够继续运行！");
                        }
                        await Task.Delay(500);
                        if (sw.Elapsed.TotalSeconds >= 30)
                        {
                            if (!SystemControl.IsGenshinImpactActiveByProcess())
                            {
                                loseFocusCount++;
                                if (loseFocusCount > 50 && loseFocusCount < 100)
                                    SystemControl.MinimizeAndActivateWindow(TaskContext.Instance().GameHandle);
                                SystemControl.ActivateWindow();
                            }
                            if (sw.Elapsed.TotalSeconds < 200) GlobalMethod.MoveMouseTo(300, 300);
                        }
                    }
                });
            }
        }
        var pendingUpdate = ScriptRepoUpdater.Instance.CommandLineAutoUpdateTask;
        if (pendingUpdate != null)
        {
            await pendingUpdate;
            ScriptRepoUpdater.Instance.CommandLineAutoUpdateTask = null;
        }
    }
}
