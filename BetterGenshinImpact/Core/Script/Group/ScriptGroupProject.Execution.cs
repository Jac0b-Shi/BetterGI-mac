using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recorder;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Service;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.GameTask.AutoPathing.Model.Enum;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.FarmingPlan;
using BetterGenshinImpact.GameTask.LogParse;
using BetterGenshinImpact.GameTask.Shell;
using BetterGenshinImpact.Helpers;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Dynamic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace BetterGenshinImpact.Core.Script.Group;

/// <summary>
/// ScriptGroupProject 的真实任务执行链。与模型文件拆分仅用于隔离依赖边界；
/// Windows 工程仍默认编译此文件，业务分支和异常语义保持不变。
/// </summary>
public partial class ScriptGroupProject
{
    public async Task Run()
    {
        ExecutionRecord executionRecord = new()
        {
            ServerStartTime =
                GroupInfo?.Config.PathingConfig.TaskCompletionSkipRuleConfig.IsBoundaryTimeBasedOnServerTime ?? false
                    ? ScriptHostServices.ServerTimeNow
                    : DateTimeOffset.Now,
            StartTime = DateTime.Now,
            GroupName = GroupInfo?.Name ?? "",
            FolderName = FolderName,
            ProjectName = Name,
            Type = Type
        };
        ExecutionRecordStorage.SaveExecutionRecord(executionRecord);
        if (Type == "Javascript")
        {
            if (Project == null)
            {
                throw new Exception("JS脚本未初始化");
            }
            JsScriptSettingsObject ??= new ExpandoObject();
            CleanInvalidSettingsValues();
            var pathingPartyConfig = GroupInfo?.Config.PathingConfig;
            await Project.ExecuteAsync(JsScriptSettingsObject, pathingPartyConfig);
        }
        else if (Type == "KeyMouse")
        {
            var json = await File.ReadAllTextAsync(Global.Absolute(@$"User\KeyMouseScript\{Name}"));
            await KeyMouseMacroPlayer.PlayMacro(json, CancellationContext.Instance.Cts.Token, false);
        }
        else if (Type == "Pathing")
        {
            var task = PathingTask.BuildFromFilePath(Path.Combine(Global.Absolute(@"User\AutoPathing"), FolderName, Name));
            if (task == null)
            {
                return;
            }
            var pathingTask = ScriptGroupExecutionServices.Current.CreatePathExecutor(CancellationContext.Instance.Cts.Token);
            pathingTask.PartyConfig = GroupInfo?.Config.PathingConfig
                ?? ScriptGroupExecutionServices.Current.DefaultPartyConfig;
            if (pathingTask.PartyConfig is null || pathingTask.PartyConfig.AutoPickEnabled)
            {
                ScriptGroupExecutionServices.Current.AddAutoPickTrigger();
            }
            await pathingTask.Pathing(task);

            executionRecord.IsSuccessful = pathingTask.SuccessEnd;
            var autoRestart = ScriptGroupExecutionServices.Current.PathingFailurePolicy;
            if (!pathingTask.SuccessEnd)
            {
                ScriptServicePlatform.Current.Logger.LogWarning("此追踪脚本未正常走完！");
                if (autoRestart.RestartEnabled && autoRestart.PathingFailureExceptional && !pathingTask.SuccessEnd)
                {
                    throw new Exception("路径追踪任务未完全走完，判定失败，触发异常！");
                }
            }

            if (task.FarmingInfo.AllowFarmingCount)
            {
                var successFight = pathingTask.SuccessEnd;
                var fightCount = 0;
                if (!successFight)
                {
                    fightCount = task.Positions.Count(pos => pos.Action == ActionEnum.Fight.Code);
                    successFight = pathingTask.SuccessFight >= fightCount;
                    if (task.FarmingInfo.PrimaryTarget != "disable" && autoRestart.RestartEnabled &&
                        autoRestart.FightFailureExceptional && !successFight)
                    {
                        throw new Exception($"实际战斗次数({pathingTask.SuccessFight})<预期战斗次数（{fightCount}），判定失败，触发异常！");
                    }
                }

                if (successFight)
                {
                    ScriptGroupExecutionServices.Current.RecordFarmingSession(task.FarmingInfo, new FarmingRouteInfo
                    {
                        GroupName = GroupInfo?.Name ?? "",
                        FolderName = FolderName,
                        ProjectName = Name
                    });
                }
                else
                {
                    ScriptServicePlatform.Current.Logger.LogWarning($"实际战斗次数({pathingTask.SuccessFight})<预期战斗次数（{fightCount}），判定失败，此次不纳入成功锄地规划的统计上限！");
                }
            }
        }
        else if (Type == "Shell")
        {
            ShellConfig? shellConfig = null;
            if (GroupInfo?.Config.EnableShellConfig ?? false)
            {
                shellConfig = GroupInfo?.Config.ShellConfig;
            }
            var task = new ShellTask(ShellTaskParam.BuildFromConfig(Name, shellConfig ?? new ShellConfig()));
            await task.Start(CancellationContext.Instance.Cts.Token);
        }

        if (Type != "Pathing")
        {
            executionRecord.IsSuccessful = true;
        }
        executionRecord.ServerEndTime =
            GroupInfo?.Config.PathingConfig.TaskCompletionSkipRuleConfig.IsBoundaryTimeBasedOnServerTime ?? false
                ? ScriptHostServices.ServerTimeNow
                : DateTimeOffset.Now;
        executionRecord.EndTime = DateTime.Now;
        ExecutionRecordStorage.SaveExecutionRecord(executionRecord);
    }

    private void CleanInvalidSettingsValues()
    {
        if (Project == null || JsScriptSettingsObject == null)
        {
            return;
        }
        try
        {
            var settingItems = Project.Manifest.LoadSettingItems(Project.ProjectPath);
            if (settingItems.Count == 0)
            {
                return;
            }
            if (JsScriptSettingsObject is not IDictionary<string, object?> settingsDict)
            {
                return;
            }
            foreach (var item in settingItems.Where(i => i.Type == "multi-checkbox"))
            {
                if (!settingsDict.ContainsKey(item.Name))
                {
                    continue;
                }
                var savedValue = settingsDict[item.Name];
                List<string>? checkedValues = null;
                if (savedValue is List<string> stringList)
                {
                    checkedValues = stringList;
                }
                else if (savedValue is List<object> objectList)
                {
                    checkedValues = objectList.Select(i => (string)i).ToList();
                    settingsDict[item.Name] = checkedValues;
                }
                if (checkedValues != null && item.Options != null)
                {
                    checkedValues.RemoveAll(value => !item.Options.Contains(value));
                }
            }
        }
        catch (Exception ex)
        {
            ScriptServicePlatform.Current.Logger.LogDebug(ex, "清理JS脚本配置中的无效值时发生异常");
        }
    }
}
