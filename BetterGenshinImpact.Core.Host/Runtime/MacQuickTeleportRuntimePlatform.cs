using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.GameTask.QuickTeleport;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacQuickTeleportRuntimePlatform : IQuickTeleportRuntimePlatform
{
    private readonly PlatformCallbackChannel _callbacks;
    private readonly string _sessionToken;
    private readonly CancellationToken _cancellationToken;

    public MacQuickTeleportRuntimePlatform(
        RuntimeLayout layout,
        PlatformCallbackChannel callbacks,
        string sessionToken,
        CancellationToken cancellationToken)
    {
        _callbacks = callbacks;
        _sessionToken = sessionToken;
        _cancellationToken = cancellationToken;
        var root = LoadRoot(layout);
        Config = root?["quickTeleportConfig"]?.Deserialize<QuickTeleportConfig>(ConfigJson.Options)
            ?? new QuickTeleportConfig();
        TickHotkey = root?["hotKeyConfig"]?["quickTeleportTickHotkey"]?.GetValue<string>() ?? "";
        IsHdrCapture = root?["captureMode"]?.GetValue<string>() == "WindowsGraphicsCaptureHdr";
    }

    public QuickTeleportConfig Config { get; }
    public string TickHotkey { get; }
    public bool IsHdrCapture { get; }

    public void UpdateConfig(QuickTeleportConfig config)
    {
        Config.TeleportListClickDelay = config.TeleportListClickDelay;
        Config.WaitTeleportPanelDelay = config.WaitTeleportPanelDelay;
        Config.HotkeyTpEnabled = config.HotkeyTpEnabled;
    }

    public bool IsTickHotkeyPressed()
    {
        if (string.IsNullOrEmpty(TickHotkey)) return false;
        var response = _callbacks.InvokeAsync(
                "input.query", JObject.FromObject(new { action = "isKeyDown", key = TickHotkey }),
                _sessionToken, _cancellationToken).GetAwaiter().GetResult()
            ?? throw new InvalidDataException("input.query returned an empty response.");
        return response.Value<bool?>("isDown")
            ?? throw new InvalidDataException("input.query did not return isDown.");
    }

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
