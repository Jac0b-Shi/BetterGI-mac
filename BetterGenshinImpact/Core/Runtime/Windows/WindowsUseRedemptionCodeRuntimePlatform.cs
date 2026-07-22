using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.UseRedeemCode;
using BetterGenshinImpact.Helpers;
using Microsoft.Extensions.Logging;
using System.Windows;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsUseRedemptionCodeRuntimePlatform :
    IUseRedemptionCodeRuntimePlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public bool PropagateTaskExceptions => false;
    public ILogger<UseRedemptionCodeTask> Logger => App.GetLogger<UseRedemptionCodeTask>();
    public void SetClipboardText(string text) =>
        UIDispatcherHelper.Invoke(() => Clipboard.SetDataObject(text));
    public void ClearClipboard() => UIDispatcherHelper.Invoke(Clipboard.Clear);
}
