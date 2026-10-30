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
        GameTaskManager.ClearTriggerRequests();
        _ = Invoke("window.metrics", null);
        inputCoordinator.WaitForGameFocus(hostCancellationToken);
        inputCoordinator.ReleaseAllWhenFocused(hostCancellationToken);
    }

    public void InitializeTask(CancellationToken cancellationToken)
    {
        InitializeTask(cancellationToken, waitForInput: true);
    }

    public void InitializeTask(CancellationToken cancellationToken, bool waitForInput)
    {
        GameTaskManager.ClearTriggerRequests();
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            hostCancellationToken, cancellationToken);
        _ = Invoke("window.metrics", null, linked.Token);
        if (waitForInput)
        {
            inputCoordinator.WaitForGameFocus(linked.Token);
            inputCoordinator.ReleaseAllWhenFocused(linked.Token);
        }
    }

    public void EndTask() => inputCoordinator.ReleaseAllWhenFocused(hostCancellationToken, includeOperationCancellation: false);

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

    private JToken Invoke(
        string method,
        JObject? parameters,
        CancellationToken cancellationToken = default) =>
        callbacks.InvokeAsync(
                method,
                parameters,
                sessionToken,
                cancellationToken.CanBeCanceled
                    ? cancellationToken
                    : hostCancellationToken)
            .GetAwaiter().GetResult()
        ?? throw new InvalidDataException($"{method} returned an empty response.");
}
