using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Script.OneDragon;
using BetterGenshinImpact.Verification.Framework;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class OneDragonPlanSuite : IVerificationSuite
{
    public string Name => "one-dragon-plan";

    public Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var legacy = new OneDragonFlowConfig
        {
            TaskEnabledList = new Dictionary<string, bool>
            {
                ["领取邮件"] = true,
                ["合成树脂"] = false,
            },
            NextTaskId = "合成树脂",
        };
        var legacyPlan = OneDragonPlan.FromConfig(legacy);
        context.Require(
            legacyPlan.OrderedSteps.Select(step => step.Name)
                .SequenceEqual(["领取邮件", "合成树脂"]) &&
            legacyPlan.ExecutionSteps.Count == 1 &&
            legacyPlan.ExecutionSteps[0] is
            {
                Id: "合成树脂",
                IsEnabled: false,
                IsResumeStep: true,
            } &&
            legacyPlan.UsesLegacyTaskNames,
            "OneDragon legacy-name configuration lost order, disabled state, or resume semantics.");

        var current = new OneDragonFlowConfig
        {
            TaskEnabledList = new Dictionary<string, bool>
            {
                ["first"] = true,
                ["second"] = false,
                ["missing-definition"] = true,
            },
            TaskDefinitions = new Dictionary<string, string>
            {
                ["first"] = "地图追踪组",
                ["second"] = "地图追踪组",
            },
            TaskOrder = ["second", "missing-definition", "first"],
            NextTaskId = "missing",
        };
        var currentPlan = OneDragonPlan.FromConfig(current);
        context.Require(
            currentPlan.OrderedSteps.Select(step => (step.Id, step.Name, step.IsEnabled))
                .SequenceEqual(
                [
                    ("second", "地图追踪组", false),
                    ("first", "地图追踪组", true),
                ]) &&
            currentPlan.ExecutionSteps.SequenceEqual(currentPlan.OrderedSteps) &&
            !currentPlan.ResumeMarkerFound &&
            !currentPlan.UsesLegacyTaskNames,
            "OneDragon current configuration lost duplicate names, explicit order, or invalid-resume fallback.");

        return Task.CompletedTask;
    }
}
