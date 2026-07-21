using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.GameTask;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

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

    public void NotifyCancellation(string message) => Notify("info", message);

    public void NotifyError(string message, Exception exception) =>
        Notify("error", $"{message}: {exception.Message}");

    private void Notify(string kind, string message) => RequireAcknowledgement(
        "notification.emit", JObject.FromObject(new { kind, message }));

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
