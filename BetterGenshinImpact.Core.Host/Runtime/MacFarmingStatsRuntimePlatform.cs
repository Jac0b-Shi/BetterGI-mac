using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.GameTask.FarmingPlan;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacFarmingStatsRuntimePlatform(
    RuntimeLayout layout,
    ILogger logger) : IFarmingStatsRuntimePlatform
{
    private readonly OtherConfig _otherConfig = LoadConfig(layout);

    public string LogDirectory { get; } = Path.Combine(layout.RootPath, "log", "FarmingPlan");
    public OtherConfig.FarmingPlan Config => _otherConfig.FarmingPlanConfig;
    public ILogger Logger { get; } = logger;
    public DateTimeOffset ServerTimeNow => ScriptHostServices.ServerTimeNow;

    public Task UpdateMiyousheDataAsync(CancellationToken cancellationToken) =>
        FarmingStatsMiyousheUpdater.UpdateAsync(
            _otherConfig,
            Logger,
            cancellationToken);

    private static OtherConfig LoadConfig(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return new OtherConfig();
        var root = JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
        return root["otherConfig"]?.Deserialize<OtherConfig>(ConfigJson.Options)
            ?? new OtherConfig();
    }
}
