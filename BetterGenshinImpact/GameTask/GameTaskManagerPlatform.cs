using System;
using System.Collections.Generic;
using System.Threading;
using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Platform.Abstractions;

namespace BetterGenshinImpact.GameTask;

public interface IGameTaskManagerPlatform
{
    ISystemInfo SystemInfo { get; }
    IReadOnlyList<KeyValuePair<string, ITaskTrigger>> CreateInitialTriggers(
        IInputBackend inputBackend, ISystemInfo systemInfo, IAutoPickRuntimeState runtimeState,
        IAutoPickConfigProvider autoPickConfigProvider,
        IPaddleAutoPickTextRecognizer paddleRecognizer, IYapAutoPickTextRecognizer yapRecognizer);
    KeyValuePair<string, ITaskTrigger>? CreateTrigger(
        string name, object? externalConfig, IAutoPickRuntimeState runtimeState,
        IInputBackend inputBackend, ISystemInfo systemInfo,
        IAutoPickConfigProvider autoPickConfigProvider,
        IPaddleAutoPickTextRecognizer paddleRecognizer, IYapAutoPickTextRecognizer yapRecognizer);
    void ReloadAssets();
    void ClearOverlay();
}

public static class GameTaskManagerPlatform
{
    private static IGameTaskManagerPlatform? _current;
    public static IGameTaskManagerPlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("GameTaskManager platform has not been composed.");

    public static void Configure(IGameTaskManagerPlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("GameTaskManager platform has already been configured.");
    }
}
