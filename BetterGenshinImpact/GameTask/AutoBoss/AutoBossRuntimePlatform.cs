using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.AutoBoss;

public enum AutoBossNotification
{
    Start,
    Reward,
    End,
}

public interface IAutoBossRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
    IOcrService OcrService { get; }
    AutoFightConfig AutoFightConfig { get; }
    ILogger<AutoBossTask> Logger { get; }
    void Notify(AutoBossNotification notification, string message);
}

public interface IAutoBossPathExecutorFactory
{
    IPathExecutor Create(CancellationToken cancellationToken);
    PathingPartyConfig CreatePartyConfig();
}

public sealed class AutoBossPathExecutorFactory(
    IScriptGroupExecutionServices executionServices,
    Func<PathingPartyConfig> partyConfigFactory) : IAutoBossPathExecutorFactory
{
    public IPathExecutor Create(CancellationToken cancellationToken) =>
        executionServices.CreatePathExecutor(cancellationToken);

    public PathingPartyConfig CreatePartyConfig() => partyConfigFactory();
}
