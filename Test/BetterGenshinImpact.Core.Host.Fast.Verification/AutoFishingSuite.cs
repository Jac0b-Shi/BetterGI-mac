using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Verification.Framework;
using CsTrees;
using CsTrees.Blackboard;
using Microsoft.Extensions.Logging.Abstractions;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class AutoFishingSuite : IVerificationSuite
{
    public string Name => "auto-fishing";

    public async Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var blackboard = new Blackboard();
        var source = new Mat(8, 8, MatType.CV_8UC4, Scalar.Black);
        var frame = new ImageRegion(source, 0, 0, drawContent: new NoopOverlayDrawPlatform());
        var captures = new Queue<ImageRegion?>([null, frame]);
        var takeScreenshot = new TakeScreenshot(
            "verification screenshot",
            NullLogger.Instance,
            blackboard)
        {
            CaptureFrame = () => captures.Dequeue(),
        };

        await takeScreenshot.TickOnce();
        context.Require(
            takeScreenshot.Status == Status.Running && !takeScreenshot.Screenshot.Exists(),
            "Auto-fishing ended the tree or retained a stale frame after a transient capture miss.");

        await takeScreenshot.TickOnce();
        context.Require(
            takeScreenshot.Status == Status.Success &&
            ReferenceEquals(takeScreenshot.Screenshot.Get(), frame),
            "Auto-fishing did not recover on the tick following a transient capture miss.");

        takeScreenshot.ReleaseFrame();
        context.Require(
            !takeScreenshot.Screenshot.Exists() && source.IsDisposed,
            "Auto-fishing did not clear the blackboard and dispose its final native frame.");

        Action<int> sleep = _ => { };
        var setSleep = new SetSleep("verification sleep", sleep, blackboard);
        await setSleep.TickOnce();
        context.Require(
            setSleep.Sleep.Exists() && ReferenceEquals(setSleep.Sleep.Get(), sleep),
            "Auto-fishing did not initialize the sleep callback.");
        blackboard.Clear();
        await setSleep.TickOnce();
        context.Require(
            setSleep.Sleep.Exists() && ReferenceEquals(setSleep.Sleep.Get(), sleep),
            "Auto-fishing did not restore the sleep callback after clearing the blackboard for a second time period.");
    }

    private sealed class NoopOverlayDrawPlatform : IOverlayDrawPlatform
    {
        public void SetRectangles(
            string name,
            Region source,
            IReadOnlyList<Rect> rectangles)
        {
        }

        public void RemoveRectangles(string name)
        {
        }

        public void ClearAll()
        {
        }
    }
}
