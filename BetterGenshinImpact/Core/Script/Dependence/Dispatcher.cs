using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Script.Dependence.Model;
using BetterGenshinImpact.GameTask.AutoEat;
using BetterGenshinImpact.GameTask.Model.GameUI;
using BetterGenshinImpact.Helpers;
using Microsoft.ClearScript;
using Microsoft.Extensions.Logging;
using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoFight.Script;
using BetterGenshinImpact.GameTask.Common;

namespace BetterGenshinImpact.Core.Script.Dependence;

public class Dispatcher
{
    private readonly ILogger _logger = ScriptHostServices.CreateLogger<Dispatcher>();
    private readonly object _config;

    public Dispatcher(object config)
    {
        _config = config;
    }

    public void RunTask()
    {
    }

    /// <summary>
    /// 添加实时任务,会清理之前的所有任务
    /// </summary>
    /// <param name="timer">实时任务触发器</param>
    /// <exception cref="ArgumentNullException"></exception>
    public void AddTimer(RealtimeTimer timer)
    {
        ClearAllTriggers();
        try
        {
            AddTrigger(timer);
        }
        catch (ArgumentException e)
        {
            if (e is ArgumentNullException)
            {
                throw;
            }
        }
    }

    /// <summary>
    /// 清理所有实时任务
    /// </summary>
    public void ClearAllTriggers()
    {
        DispatcherRuntimePlatform.Current.ClearTriggers();
    }

    /// <summary>
    /// 添加实时任务,不会清理之前的任务
    /// </summary>
    /// <param name="timer"></param>
    /// <exception cref="ArgumentNullException"></exception>
    /// <exception cref="ArgumentException"></exception>
    public void AddTrigger(RealtimeTimer timer)
    {
        var realtimeTimer = timer;
        if (realtimeTimer == null)
        {
            throw new ArgumentNullException(nameof(realtimeTimer), "实时任务对象不能为空");
        }

        if (string.IsNullOrEmpty(realtimeTimer.Name))
        {
            throw new ArgumentNullException(nameof(realtimeTimer.Name), "实时任务名称不能为空");
        }

        if (!DispatcherRuntimePlatform.Current.AddTrigger(realtimeTimer.Name, realtimeTimer.Config))
        {
            throw new ArgumentException($"添加实时任务失败: {realtimeTimer.Name}", nameof(realtimeTimer.Name));
        }
    }

    public async Task RunTask(SoloTask soloTask, CancellationTokenSource customCts)
    {
        // 创建链接的取消令牌源，任何一个取消都会触发
        CancellationTokenSource linkedCts = CancellationTokenSource.CreateLinkedTokenSource(
            customCts.Token,
            DispatcherRuntimePlatform.Current.GlobalCancellationToken);
        await RunTask(soloTask, linkedCts.Token);
    }


    /// <summary>
    /// 运行独立任务
    /// </summary>
    /// <param name="soloTask">
    /// 支持的任务名称:
    /// - AutoGeniusInvokation: 启动自动七圣召唤任务
    /// - AutoWood: 启动自动伐木任务
    /// - AutoFight: 启动自动战斗任务
    /// - AutoDomain: 启动自动秘境任务
    /// </param>
    /// <param name="customCt">自定义取消令牌，允许从JS控制任务取消</param>
    /// <exception cref="ArgumentNullException"></exception>
    /// <exception cref="ArgumentException"></exception>
    public async Task<object?> RunTask(SoloTask soloTask, CancellationToken? customCt = null)
    {
        if (soloTask == null)
        {
            throw new ArgumentNullException(nameof(soloTask), "独立任务对象不能为空");
        }

        if (soloTask.Name is not (
            "AutoGeniusInvokation" or "AutoWood" or "AutoFight" or "AutoDomain" or
            "AutoBoss" or "AutoFishing" or "AutoCook" or "AutoEat" or "CountInventoryItem"))
            throw new ArgumentException($"未知的任务名称: {soloTask.Name}", nameof(soloTask.Name));

        var platform = DispatcherRuntimePlatform.Current;
        var cancellationToken = customCt ?? platform.GlobalCancellationToken;
        DispatcherSoloTaskRequest request;
        switch (soloTask.Name)
        {
            case "AutoGeniusInvokation":
                var strategy = soloTask.Config is ScriptObject geniusConfig
                    ? ScriptObjectConverter.GetValue(geniusConfig, "strategy", "")
                    : "";
                if (string.IsNullOrEmpty(strategy) && platform.GetTcgStrategy(out strategy)) return null;
                request = new DispatcherGeniusTaskRequest(strategy);
                break;
            case "AutoWood":
                request = new DispatcherWoodTaskRequest(platform.AutoWoodRoundNum, platform.AutoWoodDailyMaxCount);
                break;
            case "AutoFight":
                request = new DispatcherFightTaskRequest(_config);
                break;
            case "AutoDomain":
                if (platform.GetFightStrategy(null, out var domainPath)) return null;
                request = new DispatcherDomainTaskRequest(domainPath);
                break;
            case "AutoBoss":
                if (platform.GetFightStrategy(platform.AutoBossStrategyName, out var bossPath)) return null;
                request = new DispatcherBossTaskRequest(bossPath);
                break;
            case "AutoFishing":
                request = new DispatcherFishingTaskRequest(soloTask.Config);
                break;
            case "AutoCook":
                request = new DispatcherCookTaskRequest();
                break;
            case "AutoEat":
                var eatConfig = soloTask.Config as ScriptObject;
                var foodName = eatConfig is null
                    ? null : ScriptObjectConverter.GetValue(eatConfig, "foodName", (string?)null);
                var effect = eatConfig is null
                    ? null : (FoodEffectType?)ScriptObjectConverter.GetValue(
                        eatConfig, "foodEffectType", (int?)null);
                if (foodName is not null && effect is not null)
                    throw new NotSupportedException("不能同时指定foodName和foodEffectType");
                if (foodName is null && effect is not null)
                {
                    if (_config is not PathingPartyConfig partyConfig)
                        throw new NotSupportedException("foodEffectType参数需要调度器配置，请在调度器下使用");
                    foodName = effect switch
                    {
                        FoodEffectType.ATKBoostingDish => partyConfig.AutoEatConfig.DefaultAtkBoostingDishName,
                        FoodEffectType.AdventurersDish => partyConfig.AutoEatConfig.DefaultAdventurersDishName,
                        FoodEffectType.DEFBoostingDish => partyConfig.AutoEatConfig.DefaultDefBoostingDishName,
                        _ => throw new NotSupportedException("JS脚本入参错误：错误的foodEffectType")
                    };
                    if (foodName is null)
                    {
                        _logger.LogInformation("缺少默认料理配置，跳过吃Buff");
                        return null;
                    }
                }
                request = new DispatcherEatTaskRequest(foodName, platform.AutoEatSettings);
                break;
            case "CountInventoryItem":
                if (soloTask.Config is not ScriptObject countConfig)
                    throw new NullReferenceException($"{nameof(soloTask.Config)}为空");
                var screenName = ScriptObjectConverter.GetValue(
                    countConfig, "gridScreenName", (GridScreenName?)null)
                    ?? throw new Exception("gridScreenName为空或错误");
                request = new DispatcherCountInventoryTaskRequest(
                    (int)screenName,
                    ScriptObjectConverter.GetValue(countConfig, "itemName", (string?)null),
                    ScriptObjectConverter.GetValue<string>(countConfig, "itemNames")?.ToList() ?? []);
                break;
            default:
                throw new ArgumentException($"未知的任务名称: {soloTask.Name}", nameof(soloTask.Name));
        }
        return await platform.ExecuteSoloTask(request, cancellationToken);
    }

    public CancellationTokenSource GetLinkedCancellationTokenSource()
    {
        // 创建一个新的链接令牌源，链接到全局令牌
        return CancellationTokenSource.CreateLinkedTokenSource(DispatcherRuntimePlatform.Current.GlobalCancellationToken);
    }


    public CancellationToken GetLinkedCancellationToken()
    {
        return GetLinkedCancellationTokenSource().Token;
    }

    /// <summary>
    /// 运行自动秘境任务
    /// </summary>
    /// <param name="param">秘境任务参数</param>
    /// <param name="customCt">自定义取消令牌</param>
    /// <returns></returns>
    public async Task<object?> RunAutoDomainTask(object param, CancellationToken? customCt = null)
    {
        if (param == null)
        {
            throw new ArgumentNullException(nameof(param), "秘境任务参数不能为空");
        }

        CancellationToken cancellationToken = customCt ?? DispatcherRuntimePlatform.Current.GlobalCancellationToken;
        return await DispatcherRuntimePlatform.Current.RunParameterizedTask("AutoDomain", param, cancellationToken);
    }

    /// <summary>
    /// 运行自动首领讨伐任务
    /// </summary>
    /// <param name="param">自动首领讨伐任务参数</param>
    /// <param name="customCt">自定义取消令牌</param>
    /// <returns></returns>
    public async Task<object?> RunAutoBossTask(object param, CancellationToken? customCt = null)
    {
        if (param == null)
        {
            throw new ArgumentNullException(nameof(param), "自动首领讨伐任务参数不能为空");
        }

        CancellationToken cancellationToken = customCt ?? DispatcherRuntimePlatform.Current.GlobalCancellationToken;
        return await DispatcherRuntimePlatform.Current.RunParameterizedTask("AutoBoss", param, cancellationToken);
    }

    /// <summary>
    /// 运行自动战斗任务
    /// </summary>
    /// <param name="param">战斗任务参数</param>
    /// <param name="customCt">自定义取消令牌</param>
    /// <returns></returns>
    public async Task RunAutoFightTask(AutoFightParam param, CancellationToken? customCt = null)
    {
        if (param == null)
        {
            throw new ArgumentNullException(nameof(param), "战斗任务参数不能为空");
        }

        CancellationToken cancellationToken = customCt ?? DispatcherRuntimePlatform.Current.GlobalCancellationToken;
        await DispatcherRuntimePlatform.Current.RunParameterizedTask("AutoFight", param, cancellationToken);
    }

    /// <summary>
    /// 运行简易战斗策略脚本。
    /// 使用策略语言直接控制角色执行动作（如 e、q、attack 等），适合快速操作。
    /// </summary>
    /// <param name="script">策略字符串，支持逗号/换行/分号分隔指令，可选角色名前缀</param>
    /// <param name="avatarName">指定操作的角色名（可选，不指定则操作当前角色）</param>
    /// <param name="customCt">自定义取消令牌</param>
    public async Task RunCombatScript(string script, string? avatarName = null, CancellationToken? customCt = null)
    {
        if (string.IsNullOrWhiteSpace(script))
        {
            throw new ArgumentException("策略字符串不能为空", nameof(script));
        }

        CancellationToken cancellationToken = customCt ?? DispatcherRuntimePlatform.Current.GlobalCancellationToken;

        // 1. 解析策略字符串（ParseContext 已处理全角符号、注释、分号/逗号分隔）
        var combatScript = CombatScriptParser.ParseContext(script, validate: false, defaultAvatarName: avatarName);
        if (combatScript.CombatCommands.Count == 0) return;

        _logger.LogInformation("执行 {Text}", "简易策略脚本");

        await CombatScriptExecutor.ExecuteAsync(combatScript, cancellationToken, _logger);
    }

    /// <summary>
    /// 运行自动地脉花任务
    /// </summary>
    /// <param name="param">自动地脉花任务参数</param>
    /// <param name="customCt">自定义取消令牌</param>
    /// <returns></returns>
    public async Task RunAutoLeyLineOutcropTask(object param, CancellationToken? customCt = null)
    {
        if (param == null)
        {
            throw new ArgumentNullException(nameof(param), "自动地脉花任务参数不能为空");
        }

        CancellationToken cancellationToken = customCt ?? DispatcherRuntimePlatform.Current.GlobalCancellationToken;
        await DispatcherRuntimePlatform.Current.RunParameterizedTask("AutoLeyLineOutcrop", param, cancellationToken);
    }


    /// <summary>
    /// 运行自动幽境危战任务
    /// </summary>
    /// <param name="param">自动幽境危战任务参数</param>
    /// <param name="customCt">自定义取消令牌</param>
    /// <returns></returns>
    public async Task RunAutoStygianOnslaughtTask(object param, CancellationToken? customCt = null)
    {
        if (param == null)
        {
            throw new ArgumentNullException(nameof(param), "自动幽境危战任务参数不能为空");
        }

        CancellationToken cancellationToken = customCt ?? DispatcherRuntimePlatform.Current.GlobalCancellationToken;
        await DispatcherRuntimePlatform.Current.RunParameterizedTask("AutoStygianOnslaught", param, cancellationToken);
    }

    /// <summary>
    /// 运行背包物品计数任务。
    /// </summary>
    /// <param name="param">背包物品计数参数。</param>
    /// <param name="customCt">自定义取消令牌。</param>
    /// <returns>单物品返回数量；多物品返回名称到数量的脚本对象。</returns>
    public async Task<object?> RunCountInventoryItemTask(object param, CancellationToken? customCt = null)
    {
        if (param == null)
        {
            throw new ArgumentNullException(nameof(param), "背包物品计数参数不能为空");
        }

        CancellationToken cancellationToken = customCt ?? DispatcherRuntimePlatform.Current.GlobalCancellationToken;
        return await DispatcherRuntimePlatform.Current.RunParameterizedTask(
            "CountInventoryItem", param, cancellationToken);
    }
}
