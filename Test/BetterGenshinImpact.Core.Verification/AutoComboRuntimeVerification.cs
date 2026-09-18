using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask.AutoCombo;
using BetterGenshinImpact.GameTask.AutoCombo.ComboBuild;
using BetterGenshinImpact.GameTask.AutoCombo.ComboRun;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoFight.Config;
using BetterGenshinImpact.GameTask.AutoGeniusInvokation.Exception;
using CsTrees.Blackboard;
using OpenCvSharp;

internal static class AutoComboRuntimeVerification
{
    // Native integration: the enclosing verifier has installed and verified the
    // actual models and composed the production CPU factory. Only game frames
    // and physical input delivery are recorded; no native dependency is skipped.
    internal static async Task<bool> CancelDuringHeldSkillAsync(RecordingTaskControlPlatform input)
    {
        var oldFrameProvider = input.CaptureFrameProvider;
        var oldObserver = input.ActionObserver;
        var oldRecordCaptures = input.RecordCaptures;
        var firstCall = input.Calls.Count;
        using var cancellation = new CancellationTokenSource();
        cancellation.CancelAfter(TimeSpan.FromSeconds(15));
        using var config = AutoFightRuntimePlatform.Current.UseConfig(new AutoFightConfig
        {
            TeamNames = "钟离,夜兰,纳西妲,久岐忍", EnableCombatTargeting = false
        });
        var blackboard = new Blackboard();
        var builder = new AutoComboBuildBuilder().WithBlackboard(blackboard)
            .Sequence("cancel-held-skill")
                .UseSkill("hold-E", "钟离", true)
            .End();
        var session = new ComboTreeSession
        {
            Builder = builder, Blackboard = blackboard,
            TeamNames = ["钟离", "夜兰", "纳西妲", "久岐忍"]
        };
        input.RecordCaptures = false;
        input.CaptureFrameProvider = () => new Mat(1080, 1920, MatType.CV_8UC3, Scalar.Black);
        input.ActionObserver = (action, keyType) =>
        {
            if (action == GIActions.ElementalSkill && keyType == KeyType.Hold)
                cancellation.Cancel();
        };
        try
        {
            try
            {
                await new AutoComboRunTask(new AutoFightParam { FightFinishDetectEnabled = false }, session)
                    .Start(cancellation.Token);
            }
            catch (NormalEndException) when (cancellation.IsCancellationRequested)
            {
                // The shared TaskControl cancellation contract; input cleanup
                // must already have run before this reaches the consumer.
            }
            var calls = input.Calls.Skip(firstCall).ToArray();
            var hold = Array.IndexOf(calls, "action:ElementalSkill:Hold");
            return cancellation.IsCancellationRequested && hold >= 0 &&
                Array.FindIndex(calls, hold + 1, call => call == "releaseAll") > hold;
        }
        finally
        {
            input.CaptureFrameProvider = oldFrameProvider;
            input.ActionObserver = oldObserver;
            input.RecordCaptures = oldRecordCaptures;
        }
    }
}
