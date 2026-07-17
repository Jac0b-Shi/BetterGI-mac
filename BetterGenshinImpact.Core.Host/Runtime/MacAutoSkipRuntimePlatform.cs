using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.Common;
using Microsoft.Extensions.Logging;
using BetterGenshinImpact.Core.Host.Transport;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoSkipRuntimePlatform(
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken cancellationToken) : IAutoSkipRuntimePlatform
{
    public IAutoSkipAudioWaiter CreateAudioWaiter() => new UnavailableAudioWaiter();
    public void SimulateBackgroundAction(GIActions action) =>
        TaskControlPlatform.Current.SimulateAction(action, KeyType.KeyPress);
    public void PressBackgroundKey(int windowsVirtualKey) =>
        TaskControlPlatform.Current.PressKey(windowsVirtualKey);
    public void BackgroundLeftButtonClick() => TaskControlPlatform.Current.LeftButtonClick();
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

    private sealed class UnavailableAudioWaiter : IAutoSkipAudioWaiter
    {
        public bool IsWaiting => false;
        public void Cancel() { }
        public void ReleaseDetector() { }
        public bool Start(int maxWaitMilliseconds, int fallbackDelayMilliseconds, ILogger logger) =>
            throw new CapabilityUnavailableException(
                "AutoSkip process-audio VAD is not available on the macOS Core Host.");
        public bool Update(ILogger logger) => true;
    }
}
