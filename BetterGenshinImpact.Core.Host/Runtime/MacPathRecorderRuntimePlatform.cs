using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.GameTask.Common.Map.Maps.Base;
using Microsoft.Extensions.Logging;
using System.Runtime.Versioning;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

[SupportedOSPlatform("macos")]
public sealed class MacPathRecorderRuntimePlatform(
    RuntimeLayout layout,
    ILogger<PathRecorderTask> logger) : IPathRecorderRuntimePlatform
{
    public PathRecorderSettings Settings
    {
        get
        {
            var root = LoadRoot();
            return new PathRecorderSettings(
                root["devConfig"]?["recordMapName"]?.GetValue<string>()
                    ?? nameof(MapTypes.Teyvat),
                root["pathingConditionConfig"]?["mapMatchingMethod"]
                    ?.GetValue<string>() ?? "TemplateMatch",
                Path.Combine(layout.UserPath, "AutoPathing"),
                Global.Version);
        }
    }

    public bool IsEditorOpen => false;

    public ILogger Logger => logger;

    public void PublishWaypoint(Waypoint waypoint)
    {
    }

    private JsonObject LoadRoot()
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path))
            return [];
        return JsonNode.Parse(
            File.ReadAllText(path),
            documentOptions: new JsonDocumentOptions
            {
                AllowTrailingCommas = true,
                CommentHandling = JsonCommentHandling.Skip,
            }) as JsonObject
            ?? throw new InvalidDataException(
                "User/config.json root must be an object.");
    }
}
