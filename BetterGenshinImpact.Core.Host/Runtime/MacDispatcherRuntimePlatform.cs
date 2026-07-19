using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Platform.Abstractions;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacDispatcherRuntimePlatform(
    CancellationToken globalCancellationToken,
    IAutoPickRuntimeState autoPickRuntimeState,
    IInputBackend inputBackend,
    Func<ISystemInfo> systemInfo,
    IAutoPickConfigProvider autoPickConfigProvider,
    IPaddleAutoPickTextRecognizer paddleRecognizer,
    IYapAutoPickTextRecognizer yapRecognizer) : IDispatcherRuntimePlatform
{
    public CancellationToken GlobalCancellationToken { get; } = globalCancellationToken;

    public void ClearTriggers() => GameTaskManager.ClearTriggers();

    public bool AddTrigger(string name, object? config)
    {
        if (!GameTaskManager.AddTrigger(
                name, config, autoPickRuntimeState, inputBackend, systemInfo(),
                autoPickConfigProvider, paddleRecognizer, yapRecognizer))
            return false;

        var trigger = GameTaskManager.TriggerDictionary![name];
        trigger.Init();
        trigger.IsEnabled = true;
        return true;
    }
}
