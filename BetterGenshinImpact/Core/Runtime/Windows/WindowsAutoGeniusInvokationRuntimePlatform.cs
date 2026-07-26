using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoGeniusInvokation;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.View.Windows;
using Microsoft.Extensions.Logging;
using OpenCvSharp;
using System.IO;
using System.Threading;
using NotifyService = BetterGenshinImpact.Service.Notification.Notify;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoGeniusInvokationRuntimePlatform :
    IAutoGeniusInvokationRuntimePlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public IOcrService OcrService => OcrFactory.Paddle;
    public bool DetailedErrorLogs => TaskContext.Instance().Config.DetailedErrorLogs;
    public bool PropagateTaskExceptions => false;
    public ILogger<T> GetLogger<T>() => App.GetLogger<T>();
    public ImageRegion Capture(bool forceNew = false) =>
        TaskControl.CaptureToRectArea(forceNew);
    public void EnsureGameActive(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        TaskControl.TrySuspend();
        TaskControlPlatform.Current.EnsureGameActive();
        cancellationToken.ThrowIfCancellationRequested();
    }

    public void ClickCapturePoint(double x, double y)
    {
        var rect = SystemInfo.CaptureAreaRect;
        DesktopRegion.DesktopRegionClick(rect.X + x, rect.Y + y);
    }

    public void MoveCapturePoint(double x, double y)
    {
        var rect = SystemInfo.CaptureAreaRect;
        DesktopRegion.DesktopRegionMove(rect.X + x, rect.Y + y);
    }

    public void LeftButtonDown() => TaskControl.LeftButtonDown();
    public void LeftButtonUp() => TaskControl.LeftButtonUp();

    public void WriteDiagnosticImage(string fileName, Mat image)
    {
        var directory = Global.Absolute("log");
        Directory.CreateDirectory(directory);
        Cv2.ImWrite(Path.Combine(directory, fileName), image);
    }

    public void ReportStrategyParseFailure(string message) =>
        ThemedMessageBox.Error(message, "策略解析失败");

    public void Notify(AutoGeniusInvokationNotification notification, string message) =>
        NotifyService.Event(notification == AutoGeniusInvokationNotification.Start
            ? "TcgStart"
            : "TcgEnd").Success(message);
}
