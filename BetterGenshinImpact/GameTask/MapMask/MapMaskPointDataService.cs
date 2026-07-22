using BetterGenshinImpact.Model.MaskMap;
using BetterGenshinImpact.Service.Interface;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.GameTask.MapMask;

public sealed class MapMaskPointDataSnapshot
{
    public IReadOnlyList<MaskMapPoint> Points { get; init; } = [];
    public IReadOnlyDictionary<string, MaskMapPointLabel> Labels { get; init; } =
        new Dictionary<string, MaskMapPointLabel>(StringComparer.Ordinal);
}

public sealed class MapMaskPointDataService(IMaskMapPointService mapPointService)
{
    public Task<IReadOnlyList<MaskMapPointLabel>> GetLabelCategoriesAsync(
        CancellationToken cancellationToken = default) =>
        mapPointService.GetLabelCategoriesAsync(cancellationToken);

    public async Task<MapMaskPointDataSnapshot> LoadAsync(
        MapMaskConfig config,
        CancellationToken cancellationToken = default)
    {
        var dataSourceKey = MapMaskStateStorage.GetDataSourceKey(config);
        var state = MapMaskStateStorage.Read(dataSourceKey);
        if (state.SelectedLabelItems.Count == 0)
        {
            return new MapMaskPointDataSnapshot();
        }

        var selectedLabels = state.SelectedLabelItems.Select(item => new MaskMapPointLabel
        {
            LabelId = item.Id,
            LabelIds = item.LabelIds,
            ParentId = item.ParentId,
            Name = item.Name,
            IconUrl = item.IconUrl,
            PointCount = item.PointCount
        }).ToArray();

        var result = await mapPointService.GetPointsAsync(selectedLabels, cancellationToken);
        var hiddenKeys = state.HiddenMapPointKeys.ToHashSet(StringComparer.Ordinal);
        foreach (var point in result.Points)
        {
            point.IsHidden = hiddenKeys.Contains(MapMaskStateStorage.GetPointKey(config, point.Id));
        }

        return new MapMaskPointDataSnapshot
        {
            Points = result.Points,
            Labels = result.Labels
                .GroupBy(label => label.LabelId, StringComparer.Ordinal)
                .ToDictionary(group => group.Key, group => group.First(), StringComparer.Ordinal)
        };
    }
}
