using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.AutoTrackPath;
using BetterGenshinImpact.GameTask.AutoTrackPath.Model;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.QuickTeleport;
using Newtonsoft.Json;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacTpTaskRuntimePlatform : ITpTaskRuntimePlatform
{
    private readonly Func<ISystemInfo> _systemInfoProvider;

    public MacTpTaskRuntimePlatform(RuntimeLayout layout, Func<ISystemInfo> systemInfoProvider)
    {
        _systemInfoProvider = systemInfoProvider ?? throw new ArgumentNullException(nameof(systemInfoProvider));
        var root = LoadRoot(layout);
        var tpNode = root?["tpConfig"];
        TpConfig = tpNode?.Deserialize<TpConfig>(ConfigJson.Options) ?? new TpConfig();
        TpConfig.ReviveStatueOfTheSeven = tpNode?["reviveStatueOfTheSeven"] is { } statueNode
            ? JsonConvert.DeserializeObject<GiTpPosition>(statueNode.ToJsonString())
            : null;
        TpConfig.ShouldMove = tpNode?["shouldMove"]?.GetValue<bool>() ?? false;
        TpConfig.IsReviveInNearestStatueOfTheSeven =
            tpNode?["isReviveInNearestStatueOfTheSeven"]?.GetValue<bool>() ?? false;
        QuickTeleportConfig = root?["quickTeleportConfig"]?.Deserialize<QuickTeleportConfig>(ConfigJson.Options)
            ?? new QuickTeleportConfig();
        MapMatchingMethod = root?["pathingConditionConfig"]?["mapMatchingMethod"]?.GetValue<string>()
            ?? "TemplateMatch";
    }

    public ISystemInfo SystemInfo => _systemInfoProvider();
    public TpConfig TpConfig { get; }
    public QuickTeleportConfig QuickTeleportConfig { get; }
    public string MapMatchingMethod { get; }
    public double DpiScale => TaskControlPlatform.Current.DpiScale;

    private static JsonObject? LoadRoot(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return null;
        return JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip,
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
    }
}
