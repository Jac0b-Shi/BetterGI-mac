using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Verification.Framework;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class RuntimeCancellationSuite : IVerificationSuite
{
    public string Name => "runtime-cancellation";

    public async Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        var coordinator = new ForegroundInputCoordinator(
            new PlatformCallbackChannel(), "verification", CancellationToken.None,
            TimeSpan.FromMilliseconds(5), () => false);
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
    }
}
