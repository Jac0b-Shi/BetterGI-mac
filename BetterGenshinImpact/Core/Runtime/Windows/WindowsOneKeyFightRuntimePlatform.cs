using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoFight;
using Microsoft.Extensions.Logging;
using System.IO;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsOneKeyFightRuntimePlatform
    : IOneKeyFightRuntimePlatform
{
    public OneKeyFightSettings Settings
    {
        get
        {
            var config = TaskContext.Instance().Config.MacroConfig;
            return new OneKeyFightSettings(
                config.CombatMacroEnabled,
                config.CombatMacroHotkeyMode,
                config.CombatMacroPriority);
        }
    }

    public ILogger Logger => App.GetLogger<OneKeyFightTask>();

    public string EnsureAvatarMacroPath()
    {
        var path = Global.Absolute("User/avatar_macro.json");
        if (!File.Exists(path))
        {
            File.Copy(
                Global.Absolute("User/avatar_macro_default.json"),
                path);
        }
        return path;
    }
}
