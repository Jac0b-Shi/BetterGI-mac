using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.GameTask.UseRedeemCode;

public interface IUseRedemptionCodeRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
    bool PropagateTaskExceptions { get; }
    ILogger<UseRedemptionCodeTask> Logger { get; }
    void SetClipboardText(string text);
    void ClearClipboard();
}
