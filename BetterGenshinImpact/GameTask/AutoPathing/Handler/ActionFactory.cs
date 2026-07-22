using System;
using System.Collections.Concurrent;
using System.Diagnostics.CodeAnalysis;
using BetterGenshinImpact.GameTask.AutoGeniusInvokation.Model;
using BetterGenshinImpact.GameTask.Common.Job;

namespace BetterGenshinImpact.GameTask.AutoPathing.Handler;

public class ActionFactory
{
    private static readonly ConcurrentDictionary<string, IActionHandler> _handlers = new();

    private static readonly IReadOnlyDictionary<string, AfterHandlerRegistration> AfterHandlerFactories =
        new Dictionary<string, AfterHandlerRegistration>(StringComparer.Ordinal)
        {
            ["nahida_collect"] = new(static () => new NahidaCollectHandler()),
            ["pick_around"] = new(static () => new PickAroundHandler()),
            ["fight"] = new(static () => new AutoFightHandler()),
#pragma warning disable CS0612 // These names remain part of the upstream route schema.
            ["normal_attack"] = new(static () => new NormalAttackHandler(), false),
            ["elemental_skill"] = new(static () => new ElementalSkillHandler(), false),
#pragma warning restore CS0612
            ["hydro_collect"] = new(static () => new ElementalCollectHandler(ElementalType.Hydro)),
            ["electro_collect"] = new(static () => new ElementalCollectHandler(ElementalType.Electro)),
            ["anemo_collect"] = new(static () => new ElementalCollectHandler(ElementalType.Anemo)),
            ["pyro_collect"] = new(static () => new ElementalCollectHandler(ElementalType.Pyro)),
            ["combat_script"] = new(static () => new CombatScriptHandler()),
            ["mining"] = new(static () => new MiningHandler()),
            ["linnea_mining"] = new(static () => new LinneaMiningHandler()),
            ["fishing"] = new(static () => new FishingHandler()),
            ["exit_and_relogin"] = new(static () => new ExitAndReloginHandler()),
            ["wonderland_cycle"] = new(static () => new EnterAndExitWonderlandHandler()),
            ["set_time"] = new(static () => new SetTimeHandler()),
            ["use_gadget"] = new(static () => new UseGadgetHandler()),
            ["pick_up_collect"] = new(static () => new PickUpCollectHandler())
        };

    private static readonly IReadOnlyDictionary<string, Func<IActionHandler>> BeforeHandlerFactories =
        new Dictionary<string, Func<IActionHandler>>(StringComparer.Ordinal)
        {
            ["up_down_grab_leaf"] = static () => new UpDownGrabLeafHandler(),
            ["stop_flying"] = static () => new StopFlyingHandler()
        };

    public static bool CanExecuteAfterWaypoint([NotNullWhen(true)] string? handlerType)
    {
        return handlerType is not null
               && AfterHandlerFactories.TryGetValue(handlerType, out var registration)
               && registration.ExecuteAfterWaypoint;
    }

    public static bool CanHandleBefore([NotNullWhen(true)] string? handlerType)
    {
        return handlerType is not null && BeforeHandlerFactories.ContainsKey(handlerType);
    }

    public static IActionHandler GetAfterHandler(string handlerType)
    {
        if (!AfterHandlerFactories.TryGetValue(handlerType, out var registration))
            throw new ArgumentException("未知的后置 action 类型", nameof(handlerType));

        return _handlers.GetOrAdd(
            handlerType,
            static (_, handlerRegistration) => handlerRegistration.Factory(),
            registration);
    }

    public static IActionHandler GetBeforeHandler(string handlerType)
    {
        if (!BeforeHandlerFactories.TryGetValue(handlerType, out var factory))
            throw new ArgumentException("未知的前置 action 类型", nameof(handlerType));

        return _handlers.GetOrAdd(handlerType, static (_, create) => create(), factory);
    }

    private sealed record AfterHandlerRegistration(
        Func<IActionHandler> Factory,
        bool ExecuteAfterWaypoint = true);
}
