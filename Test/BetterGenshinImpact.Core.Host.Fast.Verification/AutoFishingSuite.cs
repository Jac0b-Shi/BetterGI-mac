using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask;
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

        var sessionBlackboard = new Blackboard();
        var sessionScreenshot = new TakeScreenshot(
            "session screenshot",
            NullLogger.Instance,
            sessionBlackboard);
        var trackingInput = new TrackingAutoFishingInput();
        BlockingInputBehaviour? blockingBehaviour = null;
        using var trigger = new AutoFishingTrigger(
            runtime: null!,
            NullLogger<AutoFishingTrigger>.Instance,
            trackingInput,
            guardedInput => blockingBehaviour = new BlockingInputBehaviour(guardedInput),
            sessionScreenshot);
        trigger.IsEnabled = true;
        trigger.IsExclusive = true;
        using var triggerFrame = new ImageRegion(
            new Mat(8, 8, MatType.CV_8UC4, Scalar.Black),
            0,
            0,
            drawContent: new NoopOverlayDrawPlatform());
        trigger.OnCapture(new CaptureContent(triggerFrame));

        await blockingBehaviour!.Entered.Task.WaitAsync(cancellationToken);
        context.Require(
            trackingInput.IsDown && trackingInput.LeftButtonDownCount == 1,
            "Auto-fishing verification did not enter the held-input state.");

        trigger.Dispose();
        context.Require(
            !trigger.IsEnabled && !trigger.IsExclusive &&
            !trackingInput.IsDown && trackingInput.ReleaseAllCount >= 1,
            "Disposing auto-fishing did not cancel the session and release held input.");

        blockingBehaviour.Continue.TrySetResult();
        await blockingBehaviour.Completed.Task.WaitAsync(cancellationToken);
        context.Require(
            trackingInput.LeftButtonDownCount == 1,
            "An in-flight auto-fishing tick emitted new input after disposal.");

        trigger.OnCapture(new CaptureContent(triggerFrame));
        await Task.Delay(25, cancellationToken);
        context.Require(
            blockingBehaviour.UpdateCount == 1,
            "Disposed auto-fishing started another behaviour-tree tick.");

        var idleBlackboard = new Blackboard();
        var idleScreenshot = new TakeScreenshot(
            "idle screenshot",
            NullLogger.Instance,
            idleBlackboard);
        var idleInput = new TrackingAutoFishingInput();
        using var idleTrigger = new AutoFishingTrigger(
            runtime: null!,
            NullLogger<AutoFishingTrigger>.Instance,
            idleInput,
            guardedInput => new BlockingInputBehaviour(guardedInput),
            idleScreenshot);
        idleTrigger.IsEnabled = true;
        idleTrigger.IsEnabled = false;
        context.Require(
            idleInput.ReleaseAllCount == 0,
            "Disabling idle auto-fishing released inputs it does not own.");

        var activeBlackboard = new Blackboard();
        var activeScreenshot = new TakeScreenshot(
            "active screenshot",
            NullLogger.Instance,
            activeBlackboard);
        var activeInput = new TrackingAutoFishingInput();
        BlockingInputBehaviour? activeBehaviour = null;
        using var activeTrigger = new AutoFishingTrigger(
            runtime: null!,
            NullLogger<AutoFishingTrigger>.Instance,
            activeInput,
            guardedInput => activeBehaviour = new BlockingInputBehaviour(guardedInput),
            activeScreenshot);
        activeTrigger.IsEnabled = true;
        activeTrigger.IsExclusive = true;
        using var activeFrame = new ImageRegion(
            new Mat(8, 8, MatType.CV_8UC4, Scalar.Black),
            0,
            0,
            drawContent: new NoopOverlayDrawPlatform());
        activeTrigger.OnCapture(new CaptureContent(activeFrame));

        await activeBehaviour!.Entered.Task.WaitAsync(cancellationToken);
        activeTrigger.IsEnabled = false;
        context.Require(
            !activeTrigger.IsExclusive && activeInput.ReleaseAllCount >= 1,
            "Disabling an active auto-fishing session did not cancel it and release held input.");

        activeBehaviour.Continue.TrySetResult();
        await activeBehaviour.Completed.Task.WaitAsync(cancellationToken);
    }

    private sealed class BlockingInputBehaviour(IAutoFishingInput input)
        : Behaviour("blocking input")
    {
        public TaskCompletionSource Entered { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Continue { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Completed { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);
        public int UpdateCount { get; private set; }

        protected override async Task<Status> Update()
        {
            UpdateCount++;
            input.LeftButtonDown();
            Entered.TrySetResult();
            try
            {
                await Continue.Task;
                input.LeftButtonDown();
                return Status.Running;
            }
            finally
            {
                Completed.TrySetResult();
            }
        }
    }

    private sealed class TrackingAutoFishingInput : IAutoFishingInput
    {
        public bool IsDown { get; private set; }
        public int LeftButtonDownCount { get; private set; }
        public int ReleaseAllCount { get; private set; }

        public void MoveMouseBy(int x, int y) { }
        public void LeftButtonDown()
        {
            LeftButtonDownCount++;
            IsDown = true;
        }
        public void LeftButtonUp() => IsDown = false;
        public void LeftButtonClick() { }
        public void RightButtonClick() { }
        public bool IsLeftButtonDown() => IsDown;
        public void PressEscape() { }
        public void PressInteraction() { }
        public void SetMoveForward(bool isDown) { }
        public void SetMoveBackward(bool isDown) { }
        public void ReleaseAll()
        {
            ReleaseAllCount++;
            IsDown = false;
        }
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
