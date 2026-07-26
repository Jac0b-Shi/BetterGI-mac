using BetterGenshinImpact.Core.Script.Group;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;

namespace BetterGenshinImpact.Core.Script.Dependence;

public interface IScriptHostServices
{
    ILogger CreateLogger(string categoryName);
    ScriptGroupProject? CurrentProject { get; }
    TimeSpan ServerTimeZoneOffset { get; }
    bool JsNotificationEnabled { get; }
    void EmitNotification(ScriptNotificationKind kind, string message);
}

public enum ScriptNotificationKind
{
    Success,
    Error
}

/// <summary>脚本业务对象所需的进程上下文组合点；未组合时必须失败。</summary>
public static class ScriptHostServices
{
    private static IScriptHostServices? _current;

    public static void Configure(IScriptHostServices services)
    {
        ArgumentNullException.ThrowIfNull(services);
        if (Interlocked.CompareExchange(ref _current, services, null) is not null)
            throw new InvalidOperationException("Script host services have already been configured.");
    }

    public static ILogger CreateLogger<T>() => Current.CreateLogger(typeof(T).FullName ?? typeof(T).Name);
    public static ScriptGroupProject? CurrentProject => Current.CurrentProject;
    public static TimeSpan ServerTimeZoneOffset => Current.ServerTimeZoneOffset;
    public static DateTimeOffset ServerTimeNow => DateTimeOffset.UtcNow.ToOffset(Current.ServerTimeZoneOffset);
    public static bool JsNotificationEnabled => Current.JsNotificationEnabled;
    public static void EmitNotification(ScriptNotificationKind kind, string message) =>
        Current.EmitNotification(kind, message);

    private static IScriptHostServices Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException(
            "Script host services are not composed. Configure the complete runtime before creating script host objects.");
}
