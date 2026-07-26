using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.AutoGeniusInvokation;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Model.Area;
using Microsoft.Extensions.Logging;
using OpenCvSharp;
using System.Threading;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoGeniusInvokationRuntimePlatform(
    RuntimeLayout layout,
    Func<ISystemInfo> systemInfo,
    IOcrService ocrService,
    ILoggerFactory loggerFactory) : IAutoGeniusInvokationRuntimePlatform
{
    public ISystemInfo SystemInfo => systemInfo();
    public IOcrService OcrService { get; } = ocrService;
    public bool DetailedErrorLogs => false;
    public bool PropagateTaskExceptions => true;
    public ILogger<T> GetLogger<T>() => loggerFactory.CreateLogger<T>();
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
        Directory.CreateDirectory(layout.LogPath);
        Cv2.ImWrite(Path.Combine(layout.LogPath, fileName), image);
    }

    public void ReportStrategyParseFailure(string message) =>
        GetLogger<ScriptParser>().LogError("{Message}", message);

    public void Notify(AutoGeniusInvokationNotification notification, string message) =>
        GetLogger<AutoGeniusInvokationTask>().LogInformation(
            "AutoGeniusInvokation {Notification}: {Message}", notification, message);
}
