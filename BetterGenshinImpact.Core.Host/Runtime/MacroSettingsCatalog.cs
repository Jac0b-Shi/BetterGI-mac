using BetterGenshinImpact.Core.Config;
using Newtonsoft.Json.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacroSettingsCatalog(RuntimeLayout layout)
{
    private readonly object _lock = new();
    private Action<MacroSettingsSnapshot>? _updated;

    public void AttachUpdated(Action<MacroSettingsSnapshot> callback) =>
        _updated = callback ?? throw new ArgumentNullException(nameof(callback));

    public object Get()
    {
        lock (_lock)
            return Describe(ReadSnapshot(LoadRoot()));
    }

    public object Save(JObject settings)
    {
        MacroSettingsSnapshot next;
        lock (_lock)
        {
            var root = LoadRoot();
            var current = ReadSnapshot(root);
            next = new MacroSettingsSnapshot(
                RequiredBoolean(settings, "fPressHoldToContinuationEnabled"),
                RequiredInterval(settings, "fFireInterval"),
                RequiredBoolean(settings, "spacePressHoldToContinuationEnabled"),
                RequiredInterval(settings, "spaceFireInterval"),
                RequiredRunaroundMouseXInterval(
                    settings, "runaroundMouseXInterval"),
                RequiredRunaroundInterval(settings, "runaroundInterval"),
                current.PickUpOrInteractKeyCode,
                current.JumpKeyCode);
            var macro = root["macroConfig"] as JsonObject ?? [];
            macro["fPressHoldToContinuationEnabled"] =
                next.FPressHoldToContinuationEnabled;
            macro["fFireInterval"] = next.FFireInterval;
            macro["spacePressHoldToContinuationEnabled"] =
                next.SpacePressHoldToContinuationEnabled;
            macro["spaceFireInterval"] = next.SpaceFireInterval;
            macro["runaroundMouseXInterval"] =
                next.RunaroundMouseXInterval;
            macro["runaroundInterval"] = next.RunaroundInterval;
            root["macroConfig"] = macro;
            SaveRoot(root);
        }
        _updated?.Invoke(next);
        return Describe(next);
    }

    public MacroSettingsSnapshot Snapshot()
    {
        lock (_lock)
            return ReadSnapshot(LoadRoot());
    }

    public void SetRunaroundMouseXInterval(int value)
    {
        lock (_lock)
        {
            var root = LoadRoot();
            var macro = root["macroConfig"] as JsonObject ?? [];
            macro["runaroundMouseXInterval"] = value;
            root["macroConfig"] = macro;
            SaveRoot(root);
        }
    }

    private static object Describe(MacroSettingsSnapshot settings) => new
    {
        fPressHoldToContinuationEnabled =
            settings.FPressHoldToContinuationEnabled,
        fFireInterval = settings.FFireInterval,
        spacePressHoldToContinuationEnabled =
            settings.SpacePressHoldToContinuationEnabled,
        spaceFireInterval = settings.SpaceFireInterval,
        runaroundMouseXInterval = settings.RunaroundMouseXInterval,
        runaroundInterval = settings.RunaroundInterval,
        pickUpOrInteractKeyCode = settings.PickUpOrInteractKeyCode,
        jumpKeyCode = settings.JumpKeyCode
    };

    private static MacroSettingsSnapshot ReadSnapshot(JsonObject root)
    {
        var macro = root["macroConfig"] as JsonObject;
        var keyBindings = root["keyBindingsConfig"] as JsonObject;
        return new MacroSettingsSnapshot(
            macro?["fPressHoldToContinuationEnabled"]?.GetValue<bool>() ?? false,
            macro?["fFireInterval"]?.GetValue<int>() ?? 100,
            macro?["spacePressHoldToContinuationEnabled"]?.GetValue<bool>() ?? false,
            macro?["spaceFireInterval"]?.GetValue<int>() ?? 100,
            macro?["runaroundMouseXInterval"]?.GetValue<int>() ?? 500,
            macro?["runaroundInterval"]?.GetValue<int>() ?? 10,
            keyBindings?["pickUpOrInteract"]?.GetValue<int>() ?? 0x46,
            keyBindings?["jump"]?.GetValue<int>() ?? 0x20);
    }

    private JsonObject LoadRoot()
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path))
            return [];
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
        var temporaryPath = $"{path}.{Guid.NewGuid():N}.tmp";
        File.WriteAllText(temporaryPath, root.ToJsonString(ConfigJson.Options));
        File.Move(temporaryPath, path, true);
    }

    private static bool RequiredBoolean(JObject settings, string name) =>
        settings.Value<bool?>(name) ?? throw new ArgumentException($"{name} is required.");

    private static int RequiredInterval(JObject settings, string name)
    {
        var value = settings.Value<int?>(name)
            ?? throw new ArgumentException($"{name} is required.");
        return value is >= 10 and <= 10_000
            ? value
            : throw new ArgumentOutOfRangeException(name, "Interval must be between 10 and 10000 ms.");
    }

    private static int RequiredRunaroundMouseXInterval(
        JObject settings,
        string name)
    {
        var value = settings.Value<int?>(name)
            ?? throw new ArgumentException($"{name} is required.");
        return value is >= -10_000 and <= 10_000
            ? value
            : throw new ArgumentOutOfRangeException(
                name, "Mouse distance must be between -10000 and 10000.");
    }

    private static int RequiredRunaroundInterval(JObject settings, string name)
    {
        var value = settings.Value<int?>(name)
            ?? throw new ArgumentException($"{name} is required.");
        return value is >= 1 and <= 10_000
            ? value
            : throw new ArgumentOutOfRangeException(
                name, "Turn-around interval must be between 1 and 10000 ms.");
    }

}

public sealed record MacroSettingsSnapshot(
    bool FPressHoldToContinuationEnabled,
    int FFireInterval,
    bool SpacePressHoldToContinuationEnabled,
    int SpaceFireInterval,
    int RunaroundMouseXInterval,
    int RunaroundInterval,
    int PickUpOrInteractKeyCode,
    int JumpKeyCode);
