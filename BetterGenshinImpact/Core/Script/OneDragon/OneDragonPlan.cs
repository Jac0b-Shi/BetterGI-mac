using System;
using System.Collections.Generic;
using System.Linq;
using BetterGenshinImpact.Core.Config;

namespace BetterGenshinImpact.Core.Script.OneDragon;

public sealed record OneDragonPlanStep(
    string Id,
    string Name,
    bool IsEnabled,
    bool IsResumeStep);

public sealed record OneDragonPlan(
    IReadOnlyList<OneDragonPlanStep> OrderedSteps,
    IReadOnlyList<OneDragonPlanStep> ExecutionSteps,
    bool ResumeMarkerFound,
    bool UsesLegacyTaskNames)
{
    public static OneDragonPlan FromConfig(OneDragonFlowConfig config)
    {
        ArgumentNullException.ThrowIfNull(config);

        var definitions = config.TaskDefinitions ?? [];
        var enabled = config.TaskEnabledList ?? [];
        var keys = config.TaskOrder is { Count: > 0 }
            ? config.TaskOrder
            : enabled.Keys.ToList();
        var usesLegacyNames = definitions.Count == 0;
        var steps = new List<OneDragonPlanStep>(keys.Count);

        foreach (var key in keys)
        {
            if (!enabled.TryGetValue(key, out var isEnabled))
            {
                continue;
            }

            string name;
            if (usesLegacyNames)
            {
                name = key;
            }
            else if (!definitions.TryGetValue(key, out name!))
            {
                continue;
            }

            steps.Add(new OneDragonPlanStep(
                key,
                name,
                isEnabled,
                key == config.NextTaskId));
        }

        return FromOrderedSteps(steps, config.NextTaskId) with
        {
            UsesLegacyTaskNames = usesLegacyNames
        };
    }

    public static OneDragonPlan FromOrderedSteps(
        IEnumerable<OneDragonPlanStep> steps,
        string? resumeTaskId)
    {
        ArgumentNullException.ThrowIfNull(steps);

        var ordered = steps
            .Select(step => step with
            {
                IsResumeStep = !string.IsNullOrEmpty(resumeTaskId) &&
                    string.Equals(step.Id, resumeTaskId, StringComparison.Ordinal)
            })
            .ToArray();
        var resumeIndex = string.IsNullOrEmpty(resumeTaskId)
            ? 0
            : Array.FindIndex(
                ordered,
                step => string.Equals(step.Id, resumeTaskId, StringComparison.Ordinal));
        var resumeMarkerFound = string.IsNullOrEmpty(resumeTaskId) || resumeIndex >= 0;
        if (resumeIndex < 0)
        {
            resumeIndex = 0;
        }

        return new OneDragonPlan(
            ordered,
            ordered.Skip(resumeIndex).ToArray(),
            resumeMarkerFound,
            UsesLegacyTaskNames: false);
    }
}
