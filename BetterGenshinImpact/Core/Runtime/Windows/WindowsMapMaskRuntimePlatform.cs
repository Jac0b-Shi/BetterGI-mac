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

    public void Publish(MapMaskDrawCommand command) => TaskContext.Instance().Runtime?.MaskWindowMapState.Update(
        command.IsInBigMapUi, Convert(command.BigMapViewport), Convert(command.MiniMapViewport));
    private static System.Windows.Rect? Convert(MapMaskViewport? value) => value is { } v
        ? new System.Windows.Rect(v.X, v.Y, v.Width, v.Height) : null;
}
