using BetterGenshinImpact.GameTask.AutoFight;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacOneKeyFightRuntimePlatform(
    RuntimeLayout layout,
    MacroSettingsCatalog settings,
    ILogger<OneKeyFightTask> logger)
    : IOneKeyFightRuntimePlatform
{
    private readonly object _fileLock = new();

    public OneKeyFightSettings Settings
    {
        get
        {
            var snapshot = settings.Snapshot();
            return new OneKeyFightSettings(
                snapshot.CombatMacroEnabled,
                snapshot.CombatMacroHotkeyMode,
                snapshot.CombatMacroPriority);
        }
    }

    public ILogger Logger { get; } = logger;

    public string EnsureAvatarMacroPath()
    {
        lock (_fileLock)
        {
            Directory.CreateDirectory(layout.UserPath);
            var bundledDefault = Path.Combine(
                AppContext.BaseDirectory,
                "User",
                "avatar_macro_default.json");
            if (!File.Exists(bundledDefault))
            {
                throw new FileNotFoundException(
                    "The published default avatar macro is missing.",
                    bundledDefault);
            }

            var runtimeDefault = Path.Combine(
                layout.UserPath,
                "avatar_macro_default.json");
            if (!File.Exists(runtimeDefault))
                File.Copy(bundledDefault, runtimeDefault);

            var runtimeMacro = Path.Combine(
                layout.UserPath,
                "avatar_macro.json");
            if (!File.Exists(runtimeMacro))
                File.Copy(runtimeDefault, runtimeMacro);
            return runtimeMacro;
        }
    }
}
