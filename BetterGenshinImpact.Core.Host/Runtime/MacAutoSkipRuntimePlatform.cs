using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.Common;
using Microsoft.Extensions.Logging;
using BetterGenshinImpact.Core.Host.Transport;
using Newtonsoft.Json.Linq;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Platform.Abstractions;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.AutoSkip.Audio;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoSkipRuntimePlatform(
    Func<ISystemInfo> getSystemInfo,
    ILoggerFactory loggerFactory,
    IOcrService ocrService,
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken cancellationToken,
    ForegroundInputCoordinator inputCoordinator,
    IAutoPickConfigProvider autoPickConfigProvider) : IAutoSkipRuntimePlatform
{
    public ISystemInfo SystemInfo => getSystemInfo();
    public string PickKey => autoPickConfigProvider.AutoPickConfig.PickKey;
    public ILogger<T> GetLogger<T>() => loggerFactory.CreateLogger<T>();
    public IOcrService OcrService { get; } = ocrService;
    public bool IsGameActive() => Invoke("window.metrics", null).Value<bool?>("isActive")
        ?? throw new InvalidDataException("window.metrics did not return isActive.");
    public void ActivateGameWindow() => inputCoordinator.WaitForGameFocus(cancellationToken);
    public IAutoSkipAudioWaiter CreateAudioWaiter() => new DialogueOptionAudioWaiter(
        () => SystemInfo.GameProcessId,
        processId => new MacProcessAudioSampleCapture(
            processId, callbacks, sessionToken, cancellationToken));
    public void SimulateBackgroundAction(GIActions action) =>
        TaskControlPlatform.Current.SimulateAction(action, KeyType.KeyPress);
    public void PressBackgroundKey(BgiKey key) => inputCoordinator.Dispatch(
        JObject.FromObject(new { action = "keyPress", key = key.ToString() }), cancellationToken);
    public void BackgroundLeftButtonClick() => TaskControlPlatform.Current.LeftButtonClick();
    public void BackgroundClick(Region region)
    {
        region.Move();
        BackgroundLeftButtonClick();
    }
    public void ReportError(string message)
    {
        var response = callbacks.InvokeAsync("dialog.request", JObject.FromObject(new
        {
            kind = "error",
            title = "BetterGI Core",
            message,
        }), sessionToken, cancellationToken).GetAwaiter().GetResult();
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException("dialog.request did not return acknowledged=true.");
    }

    private JToken Invoke(string method, JObject? parameters) => callbacks.InvokeAsync(
            method, parameters, sessionToken, cancellationToken).GetAwaiter().GetResult()
        ?? throw new InvalidDataException($"{method} returned an empty response.");

    private void RequireAcknowledgement(string method, JObject? parameters)
    {
        if (Invoke(method, parameters).Value<bool?>("acknowledged") != true)
            throw new InvalidDataException($"{method} did not return acknowledged=true.");
    }

}
