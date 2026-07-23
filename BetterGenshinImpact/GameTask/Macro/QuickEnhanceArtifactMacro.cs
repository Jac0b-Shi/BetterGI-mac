using System.Threading;

namespace BetterGenshinImpact.GameTask.Macro;

/// <summary>
/// 一键强化圣遗物
/// </summary>
public class QuickEnhanceArtifactMacro
{
    public static void Done(CancellationToken cancellationToken = default)
    {
        var platform = QuickEnhanceArtifactRuntimePlatform.Current;
        if (!platform.IsInitialized)
        {
            platform.NotifyNotStarted();
            return;
        }

        // 快捷放入 1760x770
        platform.ClickGame1080P(1760, 770, cancellationToken);
        platform.Wait(100, cancellationToken);
        // 强化 1760x1020
        platform.ClickGame1080P(1760, 1020, cancellationToken);
        platform.Wait(
            100 + platform.EnhanceWaitDelay,
            cancellationToken);
        // 详情菜单 150x150
        platform.ClickGame1080P(150, 150, cancellationToken);
        platform.Wait(100, cancellationToken);
        // 强化菜单 150x220
        platform.ClickGame1080P(150, 220, cancellationToken);
        platform.Wait(100, cancellationToken);
        // 移动回快捷放入 #30
        platform.MoveGame1080P(1760, 770, cancellationToken);
    }
}
