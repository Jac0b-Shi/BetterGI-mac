using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.Model;
using BetterGenshinImpact.View.Controls.Webview;
using BetterGenshinImpact.ViewModel.Pages;
using Microsoft.Extensions.Logging;
using System;
using System.Windows;

namespace BetterGenshinImpact.GameTask.AutoPathing;

public class PathRecorder : Singleton<PathRecorder>
{
    private readonly PathRecorderTask _task;
    private WebpageWindow? _webWindow;

    private PathRecorder()
    {
        _task = new PathRecorderTask(
            new WindowsRuntimePlatform(this),
            new NavigationPathRecorderPositionProvider());
    }

    public bool IsRecording => _task.IsRecording;

    public PathRecorderResult Toggle() => _task.Toggle();

    public PathRecorderResult Start() => _task.Start();

    public PathRecorderResult AddWaypoint(string waypointType = "") =>
        _task.AddWaypoint(waypointType);

    public PathRecorderResult Save() => _task.Save();

    public void OpenEditorInWebView(string mapName = "Teyvat")
    {
        if (_webWindow is not { IsVisible: true })
        {
            _webWindow = new WebpageWindow
            {
                Title = "地图路径点编辑器",
                Width = 1366,
                Height = 768,
                WindowState = WindowState.Maximized,
            };
            _webWindow.Closed += (_, _) => _webWindow = null;
            _webWindow.Panel!.DownloadFolderPath =
                MapPathingViewModel.PathJsonPath;

            var htmlPath = Global.Absolute(@"Assets\Map\Editor\index.html");
            var uri = new UriBuilder(htmlPath);
            var query = System.Web.HttpUtility.ParseQueryString(string.Empty);
            query["map"] = mapName;
            uri.Query = query.ToString();
            _webWindow.NavigateToFile(uri.ToString());
            _webWindow.Panel!.OnWebViewInitializedAction = () =>
            {
                _webWindow.Panel!.WebView.CoreWebView2.AddHostObjectToScript(
                    "mapEditorWebBridge",
                    new BetterGenshinImpact.Core.Script.WebView
                        .MapEditorWebBridge());
                _webWindow.Panel!.WebView.CoreWebView2.AddHostObjectToScript(
                    "fileAccessBridge",
                    new BetterGenshinImpact.Core.Script.WebView.FileAccessBridge(
                        Global.Absolute("User/AutoPathing")));
            };
            _webWindow.Show();
        }
        else
        {
            _webWindow.Activate();
        }
    }

    private sealed class WindowsRuntimePlatform(PathRecorder owner)
        : IPathRecorderRuntimePlatform
    {
        public PathRecorderSettings Settings => new(
            TaskContext.Instance().Config.DevConfig.RecordMapName,
            TaskContext.Instance().Config.PathingConditionConfig
                .MapMatchingMethod,
            MapPathingViewModel.PathJsonPath,
            Global.Version);

        public bool IsEditorOpen => owner._webWindow is not null;

        public ILogger Logger => TaskControl.Logger;

        public void PublishWaypoint(Waypoint waypoint)
        {
            if (owner._webWindow is null)
                return;
            BetterGenshinImpact.Helpers.UIDispatcherHelper.Invoke(() =>
                owner._webWindow.WebView.ExecuteScriptAsync(
                    $"addNewPoint({waypoint.X},{waypoint.Y})"));
        }
    }
}
