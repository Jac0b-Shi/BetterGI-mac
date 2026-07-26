using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.GameLoading;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacGameLoadingRuntimePlatform(
    RuntimeLayout layout,
    Func<BetterGenshinImpact.GameTask.Model.ISystemInfo> getSystemInfo,
    ILoggerFactory loggerFactory,
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken cancellationToken,
    ForegroundInputCoordinator inputCoordinator) : IGameLoadingRuntimePlatform
{
    public GenshinStartConfig Config { get; } = LoadConfig(layout);
    public ILogger<GameLoadingTrigger> Logger { get; } = loggerFactory.CreateLogger<GameLoadingTrigger>();
    public double DpiScale => Invoke("window.metrics", null).Value<double?>("dpiScale")
        ?? throw new InvalidDataException("window.metrics did not return dpiScale.");

    public bool IsPlaytimeTrackingAvailable() => Invoke(
        "url.canOpen", JObject.FromObject(new { url = "starward://playtime/" }))
        .Value<bool?>("available")
        ?? throw new InvalidDataException("url.canOpen did not return available.");

    public bool TryStartPlaytimeTracking(string gameServer)
    {
        if (!IsPlaytimeTrackingAvailable()) return false;
        RequireAcknowledgement("url.open", JObject.FromObject(new
        {
            url = $"starward://playtime/{gameServer}"
        }));
        return true;
    }

    public string GetInstalledGameServer() => "";

    public BiliLoginWindowType GetBiliLoginWindowType()
    {
        var response = Invoke("window.biliLogin", null);
        return response.Value<string>("type") switch
        {
            "agreement" => BiliLoginWindowType.Agreement,
            "login" => BiliLoginWindowType.Login,
            "none" => BiliLoginWindowType.None,
            var value => throw new InvalidDataException($"window.biliLogin returned invalid type '{value}'.")
        };
    }

    public void BackgroundClick() => TaskControlPlatform.Current.LeftButtonClick();

    public void MoveToGame1080P(double x, double y)
    {
        var size = getSystemInfo().GameScreenSize;
        inputCoordinator.Dispatch(JObject.FromObject(new
        {
            action = "moveMouseToGame",
            x = (int)Math.Round(x * size.Width / 1920d),
            y = (int)Math.Round(y * size.Height / 1080d),
            gameWidth = size.Width,
            gameHeight = size.Height
        }), cancellationToken);
    }

    public void ClickGame1080P(double x, double y)
    {
        MoveToGame1080P(x, y);
        BackgroundClick();
    }

    private JToken Invoke(string method, JObject? parameters) => callbacks.InvokeAsync(
            method, parameters, sessionToken, cancellationToken).GetAwaiter().GetResult()
        ?? throw new InvalidDataException($"{method} returned an empty response.");

    private void RequireAcknowledgement(string method, JObject? parameters)
    {
        if (Invoke(method, parameters).Value<bool?>("acknowledged") != true)
            throw new InvalidDataException($"{method} did not return acknowledged=true.");
    }

    private static GenshinStartConfig LoadConfig(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return new GenshinStartConfig();
        var root = JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
        return root["genshinStartConfig"]?.Deserialize<GenshinStartConfig>(ConfigJson.Options)
            ?? new GenshinStartConfig();
    }
}
