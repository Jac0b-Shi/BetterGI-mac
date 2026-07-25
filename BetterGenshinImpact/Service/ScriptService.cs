using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.Core.Script.Project;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoGeniusInvokation.Exception;
using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.FarmingPlan;
using BetterGenshinImpact.GameTask.LogParse;
using BetterGenshinImpact.GameTask.TaskProgress;
using BetterGenshinImpact.Service.Interface;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Service;

public partial class ScriptService : IScriptService
{
    private ILogger _logger => ScriptServicePlatform.Current.Logger;
    private static bool IsCurrentHourEqual(string input)
    {
        // 尝试将输入字符串转换为整数
        if (int.TryParse(input, out int hour))
        {
            // 验证小时是否在合法范围内（0-23）
            if (hour is >= 0 and <= 23)
            {
                // 获取当前小时数
                int currentHour = DateTime.Now.Hour;
                // 判断是否相等
                return currentHour == hour;
            }
        }

        // 如果输入非数字或不合法，返回 false
        return false;
    }
    public bool ShouldSkipTask(ScriptGroupProject project)
    {

        if (project.GroupInfo is { Config.PathingConfig.Enabled: true })
        {
            if (IsCurrentHourEqual(project.GroupInfo.Config.PathingConfig.SkipDuring))
            {
                _logger.LogInformation($"{project.Name}任务已到禁止执行时段，将跳过！");
                return true;
            }

            var tcc = project.GroupInfo.Config.PathingConfig.TaskCycleConfig;
            if (tcc.Enable)
            {
                int index = tcc.GetExecutionOrder(ScriptHostServices.ServerTimeNow);
                if (index == -1)
                {
                    _logger.LogInformation($"{project.Name}周期配置参数错误，配置将不生效，任务正常执行！");
                }
                else if (index != tcc.Index)
                {
                    _logger.LogInformation($"{project.Name}任务已经不在执行周期（当前值${index}!=配置值${tcc.Index}），将跳过此任务！");
                    return true;
                }

            }

        }

        if (ScriptServicePlatform.Current.FarmingPlanEnabled)
        {
            try
            {
                var task = PathingTask.BuildFromFilePath(Path.Combine(ScriptServicePlatform.Current.AutoPathingRoot, project.FolderName, project.Name));
                if (task is null)
                {
                    return true;
                }
                string message;
                if (ScriptServicePlatform.Current.IsDailyFarmingLimitReached(task.FarmingInfo, out message))
                {
                    _logger.LogInformation($"{project.Name}:{message},跳过此任务！");
                    return true;
                }
            }
            catch (Exception e)
            {
                _logger.LogError("锄地规划统计异常：{Message}", e.Message);
            }


        }
        string skipMessage;
        if (ExecutionRecordStorage.IsSkipTask(project, out skipMessage))
        {
            _logger.LogInformation("{Project}:{Message},跳过此任务！", project.Name, skipMessage);
            return true;
        }
        return false; // 不跳过
    }




    //优先执行的配置组，统计每个project执行次数
    private readonly Dictionary<string, int> _projectExecutionCount = new();

    public async Task RunMulti(
        IEnumerable<ScriptGroupProject> projectList,
        string? groupName = null,
        TaskProgress? taskProgress = null,
        bool preserveCancellationContext = false)
    {
        groupName ??= "默认";

        // 启动等待之前先进行取消操作的初始化，便于在任务开始前终止任务.
        if (!preserveCancellationContext)
        {
            CancellationContext.Instance.Set();
        }

        var list = ReloadScriptProjects(projectList);

        //恢复临时的跳过标志
        foreach (var scriptGroupProject in projectList)
        {
            scriptGroupProject.SkipFlag = false;
        }



        // // 针对JS 脚本，检查是否包含定时器操作
        // var jsProjects = ExtractJsProjects(list);
        // if (!hasTimer && jsProjects.Count > 0)
        // {
        //     var codeList = await ReadCodeList(jsProjects);
        //     hasTimer = HasTimerOperation(codeList);
        // }

        // 没启动时候，启动截图器
        await StartGameTask();
        if (CancellationContext.Instance.IsCancellationRequested)
        {
            _logger.LogInformation("配置组 {Name} 在启动阶段被取消", groupName);
            return;
        }


        if (!string.IsNullOrEmpty(groupName) && !RunnerContext.Instance.IsPreExecution)
        {
            // if (hasTimer)
            // {
            //     _logger.LogInformation("配置组 {Name} 包含实时任务操作调用", groupName);
            // }

            _logger.LogInformation("配置组 {Name} 加载完成，共{Cnt}个脚本，开始执行", groupName, list.Count);
        }

        // var timerOperation = hasTimer ? DispatcherTimerOperationEnum.UseCacheImageWithTriggerEmpty : DispatcherTimerOperationEnum.UseSelfCaptureImage;


        bool fisrt = true;


        //非优先执行配置下，清空执行计数
        if (!RunnerContext.Instance.IsPreExecution)
        {
            _projectExecutionCount.Clear();
        }


        await new TaskRunner()
            .RunThreadAsync(async () =>
            {
                var stopwatch = new Stopwatch();
                int projectIndex = -1;
                for (int x = 0; x < list.Count; x++)
                {
                    var project = list[x];
                    //正常情况下，只有一个真正执行的project，存在其他优先执行配置组情况下，会有多个任务。
                    List<ScriptGroupProject> exeProjects = [project];
                    RunnerContext.Instance.IsPreExecution = false;
                    //优先执行配置组逻辑
                    if (!RunnerContext.Instance.IsPreExecution &&
                        (project.GroupInfo?.Config.PathingConfig.Enabled ?? false) &&
                        project.GroupInfo.Config.PathingConfig.PreExecutionPriorityConfig.Enabled)
                    {
                        var preConfig = project.GroupInfo.Config.PathingConfig.PreExecutionPriorityConfig;
                        var groupNames = preConfig.GroupNames;

                        if (!string.IsNullOrWhiteSpace(groupNames))
                        {
                            // 解析组名集合
                            var groupNameSet = groupNames
                                .Split(',', StringSplitOptions.RemoveEmptyEntries)
                                .Select(name => name.Trim())
                                .Where(name => !string.IsNullOrWhiteSpace(name));

                            // 获取匹配的脚本组
                            var scriptGroups = ScriptServicePlatform.Current.ScriptGroups
                                .Where(g => groupNameSet.Contains(g.Name, StringComparer.OrdinalIgnoreCase))
                                .ToList();

                            // 收集需要执行的项目
                            var preExecutionProjects = new List<ScriptGroupProject>();
                            foreach (var group in scriptGroups)
                            {
                                var skipConfig = group.Config.PathingConfig.TaskCompletionSkipRuleConfig;
                                var records = ExecutionRecordStorage.GetRecentExecutionRecordsByConfig(skipConfig);

                                foreach (var p in group.Projects)
                                {
                                    // 检查是否应该跳过任务
                                    if (ExecutionRecordStorage.IsSkipTask(p, out _, records))
                                        continue;

                                    // 生成项目唯一标识
                                    var projectKey = $"{p.Name}|{p.FolderName}|{p.GroupInfo?.Name}";

                                    // 检查执行次数
                                    if (!_projectExecutionCount.TryGetValue(projectKey, out var count))
                                    {
                                        count = 0;
                                    }

                                    // 检查是否超过最大重试次数
                                    if (count > preConfig.MaxRetryCount)
                                        continue;

                                    //增加执行计数
                                    //_projectExecutionCount[projectKey] = count + 1;
                                    preExecutionProjects.Add(p);
                                }
                            }

                            // 存在优先执行的项目，则优先执行
                            if (preExecutionProjects.Count > 0)
                            {

                                _logger.LogInformation($"存在{preExecutionProjects.Count}个需优先执行的任务！");
                                // 设置执行状态，进入优先执行任务
                                RunnerContext.Instance.IsPreExecution = true;
                                //重新构造需要执行的配置组
                                exeProjects = preExecutionProjects.Concat(new[] { project }).ToList();
                            }
                        }
                    }

                    if (!RunnerContext.Instance.IsPreExecution)
                    {
                        projectIndex++;
                    }


                    for (int y = 0; y < exeProjects.Count; y++)
                    {
                        var exeProject = exeProjects[y];
                        //最后一个执行的project，恢复正常执行状态
                        if (y == exeProjects.Count - 1)
                        {
                            RunnerContext.Instance.IsPreExecution = false;
                        }
                        if (!RunnerContext.Instance.IsPreExecution && taskProgress != null && taskProgress.Next != null)
                        {
                            if (taskProgress.Next.Index > projectIndex)
                            {
                                continue;
                            }

                            taskProgress.Next = null;
                        }

                        if (exeProject is { SkipFlag: true })
                        {
                            continue;
                        }

                        if (ShouldSkipTask(exeProject))
                        {
                            continue;
                        }

                        //月卡检测
                        await ScriptServicePlatform.Current.HandleBlessingOfTheWelkinMoon(CancellationContext.Instance.Cts.Token);
                        if (exeProject.Status != "Enabled")
                        {
                            _logger.LogInformation("脚本 {Name} 状态为禁用，跳过执行", exeProject.Name);
                            continue;
                        }

                        if (CancellationContext.Instance.Cts.IsCancellationRequested)
                        {
                            // _logger.LogInformation("执行被取消");
                            break;
                        }

                        if (fisrt)
                        {
                            fisrt = false;
                            ScriptServicePlatform.Current.NotifyGroupStart(groupName);
                        }

                        if (!RunnerContext.Instance.IsPreExecution && taskProgress != null)
                        {
                            taskProgress.CurrentScriptGroupProjectInfo = new TaskProgress.ScriptGroupProjectInfo
                            {
                                Name = exeProject.Name,
                                FolderName = exeProject.FolderName,
                                Index = projectIndex,
                                GroupName = taskProgress?.CurrentScriptGroupName ?? ""
                            };
                            TaskProgressManager.SaveTaskProgress(taskProgress!);
                        }

                        //优先执行的任务，需要计数
                        if (RunnerContext.Instance.IsPreExecution)
                        {
                            // 生成项目唯一标识
                            var projectKey = $"{exeProject.Name}|{exeProject.FolderName}|{exeProject.GroupInfo?.Name}";
                            // 检查执行次数
                            if (!_projectExecutionCount.TryGetValue(projectKey, out var preExecutionCount))
                            {
                                preExecutionCount = 0;
                            }

                            _projectExecutionCount[projectKey] = preExecutionCount + 1;
                        }


                        for (var i = 0; i < exeProject.RunNum; i++)
                        {
                            try
                            {
                                ScriptServicePlatform.Current.ClearTriggers();


                                _logger.LogInformation("------------------------------");

                                stopwatch.Reset();
                                stopwatch.Start();

                                await ExecuteProject(exeProject);

                                //多次执行时及时中断
                                if (exeProject.RunNum > 1 && ShouldSkipTask(exeProject))
                                {
                                    continue;
                                }
                            }
                            catch (NormalEndException)
                            {
                                throw;
                            }
                            catch (OperationCanceledException e)
                            {
                                _logger.LogInformation("取消执行配置组: {Msg}", e.Message);
                                throw;
                            }
                            catch (Exception e) when (CancellationContext.Instance.IsCancellationRequested)
                            {
                                _logger.LogInformation("取消执行配置组: {Msg}", e.Message);
                                throw new OperationCanceledException(
                                    "配置组执行已取消",
                                    e,
                                    CancellationContext.Instance.Cts.Token);
                            }
                            catch (Exception e)
                            {
                                _logger.LogDebug(e, "执行脚本时发生异常");
                                _logger.LogError("执行脚本时发生异常: {Msg}", e.Message);
                                if (!RunnerContext.Instance.IsPreExecution && taskProgress != null && taskProgress.CurrentScriptGroupProjectInfo != null)
                                {
                                    taskProgress.CurrentScriptGroupProjectInfo.Status = 2;
                                }
                                if (ScriptServicePlatform.Current.PropagateProjectExceptions)
                                {
                                    throw;
                                }
                            }
                            finally
                            {
                                stopwatch.Stop();
                                var elapsedTime = TimeSpan.FromMilliseconds(stopwatch.ElapsedMilliseconds);
                                // _logger.LogDebug("→ 脚本执行结束: {Name}, 耗时: {ElapsedMilliseconds} 毫秒", project.Name, stopwatch.ElapsedMilliseconds);
                                _logger.LogInformation("→ 脚本执行结束: {Name}, 耗时: {Minutes}分{Seconds:0.000}秒", exeProject.Name,
                                    elapsedTime.Hours * 60 + elapsedTime.Minutes, elapsedTime.TotalSeconds % 60);
                                _logger.LogInformation("------------------------------");
                            }

                            await Task.Delay(1000);
                        }

                        if (!RunnerContext.Instance.IsPreExecution && taskProgress != null)
                        {
                            if (taskProgress.CurrentScriptGroupProjectInfo != null)
                            {
                                taskProgress.CurrentScriptGroupProjectInfo.TaskEnd = true;
                                taskProgress.CurrentScriptGroupProjectInfo.EndTime = DateTime.Now;
                                if (taskProgress.CurrentScriptGroupProjectInfo.Status == 1)
                                {
                                    taskProgress.ConsecutiveFailureCount = 0;
                                    taskProgress.LastSuccessScriptGroupProjectInfo =
                                        taskProgress.CurrentScriptGroupProjectInfo;
                                    taskProgress.LastScriptGroupName = taskProgress.CurrentScriptGroupName;
                                }

                                //累计连续失败次数
                                if (taskProgress.CurrentScriptGroupProjectInfo.Status == 2)
                                {
                                    taskProgress.ConsecutiveFailureCount++;
                                }

                                taskProgress?.History?.Add(taskProgress.CurrentScriptGroupProjectInfo);
                                TaskProgressManager.SaveTaskProgress(taskProgress!);
                            }

                            //异常达到一次次数，重启bgi
                            var autoconfig = ScriptServicePlatform.Current.RestartPolicy;
                            if (autoconfig.Enabled && taskProgress!.ConsecutiveFailureCount >= autoconfig.FailureCount)
                            {
                                _logger.LogInformation("调度器任务出现未预期的异常，自动重启bgi");
                                ScriptServicePlatform.Current.NotifyGroupEndError("调度器任务出现未预期的异常，自动重启bgi");
                                if (autoconfig.RestartGameTogether
                                    && autoconfig.LinkedStartEnabled
                                    && autoconfig.AutoEnterGameEnabled)
                                {
                                    ScriptServicePlatform.Current.CloseGame();
                                    Thread.Sleep(2000);
                                }

                                ScriptServicePlatform.Current.RestartApplication(taskProgress.Name);
                            }
                        }
                    }
                }
            },
            resetCancellationContext: !preserveCancellationContext,
            clearCancellationContextOnCompletion: !preserveCancellationContext);


        // 还原定时器
        // TaskTriggerDispatcher.Instance().SetTriggers(GameTaskManager.LoadInitialTriggers());

        if (!string.IsNullOrEmpty(groupName) && !RunnerContext.Instance.IsPreExecution)
        {
            _logger.LogInformation("配置组 {Name} 执行结束", groupName);
        }

        if (!fisrt && !RunnerContext.Instance.IsPreExecution)
        {
            if (CancellationContext.Instance.IsManualStop is false)
            {
                ScriptServicePlatform.Current.NotifyGroupEndSuccess(groupName);
            }
        }

        if (taskProgress != null)
        {
            taskProgress.Next = null;
        }

    }

    private List<ScriptGroupProject> ReloadScriptProjects(IEnumerable<ScriptGroupProject> projectList)
    {
        var list = new List<ScriptGroupProject>();
        foreach (var project in projectList)
        {
            if (project.Type == "Javascript")
            {
                var newProject = new ScriptGroupProject(new ScriptProject(project.FolderName));
                CopyProjectProperties(project, newProject);
                list.Add(newProject);
            }
            else if (project.Type == "KeyMouse")
            {
                var newProject = ScriptGroupProject.BuildKeyMouseProject(project.Name);
                CopyProjectProperties(project, newProject);
                list.Add(newProject);
            }
            else if (project.Type == "Pathing")
            {
                var newProject = ScriptGroupProject.BuildPathingProject(project.Name, project.FolderName);
                CopyProjectProperties(project, newProject);
                list.Add(newProject);
                // hasTimer = true;
            }
            else if (project.Type == "Shell")
            {
                var newProject = ScriptGroupProject.BuildShellProject(project.Name);
                CopyProjectProperties(project, newProject);
                list.Add(newProject);
                // hasTimer = true;
            }
        }

        return list;
    }

    private void CopyProjectProperties(ScriptGroupProject source, ScriptGroupProject target)
    {
        target.Status = source.Status;
        target.Schedule = source.Schedule;
        target.RunNum = source.RunNum;
        target.JsScriptSettingsObject = source.JsScriptSettingsObject;
        target.GroupInfo = source.GroupInfo;
        target.AllowJsNotification = source.AllowJsNotification;
        target.AllowJsHTTPHash = source.AllowJsHTTPHash;
        target.SkipFlag = source.SkipFlag;
    }

    // private List<ScriptProject> ExtractJsProjects(List<ScriptGroupProject> list)
    // {
    //     var jsProjects = new List<ScriptProject>();
    //     foreach (var project in list)
    //     {
    //         if (project is { Type: "Javascript", Project: not null })
    //         {
    //             jsProjects.Add(project.Project);
    //         }
    //     }
    //
    //     return jsProjects;
    // }

    private async Task ExecuteProject(ScriptGroupProject project)
    {
        ScriptServicePlatform.Current.SetCurrentScriptProject(project);
        if (project.Type == "Javascript")
        {
            if (project.Project == null)
            {
                throw new Exception("Project 为空");
            }

            _logger.LogInformation("→ 开始执行JS脚本: {Name}", project.Name);
            if (RunnerContext.Instance.IsPreExecution) _logger.LogInformation("此任务为优先执行任务！");
            var hasSettingsBeforeRun = project.JsScriptSettingsObject != null;
            try
            {
                await project.Run();
            }
            finally
            {
                SaveScriptGroupAfterJsRun(project, hasSettingsBeforeRun);
            }
        }
        else if (project.Type == "KeyMouse")
        {
            _logger.LogInformation("→ 开始执行键鼠脚本: {Name}", project.Name);
            if (RunnerContext.Instance.IsPreExecution) _logger.LogInformation("此任务为优先执行任务！");
            await project.Run();
        }
        else if (project.Type == "Pathing")
        {
            _logger.LogInformation("→ 开始执行地图追踪任务: {Name}", project.Name);
            if (RunnerContext.Instance.IsPreExecution) _logger.LogInformation("此任务为优先执行任务！");
            await project.Run();
        }
        else if (project.Type == "Shell")
        {
            _logger.LogInformation("→ 开始执行shell: {Name}", project.Name);
            if (RunnerContext.Instance.IsPreExecution) _logger.LogInformation("此任务为优先执行任务！");
            await project.Run();
        }
    }

    private void SaveScriptGroupAfterJsRun(ScriptGroupProject project, bool hasSettingsBeforeRun)
    {
        if (!hasSettingsBeforeRun)
        {
            project.JsScriptSettingsObject = null;
            return;
        }

        var scriptGroup = project.GroupInfo!;
        try
        {
            var scriptGroupPath = Global.Absolute(@"User\ScriptGroup");
            if (!Directory.Exists(scriptGroupPath))
            {
                Directory.CreateDirectory(scriptGroupPath);
            }

            var file = Path.Combine(scriptGroupPath, $"{scriptGroup.Name}.json");
            File.WriteAllText(file, scriptGroup.ToJson());
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "保存JS脚本配置组失败: {GroupName}", scriptGroup.Name);
        }
    }

    private async Task<List<string>> ReadCodeList(List<ScriptProject> list)
    {
        var codeList = new List<string>();
        foreach (var project in list)
        {
            var code = await project.LoadCode();
            codeList.Add(code);
        }

        return codeList;
    }

    private bool HasTimerOperation(IEnumerable<string> codeList)
    {
        return codeList.Any(code => DispatcherAddTimerRegex().IsMatch(code));
    }

    [GeneratedRegex(@"^(?!\s*\/\/)\s*dispatcher\.\s*addTimer", RegexOptions.Multiline)]
    private static partial Regex DispatcherAddTimerRegex();


    public static async Task StartGameTask(bool waitForMainUi = true)
    {
        await ScriptServicePlatform.Current.StartGameTask(waitForMainUi);
    }
}
