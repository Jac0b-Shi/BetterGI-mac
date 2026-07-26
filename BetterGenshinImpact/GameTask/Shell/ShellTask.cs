using BetterGenshinImpact.Service;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.GameTask.Shell;

public class ShellTask(ShellTaskParam param) : ISoloTask
{
    public string Name => "Shell";

    public Task Start(CancellationToken ct = default)
    {
        return Execute(ct);
    }

    private async Task Execute(CancellationToken ct)
    {
        if (param.Disable)
        {
            ScriptServicePlatform.Current.Logger.LogWarning("无法执行Shell: Shell任务被禁用");
            return;
        }

        if (string.IsNullOrEmpty(param.Command))
        {
            ScriptServicePlatform.Current.Logger.LogWarning("无法执行Shell: Shell为空");
            return;
        }

        if (ct.IsCancellationRequested)
        {
            ScriptServicePlatform.Current.Logger.LogError("shell {Shell} 被取消", param.Command);
        }

        ScriptServicePlatform.Current.Logger.LogInformation("执行shell:{Shell},超时时间为 {Wait} 秒", param.Command, param.TimeoutSeconds);

        var mixedToken = ct;
        var waitForExit = true;
        CancellationTokenSource? timeoutSignal = null;
        if (param.TimeoutSeconds > 0)
        {
            timeoutSignal = new CancellationTokenSource(TimeSpan.FromSeconds(param.TimeoutSeconds));
            // 超时取消或任务被取消
            mixedToken = CancellationTokenSource.CreateLinkedTokenSource(ct, timeoutSignal.Token).Token;
        }
        else
        {
            // timeout小于0不等待,不获取输出,仅仅启动shell即返回
            waitForExit = false;
        }

        ShellExecutionRecord result;
        try
        {
            result = await ShellTaskPlatform.Current.ExecuteAsync(param, waitForExit, mixedToken);
        }
        catch (OperationCanceledException)
        {
            if (timeoutSignal is { IsCancellationRequested: true })
            {
                ScriptServicePlatform.Current.Logger.LogError("shell {Shell} 执行超时", param.Command);
                return;
            }
            ScriptServicePlatform.Current.Logger.LogError("shell {Shell} 被取消", param.Command);
            return;
        }

        if (result.End)
        {
            if (param.Output && result.HasOutput)
            {
                ScriptServicePlatform.Current.Logger.LogInformation("shell {End} 运行结束,输出:{Output}", result.Shell, result.Output);
                return;
            }

            ScriptServicePlatform.Current.Logger.LogInformation("shell {End} 运行结束", param.Command);
        }

        ShellTaskPlatform.Current.ActivateGameWindow();
    }
}
