using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.GameTask.MapMask;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacMapMaskRuntimePlatform : IMapMaskRuntimePlatform
{
    private readonly PlatformCallbackChannel _callbacks;
    private readonly string _sessionToken;
    private readonly CancellationToken _cancellationToken;

    public MacMapMaskRuntimePlatform(RuntimeLayout layout, ILoggerFactory loggerFactory,
        PlatformCallbackChannel callbacks, string sessionToken, CancellationToken cancellationToken)
    {
        _callbacks = callbacks;
        _sessionToken = sessionToken;
        _cancellationToken = cancellationToken;
        Logger = loggerFactory.CreateLogger<MapMaskTrigger>();
        var root = LoadRoot(layout);
        Config = root["mapMaskConfig"]?.Deserialize<MapMaskConfig>(ConfigJson.Options) ?? new MapMaskConfig();
        MapMatchingMethod = root["pathingConditionConfig"]?["mapMatchingMethod"]?.GetValue<string>() ?? "FeatureMatch";
    }

    public MapMaskConfig Config { get; }
    public string MapMatchingMethod { get; }
    public ILogger<MapMaskTrigger> Logger { get; }

    public void UpdateConfig(MapMaskConfig config) =>
        Config.MiniMapMaskEnabled = config.MiniMapMaskEnabled;

    public void Publish(MapMaskDrawCommand command)
    {
        var response = _callbacks.InvokeAsync("overlay.command", JObject.FromObject(new
        {
            name = "MapMask",
            operation = "setMapViewport",
            isInBigMapUi = command.IsInBigMapUi,
            bigMapViewport = command.BigMapViewport,
            miniMapViewport = command.MiniMapViewport,
        }), _sessionToken, _cancellationToken).GetAwaiter().GetResult();
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException("MapMask overlay command was not acknowledged.");
    }

    private static JsonObject LoadRoot(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return new JsonObject();
        return JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
    }
}
