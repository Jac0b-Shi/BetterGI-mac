using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoLeyLineOutcrop;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoLeyLineOutcropRuntimePlatform(
    Func<ISystemInfo> systemInfo,
    IOcrService ocrService,
    IAutoFightRuntimePlatform autoFightRuntimePlatform,
    IAutoPickConfigProvider autoPickConfigProvider,
    double mapScaleFactor,
    ILoggerFactory loggerFactory,
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken cancellationToken) : IAutoLeyLineOutcropRuntimePlatform
{
    public ISystemInfo SystemInfo => systemInfo();
    public IOcrService OcrService { get; } = ocrService;
    public AutoFightConfig AutoFightConfig => autoFightRuntimePlatform.AutoFightConfig;
    public string PickKey => autoPickConfigProvider.AutoPickConfig.PickKey;
    public double MapScaleFactor { get; } = mapScaleFactor;
    public ILogger<AutoLeyLineOutcropTask> Logger { get; } =
        loggerFactory.CreateLogger<AutoLeyLineOutcropTask>();

    public void Notify(AutoLeyLineOutcropNotification notification, string message)
    {
        var response = callbacks.InvokeAsync("notification.emit", JObject.FromObject(new
        {
            kind = notification == AutoLeyLineOutcropNotification.Error ? "error" : "info",
            message,
        }), sessionToken, cancellationToken).GetAwaiter().GetResult();
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException("notification.emit did not return acknowledged=true.");
    }

    public void EnsureOverlayVisible() { }
    public void RefreshOverlay() { }
    public void RestoreOverlayVisible() { }
}
