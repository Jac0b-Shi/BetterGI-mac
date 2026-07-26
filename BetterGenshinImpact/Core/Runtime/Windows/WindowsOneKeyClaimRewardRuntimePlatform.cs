using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.QuickClaimReward;
using Microsoft.Extensions.Logging;
using System.Threading;
using Wpf.Ui.Violeta.Controls;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsOneKeyClaimRewardRuntimePlatform
    : IOneKeyClaimRewardRuntimePlatform
{
    public bool IsInitialized => TaskContext.Instance().IsInitialized;
    public bool IsGameProcessActive =>
        SystemControl.IsGenshinImpactActiveByProcess();

    public OneKeyClaimRewardSettings Settings
    {
        get
        {
            var config = TaskContext.Instance().Config.MacroConfig;
            return new OneKeyClaimRewardSettings(
                config.OneKeyClaimRewardHotkeyMode,
                config.OneKeyClaimRewardScrollDownEnabled,
                config.OneKeyClaimRewardScrollDownAmount);
        }
    }

    public ILogger Logger => TaskControl.Logger;

    public void NotifyNotStarted() => Toast.Warning("请先启动");

    public ImageRegion Capture(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return TaskControl.CaptureToRectArea();
    }

    public void Click(
        Region region,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        region.Click();
    }

    public void PressEscape(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        TaskControlPlatform.Current.PressEscape();
    }

    public void VerticalScroll(
        int clicks,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        TaskControlPlatform.Current.VerticalScroll(clicks);
    }
}
