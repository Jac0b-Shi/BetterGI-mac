using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class ExternalKeyMappingResolver(RuntimeLayout layout)
{
    private readonly object _lock = new();
    private readonly string _configPath =
        Path.Combine(layout.UserPath, "config.json");
    private JsonObject? _cachedKeyBindings;
    private long _nextRefreshAt;

    private static readonly IReadOnlyDictionary<string, string> Mappings =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["W"] = "moveForward",
            ["S"] = "moveBackward",
            ["A"] = "moveLeft",
            ["D"] = "moveRight",
            ["LCONTROL"] = "switchToWalkOrRun",
            ["LCTRL"] = "switchToWalkOrRun",
            ["E"] = "elementalSkill",
            ["Q"] = "elementalBurst",
            ["LSHIFT"] = "sprintKeyboard",
            ["R"] = "switchAimingMode",
            ["SPACE"] = "jump",
            ["X"] = "drop",
            ["F"] = "pickUpOrInteract",
            ["Z"] = "quickUseGadget",
            ["T"] = "interactionInSomeMode",
            ["V"] = "questNavigation",
            ["P"] = "abandonChallenge",
            ["1"] = "switchMember1",
            ["2"] = "switchMember2",
            ["3"] = "switchMember3",
            ["4"] = "switchMember4",
            ["5"] = "switchMember5",
            ["TAB"] = "shortcutWheel",
            ["B"] = "openInventory",
            ["C"] = "openCharacterScreen",
            ["M"] = "openMap",
            ["F1"] = "openAdventurerHandbook",
            ["F2"] = "openCoOpScreen",
            ["F3"] = "openWishScreen",
            ["F4"] = "openBattlePassScreen",
            ["F5"] = "openTheEventsMenu",
            ["F6"] = "openTheSettingsMenu",
            ["F7"] = "openTheFurnishingScreen",
            ["F8"] = "openStellarReunion",
            ["J"] = "openQuestMenu",
            ["Y"] = "openNotificationDetails",
            ["RETURN"] = "openChatScreen",
            ["ENTER"] = "openChatScreen",
            ["U"] = "openSpecialEnvironmentInformation",
            ["G"] = "checkTutorialDetails",
            ["LMENU"] = "showCursor",
            ["LALT"] = "showCursor",
            ["L"] = "openPartySetupScreen",
            ["O"] = "openFriendsScreen",
            ["OEM_2"] = "hideUI",
            ["OEMQUESTION"] = "hideUI",
            ["SLASH"] = "hideUI",
        };

    public ResolvedGameActionKey? Resolve(string sourceKey)
    {
        var normalized = Normalize(sourceKey);
        if (!Mappings.TryGetValue(normalized, out var propertyName))
            return null;
        var config = CurrentKeyBindings();
        if (config?["globalKeyMappingEnabled"]?.GetValue<bool>() != true)
            return null;
        var value = config[propertyName]?.GetValue<int>();
        return value switch
        {
            null => null,
            0x00 or 0xFF => new ResolvedGameActionKey(null, null),
            0x01 => new ResolvedGameActionKey(null, "left"),
            0x02 => new ResolvedGameActionKey(null, "right"),
            0x04 => new ResolvedGameActionKey(null, "middle"),
            0x05 => new ResolvedGameActionKey(null, "side1"),
            0x06 => new ResolvedGameActionKey(null, "side2"),
            _ => new ResolvedGameActionKey(value, null),
        };
    }

    public void Invalidate()
    {
        lock (_lock)
        {
            _cachedKeyBindings = null;
            _nextRefreshAt = 0;
        }
    }

    private JsonObject? CurrentKeyBindings()
    {
        lock (_lock)
        {
            var now = Environment.TickCount64;
            if (now < _nextRefreshAt)
                return _cachedKeyBindings;
            _nextRefreshAt = now + 500;
            if (!File.Exists(_configPath))
                return _cachedKeyBindings = null;
            var root = JsonNode.Parse(
                File.ReadAllText(_configPath),
                documentOptions: new JsonDocumentOptions
                {
                    AllowTrailingCommas = true,
                    CommentHandling = JsonCommentHandling.Skip,
                }) as JsonObject;
            return _cachedKeyBindings =
                root?["keyBindingsConfig"] as JsonObject;
        }
    }

    private static string Normalize(string value)
    {
        var normalized = value.Trim().ToUpperInvariant();
        return normalized.StartsWith("VK_", StringComparison.Ordinal)
            ? normalized[3..]
            : normalized;
    }
}
