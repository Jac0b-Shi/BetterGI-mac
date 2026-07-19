using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.FarmingPlan;
using BetterGenshinImpact.Core.Config;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacScriptGroupExecutionServices : IScriptGroupExecutionServices
{
    private readonly PathingPartyConfig _defaultPartyConfig;
    private readonly PathingFailurePolicy _failurePolicy;

    public MacScriptGroupExecutionServices(RuntimeLayout layout)
    {
        var root = LoadRoot(layout);
        var condition = root?["pathingConditionConfig"]?.Deserialize<PathingConditionConfig>(ConfigJson.Options)
            ?? new PathingConditionConfig();
        _defaultPartyConfig = new PathingPartyConfig
        {
            OnlyInTeleportRecover = condition.OnlyInTeleportRecover,
            UseGadgetIntervalMs = condition.UseGadgetIntervalMs,
            AutoEatEnabled = condition.AutoEatEnabled
        };
        var restart = root?["otherConfig"]?["autoRestartConfig"]
            ?.Deserialize<OtherConfig.AutoRestart>(ConfigJson.Options) ?? new OtherConfig.AutoRestart();
        _failurePolicy = new PathingFailurePolicy(
            restart.Enabled, restart.IsPathingFailureExceptional, restart.IsFightFailureExceptional);
    }

    public PathingPartyConfig DefaultPartyConfig => _defaultPartyConfig;

    public IPathExecutor CreatePathExecutor(CancellationToken cancellationToken) => new PathExecutor(cancellationToken);

    public void AddAutoPickTrigger() => throw new CapabilityUnavailableException(
        "Pathing AutoPick trigger composition is unavailable until PathExecutor is composed.");

    public PathingFailurePolicy PathingFailurePolicy => _failurePolicy;

    public void RecordFarmingSession(FarmingSession session, FarmingRouteInfo route) =>
        throw new CapabilityUnavailableException(
            "Farming statistics persistence requires the remaining shared FarmingStatsRecorder closure.");

    private static JsonObject? LoadRoot(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return null;
        return JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
    }
}
