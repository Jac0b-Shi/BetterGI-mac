using BetterGenshinImpact.View;
using BetterGenshinImpact.ViewModel;
using BetterGenshinImpact.Helpers;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.GameTask.MapMask;

public sealed class WindowsMapMaskRuntimePlatform : IMapMaskRuntimePlatform
{
    public MapMaskConfig Config => TaskContext.Instance().Config.MapMaskConfig;
    public string MapMatchingMethod => TaskContext.Instance().Config.PathingConditionConfig.MapMatchingMethod;
    public ILogger<MapMaskTrigger> Logger => App.GetLogger<MapMaskTrigger>();

    public void Publish(MapMaskDrawCommand command) => UIDispatcherHelper.BeginInvoke(() =>
    {
        var window = MaskWindow.Instance();
        if (command.IsInBigMapUi is { } isInBigMapUi && window.DataContext is MaskWindowViewModel vm)
            vm.IsInBigMapUi = isInBigMapUi;
        if (command.BigMapViewport is { } big)
            window.PointsCanvasControl.UpdateViewport(big.X, big.Y, big.Width, big.Height);
        if (command.MiniMapViewport is { } mini)
            window.MiniMapPointsCanvasControl.UpdateViewport(mini.X, mini.Y, mini.Width, mini.Height);
    });
}
