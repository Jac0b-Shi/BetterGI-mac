using System.Collections.Generic;
using System.Linq;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.AutoFight.Model;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Platform.Abstractions;
using BetterGenshinImpact.View.Drawable;
using Microsoft.Extensions.Logging;
using Vanara.PInvoke;
using Point = System.Windows.Point;

namespace BetterGenshinImpact.GameTask.SkillCd;

public sealed class WindowsSkillCdRuntimePlatform : ISkillCdRuntimePlatform
{
    public SkillCdConfig Config => TaskContext.Instance().Config.SkillCdConfig;
    public int TriggerInterval => TaskContext.Instance().Config.TriggerInterval;
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public ILogger Logger => TaskControl.Logger;
    public bool IsElementalSkillDown() => IsDown((int)TaskContext.Instance().Config.KeyBindingsConfig.ElementalSkill.ToVK());
    public bool IsPartySlotDown(int zeroBasedSlot) => IsDown((int)(User32.VK.VK_1 + (byte)zeroBasedSlot));
    public CombatScenes? TrySyncCombatScenesSilent() => RunnerContext.Instance.TrySyncCombatScenesSilent();
    public void Publish(IReadOnlyList<SkillCdTextCommand>? commands) =>
        VisionContext.Instance().DrawContent.PutOrRemoveTextList("SkillCdText",
            commands?.Select(x => new TextDrawable(x.Text, new Point(x.X, x.Y))).ToList());
    private static bool IsDown(int virtualKey) => (User32.GetAsyncKeyState(virtualKey) & 0x8000) != 0;
}
