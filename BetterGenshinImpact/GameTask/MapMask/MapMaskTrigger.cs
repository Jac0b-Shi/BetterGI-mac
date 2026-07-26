using System;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.Core.Recognition.OpenCv;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.Common.Element.Assets;
using BetterGenshinImpact.GameTask.Common.Map.Maps;
using BetterGenshinImpact.GameTask.Common.Map.Maps.Base;
using BetterGenshinImpact.GameTask.Common.Map.Maps.Layer;
using BetterGenshinImpact.GameTask.Model.Area;
using Microsoft.Extensions.Logging;
using OpenCvSharp;

namespace BetterGenshinImpact.GameTask.MapMask;

/// <summary>
/// 地图遮罩触发器
/// </summary>
public class MapMaskTrigger : ITaskTrigger
{
    private readonly IMapMaskRuntimePlatform _platform = MapMaskRuntimePlatform.Current;
    private ILogger<MapMaskTrigger> Logger => _platform.Logger;

    public string Name => "地图遮罩";
    public bool IsEnabled { get; set; }
    public int Priority => 1; // 低优先级
    public bool IsExclusive => false;

    public GameUiCategory SupportedGameUiCategory => GameUiCategory.Unknown;

    public bool SupportsGameUiCategory(GameUiCategory category) =>
        category is GameUiCategory.Unknown or GameUiCategory.BigMap;

    private MapMaskConfig Config => _platform.Config;

    private readonly TemplateMatchStabilityDetector _detector = new();

    private DateTime _prevExecute = DateTime.MinValue;

    // 图像连续稳定次数
    private int _stableCount = 0;

    private OpenCvSharp.Rect _prevRect = default;
    private readonly object _prevRectLock = new();

    private const int RectDebounceThreshold = 3;

    private readonly NavigationInstance _navigationInstance = new();
    private readonly object _navigationLock = new();

    private sealed class PendingUiUpdate
    {
        public long Generation { get; init; }
        public bool? IsInBigMapUi { get; init; }
        public MapMaskViewport? BigMapViewport { get; init; }
        public MapMaskViewport? MiniMapViewport { get; init; }
    }

    private PendingUiUpdate? _pendingUiUpdate;
    private int _uiApplyScheduled;

    private sealed class ComputeWorkItem : IDisposable
    {
        public required long Generation { get; init; }
        public required string MapMatchingMethod { get; init; }
        public Mat? Mat { get; set; }

        public void Dispose()
        {
            Mat?.Dispose();
            Mat = null;
        }
    }

    private ComputeWorkItem? _pendingBigMapCompute;
    private int _bigMapWorkerRunning;
    private ComputeWorkItem? _pendingMiniMapCompute;
    private int _miniMapWorkerRunning;
    private long _captureCount;
    private long _bigMapMatchAttempts;
    private long _bigMapMatchSuccesses;
    private long _bigMapMatchFailures;
    private long _bigMapMatchRejected;
    private long _miniMapMatchAttempts;
    private long _miniMapMatchSuccesses;
    private long _miniMapMatchFailures;
    private long _uiApplyCount;
    private long _uiApplyFailures;
    private long _generation;
    private int _lastCaptureInBigMap;
    private string? _lastBigMapMatchError;
    private string? _lastBigMapRawRect;
    private string? _lastMiniMapMatchError;
    private string? _lastMiniMapPoint;
    private string? _lastUiApplyError;

    public bool IsInBigMapUi => Volatile.Read(ref _lastCaptureInBigMap) == 1;

    public object GetRuntimeStatus() => new
    {
        captures = Interlocked.Read(ref _captureCount),
        lastCaptureInBigMap = IsInBigMapUi,
        bigMapMatchAttempts = Interlocked.Read(ref _bigMapMatchAttempts),
        bigMapMatchSuccesses = Interlocked.Read(ref _bigMapMatchSuccesses),
        bigMapMatchFailures = Interlocked.Read(ref _bigMapMatchFailures),
        bigMapMatchRejected = Interlocked.Read(ref _bigMapMatchRejected),
        lastBigMapMatchError = Volatile.Read(ref _lastBigMapMatchError),
        lastBigMapRawRect = Volatile.Read(ref _lastBigMapRawRect),
        miniMapMatchAttempts = Interlocked.Read(ref _miniMapMatchAttempts),
        miniMapMatchSuccesses = Interlocked.Read(ref _miniMapMatchSuccesses),
        miniMapMatchFailures = Interlocked.Read(ref _miniMapMatchFailures),
        lastMiniMapMatchError = Volatile.Read(ref _lastMiniMapMatchError),
        lastMiniMapPoint = Volatile.Read(ref _lastMiniMapPoint),
        uiApplyScheduled = Volatile.Read(ref _uiApplyScheduled) == 1,
        uiApplyCount = Interlocked.Read(ref _uiApplyCount),
        uiApplyFailures = Interlocked.Read(ref _uiApplyFailures),
        lastUiApplyError = Volatile.Read(ref _lastUiApplyError)
    };

    /// <summary>
    /// 初始化触发器状态，并在关闭时同步隐藏遮罩UI
    /// </summary>
    public void Init()
    {
        IsEnabled = Config.Enabled;

        if (!IsEnabled)
        {
            Invalidate();
        }
    }

    public void Invalidate()
    {
        Interlocked.Increment(ref _generation);
        Interlocked.Exchange(ref _pendingBigMapCompute, null)?.Dispose();
        Interlocked.Exchange(ref _pendingMiniMapCompute, null)?.Dispose();
        Interlocked.Exchange(ref _pendingUiUpdate, null);
        Interlocked.Exchange(ref _lastCaptureInBigMap, 0);
        lock (_navigationLock)
        {
            _navigationInstance.Reset();
        }
        lock (_prevRectLock)
        {
            _prevRect = default;
        }
        _platform.Publish(new(false, new(0, 0, 0, 0), new(0, 0, 0, 0)));
    }

    public void ObserveBigMapPresence(bool isInBigMapUi)
    {
        var wasInBigMapUi = Interlocked.Exchange(
            ref _lastCaptureInBigMap, isInBigMapUi ? 1 : 0) == 1;
        if (isInBigMapUi == wasInBigMapUi)
        {
            return;
        }

        if (!isInBigMapUi)
        {
            Invalidate();
            return;
        }

        lock (_navigationLock)
        {
            _navigationInstance.Reset();
        }
    }

    /// <summary>
    /// 接收每帧截图内容并驱动大地图/小地图的异步定位与UI更新
    /// </summary>
    /// <param name="content">捕获到的画面内容</param>
    public void OnCapture(CaptureContent content)
    {
        if ((DateTime.Now - _prevExecute).TotalMilliseconds <= 50)
        {
            return;
        }

        _prevExecute = DateTime.Now;

        try
        {
            var region = content.CaptureRectArea;
            var inBigMapUi = content.CurrentGameUiCategory == GameUiCategory.BigMap || Bv.IsInBigMapUi(region);
            ObserveBigMapPresence(inBigMapUi);
            var generation = Volatile.Read(ref _generation);
            Interlocked.Increment(ref _captureCount);
            var mapMatchingMethod = _platform.MapMatchingMethod;
            PendingUiUpdate? update = null;

            if (inBigMapUi)
            {
                if (_detector.IsStable(region.CacheGreyMat))
                {
                    _stableCount++;
                    if (_stableCount >= 20)
                    {
                        _stableCount = 0;
                    }
                }
                else
                {
                    _stableCount = 0;
                }

                if (_stableCount == 0)
                {
                    var greyMat = region.CacheGreyMat.Clone();
                    EnqueueBigMapCompute(new ComputeWorkItem
                    {
                        Generation = generation,
                        MapMatchingMethod = mapMatchingMethod,
                        Mat = greyMat
                    });
                }
            }
            else
            {
                // 主界面上展示小地图
                if (Config.MiniMapMaskEnabled)
                {
                    if (Bv.IsInMainUi(region))
                    {
                        var srcMat = region.SrcMat.Clone();
                        EnqueueMiniMapCompute(new ComputeWorkItem
                        {
                            Generation = generation,
                            MapMatchingMethod = mapMatchingMethod,
                            Mat = srcMat
                        });

                        // 自动记录路径
                        if (Config.PathAutoRecordEnabled)
                        {
                            // ...
                        }
                    }
                    else
                    {
                        update = new PendingUiUpdate
                        {
                            Generation = generation,
                            MiniMapViewport = new MapMaskViewport(0, 0, 0, 0)
                        };
                    }
                }

                lock (_prevRectLock)
                {
                    _prevRect = default;
                }
            }

            update = update == null
                ? new PendingUiUpdate { Generation = generation, IsInBigMapUi = inBigMapUi }
                : new PendingUiUpdate
                {
                    Generation = generation,
                    IsInBigMapUi = inBigMapUi,
                    BigMapViewport = update.BigMapViewport,
                    MiniMapViewport = update.MiniMapViewport
                };

            QueueUiUpdate(update);
        }
        catch (Exception e)
        {
            Logger.LogDebug(e, "实时地图定位时发生异常");
        }
    }

    /// <summary>
    /// 入队大地图定位计算，仅保留正在执行与最新任务
    /// </summary>
    /// <param name="workItem">计算任务</param>
    private void EnqueueBigMapCompute(ComputeWorkItem workItem)
    {
        var previous = Interlocked.Exchange(ref _pendingBigMapCompute, workItem);
        previous?.Dispose();

        if (Interlocked.Exchange(ref _bigMapWorkerRunning, 1) == 0)
        {
            _ = Task.Run(BigMapWorkerLoop);
        }
    }

    /// <summary>
    /// 入队小地图定位计算，仅保留正在执行与最新任务
    /// </summary>
    /// <param name="workItem">计算任务</param>
    private void EnqueueMiniMapCompute(ComputeWorkItem workItem)
    {
        var previous = Interlocked.Exchange(ref _pendingMiniMapCompute, workItem);
        previous?.Dispose();

        if (Interlocked.Exchange(ref _miniMapWorkerRunning, 1) == 0)
        {
            _ = Task.Run(MiniMapWorkerLoop);
        }
    }

    /// <summary>
    /// 大地图计算工作线程循环
    /// </summary>
    private void BigMapWorkerLoop()
    {
        while (true)
        {
            var workItem = Interlocked.Exchange(ref _pendingBigMapCompute, null);
            if (workItem == null)
            {
                Interlocked.Exchange(ref _bigMapWorkerRunning, 0);
                if (Volatile.Read(ref _pendingBigMapCompute) != null && Interlocked.Exchange(ref _bigMapWorkerRunning, 1) == 0)
                {
                    continue;
                }

                return;
            }

            try
            {
                ProcessBigMapCompute(workItem);
            }
            catch (Exception e)
            {
                Logger.LogDebug(e, "地图遮罩异步计算时发生异常");
            }
            finally
            {
                workItem.Dispose();
            }
        }
    }

    /// <summary>
    /// 小地图计算工作线程循环
    /// </summary>
    private void MiniMapWorkerLoop()
    {
        while (true)
        {
            var workItem = Interlocked.Exchange(ref _pendingMiniMapCompute, null);
            if (workItem == null)
            {
                Interlocked.Exchange(ref _miniMapWorkerRunning, 0);
                if (Volatile.Read(ref _pendingMiniMapCompute) != null && Interlocked.Exchange(ref _miniMapWorkerRunning, 1) == 0)
                {
                    continue;
                }

                return;
            }

            try
            {
                ProcessMiniMapCompute(workItem);
            }
            catch (Exception e)
            {
                Logger.LogDebug(e, "地图遮罩异步计算时发生异常");
            }
            finally
            {
                workItem.Dispose();
            }
        }
    }

    /// <summary>
    /// 执行大地图定位计算并产出UI更新
    /// </summary>
    /// <param name="workItem">计算任务</param>
    private void ProcessBigMapCompute(ComputeWorkItem workItem)
    {
        if (workItem.Mat == null || workItem.Generation != Volatile.Read(ref _generation))
        {
            return;
        }

        OpenCvSharp.Rect prevRect;
        lock (_prevRectLock)
        {
            prevRect = _prevRect;
        }

        Interlocked.Increment(ref _bigMapMatchAttempts);
        OpenCvSharp.Rect rect256;
        try
        {
            var sceneMap = (SceneBaseMap)MapManager.GetMap(MapTypes.Teyvat, workItem.MapMatchingMethod);
            rect256 = BigMapTeyvat256Layer.GetInstance(sceneMap).GetBigMapRect(workItem.Mat, prevRect);
            Volatile.Write(ref _lastBigMapMatchError, null);
        }
        catch (Exception exception)
        {
            Interlocked.Increment(ref _bigMapMatchFailures);
            Volatile.Write(ref _lastBigMapMatchError, exception.ToString());
            throw;
        }
        if (rect256 == default)
        {
            Interlocked.Increment(ref _bigMapMatchFailures);
            return;
        }

        Volatile.Write(ref _lastBigMapRawRect,
            $"{rect256.X},{rect256.Y},{rect256.Width},{rect256.Height}");

        if (rect256 is { Width: < 50, Height: < 40 } || rect256 is { Width: > 3000, Height: > 1800 })
        {
            Interlocked.Increment(ref _bigMapMatchRejected);
            lock (_prevRectLock)
            {
                _prevRect = default;
            }
            return;
        }

        Interlocked.Increment(ref _bigMapMatchSuccesses);

        lock (_prevRectLock)
        {
            _prevRect = rect256;
        }

        const int s = TeyvatMap.BigMap256ScaleTo2048;
        var rect2048 = new MapMaskViewport(rect256.X * s, rect256.Y * s, rect256.Width * s, rect256.Height * s);
        QueueUiUpdate(new PendingUiUpdate
        {
            Generation = workItem.Generation,
            BigMapViewport = rect2048
        });
    }

    /// <summary>
    /// 执行小地图定位计算并产出UI更新
    /// </summary>
    /// <param name="workItem">计算任务</param>
    private void ProcessMiniMapCompute(ComputeWorkItem workItem)
    {
        if (workItem.Mat == null || workItem.Generation != Volatile.Read(ref _generation))
        {
            return;
        }

        using var imageRegion = new ImageRegion(workItem.Mat, 0, 0);
        workItem.Mat = null;

        Interlocked.Increment(ref _miniMapMatchAttempts);
        Point2f miniPoint;
        try
        {
            lock (_navigationLock)
            {
                miniPoint = _navigationInstance.GetPositionStable(
                    imageRegion, nameof(MapTypes.Teyvat), workItem.MapMatchingMethod);
            }
            Volatile.Write(ref _lastMiniMapMatchError, null);
        }
        catch (Exception exception)
        {
            Interlocked.Increment(ref _miniMapMatchFailures);
            Volatile.Write(ref _lastMiniMapMatchError, exception.ToString());
            throw;
        }

        if (miniPoint != default)
        {
            Interlocked.Increment(ref _miniMapMatchSuccesses);
            Volatile.Write(ref _lastMiniMapPoint, $"{miniPoint.X:F3},{miniPoint.Y:F3}");
            double viewportSize = MapAssets.MimiMapRect1080P.Width;
            QueueUiUpdate(new PendingUiUpdate
            {
                Generation = workItem.Generation,
                MiniMapViewport = new MapMaskViewport(
                    miniPoint.X - viewportSize / 2.0,
                    miniPoint.Y - viewportSize / 2.0,
                    viewportSize,
                    viewportSize)
            });
        }
        else
        {
            Interlocked.Increment(ref _miniMapMatchFailures);
            Volatile.Write(ref _lastMiniMapPoint, null);
            QueueUiUpdate(new PendingUiUpdate
            {
                Generation = workItem.Generation,
                MiniMapViewport = new MapMaskViewport(0, 0, 0, 0)
            });
        }
    }

    /// <summary>
    /// 合并并异步投递UI更新
    /// </summary>
    /// <param name="update">待应用的UI更新</param>
    private void QueueUiUpdate(PendingUiUpdate update)
    {
        if (update.Generation != Volatile.Read(ref _generation))
        {
            return;
        }

        while (true)
        {
            var current = Volatile.Read(ref _pendingUiUpdate);
            var sameGeneration = current?.Generation == update.Generation ? current : null;
            var merged = new PendingUiUpdate
            {
                Generation = update.Generation,
                IsInBigMapUi = update.IsInBigMapUi ?? sameGeneration?.IsInBigMapUi,
                BigMapViewport = update.BigMapViewport ?? sameGeneration?.BigMapViewport,
                MiniMapViewport = update.MiniMapViewport ?? sameGeneration?.MiniMapViewport
            };
            if (ReferenceEquals(
                    Interlocked.CompareExchange(ref _pendingUiUpdate, merged, current),
                    current))
            {
                break;
            }
        }
        TryScheduleUiApply();
    }

    /// <summary>
    /// 确保仅有一个UI更新调度在队列中
    /// </summary>
    private void TryScheduleUiApply()
    {
        if (Interlocked.Exchange(ref _uiApplyScheduled, 1) == 0)
        {
            Task.Run(ApplyPendingUiUpdate);
        }
    }

    /// <summary>
    /// 在UI线程应用合并后的更新
    /// </summary>
    private void ApplyPendingUiUpdate()
    {
        try
        {
            var update = Interlocked.Exchange(ref _pendingUiUpdate, null);
            if (update != null && update.Generation == Volatile.Read(ref _generation))
            {
                _platform.Publish(Config.Enabled
                    ? new(update.IsInBigMapUi, update.BigMapViewport, update.MiniMapViewport)
                    : new(false, new(0, 0, 0, 0), new(0, 0, 0, 0)));
                Interlocked.Increment(ref _uiApplyCount);
                Volatile.Write(ref _lastUiApplyError, null);
            }
        }
        catch (Exception exception)
        {
            Interlocked.Increment(ref _uiApplyFailures);
            Volatile.Write(ref _lastUiApplyError, exception.ToString());
            Logger.LogError(exception, "地图遮罩 UI 更新失败");
        }
        finally
        {
            Interlocked.Exchange(ref _uiApplyScheduled, 0);
            if (Volatile.Read(ref _pendingUiUpdate) != null)
            {
                TryScheduleUiApply();
            }
        }
    }
}
