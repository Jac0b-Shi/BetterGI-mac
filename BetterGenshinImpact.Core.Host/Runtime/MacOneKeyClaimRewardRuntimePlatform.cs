using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.Model.Area.Converter;
using BetterGenshinImpact.GameTask.QuickClaimReward;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using System.Runtime.Versioning;

namespace BetterGenshinImpact.Core.Host.Runtime;

[SupportedOSPlatform("macos")]
public sealed class MacOneKeyClaimRewardRuntimePlatform(
    Func<ISystemInfo> systemInfo,
    MacroSettingsCatalog settings,
    MacTaskControlPlatform taskControl,
    ForegroundInputCoordinator inputCoordinator,
    CancellationToken hostCancellationToken,
    ILogger<MacOneKeyClaimRewardRuntimePlatform> logger)
    : IOneKeyClaimRewardRuntimePlatform
{
    public bool IsInitialized
    {
        get
        {
            var size = systemInfo().GameScreenSize;
            return size.Width > 0 && size.Height > 0;
        }
    }

    public bool IsGameProcessActive =>
        inputCoordinator.IsGameFocused(hostCancellationToken);

    public OneKeyClaimRewardSettings Settings
    {
        get
        {
            var snapshot = settings.Snapshot();
            return new OneKeyClaimRewardSettings(
                snapshot.OneKeyClaimRewardHotkeyMode,
                snapshot.OneKeyClaimRewardScrollDownEnabled,
                snapshot.OneKeyClaimRewardScrollDownAmount);
        }
    }

    public ILogger Logger { get; } = logger;

    public void NotifyNotStarted() =>
        Logger.LogWarning(
            "One-key claim reward requires the BetterGI runtime.");

    public ImageRegion Capture(CancellationToken cancellationToken) =>
        taskControl.CaptureToRectArea(
            forceNew: false,
            operationCancellation: cancellationToken);

    public void Click(
        Region region,
        CancellationToken cancellationToken)
    {
        var converted = ConvertRes<DesktopRegion>.ConvertPositionToTargetRegion(
            0,
            0,
            region.Width,
            region.Height,
            region);
        inputCoordinator.Dispatch(
            JObject.FromObject(new
            {
                action = "mouseClick",
                button = "left",
                x = converted.X + converted.Width / 2,
                y = converted.Y + converted.Height / 2,
            }),
            cancellationToken);
    }

    public void PressEscape(CancellationToken cancellationToken) =>
        inputCoordinator.Dispatch(
            JObject.FromObject(new
            {
                action = "keyPress",
                windowsVirtualKey = 0x1B,
            }),
            cancellationToken);

    public void VerticalScroll(
        int clicks,
        CancellationToken cancellationToken) =>
        inputCoordinator.Dispatch(
            JObject.FromObject(new
            {
                action = "verticalScroll",
                clicks,
            }),
            cancellationToken);
}
