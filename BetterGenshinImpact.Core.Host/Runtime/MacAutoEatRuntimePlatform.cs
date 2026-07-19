using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoEat;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Core.Simulator.Extensions;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoEatRuntimePlatform(
    RuntimeLayout layout,
    ILoggerFactory loggerFactory) : IAutoEatRuntimePlatform
{
    public AutoEatConfig Config { get; } = LoadConfig(layout);
    public ILogger<T> GetLogger<T>() => loggerFactory.CreateLogger<T>();
    public void SimulateAction(GIActions action) =>
        TaskControlPlatform.Current.SimulateAction(action, KeyType.KeyPress);

    private static AutoEatConfig LoadConfig(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return new AutoEatConfig();
        var root = JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
        return root["autoEatConfig"]?.Deserialize<AutoEatConfig>(ConfigJson.Options)
            ?? new AutoEatConfig();
    }
}
