using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoBoss;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;
using NotifyService = BetterGenshinImpact.Service.Notification.Notify;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoBossRuntimePlatform : IAutoBossRuntimePlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public IOcrService OcrService => OcrFactory.Paddle;
    public AutoFightConfig AutoFightConfig => TaskContext.Instance().Config.AutoFightConfig;
    public ILogger<AutoBossTask> Logger => App.GetLogger<AutoBossTask>();

    public void Notify(AutoBossNotification notification, string message) =>
        NotifyService.Event("AutoBoss").Success(message);
}
