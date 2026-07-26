using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Macro;
using BetterGenshinImpact.GameTask.Model.Area;
using System.Threading;
using Wpf.Ui.Violeta.Controls;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsQuickEnhanceArtifactRuntimePlatform
    : IQuickEnhanceArtifactRuntimePlatform
{
    public bool IsInitialized => TaskContext.Instance().IsInitialized;
    public int EnhanceWaitDelay =>
        TaskContext.Instance().Config.MacroConfig.EnhanceWaitDelay;

    public void NotifyNotStarted() => Toast.Warning("请先启动");

    public void ClickGame1080P(
        double x,
        double y,
        CancellationToken cancellationToken) =>
        GameCaptureRegion.GameRegion1080PPosClick(x, y);

    public void MoveGame1080P(
        double x,
        double y,
        CancellationToken cancellationToken) =>
        GameCaptureRegion.GameRegion1080PPosMove(x, y);

    public void Wait(int milliseconds, CancellationToken cancellationToken)
    {
        if (!cancellationToken.CanBeCanceled)
        {
            Thread.Sleep(milliseconds);
            return;
        }
        if (cancellationToken.WaitHandle.WaitOne(milliseconds))
            cancellationToken.ThrowIfCancellationRequested();
    }
}
