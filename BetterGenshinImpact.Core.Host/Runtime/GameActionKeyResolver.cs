using BetterGenshinImpact.Core.Simulator.Extensions;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class GameActionKeyResolver(RuntimeLayout layout)
{
    private readonly object _lock = new();
    private readonly string _configPath = Path.Combine(layout.UserPath, "config.json");
    private JsonObject? _cachedKeyBindings;
    private long _nextRefreshAt;

    public void Invalidate()
    {
        lock (_lock)
        {
            _cachedKeyBindings = null;
            _nextRefreshAt = 0;
        }
    }

    public ResolvedGameActionKey Resolve(GIActions action)
    {
        var propertyName = LowerCamel(action.ToString());
        var configuredValue = CurrentKeyBindings()?[propertyName]?.GetValue<int>();
        var virtualKey = configuredValue ?? DefaultVirtualKey(action);
        return virtualKey switch
        {
            0x00 or 0xFF => new ResolvedGameActionKey(null, null),
            0x01 => new ResolvedGameActionKey(null, "left"),
            0x02 => new ResolvedGameActionKey(null, "right"),
            0x04 => new ResolvedGameActionKey(null, "middle"),
            0x05 => new ResolvedGameActionKey(null, "side1"),
            0x06 => new ResolvedGameActionKey(null, "side2"),
            _ => new ResolvedGameActionKey(virtualKey, null)
        };
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
            return _cachedKeyBindings = root?["keyBindingsConfig"] as JsonObject;
        }
    }

    private static int DefaultVirtualKey(GIActions action) => action switch
    {
        GIActions.MoveForward => 0x57,
        GIActions.MoveBackward => 0x53,
        GIActions.MoveLeft => 0x41,
        GIActions.MoveRight => 0x44,
        GIActions.SwitchToWalkOrRun => 0xA2,
        GIActions.NormalAttack => 0x01,
        GIActions.ElementalSkill => 0x45,
        GIActions.ElementalBurst => 0x51,
        GIActions.SprintKeyboard => 0xA0,
        GIActions.SprintMouse => 0x02,
        GIActions.SwitchAimingMode => 0x52,
        GIActions.Jump => 0x20,
        GIActions.Drop => 0x58,
        GIActions.PickUpOrInteract => 0x46,
        GIActions.QuickUseGadget => 0x5A,
        GIActions.InteractionInSomeMode => 0x54,
        GIActions.QuestNavigation => 0x56,
        GIActions.AbandonChallenge => 0x50,
        GIActions.SwitchMember1 => 0x31,
        GIActions.SwitchMember2 => 0x32,
        GIActions.SwitchMember3 => 0x33,
        GIActions.SwitchMember4 => 0x34,
        GIActions.SwitchMember5 => 0x35,
        GIActions.ShortcutWheel => 0x09,
        GIActions.OpenInventory => 0x42,
        GIActions.OpenCharacterScreen => 0x43,
        GIActions.OpenMap => 0x4D,
        GIActions.OpenPaimonMenu => 0x1B,
        GIActions.OpenAdventurerHandbook => 0x70,
        GIActions.OpenCoOpScreen => 0x71,
        GIActions.OpenWishScreen => 0x72,
        GIActions.OpenBattlePassScreen => 0x73,
        GIActions.OpenTheEventsMenu => 0x74,
        GIActions.OpenTheSettingsMenu => 0x75,
        GIActions.OpenTheFurnishingScreen => 0x76,
        GIActions.OpenStellarReunion => 0x77,
        GIActions.OpenQuestMenu => 0x4A,
        GIActions.OpenNotificationDetails => 0x59,
        GIActions.OpenChatScreen => 0x0D,
        GIActions.OpenSpecialEnvironmentInformation => 0x55,
        GIActions.CheckTutorialDetails => 0x47,
        GIActions.ElementalSight => 0x04,
        GIActions.ShowCursor => 0xA4,
        GIActions.OpenPartySetupScreen => 0x4C,
        GIActions.OpenFriendsScreen => 0x4F,
        GIActions.HideUI => 0xBF,
        _ => throw new ArgumentOutOfRangeException(nameof(action), action, null)
    };

    private static string LowerCamel(string value) =>
        value.Length == 0 ? value : char.ToLowerInvariant(value[0]) + value[1..];
}

public sealed record ResolvedGameActionKey(int? WindowsVirtualKey, string? MouseButton);
