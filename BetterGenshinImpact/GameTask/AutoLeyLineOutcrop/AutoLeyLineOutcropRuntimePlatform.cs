using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.GameTask.AutoLeyLineOutcrop;

public enum AutoLeyLineOutcropNotification
{
    Error,
    Summary,
}

public interface IAutoLeyLineOutcropRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
    IOcrService OcrService { get; }
    AutoFightConfig AutoFightConfig { get; }
    string PickKey { get; }
    double MapScaleFactor { get; }
    ILogger<AutoLeyLineOutcropTask> Logger { get; }
    void Notify(AutoLeyLineOutcropNotification notification, string message);
    void EnsureOverlayVisible();
    void RefreshOverlay();
    void RestoreOverlayVisible();
}
