using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.GameTask.MapMask;
using BetterGenshinImpact.Model.MaskMap;
using BetterGenshinImpact.Service;
using BetterGenshinImpact.Service.Tavern;
using LazyCache;
using LazyCache.Providers;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacMapMaskRuntimePlatform : IMapMaskRuntimePlatform
{
    private readonly PlatformCallbackChannel _callbacks;
    private readonly string _sessionToken;
    private readonly CancellationToken _cancellationToken;
    private readonly MapMaskPointDataService _pointDataService;
    private readonly object _stateLock = new();
    private MapMaskPointDataSnapshot _snapshot = new();
    private MapMaskDrawCommand _latestCommand = new(null, null, null);
    private bool _hasDrawCommand;
    private int _loadVersion;
    private int _catalogVersion;
    private int _initialized;
    private bool? _lastPublishedBigMapState;
    private IReadOnlyList<MaskMapPointLabel>? _labelCategories;
    private Task<IReadOnlyList<MaskMapPointLabel>>? _labelCatalogLoadTask;

    public MacMapMaskRuntimePlatform(RuntimeLayout layout, ILoggerFactory loggerFactory,
        PlatformCallbackChannel callbacks, string sessionToken, CancellationToken cancellationToken)
    {
        _callbacks = callbacks;
        _sessionToken = sessionToken;
        _cancellationToken = cancellationToken;
        Logger = loggerFactory.CreateLogger<MapMaskTrigger>();
        var root = LoadRoot(layout);
        Config = root["mapMaskConfig"]?.Deserialize<MapMaskConfig>(ConfigJson.Options) ?? new MapMaskConfig();
        MapMatchingMethod = root["pathingConditionConfig"]?["mapMatchingMethod"]?.GetValue<string>() ?? "FeatureMatch";
        var cache = new CachingService(new Lazy<ICacheProvider>(() =>
            new MemoryCacheProvider(new MemoryCache(new MemoryCacheOptions()))));
        _pointDataService = new MapMaskPointDataService(new MaskMapPointService(
            loggerFactory.CreateLogger<MaskMapPointService>(),
            cache,
            new HoYoLabMapApiService(() => Config),
            new MihoyoMapApiService(),
            new KongyingTavernApiService(),
            () => Config,
            () => MapMatchingMethod));
    }

    public MapMaskConfig Config { get; }
    public string MapMatchingMethod { get; }
    public ILogger<MapMaskTrigger> Logger { get; }

    public object GetStatus()
    {
        lock (_stateLock)
        {
            return new
            {
                initialized = Volatile.Read(ref _initialized) == 1,
                points = _snapshot.Points.Count,
                hasDrawCommand = _hasDrawCommand,
                isInBigMapUi = _latestCommand.IsInBigMapUi,
                bigMapViewport = DescribeViewport(_latestCommand.BigMapViewport),
                loadVersion = Volatile.Read(ref _loadVersion)
            };
        }
    }

    public void Initialize()
    {
        if (Interlocked.Exchange(ref _initialized, 1) != 0)
        {
            return;
        }

        PublishPointData(_snapshot, true);
        ReloadPoints();
    }

    public void UpdateConfig(MapMaskConfig config)
    {
        var sourceChanged = Config.MapPointApiProvider != config.MapPointApiProvider ||
                            !string.Equals(Config.HoYoLabLanguage, config.HoYoLabLanguage,
                                StringComparison.OrdinalIgnoreCase);
        Config.MiniMapMaskEnabled = config.MiniMapMaskEnabled;
        Config.MapPointApiProvider = config.MapPointApiProvider;
        Config.HoYoLabLanguage = config.HoYoLabLanguage;
        if (sourceChanged)
        {
            lock (_stateLock)
            {
                _catalogVersion++;
                _labelCategories = null;
                _labelCatalogLoadTask = null;
            }
            ReloadPoints();
        }
    }

    public async Task<object> GetPointCatalogAsync(CancellationToken cancellationToken)
    {
        var categories = await GetLabelCategoriesAsync(cancellationToken);
        return categories.Select(DescribeLabel).ToArray();
    }

    public object GetPointSelection()
    {
        var state = MapMaskStateStorage.Read(MapMaskStateStorage.GetDataSourceKey(Config));
        return new
        {
            selectedIds = state.SelectedLabelItems.Select(item => item.Id).ToArray()
        };
    }

    public async Task<object> SavePointSelectionAsync(
        IReadOnlyCollection<string> selectedIds,
        CancellationToken cancellationToken)
    {
        var requestedIds = selectedIds
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .ToHashSet(StringComparer.Ordinal);
        MaskMapPointLabel[] labels = [];
        if (requestedIds.Count > 0)
        {
            var categories = await GetLabelCategoriesAsync(cancellationToken);
            labels = FlattenLabels(categories)
                .Where(label => requestedIds.Contains(label.LabelId))
                .GroupBy(label => label.LabelId, StringComparer.Ordinal)
                .Select(group => group.First())
                .ToArray();
            if (labels.Length != requestedIds.Count)
            {
                throw new ArgumentException("selectedIds contains an unknown MapMask label.");
            }
        }

        var dataSourceKey = MapMaskStateStorage.GetDataSourceKey(Config);
        MapMaskStateStorage.Update(dataSourceKey, state =>
            state.SelectedLabelItems = labels.Select(label => new MapMaskSelectedLabelState
            {
                Id = label.LabelId,
                LabelIds = label.LabelIds.ToList(),
                ParentId = label.ParentId,
                Name = label.Name,
                IconUrl = label.IconUrl,
                PointCount = label.PointCount
            }).ToList());
        ReloadPoints();
        return GetPointSelection();
    }

    private async Task<IReadOnlyList<MaskMapPointLabel>> GetLabelCategoriesAsync(
        CancellationToken cancellationToken)
    {
        Task<IReadOnlyList<MaskMapPointLabel>> loadTask;
        int version;
        lock (_stateLock)
        {
            if (_labelCategories != null)
            {
                return _labelCategories;
            }

            version = _catalogVersion;
            loadTask = _labelCatalogLoadTask ??=
                _pointDataService.GetLabelCategoriesAsync(_cancellationToken);
        }

        IReadOnlyList<MaskMapPointLabel> categories;
        try
        {
            categories = await loadTask.WaitAsync(cancellationToken);
        }
        catch
        {
            lock (_stateLock)
            {
                if (ReferenceEquals(_labelCatalogLoadTask, loadTask))
                {
                    _labelCatalogLoadTask = null;
                }
            }
            throw;
        }

        lock (_stateLock)
        {
            if (version == _catalogVersion)
            {
                _labelCategories = categories;
                if (ReferenceEquals(_labelCatalogLoadTask, loadTask))
                {
                    _labelCatalogLoadTask = null;
                }
                return categories;
            }
        }

        return await GetLabelCategoriesAsync(cancellationToken);
    }

    public void Publish(MapMaskDrawCommand command)
    {
        MapMaskDrawCommand latest;
        bool shouldPublish;
        lock (_stateLock)
        {
            var next = new MapMaskDrawCommand(
                command.IsInBigMapUi ?? _latestCommand.IsInBigMapUi,
                command.BigMapViewport ?? _latestCommand.BigMapViewport,
                command.MiniMapViewport ?? _latestCommand.MiniMapViewport);
            shouldPublish = !_hasDrawCommand || next != _latestCommand;
            _latestCommand = next;
            _hasDrawCommand = true;
            latest = _latestCommand;
        }

        if (shouldPublish)
        {
            PublishViewport(latest);
        }
    }

    private void ReloadPoints()
    {
        var version = Interlocked.Increment(ref _loadVersion);
        _ = LoadPointsAsync(version);
    }

    private async Task LoadPointsAsync(int version)
    {
        try
        {
            var snapshot = await _pointDataService.LoadAsync(Config, _cancellationToken);
            lock (_stateLock)
            {
                if (version != Volatile.Read(ref _loadVersion))
                {
                    return;
                }
                _snapshot = snapshot;
            }
            PublishPointData(snapshot, false);
        }
        catch (OperationCanceledException) when (_cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            lock (_stateLock)
            {
                if (version != Volatile.Read(ref _loadVersion))
                {
                    return;
                }
            }
            Logger.LogWarning(exception, "加载地图遮罩点位失败");
            PublishPointData(new MapMaskPointDataSnapshot(), false);
        }
    }

    private static object DescribeLabel(MaskMapPointLabel label) => new
    {
        id = label.LabelId,
        parentId = label.ParentId,
        name = label.Name,
        iconUrl = label.IconUrl,
        pointCount = label.PointCount,
        children = label.Children.Select(DescribeLabel).ToArray()
    };

    private static IEnumerable<MaskMapPointLabel> FlattenLabels(
        IEnumerable<MaskMapPointLabel> labels)
    {
        foreach (var label in labels)
        {
            yield return label;
            foreach (var child in FlattenLabels(label.Children))
            {
                yield return child;
            }
        }
    }

    private void PublishPointData(MapMaskPointDataSnapshot snapshot, bool isLoading)
    {
        var response = _callbacks.InvokeAsync("overlay.command", JObject.FromObject(new
        {
            name = "MapMask",
            operation = "setMapPointData",
            isLoading,
            points = snapshot.Points.Select(point =>
            {
                snapshot.Labels.TryGetValue(point.LabelId, out var label);
                return new
                {
                    id = point.Id,
                    label = label?.Name ?? $"点位 {point.Id}",
                    iconUrl = label?.IconUrl ?? string.Empty,
                    imageX = point.ImageX,
                    imageY = point.ImageY,
                    isHidden = point.IsHidden
                };
            }).ToArray()
        }), _sessionToken, _cancellationToken).GetAwaiter().GetResult();
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException("MapMask point-data command was not acknowledged.");
    }

    private void PublishViewport(MapMaskDrawCommand command)
    {
        if (command.IsInBigMapUi != _lastPublishedBigMapState)
        {
            _lastPublishedBigMapState = command.IsInBigMapUi;
            Logger.LogInformation("MapMask 大地图状态切换为 {IsInBigMapUi}", command.IsInBigMapUi);
        }
        var response = _callbacks.InvokeAsync("overlay.command", JObject.FromObject(new
        {
            name = "MapMask",
            operation = "setMapViewport",
            isInBigMapUi = command.IsInBigMapUi,
            bigMapViewport = DescribeViewport(command.BigMapViewport),
            miniMapViewport = DescribeViewport(command.MiniMapViewport)
        }), _sessionToken, _cancellationToken).GetAwaiter().GetResult();
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException("MapMask viewport command was not acknowledged.");
    }

    private static object? DescribeViewport(MapMaskViewport? viewport) => viewport is { } value
        ? new { x = value.X, y = value.Y, width = value.Width, height = value.Height }
        : null;

    private static JsonObject LoadRoot(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return new JsonObject();
        return JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
    }
}
