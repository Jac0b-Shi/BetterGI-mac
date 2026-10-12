using BetterGenshinImpact.Core.Host.Runtime;
using Microsoft.Extensions.Logging.Abstractions;
using System.Collections.Concurrent;
using BetterGenshinImpact.Core.Input;
using BetterGenshinImpact.Core.Mask;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.Verification.Framework;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class InputMaskLifecycleSuite : IVerificationSuite
{
    public string Name => "input-mask-lifecycle";
    public async Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        using var channel = new BlockingChannel();
        var down = Task.Run(() => channel.KeyDown(65), cancellationToken);
        context.Require(channel.DownEntered.Wait(TimeSpan.FromSeconds(5)), "Input did not enter the backend.");
        var release = Task.Run(channel.ReleaseAll, cancellationToken);
        channel.AllowDown.Set();
        await Task.WhenAll(down, release).WaitAsync(TimeSpan.FromSeconds(5), cancellationToken);
        context.Require(channel.Events.SequenceEqual(new[] { "down:65", "up:65" }) && !channel.IsKeyDown(65),
            "Release raced ahead of an in-flight key-down or lost input ownership.");
        channel.KeyDown(66);
        channel.ReleaseAll();
        channel.ReleaseAll();
        context.Require(channel.Events.SequenceEqual(new[] { "down:65", "up:65", "down:66", "up:66" }),
            "ReleaseAll released unrelated keys or repeated a completed release.");

        GameTaskManager.ClearTriggerRequests();
        using (var first = GameTaskManager.RequestTriggerLease("lease-contract", "first"))
        {
            using (GameTaskManager.RequestTriggerLease("lease-contract", "second"))
                context.Require(Equals(GameTaskManager.RequestedTriggers["lease-contract"].Options, "second"), "Latest trigger owner was not selected.");
            context.Require(Equals(GameTaskManager.RequestedTriggers["lease-contract"].Options, "first"), "Nested trigger lease did not restore its live owner.");
        }
        context.Require(!GameTaskManager.RequestedTriggers.ContainsKey("lease-contract"), "Disposed trigger owner remained requested.");

        var original = GameTaskManager.TriggerDictionary;
        var trigger = new LifecycleTrigger();
        var taskRunning = false;
        var dispatcher = new MacTriggerDispatcher(NullLogger<MacTriggerDispatcher>.Instance, cancellationToken,
            isTaskRunning: () => taskRunning);
        try
        {
            GameTaskManager.TriggerDictionary = new ConcurrentDictionary<string, ITaskTrigger>(
                [new KeyValuePair<string, ITaskTrigger>("lifecycle-contract", trigger)]);
            dispatcher.UpdateLifecycle(true);
            dispatcher.UpdateLifecycle(true);
            dispatcher.UpdateLifecycle(false);
            context.Require(trigger.Events.SequenceEqual(new[] { "enable", "disable" }), "Focus loss did not disable the trigger exactly once.");
            dispatcher.UpdateLifecycle(true);
            GameTaskManager.RequestRefresh("lifecycle-contract");
            dispatcher.UpdateLifecycle(true);
            taskRunning = true;
            dispatcher.UpdateLifecycle(true);
            using (GameTaskManager.RequestTriggerLease("lifecycle-contract", null)) dispatcher.UpdateLifecycle(true);
            dispatcher.UpdateLifecycle(true);
            context.Require(trigger.Events.SequenceEqual(new[] { "enable", "disable", "enable", "disable", "enable", "disable", "enable", "disable" }),
                "Refresh or task-request edges did not complete trigger cleanup before re-enabling.");
        }
        finally
        {
            GameTaskManager.TriggerDictionary = original;
            dispatcher.UpdateLifecycle(false);
        }

        new BetterGenshinImpact.GameTask.Model.Area.Region(0, 0, 10, 10).DrawSelf("offscreen-contract");
        var board = new MaskWindowDrawingBoard();
        var shapes = new List<MaskWindowDrawingShape> { new MaskWindowDrawingRect(new MaskRect(1, 2, 3, 4)) };
        board.Set("rect", shapes);
        shapes.Clear();
        board.Set(new MaskWindowDrawingGroup("text", MaskWindowDrawingKind.Feature),
            [new MaskWindowDrawingText("CD", new MaskPoint(5, 6))]);
        var snapshot = board.Current;
        board.Clear("rect");
        context.Require(snapshot.Entries.Count == 2 && snapshot.Entries.Single(x => x.Group.Name == "rect").Shapes.Count == 1 &&
            board.Current.Entries.Single().Group.Name == "text", "Drawing removal changed an unrelated group or mutated a published snapshot.");
        board.ClearAll();
        context.Require(board.Current.IsEmpty && board.Current.Version > snapshot.Version, "Drawing clear did not publish an empty snapshot.");
    }

    private sealed class LifecycleTrigger : ITaskTrigger
    {
        public string Name => "lifecycle-contract";
        public int Priority => 0;
        public bool IsEnabledByConfig => true;
        public bool IsExclusive => false;
        public List<string> Events { get; } = [];
        public void OnEnabled(object? options) => Events.Add("enable");
        public void OnDisabled() => Events.Add("disable");
        public void OnCapture(CaptureContent content) { }
    }

    private sealed class BlockingChannel : InputChannelBase, IDisposable
    {
        public ManualResetEventSlim DownEntered { get; } = new();
        public ManualResetEventSlim AllowDown { get; } = new();
        public List<string> Events { get; } = [];
        protected override void OnKeyDown(int key)
        {
            DownEntered.Set();
            if (!AllowDown.Wait(TimeSpan.FromSeconds(5))) throw new TimeoutException();
            Events.Add($"down:{key}");
        }
        protected override void OnKeyUp(int key) => Events.Add($"up:{key}");
        protected override void OnMouseButton(InputMouseButton button, bool down) { }
        protected override void OnMoveBy(int dx, int dy) { }
        protected override void OnMoveTo(double x, double y) { }
        protected override void OnScroll(int clicks) { }
        public void Dispose() { DownEntered.Dispose(); AllowDown.Dispose(); }
    }
}
