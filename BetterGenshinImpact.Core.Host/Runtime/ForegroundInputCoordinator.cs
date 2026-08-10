using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.GameTask.Music.Service;
using Newtonsoft.Json.Linq;
using System.Diagnostics;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>Pauses macOS real input until the user returns focus to the selected game.</summary>
public sealed class ForegroundInputCoordinator(
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken hostCancellationToken,
    TimeSpan? pollInterval = null,
    Func<bool>? focusProbe = null,
    Func<bool>? inputAvailabilityProbe = null)
{
    private readonly TimeSpan _pollInterval = pollInterval ?? TimeSpan.FromMilliseconds(100);
    private static readonly TimeSpan TextForegroundStability =
        TimeSpan.FromMilliseconds(200);
    private readonly AsyncLocal<CancellationToken?> _operationCancellation = new();
    private int _releaseRequired;

    public IDisposable UseCancellationToken(CancellationToken cancellationToken)
    {
        var previous = _operationCancellation.Value;
        _operationCancellation.Value = cancellationToken;
        return new CancellationScope(_operationCancellation, previous);
    }

    public void WaitForGameFocus(CancellationToken cancellationToken = default)
    {
        using var linked = CreateLinkedCancellation(cancellationToken);
        while (true)
        {
            ThrowIfTaskCancelled(linked.Token);
            if (IsInputAvailable(linked.Token))
                return;

            Interlocked.Exchange(ref _releaseRequired, 1);
            Task.Delay(_pollInterval, linked.Token).GetAwaiter().GetResult();
        }
    }

    public void Dispatch(JObject parameters, CancellationToken cancellationToken = default)
    {
        using var linked = CreateLinkedCancellation(cancellationToken);
        var isTextInput = string.Equals(
            parameters.Value<string>("action"),
            "inputText",
            StringComparison.Ordinal);
        while (true)
        {
            if (isTextInput)
                WaitForHostForegroundForText(linked.Token);
            else
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
                when (string.Equals(
                    exception.Code,
                    "input_not_frontmost",
                    StringComparison.Ordinal))
            {
                if (!isTextInput)
                    Interlocked.Exchange(ref _releaseRequired, 1);
            }
        }
    }

    public void DispatchOnce(JObject parameters, CancellationToken cancellationToken = default)
    {
        using var linked = CreateLinkedCancellation(cancellationToken);
        if (!IsInputAvailable(linked.Token))
        {
            Interlocked.Exchange(ref _releaseRequired, 1);
            throw new MusicInputUnavailableException();
        }

        try
        {
            if (Interlocked.Exchange(ref _releaseRequired, 0) != 0)
            {
                RequireAcknowledgement(
                    "input.dispatch",
                    JObject.FromObject(new { action = "releaseAll" }),
                    linked.Token);
            }
            RequireAcknowledgement("input.dispatch", parameters, linked.Token);
        }
        catch (PlatformCallbackException exception)
            when (string.Equals(exception.Code, "input_not_frontmost", StringComparison.Ordinal))
        {
            Interlocked.Exchange(ref _releaseRequired, 1);
            throw new MusicInputUnavailableException(
                "The game lost input focus while dispatching a music key.", exception);
        }
    }

    private void WaitForHostForegroundForText(CancellationToken cancellationToken)
    {
        if (focusProbe is not null)
        {
            if (focusProbe())
                return;
            WaitForStableTextForeground(
                cancellationToken,
                () => (focusProbe(), true));
            return;
        }

        var initialMetrics = Metrics(cancellationToken);
        var initiallyActive = initialMetrics.Value<bool?>("isActive")
            ?? throw new InvalidDataException(
                "window.metrics did not return isActive.");
        if (!ShouldWaitForHostForegroundForText(
                initiallyActive,
                initialMetrics.Value<string>("backgroundTextInputPolicy")))
            return;

        WaitForStableTextForeground(
            cancellationToken,
            () =>
            {
                var metrics = Metrics(cancellationToken);
                var isActive = metrics.Value<bool?>("isActive")
                    ?? throw new InvalidDataException(
                        "window.metrics did not return isActive.");
                return (
                    isActive,
                    !string.Equals(
                        metrics.Value<string>("backgroundTextInputPolicy"),
                        "skipAndContinue",
                        StringComparison.Ordinal));
            });
    }

    private void WaitForStableTextForeground(
        CancellationToken cancellationToken,
        Func<(bool IsFocused, bool ShouldWait)> stateProbe)
    {
        long? stableSince = null;
        while (true)
        {
            ThrowIfTaskCancelled(cancellationToken);
            var state = stateProbe();
            if (!state.ShouldWait)
                return;
            if (!state.IsFocused)
            {
                stableSince = null;
            }
            else if (stableSince is null)
            {
                stableSince = Stopwatch.GetTimestamp();
            }
            else if (Stopwatch.GetElapsedTime(stableSince.Value) >= TextForegroundStability)
            {
                return;
            }

            Task.Delay(_pollInterval, cancellationToken).GetAwaiter().GetResult();
        }
    }

    public void ReleaseAllWhenFocused(
        CancellationToken cancellationToken = default,
        bool includeOperationCancellation = true)
    {
        using var linked = includeOperationCancellation
            ? CreateLinkedCancellation(cancellationToken)
            : CancellationTokenSource.CreateLinkedTokenSource(
                hostCancellationToken, cancellationToken);
        if (!IsInputAvailable(linked.Token))
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

    public bool IsGameFocused(CancellationToken cancellationToken = default) =>
        focusProbe?.Invoke()
        ?? Metrics(cancellationToken).Value<bool?>("isActive")
        ?? throw new InvalidDataException("window.metrics did not return isActive.");

    public bool IsInputAvailable(CancellationToken cancellationToken = default)
    {
        if (inputAvailabilityProbe is not null)
            return inputAvailabilityProbe();
        if (focusProbe is not null)
            return focusProbe();

        var metrics = Metrics(cancellationToken);
        var isActive = metrics.Value<bool?>("isActive")
            ?? throw new InvalidDataException("window.metrics did not return isActive.");
        var requiresHostForeground =
            metrics.Value<bool?>("inputRequiresHostForeground") ?? true;
        var supportsBackgroundDelivery =
            metrics.Value<bool?>("supportsBackgroundInputDelivery") == true;
        return EvaluateInputAvailability(
            isActive, requiresHostForeground, supportsBackgroundDelivery);
    }

    public static bool EvaluateInputAvailability(
        bool isActive,
        bool requiresHostForeground,
        bool supportsBackgroundDelivery) =>
        isActive || !requiresHostForeground && supportsBackgroundDelivery;

    public static bool ShouldWaitForHostForegroundForText(
        bool isActive,
        string? policy) =>
        !isActive &&
        !string.Equals(
            policy,
            "skipAndContinue",
            StringComparison.Ordinal);

    private CancellationTokenSource CreateLinkedCancellation(CancellationToken cancellationToken)
    {
        var operationCancellation = _operationCancellation.Value;
        return operationCancellation is { } operation
            ? CancellationTokenSource.CreateLinkedTokenSource(
                hostCancellationToken, cancellationToken, operation)
            : CancellationTokenSource.CreateLinkedTokenSource(
                hostCancellationToken, cancellationToken);
    }

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

    private sealed class CancellationScope(
        AsyncLocal<CancellationToken?> storage,
        CancellationToken? previous) : IDisposable
    {
        private int _disposed;

        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) == 0)
                storage.Value = previous;
        }
    }
}
