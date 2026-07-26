using BetterGenshinImpact.GameTask.Screenshot;
using BetterGenshinImpact.Verification.Framework;
using Microsoft.Extensions.Logging.Abstractions;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class GameScreenshotSuite : IVerificationSuite
{
    public string Name => "game-screenshot";

    public Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var root = Path.Combine(
            Path.GetTempPath(), $"bettergi-screenshot-{Guid.NewGuid():N}");
        try
        {
            var platform = new RecordingScreenshotPlatform(root);
            var task = new GameScreenshotTask(
                platform,
                NullLogger<GameScreenshotTask>.Instance,
                new FixedTimeProvider(
                    new DateTimeOffset(
                        2026, 7, 24, 12, 34, 56, 789, TimeSpan.Zero)));
            var path = task.TakeScreenshot();
            context.Require(
                path == Path.Combine(root, "202607241234567890.png") &&
                File.Exists(path),
                "Game screenshot did not preserve the upstream timestamped PNG contract.");

            using var saved = Cv2.ImRead(path, ImreadModes.Unchanged);
            context.Require(
                !saved.Empty() &&
                saved.Width == 1920 &&
                saved.Height == 1080 &&
                saved.Channels() == 3 &&
                saved.At<Vec3b>(1060, 1700) ==
                    new Vec3b(255, 255, 255) &&
                saved.At<Vec3b>(100, 100) ==
                    new Vec3b(1, 2, 3),
                "Game screenshot did not apply only the shared upstream UID cover.");
        }
        finally
        {
            if (Directory.Exists(root))
                Directory.Delete(root, recursive: true);
        }
        return Task.CompletedTask;
    }

    private sealed class RecordingScreenshotPlatform(string directory)
        : IGameScreenshotRuntimePlatform
    {
        public string ScreenshotDirectory => directory;
        public bool ScreenshotUidCoverEnabled => true;
        public double ScaleTo1080PRatio => 1;

        public Mat Capture() =>
            new(1080, 1920, MatType.CV_8UC4, new Scalar(1, 2, 3, 255));
    }

    private sealed class FixedTimeProvider(DateTimeOffset utcNow)
        : TimeProvider
    {
        public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Utc;
        public override DateTimeOffset GetUtcNow() => utcNow;
    }
}
