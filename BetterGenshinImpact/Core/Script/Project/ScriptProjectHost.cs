using Microsoft.ClearScript;
using System;
using System.Threading;

namespace BetterGenshinImpact.Core.Script.Project;

public interface IScriptProjectHostInitializer
{
    void Initialize(IScriptEngine engine, string workDir, string[] searchPaths, object? config);
    void SetGameMetrics(int width, int height);
}

/// <summary>
/// Composition boundary for script host objects. The shared ScriptProject keeps
/// BetterGI module semantics; platform composition supplies input/capture/UI
/// capabilities explicitly.
/// </summary>
public static class ScriptProjectHost
{
    private static IScriptProjectHostInitializer? _initializer;

    public static void Configure(IScriptProjectHostInitializer initializer)
    {
        ArgumentNullException.ThrowIfNull(initializer);
        if (Interlocked.CompareExchange(ref _initializer, initializer, null) is not null)
            throw new InvalidOperationException("ScriptProject host has already been configured.");
    }

    public static void Initialize(IScriptEngine engine, string workDir, string[] searchPaths, object? config)
    {
        var initializer = Volatile.Read(ref _initializer)
            ?? throw new InvalidOperationException(
                "ScriptProject host is not composed. Configure the complete platform host before executing scripts.");
        initializer.Initialize(engine, workDir, searchPaths, config);
    }

    public static void SetGameMetrics(int width, int height)
    {
        var initializer = Volatile.Read(ref _initializer)
            ?? throw new InvalidOperationException(
                "ScriptProject host is not composed. Configure the complete platform host before executing scripts.");
        initializer.SetGameMetrics(width, height);
    }
}
