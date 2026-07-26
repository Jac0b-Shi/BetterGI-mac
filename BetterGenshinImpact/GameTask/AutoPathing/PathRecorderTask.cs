using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.GameTask.AutoPathing.Model.Enum;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.Map.Maps;
using BetterGenshinImpact.GameTask.Common.Map.Maps.Base;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using OpenCvSharp;
using System;
using System.IO;

namespace BetterGenshinImpact.GameTask.AutoPathing;

public sealed record PathRecorderSettings(
    string MapName,
    string MapMatchingMethod,
    string OutputDirectory,
    string BetterGIVersion);

public sealed record PathRecorderResult(
    [property: JsonProperty("state")] string State,
    [property: JsonProperty("waypointCount")] int WaypointCount,
    [property: JsonProperty("path")] string? Path = null);

public interface IPathRecorderRuntimePlatform
{
    PathRecorderSettings Settings { get; }

    bool IsEditorOpen { get; }

    ILogger Logger { get; }

    void PublishWaypoint(Waypoint waypoint);
}

public interface IPathRecorderPositionProvider
{
    void WarmUp(string matchingMethod);

    Point2f? GetCurrentPosition(string mapName, string matchingMethod);
}

public interface IPathRecorderAction
{
    PathRecorderResult Toggle();

    PathRecorderResult AddWaypoint(string waypointType = "");
}

public sealed class NavigationPathRecorderPositionProvider
    : IPathRecorderPositionProvider
{
    public void WarmUp(string matchingMethod) =>
        Navigation.WarmUp(matchingMethod);

    public Point2f? GetCurrentPosition(
        string mapName,
        string matchingMethod)
    {
        using var screen = TaskControl.CaptureToRectArea();
        var imagePosition = Navigation.GetPositionStable(
            screen,
            mapName,
            matchingMethod);
        return MapManager.GetMap(mapName, matchingMethod)
            .ConvertImageCoordinatesToGenshinMapCoordinates(imagePosition);
    }
}

public sealed class PathRecorderTask(
    IPathRecorderRuntimePlatform platform,
    IPathRecorderPositionProvider positionProvider,
    TimeProvider? timeProvider = null) : IPathRecorderAction
{
    private readonly object _lock = new();
    private readonly TimeProvider _timeProvider =
        timeProvider ?? TimeProvider.System;
    private PathingTask? _pathingTask;
    private bool _isRecording;

    public bool IsRecording
    {
        get
        {
            lock (_lock)
                return _isRecording;
        }
    }

    public PathRecorderResult Toggle()
    {
        lock (_lock)
            return _isRecording ? SaveLocked() : StartLocked();
    }

    public PathRecorderResult Start()
    {
        lock (_lock)
            return StartLocked();
    }

    public PathRecorderResult AddWaypoint(string waypointType = "")
    {
        lock (_lock)
        {
            if (!_isRecording)
                return new PathRecorderResult(
                    "inactive",
                    WaypointCount);

            var settings = Normalize(platform.Settings);
            var waypoint = CreateWaypoint(
                settings,
                string.IsNullOrEmpty(waypointType)
                    ? WaypointType.Path.Code
                    : waypointType);
            if (waypoint is null)
                return new PathRecorderResult(
                    "unrecognized",
                    WaypointCount);

            _pathingTask!.Positions.Add(waypoint);
            platform.Logger.LogInformation(
                "已添加途径点({x},{y})",
                waypoint.X,
                waypoint.Y);
            platform.PublishWaypoint(waypoint);
            return new PathRecorderResult(
                "waypointAdded",
                WaypointCount);
        }
    }

    public PathRecorderResult Save()
    {
        lock (_lock)
            return SaveLocked();
    }

    private PathRecorderResult StartLocked()
    {
        var settings = Normalize(platform.Settings);
        positionProvider.WarmUp(settings.MapMatchingMethod);
        _pathingTask = new PathingTask();
        platform.Logger.LogInformation("开始路径点记录");
        if (settings.MapName == nameof(MapTypes.Teyvat))
        {
            platform.Logger.LogInformation(
                "如果需要切换其他地图，请在 {Msg} 中切换",
                "地图追踪——开发者工具");
        }

        var waypoint = CreateWaypoint(
            settings,
            WaypointType.Teleport.Code);
        if (waypoint is not null)
        {
            _pathingTask.Positions.Add(waypoint);
            if (platform.IsEditorOpen)
            {
                platform.Logger.LogInformation(
                    "已添加途径点({x},{y})",
                    waypoint.X,
                    waypoint.Y);
                platform.PublishWaypoint(waypoint);
            }
            else
            {
                platform.Logger.LogInformation(
                    "已创建初始路径点({x},{y})",
                    waypoint.X,
                    waypoint.Y);
            }
        }
        _isRecording = true;
        return new PathRecorderResult(
            "recording",
            WaypointCount);
    }

    private PathRecorderResult SaveLocked()
    {
        if (!_isRecording)
            return new PathRecorderResult(
                "inactive",
                WaypointCount);

        if (platform.IsEditorOpen)
        {
            platform.Logger.LogInformation(
                "路径点记录结束，请在录制编辑器中查看并编辑结果");
            platform.Logger.LogInformation(
                "如果要重新录制新的路径，请在录制编辑器中删除已有路径或创建新的路径");
            platform.Logger.LogInformation(
                "修改完毕后请务必记得导出路径！");
            _isRecording = false;
            return new PathRecorderResult(
                "editor",
                WaypointCount);
        }

        var settings = Normalize(platform.Settings);
        _pathingTask!.Info = new PathingTaskInfo
        {
            Name = "未命名路线",
            Type = PathingTaskType.Collect.Code,
            MapName = settings.MapName,
            MapMatchMethod = settings.MapMatchingMethod,
            BgiVersion = settings.BetterGIVersion,
        };
        Directory.CreateDirectory(settings.OutputDirectory);
        var name =
            $"{_timeProvider.GetLocalNow():yyyyMMdd_HHmmss}.json";
        var path = Path.Combine(settings.OutputDirectory, name);
        _pathingTask!.SaveToFile(path);
        platform.Logger.LogInformation(
            "录制编辑器未打开，直接保存路径点记录:{Name}",
            name);
        _isRecording = false;
        return new PathRecorderResult(
            "saved",
            WaypointCount,
            path);
    }

    private Waypoint? CreateWaypoint(
        PathRecorderSettings settings,
        string waypointType)
    {
        var position = positionProvider.GetCurrentPosition(
            settings.MapName,
            settings.MapMatchingMethod);
        if (position is null)
        {
            platform.Logger.LogWarning("未识别到当前位置！");
            return null;
        }

        return new Waypoint
        {
            X = position.Value.X,
            Y = position.Value.Y,
            Type = waypointType,
            MoveMode = MoveModeEnum.Walk.Code,
        };
    }

    private static PathRecorderSettings Normalize(
        PathRecorderSettings settings) =>
        settings with
        {
            MapName = string.IsNullOrEmpty(settings.MapName)
                ? nameof(MapTypes.Teyvat)
                : settings.MapName,
        };

    private int WaypointCount => _pathingTask?.Positions.Count ?? 0;
}
