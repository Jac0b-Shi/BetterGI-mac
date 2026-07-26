using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.Service.Notification.Model.Enum;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using NotifyService = BetterGenshinImpact.Service.Notification.Notify;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>macOS lifecycle effects for the shared upstream TaskRunner.</summary>
public sealed class MacTaskRunnerPlatform(
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken hostCancellationToken,
    ILogger logger,
    ILogger runnerLogger,
    ForegroundInputCoordinator inputCoordinator) : ITaskRunnerPlatform
{
    public ILogger Logger { get; } = logger;
    public ILogger RunnerLogger { get; } = runnerLogger;
    public SemaphoreSlim TaskSemaphore { get; } = new(1, 1);
    public bool RethrowUnexpectedExceptions => true;
    public bool ThrowOnLockFailure => true;

    public void InitializeTask()
    {
        _ = Invoke("window.metrics", null);
        inputCoordinator.WaitForGameFocus(hostCancellationToken);
    }

    public void EndTask() => inputCoordinator.ReleaseAllWhenFocused(hostCancellationToken);

    public void NotifyCancellation(string message) =>
        NotifyService.Event(NotificationEvent.TaskCancel).Success(message);

    public void NotifyError(string message, Exception exception) =>
        NotifyService.Event(NotificationEvent.TaskError).Error(message, exception);

    private void RequireAcknowledgement(string method, JObject? parameters)
    {
        var response = Invoke(method, parameters);
        if (response.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException($"{method} did not return acknowledged=true.");
    }

    private JToken Invoke(string method, JObject? parameters) =>
        callbacks.InvokeAsync(method, parameters, sessionToken, hostCancellationToken)
            .GetAwaiter().GetResult()
        ?? throw new InvalidDataException($"{method} returned an empty response.");
}
