using BetterGenshinImpact.GameTask.Macro;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacQuickEnhanceArtifactRuntimePlatform(
    MacroSettingsCatalog settings,
    Func<ISystemInfo> systemInfo,
    ForegroundInputCoordinator inputCoordinator,
    CancellationToken hostCancellationToken,
    ILogger<MacQuickEnhanceArtifactRuntimePlatform> logger)
    : IQuickEnhanceArtifactRuntimePlatform
{
    public bool IsInitialized
    {
        get
        {
            var size = systemInfo().GameScreenSize;
            return size.Width > 0 && size.Height > 0;
        }
    }
    public int EnhanceWaitDelay => settings.Snapshot().EnhanceWaitDelay;

    public void NotifyNotStarted() =>
        logger.LogWarning("Quick enhance requires the BetterGI runtime.");

    public void ClickGame1080P(
        double x,
        double y,
        CancellationToken cancellationToken)
    {
        var point = ResolveScreenPoint(x, y);
        inputCoordinator.Dispatch(
            JObject.FromObject(new
            {
                action = "mouseClick",
                button = "left",
                x = point.X,
                y = point.Y,
            }),
            cancellationToken);
    }

    public void MoveGame1080P(
        double x,
        double y,
        CancellationToken cancellationToken)
    {
        var point = ResolveScreenPoint(x, y);
        inputCoordinator.Dispatch(
            JObject.FromObject(new
            {
                action = "moveMouseToScreen",
                x = point.X,
                y = point.Y,
            }),
            cancellationToken);
    }

    public void Wait(int milliseconds, CancellationToken cancellationToken)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            hostCancellationToken, cancellationToken);
        Task.Delay(milliseconds, linked.Token).GetAwaiter().GetResult();
    }

    private (int X, int Y) ResolveScreenPoint(double x, double y)
    {
        var info = systemInfo();
        var capture = info.CaptureAreaRect;
        var scale = info.ScaleTo1080PRatio;
        return (
            capture.X + (int)Math.Round(x * scale),
            capture.Y + (int)Math.Round(y * scale));
    }
}
