using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.GameTask.AutoGeniusInvokation.Exception;

using Microsoft.Extensions.Logging;
using System;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.Service;

namespace BetterGenshinImpact.GameTask;

/// <summary>
/// 用于以独立任务的方式执行任意方法
/// </summary>
public class TaskRunner
{
    private ILogger _logger => TaskRunnerPlatform.Current.Logger;

    // private readonly DispatcherTimerOperationEnum _timerOperation = DispatcherTimerOperationEnum.None;

    private readonly string _name = string.Empty;

    public TaskRunner()
    {
    }

    // public TaskRunner(DispatcherTimerOperationEnum timerOperation)
    // {
    //     _timerOperation = timerOperation;
    // }

    /// <summary>
    /// 加锁并独立运行任务
    /// </summary>
    /// <param name="action"></param>
    /// <param name="resetCancellationContext">任务开始时是否重建 CancellationContext。</param>
    /// <param name="clearCancellationContextOnLockFailure">获取信号量锁失败时是否清理 CancellationContext。</param>
    /// <param name="clearCancellationContextOnCompletion">任务结束时是否清理 CancellationContext。</param>
    /// <returns></returns>
    public async Task RunCurrentAsync(
        Func<Task> action,
        bool resetCancellationContext = true,
        bool clearCancellationContextOnLockFailure = false,
        bool clearCancellationContextOnCompletion = true)
    {
        // 加锁
        var taskSemaphore = TaskRunnerPlatform.Current.TaskSemaphore;
        var hasLock = await taskSemaphore.WaitAsync(0);
        if (!hasLock)
        {
            _logger.LogError("任务启动失败：当前存在正在运行中的独立任务，请不要重复执行任务！");
            if (clearCancellationContextOnLockFailure)
            {
                CancellationContext.Instance.Clear();
            }
            if (TaskRunnerPlatform.Current.ThrowOnLockFailure)
            {
                throw new InvalidOperationException("TaskRunner could not acquire the task semaphore.");
            }
            return;
        }
        try
        {
            _logger.LogInformation("→ {Text}", _name + "任务启动！");

            // 初始化
            Init();
            if (resetCancellationContext)
            {
                CancellationContext.Instance.Set();
            }
            RunnerContext.Instance.Clear();

            await action();
        }
        catch (NormalEndException e)
        {
            TaskRunnerPlatform.Current.NotifyCancellation("任务手动取消，或正常结束");
            _logger.LogInformation("任务中断:{Msg}", e.Message);
            if (RunnerContext.Instance.IsContinuousRunGroup)
            {
                // 连续执行时，抛出异常，终止执行
                throw;
            }
        }
        catch (OperationCanceledException)
        {
            TaskRunnerPlatform.Current.NotifyCancellation("任务被手动取消");
            _logger.LogInformation("任务中断:{Msg}", "任务被取消");
            if (RunnerContext.Instance.IsContinuousRunGroup)
            {
                // 连续执行时，抛出异常，终止执行
                throw;
            }
        }
        catch (Exception e)
        {
            TaskRunnerPlatform.Current.NotifyError("任务执行异常", e);
            _logger.LogError(e.Message);
            _logger.LogDebug(e.StackTrace);
            if (TaskRunnerPlatform.Current.RethrowUnexpectedExceptions)
            {
                throw;
            }
        }
        finally
        {
            End();
            _logger.LogInformation("→ {Text}", _name + "任务结束");

            if (clearCancellationContextOnCompletion)
            {
                CancellationContext.Instance.Clear();
            }
            RunnerContext.Instance.Clear();

            // 释放锁
            if (hasLock)
            {
                taskSemaphore.Release();
            }
        }
    }

    public void FireAndForget(Func<Task> action)
    {
        Task.Run(() => RunCurrentAsync(action));
    }

    public async Task RunThreadAsync(
        Func<Task> action,
        bool resetCancellationContext = true,
        bool clearCancellationContextOnLockFailure = false,
        bool clearCancellationContextOnCompletion = true)
    {
        await Task.Run(() => RunCurrentAsync(
            action,
            resetCancellationContext,
            clearCancellationContextOnLockFailure,
            clearCancellationContextOnCompletion));
    }

    public async Task RunSoloTaskAsync(ISoloTask soloTask)
    {
        // 启动等待之前先进行取消操作的初始化，便于在任务开始前终止任务.
        CancellationContext.Instance.Set();

        // 没启动的时候先启动
        bool waitForMainUi = soloTask.Name != "自动七圣召唤" && !soloTask.Name.Contains("自动音游") &&
                             !soloTask.Name.Contains("幽境危战");
        await ScriptServicePlatform.Current.StartGameTask(waitForMainUi);
        if (CancellationContext.Instance.IsCancellationRequested)
        {
            _logger.LogInformation("独立任务在启动阶段被取消: {Name}", soloTask.Name);
            CancellationContext.Instance.Clear();
            return;
        }

        await Task.Run(() => RunCurrentAsync(
            async () => await soloTask.Start(CancellationContext.Instance.Cts.Token),
            resetCancellationContext: false,
            clearCancellationContextOnLockFailure: true));
    }

    public void Init()
    {
        TaskRunnerPlatform.Current.InitializeTask();
    }

    public void End()
    {
        TaskRunnerPlatform.Current.EndTask();
    }

}
