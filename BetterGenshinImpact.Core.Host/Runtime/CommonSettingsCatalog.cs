using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class CommonSettingsCatalog(RuntimeLayout layout)
{
    private readonly object _lock = new();

    public object Get()
    {
        lock (_lock)
        {
            return Describe(LoadRoot());
        }
    }

    public object Save(JObject settings)
    {
        lock (_lock)
        {
            var root = LoadRoot();
            var common = root["commonConfig"] as JsonObject ?? [];
            common["screenshotEnabled"] = RequiredBool(settings, "screenshotEnabled");
            common["screenshotUidCoverEnabled"] =
                RequiredBool(settings, "screenshotUidCoverEnabled");
            root["commonConfig"] = common;
            SaveRoot(root);
            return Describe(root);
        }
    }

    internal static bool ScreenshotEnabled(JsonObject root) =>
        root["commonConfig"]?["screenshotEnabled"]?.GetValue<bool>() ?? false;

    private static object Describe(JsonObject root) => new
    {
        screenshotEnabled = ScreenshotEnabled(root),
        screenshotUidCoverEnabled =
            root["commonConfig"]?["screenshotUidCoverEnabled"]?.GetValue<bool>() ?? true,
    };

    private static bool RequiredBool(JObject settings, string name) =>
        settings.Value<bool?>(name) ?? throw new ArgumentException($"{name} is required.");

    private JsonObject LoadRoot()
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return [];
        return JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip,
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
    }

    private void SaveRoot(JsonObject root)
    {
        Directory.CreateDirectory(layout.UserPath);
        var path = Path.Combine(layout.UserPath, "config.json");
        var temporaryPath = path + ".tmp";
        File.WriteAllText(temporaryPath, root.ToJsonString(ConfigJson.Options));
        File.Move(temporaryPath, path, true);
    }
}
