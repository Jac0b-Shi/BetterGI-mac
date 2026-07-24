using BetterGenshinImpact.Core.Config;
using Newtonsoft.Json.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class HotKeySettingsCatalog(RuntimeLayout layout)
{
    private readonly object _lock = new();
    private Action<string, string>? _updated;
    private static readonly HashSet<string> ModifierNames =
        new(StringComparer.Ordinal)
        {
            "Ctrl",
            "Shift",
            "Alt",
            "Win",
        };
    private static readonly HashSet<string> NamedKeyNames =
        new(StringComparer.Ordinal)
        {
            "Escape",
            "Return",
            "Enter",
            "Tab",
            "Space",
            "Back",
            "Backspace",
            "Delete",
            "Left",
            "Right",
            "Up",
            "Down",
            "Home",
            "End",
            "PageUp",
            "PageDown",
            "OemComma",
            "OemMinus",
            "OemPlus",
            "OemPeriod",
            "OemQuestion",
            "OemPipe",
            "OemSemicolon",
            "OemOpenBrackets",
            "OemCloseBrackets",
            "OemQuotes",
            "OemTilde",
        };

    private static readonly Descriptor[] Descriptors =
    [
        new(
            "BgiEnabledHotkey", "常用", "启动停止 BetterGI",
            "bgiEnabledHotkey", "runtime.toggle", "swift", false, true,
            "F11", "GlobalRegister"),
        new(
            "CancelTaskHotkey", "系统控制", "停止当前脚本/独立任务",
            "cancelTaskHotkey", "automation.cancel", "core", false, true),
        new(
            "SuspendHotkey", "系统控制", "暂停当前脚本/独立任务",
            "suspendHotkey", "automation.suspend.toggle", "core", false, true),
        new(
            "LogBoxDisplayHotkey", "系统控制", "日志，状态窗与指标栏展示开关",
            "logBoxDisplayHotkey", "overlay.log.toggle", "swift", false, true),
        new(
            "AutoPickEnabledHotkey", "实时任务", "自动拾取开关",
            "autoPickEnabledHotkey", "trigger.toggle:AutoPick", "core", false, true),
        new(
            "AutoSkipEnabledHotkey", "实时任务", "自动剧情开关",
            "autoSkipEnabledHotkey", "trigger.toggle:AutoSkip", "core", false, true),
        new(
            "AutoSkipHangoutEnabledHotkey", "实时任务", "自动邀约开关",
            "autoSkipHangoutEnabledHotkey", "trigger.toggleHangout", "core", false, true),
        new(
            "AutoFishingEnabledHotkey", "实时任务", "自动钓鱼开关",
            "autoFishingEnabledHotkey", "trigger.toggle:AutoFish", "core", false, true),
        new(
            "QuickTeleportEnabledHotkey", "实时任务", "快速传送开关",
            "quickTeleportEnabledHotkey", "trigger.toggle:QuickTeleport", "core", false, true),
        new(
            "SkillCdEnabledHotkey", "实时任务", "冷却提示开关",
            "skillCdEnabledHotkey", "trigger.toggle:SkillCd", "core", false, true),
        new(
            "QuickTeleportTickHotkey", "实时任务", "手动触发快速传送触发快捷键（按住起效）",
            "quickTeleportTickHotkey", "quickTeleport.observe", "core", true, false),
        new(
            "MapMaskEnabledHotkey", "实时任务", "地图遮罩开关",
            "mapMaskEnabledHotkey", "trigger.toggle:MapMask", "core", false, true),
        new(
            "AutoGeniusInvokationHotkey", "独立任务", "启动/停止自动七圣召唤",
            "autoGeniusInvokationHotkey", "solo.toggle:AutoGeniusInvokation", "core", false, true),
        new(
            "AutoWoodHotkey", "独立任务", "启动/停止自动伐木",
            "autoWoodHotkey", "solo.toggle:AutoWood", "core", false, true),
        new(
            "AutoFightHotkey", "独立任务", "启动/停止自动战斗",
            "autoFightHotkey", "solo.toggle:AutoFight", "core", false, true),
        new(
            "AutoDomainHotkey", "独立任务", "启动/停止自动秘境",
            "autoDomainHotkey", "solo.toggle:AutoDomain", "core", false, true),
        new(
            "AutoMusicGameHotkey", "独立任务", "启动/停止自动音游",
            "autoMusicGameHotkey", "solo.toggle:AutoMusicGame", "core", false, true),
        new(
            "AutoFishingGameHotkey", "独立任务", "启动/停止自动钓鱼",
            "autoFishingGameHotkey", "solo.toggle:AutoFishing", "core", false, true),
        new(
            "AutoCookGameHotkey", "独立任务", "启动/停止自动烹饪",
            "autoCookGameHotkey", "solo.toggle:AutoCook", "core", false, true),
        new(
            "KeyMouseMacroRecordHotkey", "操控辅助", "启动/停止键鼠录制",
            "keyMouseMacroRecordHotkey", "recording.toggle", "swift", false, true),
        new(
            "TurnAroundHotkey", "操控辅助", "长按旋转视角 - 那维莱特转圈",
            "turnAroundHotkey", "macro.turnAround", "core", true, true,
            DispatchOnRelease: true),
        new(
            "ClickGenshinConfirmButtonHotkey", "操控辅助",
            "快捷点击原神内确认按钮",
            "clickGenshinConfirmButtonHotkey", "macro.dialog.confirm",
            "core", true, true, DispatchOnRelease: true),
        new(
            "ClickGenshinCancelButtonHotkey", "操控辅助",
            "快捷点击原神内取消按钮",
            "clickGenshinCancelButtonHotkey", "macro.dialog.cancel",
            "core", true, true, DispatchOnRelease: true),
        new(
            "EnhanceArtifactHotkey", "操控辅助", "按下快速强化圣遗物",
            "enhanceArtifactHotkey", "macro.artifact.enhance",
            "core", true, true, DispatchOnRelease: true),
        new(
            "QuickBuyHotkey", "操控辅助", "按下快速购买商店物品",
            "quickBuyHotkey", "macro.quickBuy",
            "core", true, true, DispatchOnRelease: true),
        new(
            "OneKeyClaimRewardHotkey", "操控辅助", "一键领取奖励",
            "oneKeyClaimRewardHotkey", "macro.claimReward",
            "core", true, true, DispatchOnRelease: true),
        new(
            "OneKeyFightHotkey", "操控辅助", "一键战斗宏快捷键",
            "oneKeyFightHotkey", "macro.oneKeyFight",
            "core", true, true, DispatchOnRelease: true),
    ];

    public void AttachUpdated(Action<string, string> callback) =>
        _updated = callback ?? throw new ArgumentNullException(nameof(callback));

    public object List()
    {
        lock (_lock)
        {
            var config = LoadConfig();
            return Descriptors.Select(descriptor => Describe(descriptor, config)).ToArray();
        }
    }

    public object Save(JObject value)
    {
        var id = value.Value<string>("id")
            ?? throw new ArgumentException("id is required.");
        var hotKey = value.Value<string>("hotKey")
            ?? throw new ArgumentException("hotKey is required.");
        var hotKeyType = value.Value<string>("hotKeyType")
            ?? throw new ArgumentException("hotKeyType is required.");
        var descriptor = RequireDescriptor(id);
        if (hotKeyType is not ("KeyboardMonitor" or "GlobalRegister"))
            throw new ArgumentException("hotKeyType must be KeyboardMonitor or GlobalRegister.");
        if (descriptor.IsHold && hotKeyType != "KeyboardMonitor")
            throw new ArgumentException("Hold hotkeys must use KeyboardMonitor.");
        ValidateHotKey(hotKey, hotKeyType);

        lock (_lock)
        {
            var root = LoadRoot();
            var config = root["hotKeyConfig"] as JsonObject ?? [];
            var updates = new List<(string Id, string HotKey)>();
            if (!string.IsNullOrWhiteSpace(hotKey))
            {
                foreach (var item in Descriptors)
                {
                    if (!string.Equals(item.ConfigKey, descriptor.ConfigKey, StringComparison.Ordinal) &&
                        string.Equals(
                            config[item.ConfigKey]?.GetValue<string>(), hotKey,
                            StringComparison.OrdinalIgnoreCase))
                    {
                        config[item.ConfigKey] = "";
                        updates.Add((item.Id, ""));
                    }
                }
            }
            config[descriptor.ConfigKey] = hotKey;
            config[$"{descriptor.ConfigKey}Type"] = hotKeyType;
            updates.Add((descriptor.Id, hotKey));
            root["hotKeyConfig"] = config;
            SaveRoot(root);
            foreach (var update in updates)
                _updated?.Invoke(update.Id, update.HotKey);
            return Descriptors.Select(item => Describe(item, config)).ToArray();
        }
    }

    public Descriptor RequireDescriptor(string id) =>
        Descriptors.FirstOrDefault(
            descriptor => string.Equals(descriptor.Id, id, StringComparison.Ordinal))
        ?? throw new KeyNotFoundException($"Unknown supported hotkey id: {id}");

    private JsonObject LoadConfig() =>
        LoadRoot()["hotKeyConfig"] as JsonObject ?? [];

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
            ?? throw new InvalidDataException("User/config.json root must be an object.");
    }

    private void SaveRoot(JsonObject root)
    {
        Directory.CreateDirectory(layout.UserPath);
        var path = Path.Combine(layout.UserPath, "config.json");
        var temporaryPath = $"{path}.{Guid.NewGuid():N}.tmp";
        File.WriteAllText(temporaryPath, root.ToJsonString(ConfigJson.Options));
        File.Move(temporaryPath, path, true);
    }

    private static void ValidateHotKey(string hotKey, string hotKeyType)
    {
        if (string.IsNullOrWhiteSpace(hotKey) || hotKey == "< None >")
            return;
        if (hotKey is "XButton1" or "XButton2")
        {
            if (hotKeyType != "KeyboardMonitor")
                throw new ArgumentException("Mouse side buttons require KeyboardMonitor.");
            return;
        }

        var parts = hotKey.Split(
            " + ", StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0 || string.Join(" + ", parts) != hotKey)
            throw new ArgumentException("hotKey must use the upstream ' + ' separator format.");

        var keyNames = parts.Where(part => !ModifierNames.Contains(part)).ToArray();
        if (keyNames.Length != 1 || !IsSupportedKeyName(keyNames[0]))
            throw new ArgumentException($"Unsupported hotKey value: {hotKey}");
        if (parts.Distinct(StringComparer.Ordinal).Count() != parts.Length)
            throw new ArgumentException("hotKey cannot contain duplicate components.");
        if (hotKeyType == "KeyboardMonitor" && parts.Length != 1)
            throw new ArgumentException("KeyboardMonitor does not support modifier combinations.");
        if (hotKeyType == "GlobalRegister")
        {
            var keyName = keyNames[0];
            var modifiers = parts.Length - 1;
            if (modifiers == 0 &&
                keyName is "Return" or "Enter" or "Space" or "Tab")
            {
                throw new ArgumentException(
                    "GlobalRegister requires a modifier for Return, Space or Tab.");
            }
            if (IsCharacterKeyName(keyName) &&
                (modifiers == 0 || parts.All(part => part is "Shift" || part == keyName)))
            {
                throw new ArgumentException(
                    "GlobalRegister character keys require Ctrl, Alt or Win.");
            }
        }
    }

    private static bool IsSupportedKeyName(string value) =>
        NamedKeyNames.Contains(value) ||
        value.Length == 1 && value[0] is >= 'A' and <= 'Z' ||
        value.Length == 2 && value[0] == 'D' && char.IsAsciiDigit(value[1]) ||
        value.Length is 2 or 3 && value[0] == 'F' &&
        int.TryParse(value.AsSpan(1), out var functionKey) &&
        functionKey is >= 1 and <= 12;

    private static bool IsCharacterKeyName(string value) =>
        value.Length == 1 && value[0] is >= 'A' and <= 'Z' ||
        value.Length == 2 && value[0] == 'D' && char.IsAsciiDigit(value[1]) ||
        value.StartsWith("Oem", StringComparison.Ordinal);

    private static object Describe(Descriptor descriptor, JsonObject config)
    {
        var configuredType =
            config[$"{descriptor.ConfigKey}Type"]?.GetValue<string>();
        var hotKeyType = configuredType is "KeyboardMonitor" or "GlobalRegister"
            ? configuredType
            : descriptor.DefaultHotKeyType;
        if (descriptor.IsHold)
            hotKeyType = "KeyboardMonitor";
        return new
        {
            id = descriptor.Id,
            category = descriptor.Category,
            functionName = descriptor.FunctionName,
            hotKey =
                config[descriptor.ConfigKey]?.GetValue<string>()
                ?? descriptor.DefaultHotKey,
            hotKeyType,
            action = descriptor.Action,
            executionOwner = descriptor.ExecutionOwner,
            isHold = descriptor.IsHold,
            dispatchOnPress = descriptor.DispatchOnPress,
            dispatchOnRelease = descriptor.DispatchOnRelease,
        };
    }

    public sealed record Descriptor(
        string Id,
        string Category,
        string FunctionName,
        string ConfigKey,
        string Action,
        string ExecutionOwner,
        bool IsHold,
        bool DispatchOnPress,
        string DefaultHotKey = "",
        string DefaultHotKeyType = "KeyboardMonitor",
        bool DispatchOnRelease = false);
}
