using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.QuickClaimReward;
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
                RequiredEnhanceWaitDelay(settings, "enhanceWaitDelay"),
                RequiredBoolean(settings, "combatMacroEnabled"),
                RequiredOneKeyFightMode(
                    settings,
                    "combatMacroHotkeyMode"),
                RequiredOneKeyFightPriority(
                    settings,
                    "combatMacroPriority"),
                RequiredOneKeyClaimRewardMode(
                    settings,
                    "oneKeyClaimRewardHotkeyMode"),
                RequiredBoolean(
                    settings,
                    "oneKeyClaimRewardScrollDownEnabled"),
                RequiredOneKeyClaimRewardScrollAmount(
                    settings,
                    "oneKeyClaimRewardScrollDownAmount"),
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
            macro["enhanceWaitDelay"] = next.EnhanceWaitDelay;
            macro["combatMacroEnabled"] = next.CombatMacroEnabled;
            macro["combatMacroHotkeyMode"] =
                next.CombatMacroHotkeyMode;
            macro["combatMacroPriority"] = next.CombatMacroPriority;
            macro["oneKeyClaimRewardHotkeyMode"] =
                next.OneKeyClaimRewardHotkeyMode;
            macro["oneKeyClaimRewardScrollDownEnabled"] =
                next.OneKeyClaimRewardScrollDownEnabled;
            macro["oneKeyClaimRewardScrollDownAmount"] =
                next.OneKeyClaimRewardScrollDownAmount;
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
        enhanceWaitDelay = settings.EnhanceWaitDelay,
        combatMacroEnabled = settings.CombatMacroEnabled,
        combatMacroHotkeyMode = settings.CombatMacroHotkeyMode,
        combatMacroHotkeyModeOptions = new[]
        {
            OneKeyFightTask.HoldOnMode,
            OneKeyFightTask.HoldFinishMode,
            OneKeyFightTask.TickMode,
        },
        combatMacroPriority = settings.CombatMacroPriority,
        oneKeyClaimRewardHotkeyMode =
            settings.OneKeyClaimRewardHotkeyMode,
        oneKeyClaimRewardHotkeyModeOptions = new[]
        {
            OneKeyClaimRewardTask.ClickOnceMode,
            OneKeyClaimRewardTask.HoldMode,
        },
        oneKeyClaimRewardHoldMode = OneKeyClaimRewardTask.HoldMode,
        oneKeyClaimRewardScrollDownEnabled =
            settings.OneKeyClaimRewardScrollDownEnabled,
        oneKeyClaimRewardScrollDownAmount =
            settings.OneKeyClaimRewardScrollDownAmount,
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
            macro?["enhanceWaitDelay"]?.GetValue<int>() ?? 0,
            macro?["combatMacroEnabled"]?.GetValue<bool>() ?? false,
            macro?["combatMacroHotkeyMode"]?.GetValue<string>()
                ?? OneKeyFightTask.HoldOnMode,
            macro?["combatMacroPriority"]?.GetValue<int>() ?? 1,
            macro?["oneKeyClaimRewardHotkeyMode"]?.GetValue<string>()
                ?? OneKeyClaimRewardTask.ClickOnceMode,
            macro?["oneKeyClaimRewardScrollDownEnabled"]?.GetValue<bool>()
                ?? false,
            macro?["oneKeyClaimRewardScrollDownAmount"]?.GetValue<int>()
                ?? 2,
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

    private static int RequiredEnhanceWaitDelay(JObject settings, string name)
    {
        var value = settings.Value<int?>(name)
            ?? throw new ArgumentException($"{name} is required.");
        return value is >= 0 and <= 1_000
            ? value
            : throw new ArgumentOutOfRangeException(
                name, "Enhance wait delay must be between 0 and 1000 ms.");
    }

    private static string RequiredOneKeyClaimRewardMode(
        JObject settings,
        string name)
    {
        var value = settings.Value<string>(name)
            ?? throw new ArgumentException($"{name} is required.");
        return value is OneKeyClaimRewardTask.ClickOnceMode
            or OneKeyClaimRewardTask.HoldMode
            ? value
            : throw new ArgumentException(
                $"Unsupported one-key claim reward mode: {value}",
                name);
    }

    private static string RequiredOneKeyFightMode(
        JObject settings,
        string name)
    {
        var value = settings.Value<string>(name)
            ?? throw new ArgumentException($"{name} is required.");
        return value == OneKeyFightTask.HoldOnMode ||
               value == OneKeyFightTask.HoldFinishMode ||
               value == OneKeyFightTask.TickMode
            ? value
            : throw new ArgumentException(
                $"Unsupported one-key fight mode: {value}",
                name);
    }

    private static int RequiredOneKeyFightPriority(
        JObject settings,
        string name)
    {
        var value = settings.Value<int?>(name)
            ?? throw new ArgumentException($"{name} is required.");
        return value is >= 1 and <= 5
            ? value
            : throw new ArgumentOutOfRangeException(
                name,
                "Combat macro priority must be between 1 and 5.");
    }

    private static int RequiredOneKeyClaimRewardScrollAmount(
        JObject settings,
        string name)
    {
        var value = settings.Value<int?>(name)
            ?? throw new ArgumentException($"{name} is required.");
        return value is >= 1 and <= 1_000
            ? value
            : throw new ArgumentOutOfRangeException(
                name,
                "Scroll amount must be between 1 and 1000.");
    }

}

public sealed record MacroSettingsSnapshot(
    bool FPressHoldToContinuationEnabled,
    int FFireInterval,
    bool SpacePressHoldToContinuationEnabled,
    int SpaceFireInterval,
    int RunaroundMouseXInterval,
    int RunaroundInterval,
    int EnhanceWaitDelay,
    bool CombatMacroEnabled,
    string CombatMacroHotkeyMode,
    int CombatMacroPriority,
    string OneKeyClaimRewardHotkeyMode,
    bool OneKeyClaimRewardScrollDownEnabled,
    int OneKeyClaimRewardScrollDownAmount,
    int PickUpOrInteractKeyCode,
    int JumpKeyCode);
