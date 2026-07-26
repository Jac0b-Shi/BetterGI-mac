using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.GameTask.Common;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.GameTask.AutoGeniusInvokation;

public class AutoGeniusInvokationTask(
    GeniusInvokationTaskParam taskParam,
    AutoGeniusInvokationConfig config,
    IAutoGeniusInvokationRuntimePlatform platform) : ISoloTask
{
    public string Name => "自动七圣召唤";

    public Task Start(CancellationToken ct)
    {
        try
        {
            var control = new GeniusInvokationControl(platform, config, ct);
            var duel = new ScriptParser(platform, control, config)
                .Parse(taskParam.StrategyContent);
            duel.Run(ct);
        }
        catch (System.Exception e)
        {
            var logger = platform.GetLogger<AutoGeniusInvokationTask>();
            logger.LogDebug(e, "执行自动七圣召唤任务异常");
            logger.LogError("执行自动七圣召唤任务异常：{Exception}", e.Message);
            if (platform.PropagateTaskExceptions) throw;
        }
        return Task.CompletedTask;
    }
}
