using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Script.Dependence.Model.TimerConfig;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.AutoPick.Assets;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Platform.Abstractions;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Composition;

/// <summary>
/// macOS AutoPick composition root. Assembles the full trigger object graph
/// (config provider, runtime state, assets, trigger) in a single one-shot Compose call.
/// </summary>
public sealed class MacAutoPickComposition
{
    private enum CompositionState { NotComposed, Composing, Composed, Failed }
    private static CompositionState _state = CompositionState.NotComposed;
    private static readonly object StateLock = new();

    public AutoPickTrigger Trigger { get; }

    private MacAutoPickComposition(AutoPickTrigger trigger)
    {
        Trigger = trigger;
    }

    /// <summary>
    /// Compose a fully-wired AutoPickTrigger for macOS.
    /// Call exactly once per process lifetime.
    /// </summary>
    /// <param name="configProvider">AutoPick configuration provider.</param>
    /// <param name="runtimeState">AutoPick runtime state (StopCount coordination).</param>
    /// <param name="externalConfig">Optional script-layer override config.</param>
    /// <param name="inputBackend">Platform input backend.</param>
    public static MacAutoPickComposition Compose(
        IAutoPickConfigProvider configProvider,
        IAutoPickRuntimeState runtimeState,
        IInputBackend inputBackend,
        ISystemInfo systemInfo,
        ILogger<AutoPickAssets> autoPickAssetsLogger,
        ILogger<AutoPickTrigger> autoPickTriggerLogger,
        IPaddleAutoPickTextRecognizer paddleRecognizer,
        IYapAutoPickTextRecognizer yapRecognizer,
        AutoPickExternalConfig? externalConfig = null)
    {
        // Validate arguments BEFORE touching any static state.
        // Null args are a caller bug, not a composition failure — must not
        // transition the state machine to Failed.
        ArgumentNullException.ThrowIfNull(configProvider);
        ArgumentNullException.ThrowIfNull(runtimeState);
        ArgumentNullException.ThrowIfNull(inputBackend);
        ArgumentNullException.ThrowIfNull(systemInfo);
        ArgumentNullException.ThrowIfNull(autoPickAssetsLogger);
        ArgumentNullException.ThrowIfNull(autoPickTriggerLogger);
        ArgumentNullException.ThrowIfNull(paddleRecognizer);
        ArgumentNullException.ThrowIfNull(yapRecognizer);

        lock (StateLock)
        {
            ThrowIfCannotCompose();
            _state = CompositionState.Composing;
        }

        try
        {
            var trigger = new AutoPickTrigger(externalConfig, runtimeState, configProvider, inputBackend, systemInfo, autoPickTriggerLogger, paddleRecognizer, yapRecognizer);
            trigger.Init();

            lock (StateLock)
            {
                _state = CompositionState.Composed;
            }
            return new MacAutoPickComposition(trigger);
        }
        catch
        {
            lock (StateLock)
            {
                _state = CompositionState.Failed;
            }
            throw;
        }
    }

    private static void ThrowIfCannotCompose()
    {
        switch (_state)
        {
            case CompositionState.Composing:
                throw new InvalidOperationException(
                    "MacAutoPickComposition is already being composed.");
            case CompositionState.Composed:
                throw new InvalidOperationException(
                    "MacAutoPickComposition has already been composed. " +
                    "Restart the application.");
            case CompositionState.Failed:
                throw new InvalidOperationException(
                    "Previous macOS AutoPick composition failed. " +
                    "Restart the process.");
        }
    }

    /// <summary>
    /// For verification tests only. Resets composition state so tests
    /// can run Compose() multiple times in a single process.
    /// </summary>
    internal static void ResetForVerification()
    {
        lock (StateLock)
        {
            _state = CompositionState.NotComposed;
        }
    }
}
