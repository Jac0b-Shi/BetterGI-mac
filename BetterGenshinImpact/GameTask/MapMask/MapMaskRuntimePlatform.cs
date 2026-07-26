using System;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.GameTask.MapMask;

public readonly record struct MapMaskViewport(double X, double Y, double Width, double Height);

public readonly record struct MapMaskDrawCommand(
    bool? IsInBigMapUi,
    MapMaskViewport? BigMapViewport,
    MapMaskViewport? MiniMapViewport);

public interface IMapMaskRuntimePlatform
{
    MapMaskConfig Config { get; }
    string MapMatchingMethod { get; }
    ILogger<MapMaskTrigger> Logger { get; }
    void Publish(MapMaskDrawCommand command);
}

public static class MapMaskRuntimePlatform
{
    public static IMapMaskRuntimePlatform Current { get; set; } = null!;
    public static void Configure(IMapMaskRuntimePlatform platform) =>
        Current = platform ?? throw new ArgumentNullException(nameof(platform));
}
