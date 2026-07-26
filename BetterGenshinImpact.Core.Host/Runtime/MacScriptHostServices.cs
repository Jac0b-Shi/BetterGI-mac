using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Core.Script.Group;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>macOS Core Host 的脚本进程上下文；调度器负责设置当前项目。</summary>
public sealed class MacScriptHostServices(ILoggerFactory loggerFactory) : IScriptHostServices
{
    private ScriptGroupProject? _currentProject;
    private TimeSpan? _serverTimeZoneOffset;
    private bool? _jsNotificationEnabled;
    private Action<ScriptNotificationKind, string>? _notificationEmitter;

    public ILogger CreateLogger(string categoryName) => loggerFactory.CreateLogger(categoryName);
    public ScriptGroupProject? CurrentProject => Volatile.Read(ref _currentProject);
    public TimeSpan ServerTimeZoneOffset => _serverTimeZoneOffset
        ?? throw new InvalidOperationException("Server time zone offset has not been initialized by core.initialize.");
    public bool JsNotificationEnabled => _jsNotificationEnabled
        ?? throw new InvalidOperationException("JS notification permission has not been initialized by core.initialize.");

    public void SetCurrentProject(ScriptGroupProject? project) => Volatile.Write(ref _currentProject, project);

    public void SetServerTimeZoneOffset(TimeSpan offset)
    {
        if (offset < TimeSpan.FromHours(-12) || offset > TimeSpan.FromHours(14))
            throw new ArgumentOutOfRangeException(nameof(offset), "Server time zone offset is outside the valid range.");
        _serverTimeZoneOffset = offset;
    }

    public void SetJsNotificationEnabled(bool enabled) => _jsNotificationEnabled = enabled;
    public void SetNotificationEmitter(Action<ScriptNotificationKind, string> emitter) =>
        _notificationEmitter = emitter ?? throw new ArgumentNullException(nameof(emitter));

    public void EmitNotification(ScriptNotificationKind kind, string message)
    {
        var emitter = _notificationEmitter
            ?? throw new InvalidOperationException("Notification emitter has not been initialized.");
        emitter(kind, message);
    }
}
