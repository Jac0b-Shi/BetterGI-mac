using BetterGenshinImpact.Core.Config;
using Newtonsoft.Json.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class KeyBindingSettingsCatalog(RuntimeLayout layout)
{
    private readonly object _lock = new();
    private Action? _updated;

    private static readonly Descriptor[] Descriptors =
    [
        new("moveForward", "操作", "向前移动", 0x57),
        new("moveBackward", "操作", "向后移动", 0x53),
        new("moveLeft", "操作", "向左移动", 0x41),
        new("moveRight", "操作", "向右移动", 0x44),
        new("switchToWalkOrRun", "操作", "切换走/跑；特定操作模式下向下移动", 0xA2),
        new("normalAttack", "操作", "普通攻击", 0x01),
        new("elementalSkill", "操作", "元素战技", 0x45),
        new("elementalBurst", "操作", "元素爆发", 0x51),
        new("sprintKeyboard", "操作", "冲刺（键盘）", 0xA0),
        new("sprintMouse", "操作", "冲刺（鼠标）", 0x02),
        new("switchAimingMode", "操作", "切换瞄准模式", 0x52),
        new("jump", "操作", "跳跃；特定操作模式下向上移动", 0x20),
        new("drop", "操作", "落下", 0x58),
        new("pickUpOrInteract", "操作", "拾取/交互（自动拾取由 AutoPick 管理）", 0x46),
        new("quickUseGadget", "操作", "快捷使用小道具", 0x5A),
        new("interactionInSomeMode", "操作", "特定玩法内交互操作", 0x54),
        new("questNavigation", "操作", "开启任务追踪", 0x56),
        new("abandonChallenge", "操作", "中断挑战", 0x50),
        new("switchMember1", "操作", "切换小队角色 1", 0x31),
        new("switchMember2", "操作", "切换小队角色 2", 0x32),
        new("switchMember3", "操作", "切换小队角色 3", 0x33),
        new("switchMember4", "操作", "切换小队角色 4", 0x34),
        new("switchMember5", "操作", "切换小队角色 5", 0x35),
        new("shortcutWheel", "操作", "呼出快捷轮盘", 0x09),
        new("openInventory", "菜单", "打开背包", 0x42),
        new("openCharacterScreen", "菜单", "打开角色界面", 0x43),
        new("openMap", "菜单", "打开地图", 0x4D),
        new("openPaimonMenu", "菜单", "打开派蒙界面", 0x1B),
        new("openAdventurerHandbook", "菜单", "打开冒险之证界面", 0x70),
        new("openCoOpScreen", "菜单", "打开多人游戏界面", 0x71),
        new("openWishScreen", "菜单", "打开祈愿界面", 0x72),
        new("openBattlePassScreen", "菜单", "打开纪行界面", 0x73),
        new("openTheEventsMenu", "菜单", "打开活动面板", 0x74),
        new("openTheSettingsMenu", "菜单", "打开玩法系统界面", 0x75),
        new("openTheFurnishingScreen", "菜单", "打开摆设界面", 0x76),
        new("openStellarReunion", "菜单", "打开星之归还", 0x77),
        new("openQuestMenu", "菜单", "开关任务菜单", 0x4A),
        new("openNotificationDetails", "菜单", "打开通知详情", 0x59),
        new("openChatScreen", "菜单", "打开聊天界面", 0x0D),
        new("openSpecialEnvironmentInformation", "菜单", "打开特殊环境说明", 0x55),
        new("checkTutorialDetails", "菜单", "查看教程详情", 0x47),
        new("elementalSight", "菜单", "长按打开元素视野", 0x04),
        new("showCursor", "菜单", "呼出鼠标", 0xA4),
        new("openPartySetupScreen", "菜单", "打开队伍配置界面", 0x4C),
        new("openFriendsScreen", "菜单", "打开好友界面", 0x4F),
        new("hideUI", "菜单", "隐藏主界面", 0xBF),
    ];

    private static readonly KeyOption[] Options = BuildOptions();
    private static readonly HashSet<int> SupportedValues =
        Options.Select(option => option.Value).ToHashSet();

    public void AttachUpdated(Action callback) =>
        _updated = callback ?? throw new ArgumentNullException(nameof(callback));

    public object Get()
    {
        lock (_lock)
            return Describe(LoadRoot());
    }

    public object Save(JObject settings)
    {
        lock (_lock)
        {
            var globalKeyMappingEnabled =
                settings.Value<bool?>("globalKeyMappingEnabled")
                ?? throw new ArgumentException(
                    "globalKeyMappingEnabled is required.");
            var values = settings["bindings"] as JArray
                ?? throw new ArgumentException("bindings is required.");
            var submitted = values
                .OfType<JObject>()
                .ToDictionary(
                    value => value.Value<string>("id")
                        ?? throw new ArgumentException(
                            "Every key binding requires id."),
                    value => value.Value<int?>("value")
                        ?? throw new ArgumentException(
                            "Every key binding requires value."),
                    StringComparer.Ordinal);
            if (submitted.Count != Descriptors.Length ||
                Descriptors.Any(descriptor =>
                    !submitted.ContainsKey(descriptor.Id)))
            {
                throw new ArgumentException(
                    "bindings must contain every supported game action exactly once.");
            }
            foreach (var (id, value) in submitted)
            {
                if (!SupportedValues.Contains(value))
                    throw new ArgumentException(
                        $"Unsupported macOS key binding value for {id}: {value}.");
            }

            var root = LoadRoot();
            var config = root["keyBindingsConfig"] as JsonObject ?? [];
            config["globalKeyMappingEnabled"] = globalKeyMappingEnabled;
            foreach (var descriptor in Descriptors)
                config[descriptor.Id] = submitted[descriptor.Id];
            root["keyBindingsConfig"] = config;
            SaveRoot(root);
            _updated?.Invoke();
            return Describe(root);
        }
    }

    private static object Describe(JsonObject root)
    {
        var config = root["keyBindingsConfig"] as JsonObject;
        return new
        {
            globalKeyMappingEnabled =
                config?["globalKeyMappingEnabled"]?.GetValue<bool>() ?? false,
            bindings = Descriptors.Select(descriptor =>
            {
                var value = config?[descriptor.Id]?.GetValue<int>()
                    ?? descriptor.DefaultValue;
                var option = Options.FirstOrDefault(item => item.Value == value);
                return new
                {
                    id = descriptor.Id,
                    category = descriptor.Category,
                    actionName = descriptor.ActionName,
                    value,
                    displayValue = option?.DisplayName
                        ?? $"不支持的键值 ({value})",
                    supported = option is not null,
                };
            }).ToArray(),
            options = Options.Select(option => new
            {
                value = option.Value,
                displayName = option.DisplayName,
            }).ToArray(),
        };
    }

    private JsonObject LoadRoot()
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path))
            return [];
        return JsonNode.Parse(
            File.ReadAllText(path),
            documentOptions: new JsonDocumentOptions
            {
                AllowTrailingCommas = true,
                CommentHandling = JsonCommentHandling.Skip,
            }) as JsonObject
            ?? throw new InvalidDataException(
                "User/config.json root must be an object.");
    }

    private void SaveRoot(JsonObject root)
    {
        Directory.CreateDirectory(layout.UserPath);
        var path = Path.Combine(layout.UserPath, "config.json");
        var temporaryPath = $"{path}.{Guid.NewGuid():N}.tmp";
        File.WriteAllText(
            temporaryPath,
            root.ToJsonString(ConfigJson.Options));
        File.Move(temporaryPath, path, true);
    }

    private static KeyOption[] BuildOptions()
    {
        var options = new List<KeyOption>
        {
            new(0x00, "<未指定>"),
            new(0x01, "鼠标左键"),
            new(0x02, "鼠标右键"),
            new(0x04, "鼠标中键"),
            new(0x05, "鼠标侧键 1"),
            new(0x06, "鼠标侧键 2"),
            new(0x08, "Backspace"),
            new(0x09, "Tab"),
            new(0x0D, "Enter"),
            new(0x14, "Caps Lock"),
            new(0x1B, "Esc"),
            new(0x20, "Space"),
            new(0x21, "Page Up"),
            new(0x22, "Page Down"),
            new(0x23, "End"),
            new(0x24, "Home"),
            new(0x25, "←"),
            new(0x26, "↑"),
            new(0x27, "→"),
            new(0x28, "↓"),
            new(0x2E, "Delete"),
        };
        options.AddRange(
            Enumerable.Range(0, 10)
                .Select(value => new KeyOption(
                    0x30 + value, value.ToString())));
        options.AddRange(
            Enumerable.Range('A', 26)
                .Select(value => new KeyOption(
                    value, ((char)value).ToString())));
        options.AddRange(
            Enumerable.Range(1, 12)
                .Select(value => new KeyOption(
                    0x6F + value, $"F{value}")));
        options.AddRange(
        [
            new(0xA0, "左 Shift"),
            new(0xA2, "左 Ctrl"),
            new(0xA4, "左 Alt"),
            new(0xBA, ";"),
            new(0xBB, "="),
            new(0xBC, ","),
            new(0xBD, "-"),
            new(0xBE, "."),
            new(0xBF, "/"),
            new(0xC0, "`"),
            new(0xDB, "["),
            new(0xDC, "\\"),
            new(0xDD, "]"),
            new(0xDE, "'"),
        ]);
        return options.ToArray();
    }

    private sealed record Descriptor(
        string Id,
        string Category,
        string ActionName,
        int DefaultValue);

    private sealed record KeyOption(int Value, string DisplayName);
}
