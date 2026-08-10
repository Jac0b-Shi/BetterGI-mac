using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Host.Protocol;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.GameTask.Music.Service;
using BetterGenshinImpact.Verification.Framework;
using Newtonsoft.Json.Linq;
using System.Net.Sockets;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class RuntimeCancellationSuite : IVerificationSuite
{
    public string Name => "runtime-cancellation";

    public async Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        context.Require(
            ForegroundInputCoordinator.EvaluateInputAvailability(
                true, true, false),
            "Foreground input was rejected.");
        context.Require(
            !ForegroundInputCoordinator.EvaluateInputAvailability(
                false, true, false),
            "A foreground-only backend bypassed the host foreground gate.");
        context.Require(
            ForegroundInputCoordinator.EvaluateInputAvailability(
                false, false, true),
            "A validated background-delivery capability was rejected.");
        context.Require(
            !ForegroundInputCoordinator.EvaluateInputAvailability(
                false, false, false),
            "A backend without background-delivery support bypassed the gate.");
        context.Require(
            ForegroundInputCoordinator.ShouldWaitForHostForegroundForText(
                false, "waitForForeground") &&
            ForegroundInputCoordinator.ShouldWaitForHostForegroundForText(
                false, null) &&
            !ForegroundInputCoordinator.ShouldWaitForHostForegroundForText(
                false, "skipAndContinue") &&
            !ForegroundInputCoordinator.ShouldWaitForHostForegroundForText(
                true, "waitForForeground"),
            "Background text input policy did not preserve wait and skip semantics.");

        var coordinator = new ForegroundInputCoordinator(
            new PlatformCallbackChannel(), "verification", CancellationToken.None,
            TimeSpan.FromMilliseconds(5), () => false);
        var musicDispatchRejected = false;
        try
        {
            coordinator.DispatchOnce(JObject.FromObject(new { action = "keyDown" }));
        }
        catch (MusicInputUnavailableException)
        {
            musicDispatchRejected = true;
        }
        context.Require(
            musicDispatchRejected,
            "Music key dispatch waited for focus instead of reporting temporary unavailability.");
        using var operationCancellation = new CancellationTokenSource();
        var wait = Task.Run(() =>
        {
            using var scope = coordinator.UseCancellationToken(operationCancellation.Token);
            coordinator.WaitForGameFocus();
        }, cancellationToken);

        await Task.Delay(25, cancellationToken);
        context.Require(!wait.IsCompleted,
            "Unfocused input did not wait for the selected game.");
        operationCancellation.Cancel();
        try
        {
            await wait;
            throw new InvalidDataException(
                "Task cancellation did not interrupt the foreground wait.");
        }
        catch (OperationCanceledException)
        {
        }

        var diagnosticCoordinator = new ForegroundInputCoordinator(
            new PlatformCallbackChannel(), "verification", CancellationToken.None,
            TimeSpan.FromMilliseconds(5), () => false, () => true);
        diagnosticCoordinator.WaitForGameFocus(cancellationToken);

        CancellationContext.Instance.Set();
        var scriptCancellation = CancellationContext.Instance.Cts.Token;
        CancellationContext.Instance.ManualCancel();
        context.Require(
            scriptCancellation.IsCancellationRequested &&
            CancellationContext.Instance.IsManualStop,
            "Scheduler stop did not cancel the upstream script cancellation context.");
        CancellationContext.Instance.Clear();
        CancellationContext.Instance.Set();

        var cleanupCount = 0;
        using var dispatcherCancellation = new CancellationTokenSource();
        var dispatcher = new MacTriggerDispatcher(
            Microsoft.Extensions.Logging.Abstractions.NullLogger<MacTriggerDispatcher>.Instance,
            dispatcherCancellation.Token,
            token => Task.Delay(Timeout.InfiniteTimeSpan, token),
            _ =>
            {
                Interlocked.Increment(ref cleanupCount);
                return Task.CompletedTask;
            });
        dispatcher.Start();
        await dispatcher.StopAsync(cancellationToken);
        context.Require(
            cleanupCount == 1 && !dispatcher.IsRunning,
            "Runtime stop did not close the platform-owned HTML masks.");

        await VerifyTriggerStopCancellation(context, cancellationToken);
        await VerifyInFlightPlatformCallbackCancellation(context, cancellationToken);
        await VerifyPlatformCallbackTimeoutOverrides(context, cancellationToken);
        await VerifyPlatformCallbackTimeout(context, cancellationToken);
    }

    private static async Task VerifyTriggerStopCancellation(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var releaseLoop = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var dispatcher = new MacTriggerDispatcher(
            Microsoft.Extensions.Logging.Abstractions.NullLogger<MacTriggerDispatcher>.Instance,
            cancellationToken,
            _ => releaseLoop.Task);
        dispatcher.Start();
        using var stopCancellation = new CancellationTokenSource(
            TimeSpan.FromMilliseconds(50));
        try
        {
            await dispatcher.StopAsync(stopCancellation.Token);
            throw new InvalidDataException(
                "Trigger dispatcher stop ignored caller cancellation.");
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            releaseLoop.TrySetResult();
        }
        await dispatcher.StopAsync(cancellationToken);
        context.Require(
            !dispatcher.IsRunning,
            "Trigger dispatcher did not finish after its blocked loop was released.");
    }

    private static async Task VerifyInFlightPlatformCallbackCancellation(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var socketPath = $"/tmp/bgi-callback-{Guid.NewGuid():N}.sock";
        using var listener = new Socket(
            AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
        try
        {
            listener.Bind(new UnixDomainSocketEndPoint(socketPath));
            listener.Listen(1);

            using var swiftSocket = new Socket(
                AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
            var connectTask = swiftSocket.ConnectAsync(
                new UnixDomainSocketEndPoint(socketPath), cancellationToken);
            using var coreSocket = await listener.AcceptAsync(cancellationToken);
            await connectTask;

            await using var coreConnection = new FramedJsonConnection(coreSocket);
            await using var swiftConnection = new FramedJsonConnection(swiftSocket);
            var callbacks = new PlatformCallbackChannel();
            var attached = callbacks.AttachAsync(
                coreConnection, CancellationToken.None);

            using var operationCancellation = new CancellationTokenSource();
            var firstInvoke = callbacks.InvokeAsync(
                "capture.request", null, "verification",
                operationCancellation.Token);
            var firstRequest = await swiftConnection.ReadRequestAsync(cancellationToken)
                ?? throw new EndOfStreamException(
                    "Core did not send the first platform callback.");
            operationCancellation.Cancel();
            await swiftConnection.WriteResponseAsync(
                RpcResponse.Success(firstRequest.Id, new { acknowledged = true }),
                cancellationToken);

            try
            {
                await firstInvoke;
                throw new InvalidDataException(
                    "Cancelled platform callback completed successfully.");
            }
            catch (OperationCanceledException)
            {
            }

            context.Require(
                callbacks.IsAttached,
                "Cancelling an in-flight platform callback detached the shared channel.");

            var secondInvoke = callbacks.InvokeAsync(
                "htmlMask.closeAll", null, "verification", cancellationToken);
            var secondRequest = await swiftConnection.ReadRequestAsync(cancellationToken)
                ?? throw new EndOfStreamException(
                    "Core did not send the second platform callback.");
            await swiftConnection.WriteResponseAsync(
                RpcResponse.Success(secondRequest.Id, JObject.FromObject(new
                {
                    acknowledged = true,
                })),
                cancellationToken);
            var secondResult = await secondInvoke;
            context.Require(
                secondResult?.Value<bool>("acknowledged") == true,
                "Platform callback channel could not be reused after cancellation.");

            callbacks.Detach(coreConnection);
            await attached;
        }
        finally
        {
            try { File.Delete(socketPath); }
            catch { }
        }
    }

    private static async Task VerifyPlatformCallbackTimeout(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var socketPath = $"/tmp/bgi-callback-timeout-{Guid.NewGuid():N}.sock";
        using var listener = new Socket(
            AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
        try
        {
            listener.Bind(new UnixDomainSocketEndPoint(socketPath));
            listener.Listen(1);
            using var swiftSocket = new Socket(
                AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
            var connectTask = swiftSocket.ConnectAsync(
                new UnixDomainSocketEndPoint(socketPath), cancellationToken);
            using var coreSocket = await listener.AcceptAsync(cancellationToken);
            await connectTask;

            await using var coreConnection = new FramedJsonConnection(coreSocket);
            await using var swiftConnection = new FramedJsonConnection(swiftSocket);
            var callbacks = new PlatformCallbackChannel(
                TimeSpan.FromMilliseconds(50));
            var attached = callbacks.AttachAsync(
                coreConnection, CancellationToken.None);
            var invoke = callbacks.InvokeAsync(
                "capture.request", null, "verification", cancellationToken);
            _ = await swiftConnection.ReadRequestAsync(cancellationToken)
                ?? throw new EndOfStreamException(
                    "Core did not send the timed platform callback.");

            try
            {
                await invoke;
                throw new InvalidDataException(
                    "Platform callback response timeout was not enforced.");
            }
            catch (TimeoutException)
            {
            }

            context.Require(
                !callbacks.IsAttached,
                "A timed-out platform callback left the shared channel attached.");
            await attached;
        }
        finally
        {
            try { File.Delete(socketPath); }
            catch { }
        }
    }

    private static async Task VerifyPlatformCallbackTimeoutOverrides(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var socketPath = $"/tmp/bgi-callback-timeout-override-{Guid.NewGuid():N}.sock";
        using var listener = new Socket(
            AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
        try
        {
            listener.Bind(new UnixDomainSocketEndPoint(socketPath));
            listener.Listen(1);
            using var swiftSocket = new Socket(
                AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
            var connectTask = swiftSocket.ConnectAsync(
                new UnixDomainSocketEndPoint(socketPath), cancellationToken);
            using var coreSocket = await listener.AcceptAsync(cancellationToken);
            await connectTask;

            await using var coreConnection = new FramedJsonConnection(coreSocket);
            await using var swiftConnection = new FramedJsonConnection(swiftSocket);
            var callbacks = new PlatformCallbackChannel(TimeSpan.FromMilliseconds(50));
            var attached = callbacks.AttachAsync(coreConnection, CancellationToken.None);

            var infiniteInvoke = callbacks.InvokeAsync(
                "htmlMask.receive", JObject.FromObject(new { timeoutMs = 0 }),
                "verification", cancellationToken, Timeout.InfiniteTimeSpan);
            var infiniteRequest = await swiftConnection.ReadRequestAsync(cancellationToken)
                ?? throw new EndOfStreamException(
                    "Core did not send the infinite platform callback.");
            await Task.Delay(100, cancellationToken);
            context.Require(
                !infiniteInvoke.IsCompleted && callbacks.IsAttached,
                "An infinite HTML mask callback used the default response timeout.");
            await swiftConnection.WriteResponseAsync(
                RpcResponse.Success(infiniteRequest.Id, new { acknowledged = true }),
                cancellationToken);
            await infiniteInvoke;

            var extendedInvoke = callbacks.InvokeAsync(
                "htmlMask.request", JObject.FromObject(new { timeoutMs = 200 }),
                "verification", cancellationToken, TimeSpan.FromMilliseconds(250));
            var extendedRequest = await swiftConnection.ReadRequestAsync(cancellationToken)
                ?? throw new EndOfStreamException(
                    "Core did not send the extended platform callback.");
            await Task.Delay(100, cancellationToken);
            context.Require(
                !extendedInvoke.IsCompleted && callbacks.IsAttached,
                "A caller-defined platform callback deadline was replaced by the default timeout.");
            await swiftConnection.WriteResponseAsync(
                RpcResponse.Success(extendedRequest.Id, new { acknowledged = true }),
                cancellationToken);
            await extendedInvoke;

            callbacks.Detach(coreConnection);
            await attached;
        }
        finally
        {
            try { File.Delete(socketPath); }
            catch { }
        }
    }
}
