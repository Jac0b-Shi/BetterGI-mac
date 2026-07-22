using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.UseRedeemCode;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacUseRedemptionCodeRuntimePlatform(
    Func<ISystemInfo> systemInfo,
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken shutdownToken,
    ILogger<UseRedemptionCodeTask> logger) : IUseRedemptionCodeRuntimePlatform
{
    public ISystemInfo SystemInfo => systemInfo();
    public bool PropagateTaskExceptions => true;
    public ILogger<UseRedemptionCodeTask> Logger { get; } = logger;

    public void SetClipboardText(string text) => RequireAcknowledgement(
        "clipboard.write", JObject.FromObject(new { text }));

    public void ClearClipboard() => RequireAcknowledgement("clipboard.clear", null);

    private void RequireAcknowledgement(string method, JObject? parameters)
    {
        var response = callbacks.InvokeAsync(method, parameters, sessionToken, shutdownToken)
            .GetAwaiter().GetResult();
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException($"{method} did not return acknowledged=true.");
    }
}
