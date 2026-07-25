using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Verification.Framework;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using System.Runtime.Versioning;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class ScriptStartupSuite : IVerificationSuite
{
    public string Name => "script-startup";

    [SupportedOSPlatform("macos")]
    public async Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var root = Path.Combine(
            Path.GetTempPath(), $"bettergi-script-startup-{Guid.NewGuid():N}");
        try
        {
            var layout = new RuntimeLayout(root);
            layout.EnsureCreated();
            using var loggerFactory = LoggerFactory.Create(_ => { });
            var callbacks = new PlatformCallbackChannel();
            var focusProbeCount = 0;
            var foreground = new ForegroundInputCoordinator(
                callbacks,
                "verification",
                cancellationToken,
                focusProbe: () =>
                {
                    focusProbeCount++;
                    return true;
                });
            var gameTaskManager = new MacGameTaskManagerPlatform(
                layout,
                callbacks,
                "verification",
                cancellationToken,
                loggerFactory);

            var runningDispatcherService = new MacScriptServicePlatform(
                layout,
                NullLogger.Instance,
                new MacScriptHostServices(loggerFactory),
                callbacks,
                "verification",
                cancellationToken,
                new SharedCaptureRingReader(layout, allowFileFixture: true),
                gameTaskManager,
                foreground,
                () => true);
            await runningDispatcherService.StartGameTask(waitForMainUi: true);
            context.Require(
                focusProbeCount == 0,
                "An already-running trigger dispatcher still entered the game startup wait.");

            var stoppedDispatcherService = new MacScriptServicePlatform(
                layout,
                NullLogger.Instance,
                new MacScriptHostServices(loggerFactory),
                callbacks,
                "verification",
                cancellationToken,
                new SharedCaptureRingReader(layout, allowFileFixture: true),
                gameTaskManager,
                foreground,
                () => false);
            await stoppedDispatcherService.StartGameTask(waitForMainUi: false);
            context.Require(
                focusProbeCount == 1,
                "Starting without the trigger dispatcher bypassed the foreground safety gate.");
        }
        finally
        {
            if (Directory.Exists(root))
                Directory.Delete(root, recursive: true);
        }
    }
}
