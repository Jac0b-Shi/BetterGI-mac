using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Model.Area;
using Microsoft.Extensions.Logging;
using OpenCvSharp;
using System.Threading;

namespace BetterGenshinImpact.GameTask.AutoGeniusInvokation;

public enum AutoGeniusInvokationNotification
{
    Start,
    End,
}

public interface IAutoGeniusInvokationRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
    IOcrService OcrService { get; }
    bool DetailedErrorLogs { get; }
    bool PropagateTaskExceptions { get; }
    ILogger<T> GetLogger<T>();
    ImageRegion Capture(bool forceNew = false);
    void EnsureGameActive(CancellationToken cancellationToken);
    void ClickCapturePoint(double x, double y);
    void MoveCapturePoint(double x, double y);
    void LeftButtonDown();
    void LeftButtonUp();
    void WriteDiagnosticImage(string fileName, Mat image);
    void ReportStrategyParseFailure(string message);
    void Notify(AutoGeniusInvokationNotification notification, string message);
}
