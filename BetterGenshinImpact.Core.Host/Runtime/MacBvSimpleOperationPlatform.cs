using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.Model;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacBvSimpleOperationPlatform : IBvSimpleOperationPlatform
{
    private readonly Func<ISystemInfo> _systemInfoProvider;

    public MacBvSimpleOperationPlatform(RuntimeLayout layout, Func<ISystemInfo> systemInfoProvider)
    {
        _systemInfoProvider = systemInfoProvider ?? throw new ArgumentNullException(nameof(systemInfoProvider));
        AutoPickConfig = LoadConfig(layout);
    }

    public ISystemInfo SystemInfo => _systemInfoProvider();
    public AutoPickConfig AutoPickConfig { get; }
    public void PressPickKey() => TaskControlPlatform.Current.SimulateAction(
        GIActions.PickUpOrInteract, KeyType.KeyPress);

    private static AutoPickConfig LoadConfig(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return new AutoPickConfig();
        var root = JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip,
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
        return root["autoPickConfig"]?.Deserialize<AutoPickConfig>(ConfigJson.Options)
            ?? new AutoPickConfig();
    }
}
