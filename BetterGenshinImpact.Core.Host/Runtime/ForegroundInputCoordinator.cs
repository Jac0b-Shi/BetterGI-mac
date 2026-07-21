using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Script;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>Pauses macOS real input until the user returns focus to the selected game.</summary>
public sealed class ForegroundInputCoordinator(
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken hostCancellationToken,
    TimeSpan? pollInterval = null,
    Func<bool>? focusProbe = null)
{
    private readonly TimeSpan _pollInterval = pollInterval ?? TimeSpan.FromMilliseconds(100);
    private int _releaseRequired;

    public void WaitForGameFocus(CancellationToken cancellationToken = default)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            hostCancellationToken, cancellationToken);
        while (true)
        {
            ThrowIfTaskCancelled(linked.Token);
            if (IsGameFocused(linked.Token))
                return;

            Interlocked.Exchange(ref _releaseRequired, 1);
            Task.Delay(_pollInterval, linked.Token).GetAwaiter().GetResult();
        }
    }

    public void Dispatch(JObject parameters, CancellationToken cancellationToken = default)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            hostCancellationToken, cancellationToken);
        while (true)
        {
            WaitForGameFocus(linked.Token);

            if (Interlocked.Exchange(ref _releaseRequired, 0) != 0)
                RequireAcknowledgement(
                    "input.dispatch", JObject.FromObject(new { action = "releaseAll" }), linked.Token);

            try
            {
                RequireAcknowledgement("input.dispatch", parameters, linked.Token);
                return;
            }
            catch (PlatformCallbackException exception)
                when (exception.Message.Contains("not frontmost", StringComparison.OrdinalIgnoreCase))
            {
                Interlocked.Exchange(ref _releaseRequired, 1);
            }
        }
    }

    public void ReleaseAllWhenFocused(CancellationToken cancellationToken = default)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            hostCancellationToken, cancellationToken);
        if (!IsGameFocused(linked.Token))
        {
            Interlocked.Exchange(ref _releaseRequired, 1);
            return;
        }

        RequireAcknowledgement(
            "input.dispatch", JObject.FromObject(new { action = "releaseAll" }), linked.Token);
        Interlocked.Exchange(ref _releaseRequired, 0);
    }

    private JObject Metrics(CancellationToken cancellationToken) =>
        callbacks.InvokeAsync("window.metrics", null, sessionToken, cancellationToken)
            .GetAwaiter().GetResult() as JObject
        ?? throw new InvalidDataException("window.metrics did not return an object.");

    private bool IsGameFocused(CancellationToken cancellationToken) => focusProbe?.Invoke()
        ?? Metrics(cancellationToken).Value<bool?>("isActive")
        ?? throw new InvalidDataException("window.metrics did not return isActive.");

    private void RequireAcknowledgement(
        string method, JObject parameters, CancellationToken cancellationToken)
    {
        var response = callbacks.InvokeAsync(method, parameters, sessionToken, cancellationToken)
            .GetAwaiter().GetResult();
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException($"{method} did not return acknowledged=true.");
    }

    private static void ThrowIfTaskCancelled(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (CancellationContext.Instance.IsCancellationRequested)
            throw new OperationCanceledException("BetterGI task was cancelled while waiting for game focus.");
    }
}
