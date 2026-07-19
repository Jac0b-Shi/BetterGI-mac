using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask;

namespace BetterGenshinImpact.Core.Host.Runtime;

using BetterGenshinImpact.GameTask.AutoSkip;

/// <summary>Composes the real shared AutoSkipTrigger for PathExecutor dialogue frames.</summary>
public sealed class MacPathExecutorAutoSkipPlatform : IPathExecutorAutoSkipPlatform
{
    public IPathExecutorAutoSkipSession CreateSession()
    {
        var trigger = new AutoSkipTrigger();
        trigger.Init();
        trigger.IsEnabled = true;
        return new Session(trigger);
    }

    private sealed class Session(AutoSkipTrigger trigger) : IPathExecutorAutoSkipSession
    {
        public void OnCapture(CaptureContent content) => trigger.OnCapture(content);
    }
}
