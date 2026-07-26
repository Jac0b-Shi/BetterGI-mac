using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.Core.Script.OneDragon;
using BetterGenshinImpact.GameTask.AutoArtifactSalvage;
using BetterGenshinImpact.GameTask.AutoBoss;
using BetterGenshinImpact.GameTask.AutoDomain;
using BetterGenshinImpact.GameTask.AutoLeyLineOutcrop;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.AutoStygianOnslaught;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.Service;
using BetterGenshinImpact.Service.Notification;
using BetterGenshinImpact.Service.Notification.Model.Enum;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacOneDragonExecutionPlatform(
    RuntimeLayout layout,
    OneDragonCatalog catalog,
    MacDispatcherRuntimePlatform dispatcher,
    IAutoDomainRuntimePlatform autoDomainRuntime,
    IAutoBossRuntimePlatform autoBossRuntime,
    IAutoBossPathExecutorFactory autoBossPathExecutorFactory,
    IAutoLeyLineOutcropRuntimePlatform autoLeyLineRuntime,
    IAutoStygianOnslaughtRuntimePlatform autoStygianRuntime,
    IScriptGroupExecutionServices scriptGroupExecutionServices,
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken hostCancellationToken,
    ILogger<MacOneDragonExecutionPlatform> logger)
    : IOneDragonExecutionPlatform
{
    public ILogger Logger { get; } = logger;

    public Task StartGameTask() => ScriptService.StartGameTask();

    public async Task ExecuteBuiltInTask(
        OneDragonBuiltInTaskRequest request,
        CancellationToken cancellationToken)
    {
        switch (request.Task)
        {
            case OneDragonBuiltInTask.ClaimMail:
                await new ClaimMailRewardsTask().Start(cancellationToken);
                return;
            case OneDragonBuiltInTask.CraftCondensedResin:
                await new GoToCraftingBenchTask().Start(
                    request.Config.CraftingBenchCountry,
                    cancellationToken);
                return;
            case OneDragonBuiltInTask.AutoDomain:
                await RunAutoDomain(request.Config, cancellationToken);
                return;
            case OneDragonBuiltInTask.AutoBoss:
                await RunAutoBoss(request.Config, cancellationToken);
                return;
            case OneDragonBuiltInTask.AutoStygianOnslaught:
                await RunAutoStygian(cancellationToken);
                return;
            case OneDragonBuiltInTask.AutoLeyLineOutcrop:
                await RunAutoLeyLine(request.Config, cancellationToken);
                return;
            case OneDragonBuiltInTask.ClaimDailyRewards:
                await new GoToAdventurersGuildTask().Start(
                    request.Config.AdventurersGuildCountry,
                    cancellationToken,
                    request.Config.DailyRewardPartyName);
                await new ClaimBattlePassRewardsTask().Start(cancellationToken);
                return;
            case OneDragonBuiltInTask.ClaimSereniteaPotRewards:
                await new GoToSereniteaPotTask(request.Config)
                    .Start(cancellationToken);
                return;
            default:
                throw new ArgumentOutOfRangeException(
                    nameof(request),
                    request.Task,
                    null);
        }
    }

    public async Task ExecuteScriptGroup(
        OneDragonScriptGroupRequest request,
        CancellationToken cancellationToken)
    {
        var path = ResolveScriptGroup(request.Name);
        var group = ScriptGroup.FromJson(
            await File.ReadAllTextAsync(path, cancellationToken));
        ScriptGroupResumeState.ApplyAndConsume(layout, group);
        await new ScriptService().RunMulti(
            group.Projects,
            group.Name,
            preserveCancellationContext: true);
    }

    public Task CheckRewards(CancellationToken cancellationToken) =>
        new CheckRewardsTask().Start(cancellationToken);

    public void SaveConfiguration(OneDragonFlowConfig config) =>
        catalog.Save(config);

    public void ResumeMarkerConsumed(OneDragonFlowConfig config) =>
        catalog.Save(config);

    public void NotifyDragonStart(string message) =>
        Notify.Event(NotificationEvent.DragonStart).Success(message);

    public void NotifyDragonEnd(string message) =>
        Notify.Event(NotificationEvent.DragonEnd).Success(message);

    public void ReportScriptGroupFailure(
        OneDragonScriptGroupRequest request,
        Exception exception) =>
        Logger.LogError(
            exception,
            "执行配置组任务时失败: {Name}",
            request.Name);

    public void ExecuteCompletionAction(OneDragonCompletionAction action)
    {
        switch (action)
        {
            case OneDragonCompletionAction.None:
                return;
            case OneDragonCompletionAction.CloseGame:
                RequireAcknowledgement("game.close");
                return;
            case OneDragonCompletionAction.CloseApplication:
                RequireAcknowledgement("application.quit");
                return;
            case OneDragonCompletionAction.CloseGameAndApplication:
                RequireAcknowledgement("game.close");
                RequireAcknowledgement("application.quit");
                return;
            case OneDragonCompletionAction.Shutdown:
                RequireAcknowledgement("game.close");
                RequireAcknowledgement("system.shutdown");
                return;
            default:
                throw new ArgumentOutOfRangeException(nameof(action), action, null);
        }
    }

    private async Task RunAutoDomain(
        OneDragonFlowConfig oneDragonConfig,
        CancellationToken cancellationToken)
    {
        if (dispatcher.GetFightStrategy(null, out var strategyPath))
        {
            Logger.LogError("自动秘境战斗策略未配置，跳过");
            return;
        }
        var (partyName, domainName, sundaySelectedValue) =
            oneDragonConfig.GetDomainConfig();
        if (string.IsNullOrWhiteSpace(domainName))
        {
            Logger.LogError("一条龙配置未选择需要刷取的秘境，跳过");
            return;
        }
        var config = MacDispatcherRuntimePlatform.LoadUserConfig<AutoDomainConfig>(
            layout,
            "autoDomainConfig");
        var artifact = MacDispatcherRuntimePlatform
            .LoadUserConfig<AutoArtifactSalvageConfig>(
                layout,
                "autoArtifactSalvageConfig");
        var pick = MacDispatcherRuntimePlatform.LoadUserConfig<AutoPickConfig>(
            layout,
            "autoPickConfig");
        var parameter = new AutoDomainParam(
            0,
            strategyPath,
            config,
            artifact.MaxArtifactStar)
        {
            PartyName = partyName,
            DomainName = domainName,
            SundaySelectedValue = sundaySelectedValue,
        };
        await new AutoDomainTask(
                parameter,
                config,
                pick.PickKey,
                autoDomainRuntime)
            .Start(cancellationToken);
    }

    private async Task RunAutoBoss(
        OneDragonFlowConfig config,
        CancellationToken cancellationToken)
    {
        var strategyName = string.IsNullOrWhiteSpace(config.AutoBossStrategyName)
            ? "根据队伍自动选择"
            : config.AutoBossStrategyName;
        if (dispatcher.GetFightStrategy(strategyName, out var strategyPath))
        {
            Logger.LogError("自动首领讨伐战斗策略未配置，跳过");
            return;
        }
        if (string.IsNullOrWhiteSpace(config.AutoBossName))
        {
            Logger.LogError("一条龙配置未选择需要讨伐的首领，跳过");
            return;
        }
        var parameter = new AutoBossParam(
            strategyPath,
            new AutoBossConfig())
        {
            BossName = config.AutoBossName,
            StrategyName = strategyName,
            TeamName = config.AutoBossTeamName,
            SpecifyRunCount = config.AutoBossSpecifyRunCount,
            RunCount = config.AutoBossRunCount,
            UseTransientResin = config.AutoBossUseTransientResin,
            UseFragileResin = config.AutoBossUseFragileResin,
            ReviveRetryCount = config.AutoBossReviveRetryCount,
            ReturnToStatueAfterEachRound =
                config.AutoBossReturnToStatueAfterEachRound,
            RewardRecognitionEnabled =
                config.AutoBossRewardRecognitionEnabled,
        };
        parameter.CombatStrategyPath = strategyPath;
        await new AutoBossTask(
                parameter,
                autoBossRuntime,
                autoBossPathExecutorFactory)
            .Start(cancellationToken);
    }

    private async Task RunAutoStygian(CancellationToken cancellationToken)
    {
        var config = MacDispatcherRuntimePlatform
            .LoadUserConfig<AutoStygianOnslaughtConfig>(
                layout,
                "autoStygianOnslaughtConfig");
        var defaultFight = MacDispatcherRuntimePlatform
            .LoadUserConfig<BetterGenshinImpact.GameTask.AutoFight.AutoFightConfig>(
                layout,
                "autoFightConfig");
        var artifact = MacDispatcherRuntimePlatform
            .LoadUserConfig<AutoArtifactSalvageConfig>(
                layout,
                "autoArtifactSalvageConfig");
        var strategyName = string.IsNullOrWhiteSpace(config.StrategyName)
            ? defaultFight.StrategyName
            : config.StrategyName;
        if (dispatcher.GetFightStrategy(strategyName, out var strategyPath))
        {
            Logger.LogError("自动幽境危战战斗策略未配置，跳过");
            return;
        }
        _ = int.TryParse(artifact.MaxArtifactStar, out var artifactStar);
        var parameter = new AutoStygianOnslaughtParam(
            config,
            defaultFight.StrategyName,
            artifactStar);
        await new AutoStygianOnslaughtTask(
                parameter,
                strategyPath,
                autoStygianRuntime)
            .Start(cancellationToken);
    }

    private async Task RunAutoLeyLine(
        OneDragonFlowConfig oneDragonConfig,
        CancellationToken cancellationToken)
    {
        if (!oneDragonConfig.ShouldRunLeyLineToday())
        {
            Logger.LogInformation("自动地脉花未在运行日期内，跳过");
            return;
        }
        var config = MacDispatcherRuntimePlatform
            .LoadUserConfig<AutoLeyLineOutcropConfig>(
                layout,
                "autoLeyLineOutcropConfig");
        var (type, country) = oneDragonConfig.GetLeyLineConfigForToday(config);
        config.LeyLineOutcropType = type;
        config.Country = country;
        config.IsResinExhaustionMode =
            oneDragonConfig.LeyLineResinExhaustionMode;
        config.OpenModeCountMin = oneDragonConfig.LeyLineOpenModeCountMin;
        if (oneDragonConfig.LeyLineRunCount > 0)
            config.Count = oneDragonConfig.LeyLineRunCount;
        var parameter = new AutoLeyLineOutcropParam(config);
        await new AutoLeyLineOutcropTask(
                parameter,
                autoLeyLineRuntime,
                scriptGroupExecutionServices,
                oneDragonConfig.LeyLineOneDragonMode)
            .Start(cancellationToken);
    }

    private string ResolveScriptGroup(string name)
    {
        if (string.IsNullOrWhiteSpace(name) ||
            name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 ||
            name.Contains('/') ||
            name.Contains('\\') ||
            name is "." or "..")
        {
            throw new ArgumentException(
                "Invalid script group name.",
                nameof(name));
        }
        var path = Path.Combine(layout.ScriptGroupPath, name + ".json");
        return File.Exists(path)
            ? path
            : throw new FileNotFoundException(
                $"Script group does not exist: {name}",
                path);
    }

    private void RequireAcknowledgement(string method)
    {
        var response = callbacks.InvokeAsync(
                method,
                null,
                sessionToken,
                hostCancellationToken)
            .GetAwaiter()
            .GetResult();
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException(
                $"{method} did not return acknowledged=true.");
    }
}
